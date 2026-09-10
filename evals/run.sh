#!/usr/bin/env bash
#
# run.sh — the blueprint conformance runner: does the agent behave the way the
# blueprint prescribes?
#
# Each case is a prompt plus a grader file, in the layout `claude plugin eval`
# documents (`<case>/prompt.md` + `<case>/graders/criteria.md`) — when that runner
# leaves early access, these cases move over unchanged; only the wrapper is
# retired. (Checked 2026-09-07 on claude 2.1.263: `plugin eval` still refuses to
# run on this account — "currently in early access".)
#
# What this adds over reading answers by hand:
#   - a scored judge: every answer is graded against its criteria by a fresh
#     model; a case's score is passes/runs
#   - a gate: exit 1 when any case scores below --threshold (default 0.9)
#   - --baseline: the same prompts run in an empty directory WITHOUT the
#     blueprint — the with/without delta is the only honest answer to "does the
#     blueprint actually cause this behavior"
#
# Cost model (learned the hard way on the 0.3.0 release run): a full gate used to
# be 90 claude calls (15 cases x 3 answers + 45 judge calls), and EVERY call paid
# MCP server startup — including an atlassian SSE auth probe that can hang for
# minutes. That is what burned straight through a session limit. Two structural
# cuts, both defaults:
#   - MCP servers are stripped from eval sessions (--mcp-config {} +
#     --strict-mcp-config): the scenarios reason about MCP tools, they never call
#     them. Cuts per-call latency from minutes to seconds and drops the tool
#     schemas from every call's context. --with-mcp opts back in.
#   - the judge grades all runs of a case in ONE call (15 judge calls instead of
#     45), instructed to grade independently and emit one verdict line per run.
# So a full --runs 3 gate is 45 + 15 calls, each cheap. Dev loop: run only the
# cases whose norms you touched (evals/COVERAGE.md maps norm → case).
#
# Usage:
#   bash evals/run.sh                     all cases, judged, gate applied
#   bash evals/run.sh routing-absent      one case
#   bash evals/run.sh --runs 3            three runs per case (variance matters:
#                                         one pass is a smoke test)
#   bash evals/run.sh --baseline          also run each prompt without the
#                                         blueprint (one run per case) and
#                                         report the delta
#   bash evals/run.sh --no-judge          answers only, no scoring, no gate
#   bash evals/run.sh --threshold 1.0     stricter gate
#   bash evals/run.sh --model sonnet      model for the ANSWER sessions
#   bash evals/run.sh --judge-model opus  model for the judge (default: same CLI
#                                         default as the answers)
#   bash evals/run.sh --with-mcp          keep MCP servers in eval sessions
#                                         (slower; only for MCP-specific cases)
#   bash evals/run.sh --list              list cases, run nothing
#
# Answers and verdicts land in evals/results/<timestamp>/ (gitignored): the
# cases are source, the answers are output.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNS=1
JUDGE=1
BASELINE=0
THRESHOLD="0.9"
MODEL=""
JUDGE_MODEL=""
WITH_MCP=0
CASES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --list)  for d in "$HERE"/*/; do [ -f "$d/prompt.md" ] && basename "$d"; done; exit 0 ;;
    --no-judge) JUDGE=0 ;;
    --baseline) BASELINE=1 ;;
    --with-mcp) WITH_MCP=1 ;;
    --runs) RUNS="${2:?--runs needs a number}"; shift ;;
    --threshold) THRESHOLD="${2:?--threshold needs 0..1}"; shift ;;
    --model) MODEL="${2:?--model needs a name}"; shift ;;
    --judge-model) JUDGE_MODEL="${2:?--judge-model needs a name}"; shift ;;
    -h|--help) sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) CASES+=("$1") ;;
  esac
  shift
done

# Resolve the CLI: it is frequently not on PATH in a non-interactive shell.
CLAUDE="${CLAUDE_CODE_EXECPATH:-}"
if [ -z "$CLAUDE" ] || [ ! -x "$CLAUDE" ]; then
  CLAUDE="$(command -v claude 2>/dev/null || true)"
fi
if [ -z "$CLAUDE" ] || [ ! -x "$CLAUDE" ]; then
  echo "claude CLI not found (looked at \$CLAUDE_CODE_EXECPATH and \$PATH)." >&2
  exit 1
fi

# Shared invocation args. MCP is stripped by default (see the cost model above);
# an empty --mcp-config + --strict-mcp-config means "no servers at all".
MCP_ARGS=()
[ "$WITH_MCP" -eq 0 ] && MCP_ARGS=(--mcp-config '{"mcpServers":{}}' --strict-mcp-config)
MODEL_ARGS=();       [ -n "$MODEL" ] && MODEL_ARGS=(--model "$MODEL")
JUDGE_MODEL_ARGS=(); [ -n "$JUDGE_MODEL" ] && JUDGE_MODEL_ARGS=(--model "$JUDGE_MODEL")

if [ "${#CASES[@]}" -eq 0 ]; then
  while IFS= read -r d; do CASES+=("$(basename "$d")"); done < <(find "$HERE" -mindepth 1 -maxdepth 1 -type d ! -name results | sort)
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HERE/results/$STAMP"
mkdir -p "$OUT"
echo "Answers → $OUT  (runs per case: $RUNS, judge: $([ $JUDGE -eq 1 ] && echo on || echo off), baseline: $([ $BASELINE -eq 1 ] && echo on || echo off), threshold: $THRESHOLD, mcp: $([ $WITH_MCP -eq 1 ] && echo on || echo off)${MODEL:+, model: $MODEL}${JUDGE_MODEL:+, judge-model: $JUDGE_MODEL})"
echo

# $1=cwd  $2=output file  $3=prompt text  -> 0 ok, 1 execution error
gen_answer() {
  local cwd="$1" outfile="$2" prompt="$3" answer
  answer="$(cd "$cwd" && "$CLAUDE" -p ${MCP_ARGS[@]+"${MCP_ARGS[@]}"} ${MODEL_ARGS[@]+"${MODEL_ARGS[@]}"} "$prompt" 2>&1)"
  local rc=$?
  printf '%s\n' "$answer" > "$outfile"
  return $rc
}

# $1=criteria file  $2=verdict outfile  $3..=answer files
# One judge call grades all runs of a case. Prints one token per run, in order:
# PASS | FAIL | UNSCORED.
judge_case() {
  local criteria="$1" outfile="$2"; shift 2
  local files=("$@") n="${#files[@]}"
  local prompt="You are grading $n independent answer(s) against fixed criteria.
For EACH answer separately: work through the criteria (quote the answer per
requirement when the criteria ask for it), in at most six lines per answer.
Grade each answer independently — answer 2's quality must not change your
reading of answer 1. Do not be generous: the criteria list explicit failure
conditions, and a fluent answer that misses a required element is a FAIL.
After discussing all answers, end your reply with exactly $n verdict line(s) —
one per answer, in order, nothing after them:
RUN 1: PASS
RUN 2: FAIL
(etc. — PASS or FAIL per line; the verdict lines are the machine-readable part,
any earlier PASS/FAIL word in your reasoning is ignored)

=== CRITERIA ===
$(cat "$criteria")
"
  local i
  for i in "${!files[@]}"; do
    prompt="$prompt

=== ANSWER $((i+1)) ===
$(cat "${files[$i]}")"
  done
  local verdict
  verdict="$("$CLAUDE" -p ${MCP_ARGS[@]+"${MCP_ARGS[@]}"} ${JUDGE_MODEL_ARGS[@]+"${JUDGE_MODEL_ARGS[@]}"} "$prompt" 2>&1)"
  printf '%s\n' "$verdict" > "$outfile"
  # The verdicts are the RUN lines — a judge that reasons its way from an
  # initial PASS to a grounded FAIL must be scored by its conclusion. Missing
  # or malformed line for a run → UNSCORED (loud at the gate when a case ends
  # with zero scored runs).
  for i in $(seq 1 "$n"); do
    printf '%s' "$verdict" | grep -E "^RUN $i: (PASS|FAIL)\b" | tail -1 | sed -E "s/^RUN $i: (PASS|FAIL).*/\1/"
    printf '%s' "$verdict" | grep -qE "^RUN $i: (PASS|FAIL)\b" || echo "UNSCORED"
  done
}

BASELINE_DIR=""
if [ "$BASELINE" -eq 1 ]; then
  BASELINE_DIR="$(mktemp -d /tmp/qa-eval-baseline.XXXXXX)"
fi

GATE_FAILURES=()
printf '%-28s %-14s %s\n' "case" "score" "baseline"
for name in "${CASES[@]}"; do
  if [ ! -f "$HERE/$name/prompt.md" ]; then
    printf '%-28s %s\n' "$name" "skipped (no prompt.md)"
    continue
  fi
  criteria="$HERE/$name/graders/criteria.md"
  answer_files=()
  for i in $(seq 1 "$RUNS"); do
    suffix="$name"; [ "$RUNS" -gt 1 ] && suffix="$name.run$i"
    if gen_answer "$REPO" "$OUT/$suffix.answer.md" "$(cat "$HERE/$name/prompt.md")"; then
      answer_files+=("$OUT/$suffix.answer.md")
    else
      printf '  %-26s run %s FAILED to execute — see %s\n' "" "$i" "$OUT/$suffix.answer.md"
    fi
  done
  passes=0; scored=0
  if [ "$JUDGE" -eq 1 ] && [ -f "$criteria" ] && [ "${#answer_files[@]}" -gt 0 ]; then
    while IFS= read -r v; do
      case "$v" in
        PASS) passes=$((passes+1)); scored=$((scored+1)) ;;
        FAIL) scored=$((scored+1)) ;;
      esac
    done < <(judge_case "$criteria" "$OUT/$name.verdicts.md" "${answer_files[@]}")
  fi
  if [ "$JUDGE" -eq 1 ] && [ "$scored" -gt 0 ]; then
    score="$(awk -v p="$passes" -v s="$scored" 'BEGIN{printf "%.2f", p/s}')"
    below="$(awk -v p="$passes" -v s="$scored" -v t="$THRESHOLD" 'BEGIN{print ((p/s < t) ? 1 : 0)}')"
    [ "$below" = "1" ] && GATE_FAILURES+=("$name ($score < $THRESHOLD)")
    scorestr="$score ($passes/$scored)"
    # pass^k trend history: one line per case per run, local and gitignored.
    # `grep <case> evals/results/history.log` answers "was this better last week?"
    printf '%s %s %s/%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$name" "$passes" "$scored" >> "$HERE/results/history.log"
  elif [ "$JUDGE" -eq 1 ]; then
    # Zero scored runs — every run errored out (harness broken, e.g. expired
    # auth) or the judge returned no parseable verdicts. A case that produced
    # no score is not a pass: without this branch the gate printed "passed" on
    # a run where NOTHING ran (seen live on 0.3.0's release run).
    scorestr="unscored"
    GATE_FAILURES+=("$name (0 scored of $RUNS — harness/judge error, not a pass)")
  else
    scorestr="unscored"
  fi
  basestr="-"
  if [ "$BASELINE" -eq 1 ]; then
    if gen_answer "$BASELINE_DIR" "$OUT/$name.baseline.answer.md" "$(cat "$HERE/$name/prompt.md")"; then
      if [ "$JUDGE" -eq 1 ] && [ -f "$criteria" ]; then
        basestr="$(judge_case "$criteria" "$OUT/$name.baseline.verdict.md" "$OUT/$name.baseline.answer.md")"
      else
        basestr="answered"
      fi
    else
      basestr="ERROR"
    fi
  fi
  printf '%-28s %-14s %s\n' "$name" "$scorestr" "$basestr"
done

[ -n "$BASELINE_DIR" ] && rm -rf "$BASELINE_DIR"

echo
if [ "$JUDGE" -eq 0 ]; then
  echo "Judge off — grade by reading each answer next to evals/<case>/graders/criteria.md."
  exit 0
fi
if [ "${#GATE_FAILURES[@]}" -gt 0 ]; then
  echo "GATE FAILED (threshold $THRESHOLD):"
  printf '  - %s\n' "${GATE_FAILURES[@]}"
  exit 1
fi
echo "Gate passed (threshold $THRESHOLD). Verdicts are in $OUT/*.verdicts.md — a second opinion you should read, not just count."

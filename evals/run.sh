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
CASES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --list)  for d in "$HERE"/*/; do [ -f "$d/prompt.md" ] && basename "$d"; done; exit 0 ;;
    --no-judge) JUDGE=0 ;;
    --baseline) BASELINE=1 ;;
    --runs) RUNS="${2:?--runs needs a number}"; shift ;;
    --threshold) THRESHOLD="${2:?--threshold needs 0..1}"; shift ;;
    -h|--help) sed -n '2,37p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

if [ "${#CASES[@]}" -eq 0 ]; then
  while IFS= read -r d; do CASES+=("$(basename "$d")"); done < <(find "$HERE" -mindepth 1 -maxdepth 1 -type d ! -name results | sort)
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HERE/results/$STAMP"
mkdir -p "$OUT"
echo "Answers → $OUT  (runs per case: $RUNS, judge: $([ $JUDGE -eq 1 ] && echo on || echo off), baseline: $([ $BASELINE -eq 1 ] && echo on || echo off), threshold: $THRESHOLD)"
echo

judge_answer() { # $1=criteria file  $2=answer text  -> prints verdict, first line PASS|FAIL
  "$CLAUDE" -p "You are grading one answer against fixed criteria. Reply with PASS
or FAIL on the first line, then at most three lines saying why. Do not be generous:
the criteria list explicit failure conditions, and a fluent answer that misses a
required element is a FAIL.

=== CRITERIA ===
$(cat "$1")

=== ANSWER ===
$2" 2>&1
}

run_one() { # $1=case name  $2=cwd  $3=output prefix
  local name="$1" cwd="$2" prefix="$3"
  local prompt="$HERE/$name/prompt.md" criteria="$HERE/$name/graders/criteria.md"
  local answer verdict first
  answer="$(cd "$cwd" && "$CLAUDE" -p "$(cat "$prompt")" 2>&1)"
  if [ $? -ne 0 ]; then
    printf '%s\n' "$answer" > "$OUT/$prefix.answer.md"
    echo "ERROR"
    return
  fi
  printf '%s\n' "$answer" > "$OUT/$prefix.answer.md"
  if [ "$JUDGE" -eq 1 ] && [ -f "$criteria" ]; then
    verdict="$(cd "$cwd" && judge_answer "$criteria" "$answer")"
    printf '%s\n' "$verdict" > "$OUT/$prefix.verdict.md"
    first="$(printf '%s' "$verdict" | head -1)"
    case "$first" in PASS*) echo "PASS" ;; FAIL*) echo "FAIL" ;; *) echo "UNSCORED" ;; esac
  else
    echo "answered"
  fi
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
  passes=0; scored=0
  for i in $(seq 1 "$RUNS"); do
    suffix="$name"; [ "$RUNS" -gt 1 ] && suffix="$name.run$i"
    result="$(run_one "$name" "$REPO" "$suffix")"
    case "$result" in
      PASS) passes=$((passes+1)); scored=$((scored+1)) ;;
      FAIL) scored=$((scored+1)) ;;
      ERROR) printf '  %-26s run %s FAILED to execute — see %s\n' "" "$i" "$OUT/$suffix.answer.md" ;;
    esac
  done
  if [ "$JUDGE" -eq 1 ] && [ "$scored" -gt 0 ]; then
    score="$(awk -v p="$passes" -v s="$scored" 'BEGIN{printf "%.2f", p/s}')"
    below="$(awk -v p="$passes" -v s="$scored" -v t="$THRESHOLD" 'BEGIN{print ((p/s < t) ? 1 : 0)}')"
    [ "$below" = "1" ] && GATE_FAILURES+=("$name ($score < $THRESHOLD)")
    scorestr="$score ($passes/$scored)"
    # pass^k trend history: one line per case per run, local and gitignored.
    # `grep <case> evals/results/history.log` answers "was this better last week?"
    printf '%s %s %s/%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$name" "$passes" "$scored" >> "$HERE/results/history.log"
  elif [ "$JUDGE" -eq 1 ]; then
    # Every run errored out (harness broken — e.g. expired auth). A case that
    # never executed is not a pass: without this branch the gate printed
    # "passed" on a run where NOTHING ran (seen live on 0.3.0's release run).
    scorestr="unscored"
    GATE_FAILURES+=("$name (0/$RUNS executed — harness error, not a pass)")
  else
    scorestr="unscored"
  fi
  basestr="-"
  if [ "$BASELINE" -eq 1 ]; then
    b="$(run_one "$name" "$BASELINE_DIR" "$name.baseline")"
    basestr="$b"
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
echo "Gate passed (threshold $THRESHOLD). Verdicts are in $OUT/*.verdict.md — a second opinion you should read, not just count."

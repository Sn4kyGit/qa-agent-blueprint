#!/usr/bin/env bash
#
# run-opencode.sh — the blueprint conformance runner for the opencode harness:
# same cases, same gate, different CLI (D9 in docs/opencode-port-plan.md).
#
# Reads the SAME case directories as run.sh (<case>/prompt.md +
# graders/criteria.md + optional scenario/ + tier file) — the cases are the
# shared norm→test matrix; only the harness invocation differs.
#
# Harness mapping (vs. run.sh):
#   claude -p <prompt>                 →  opencode run --auto --pure --dir <cwd>
#   --dangerously-skip-permissions     →  --auto (opencode's documented
#                                         non-interactive approve flag)
#   --mcp-config {} --strict-mcp-config →  XDG_CONFIG_HOME=<empty tempdir>:
#                                         opencode MERGES the global config
#                                         (~/.config/opencode), so per-key
#                                         overrides can never strip MCP
#                                         servers — hiding the global config
#                                         wholesale is the only hard cut
#                                         (the 0.3.0 cost lesson applies here
#                                         verbatim). Auth survives: providers
#                                         read their keys from env.
#   blueprint materialization          →  consumer layout: .opencode/ROUTER.md,
#                                         .opencode/agents, .opencode/commands
#                                         (from opencode/), .claude/{skills,
#                                         rules}, docs/, projects/, memory/ +
#                                         a generated opencode.json carrying
#                                         instructions + subagent_depth (the
#                                         template's mcp/permission keys stay
#                                         out — no MCP in eval sessions).
#                                         The plugin (qa-blueprint.ts) is NOT
#                                         copied: the behavioral evals measure
#                                         router/skill conformance, hook
#                                         mechanics are unit-tested — same
#                                         parity as the Claude side, where no
#                                         settings.json registers the hooks.
#
# Model selection (D6 — the runner anchors NOTHING):
#   QA_EVAL_MODEL=openrouter/z-ai/glm-5.3-flash bash evals/run-opencode.sh ...
#   QA_JUDGE_MODEL=... (default: the eval model — cross-model judging is an
#   explicit choice, not a default). --model/--judge-model flags override.
#   No defaults: without one of these the runner exits with an error.
#
# Usage:
#   bash evals/run-opencode.sh                     all cases, judged, gate applied
#   bash evals/run-opencode.sh routing-absent      one case
#   bash evals/run-opencode.sh --runs 3            three runs per case
#   bash evals/run-opencode.sh --baseline          also run without the blueprint
#   bash evals/run-opencode.sh --no-judge          answers only
#   bash evals/run-opencode.sh --threshold 1.0     stricter gate for HARD cases
#   bash evals/run-opencode.sh --variance-threshold 0.5
#   bash evals/run-opencode.sh --list              list cases, run nothing
#
# Answers and verdicts land in evals/results/<timestamp>-opencode/
# (gitignored); history.log lines are prefixed "opencode/<case>".
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
RUNS=1
JUDGE=1
BASELINE=0
THRESHOLD="0.9"
VAR_THRESHOLD="0.66"
MODEL="${QA_EVAL_MODEL:-}"
JUDGE_MODEL="${QA_JUDGE_MODEL:-}"
CASES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --list)  for d in "$HERE"/*/; do [ -f "$d/prompt.md" ] && basename "$d"; done; exit 0 ;;
    --no-judge) JUDGE=0 ;;
    --baseline) BASELINE=1 ;;
    --with-mcp) echo "note: --with-mcp is not wired on the opencode runner yet (eval sessions carry no MCP config); ignoring" >&2 ;;
    --runs) RUNS="${2:?--runs needs a number}"; shift ;;
    --threshold) THRESHOLD="${2:?--threshold needs 0..1}"; shift ;;
    --variance-threshold) VAR_THRESHOLD="${2:?--variance-threshold needs 0..1}"; shift ;;
    --model) MODEL="${2:?--model needs provider/model}"; shift ;;
    --judge-model) JUDGE_MODEL="${2:?--judge-model needs provider/model}"; shift ;;
    -h|--help) sed -n '2,52p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) CASES+=("$1") ;;
  esac
  shift
done

if [ -z "$MODEL" ]; then
  echo "no model: set QA_EVAL_MODEL (e.g. openrouter/z-ai/glm-5.3-flash) or pass --model provider/model." >&2
  echo "The runner anchors no model by design (docs/opencode-port-plan.md, D6)." >&2
  exit 1
fi
case "$MODEL" in */*) ;; *) echo "model must be provider/model, got: $MODEL" >&2; exit 1 ;; esac
JUDGE_MODEL="${JUDGE_MODEL:-$MODEL}"

OPENCODE="$(command -v opencode 2>/dev/null || true)"
if [ -z "$OPENCODE" ]; then
  echo "opencode CLI not found on PATH." >&2
  exit 1
fi

# Provider auth from evals/.env.openrouter (gitignored) — the key reaches
# opencode via the environment, never via a config file or a commit.
# set -a matters: the file carries no `export` keyword (run-openrouter.sh
# re-exports explicitly into ANTHROPIC_AUTH_TOKEN; opencode reads the var
# from its process env directly — unexported, the child never sees it).
if [ -f "$HERE/.env.openrouter" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$HERE/.env.openrouter"
  set +a
fi

# Global-config isolation (see header): one hidden XDG home for the whole
# suite run. ~/.local/share (session storage, auth) is deliberately NOT
# redirected — sessions belong in the user's normal opencode store.
EVAL_XDG="$(mktemp -d /tmp/qa-eval-xdg.XXXXXX)"
trap 'rm -rf "$EVAL_XDG"' EXIT
export XDG_CONFIG_HOME="$EVAL_XDG"

MODEL_ARGS=(--model "$MODEL")
JUDGE_MODEL_ARGS=(--model "$JUDGE_MODEL")

if [ "${#CASES[@]}" -eq 0 ]; then
  while IFS= read -r d; do CASES+=("$(basename "$d")"); done < <(find "$HERE" -mindepth 1 -maxdepth 1 -type d ! -name results | sort)
fi

STAMP="$(date +%Y%m%d-%H%M%S)-opencode"
OUT="$HERE/results/$STAMP"
mkdir -p "$OUT"
echo "Answers → $OUT  (runs per case: $RUNS, judge: $([ $JUDGE -eq 1 ] && echo on || echo off), baseline: $([ $BASELINE -eq 1 ] && echo on || echo off), threshold: $THRESHOLD, model: $MODEL, judge-model: $JUDGE_MODEL)"
echo

# $1=cwd  $2=output file  $3=prompt text  ->  0 ok, 1 execution error
gen_answer() {
  local cwd="$1" outfile="$2" prompt="$3" answer
  answer="$("$OPENCODE" run --auto --pure --dir "$cwd" "${MODEL_ARGS[@]}" "$prompt" 2>&1)"
  local rc=$?
  printf '%s\n' "$answer" > "$outfile"
  return $rc
}

# $1=criteria file  $2=verdict outfile  $3..=answer files
# One judge call grades all runs of a case — identical prompt and verdict-line
# protocol as run.sh (the criteria are harness-agnostic, the judge is a fresh
# model session in an EMPTY dir so the blueprint cannot bias the grading).
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
one per answer, in order, nothing after them. Plain text only — no markdown,
no asterisks, the line must start with RUN:
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
  local judge_dir verdict
  judge_dir="$(mktemp -d /tmp/qa-eval-judge.XXXXXX)"
  verdict="$("$OPENCODE" run --auto --pure --dir "$judge_dir" "${JUDGE_MODEL_ARGS[@]}" "$prompt" 2>&1)"
  rm -rf "$judge_dir"
  printf '%s\n' "$verdict" > "$outfile"
  for i in $(seq 1 "$n"); do
    printf '%s' "$verdict" | grep -E "^\*{0,2}RUN $i: (PASS|FAIL)\b" | tail -1 | sed -E "s/^\*{0,2}RUN $i: (PASS|FAIL).*/\1/"
    printf '%s' "$verdict" | grep -qE "^\*{0,2}RUN $i: (PASS|FAIL)\b" || echo "UNSCORED"
  done
}

# $1=case name -> prints a materialized tempdir (always — see below)
# opencode consumer layout (what install.sh --mode opencode will symlink):
# ROUTER.md + ported agents/commands under .opencode/, skills+rules shared
# under .claude/, plus a generated opencode.json — the template minus its mcp
# and permission keys (no MCP in eval sessions; --auto approves writes).
#
# Unlike run.sh this materializes EVERY case, not just scenario cases: on the
# Claude side the repo root auto-loads CLAUDE.md, so non-scenario cases can run
# in $REPO with the blueprint active. The opencode harness has no auto-load —
# without opencode.json + .opencode/ the blueprint would silently be ABSENT.
materialize_case() {
  local name="$1" dir
  dir="$(mktemp -d /tmp/qa-eval-opencode.XXXXXX)"
  mkdir -p "$dir/.opencode"
  cp "$REPO/opencode/ROUTER.md" "$dir/.opencode/ROUTER.md"
  cp -R "$REPO/opencode/agents" "$dir/.opencode/agents"
  cp -R "$REPO/opencode/commands" "$dir/.opencode/commands"
  cp -R "$REPO/.claude" "$dir/.claude"
  rm -rf "$dir/.claude/hooks" "$dir/.claude/agents" # inert for opencode; keep the layer lean
  for item in docs projects memory; do
    [ -e "$REPO/$item" ] && cp -R "$REPO/$item" "$dir/"
  done
  cat > "$dir/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "instructions": [".opencode/ROUTER.md", ".claude/rules/core/*.md"],
  "subagent_depth": 2
}
JSON
  [ -d "$HERE/$name/scenario" ] && cp -R "$HERE/$name/scenario/"* "$dir/"
  printf '%s' "$dir"
}

# HARNESS FACT file lists: exclude opencode's own runtime noise — the harness
# bootstraps .opencode/node_modules (+ lockfiles/.gitignore) in any project
# that has a .opencode dir, even under --pure. Those files are harness
# mechanics, never agent output.
scenario_files() {
  (cd "$1" && find . -type f \
    ! -path "./.opencode/node_modules/*" \
    ! -path "./.opencode/.gitignore" \
    ! -path "./.opencode/package.json" \
    ! -path "./.opencode/package-lock.json" \
    ! -path "./.opencode/bun.lock" | sort)
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
    # Per run, not per case: each run gets its own materialized copy so a
    # write from run 1 can't leak into run 2's filesystem.
    answer_cwd="$(materialize_case "$name")"
    before_list="$(scenario_files "$answer_cwd")"
    if gen_answer "$answer_cwd" "$OUT/$suffix.answer.md" "$(cat "$HERE/$name/prompt.md")"; then
      after_list="$(scenario_files "$answer_cwd")"
      {
        printf '\n\n---\nHARNESS FACT (appended by the runner; ground truth, not the agent): '
        printf 'files the session actually created on disk (empty = it wrote nothing):\n'
        comm -13 <(printf '%s\n' "$before_list") <(printf '%s\n' "$after_list") | sed 's/^/  /'
      } >> "$OUT/$suffix.answer.md"
      rm -rf "$answer_cwd"
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
    tier="hard"
    [ -f "$HERE/$name/tier" ] && tier="$(tr -d '[:space:]' < "$HERE/$name/tier")"
    [ "$tier" = "variance" ] && eff_threshold="$VAR_THRESHOLD" || eff_threshold="$THRESHOLD"
    score="$(awk -v p="$passes" -v s="$scored" 'BEGIN{printf "%.2f", p/s}')"
    below="$(awk -v p="$passes" -v s="$scored" -v t="$eff_threshold" 'BEGIN{print ((p/s < t) ? 1 : 0)}')"
    [ "$below" = "1" ] && GATE_FAILURES+=("$name [$tier] ($score < $eff_threshold)")
    scorestr="$score ($passes/$scored) [$tier]"
    printf '%s %s %s/%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "opencode/$name" "$passes" "$scored" >> "$HERE/results/history.log"
  elif [ "$JUDGE" -eq 1 ]; then
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
  echo "GATE FAILED (hard threshold $THRESHOLD, variance floor $VAR_THRESHOLD):"
  printf '  - %s\n' "${GATE_FAILURES[@]}"
  exit 1
fi
echo "Gate passed (hard $THRESHOLD / variance $VAR_THRESHOLD). Verdicts are in $OUT/*.verdicts.md — a second opinion you should read, not just count."

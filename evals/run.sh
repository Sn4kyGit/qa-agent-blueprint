#!/usr/bin/env bash
#
# run.sh — run the eval cases today, without the official runner.
#
# `claude plugin eval` is the intended way to run these and is in early access; it
# refuses to start on machines that do not have it. Rather than let six cases rot
# until then, this drives each prompt through `claude -p` in a fresh process and
# saves the answers for grading. When the official runner becomes available, use it
# instead — it adds the two things this cannot do: an LLM judge with a score, and
# `--ablation`, which measures the blueprint's actual effect by running each case
# with and without the plugin.
#
# Usage:
#   bash evals/run.sh                  run every case, save answers
#   bash evals/run.sh routing-absent   run one case
#   bash evals/run.sh --list           list cases, run nothing
#   bash evals/run.sh --judge          after answering, ask a fresh model to grade
#                                      each answer against its criteria file
#
# Answers land in evals/results/<timestamp>/. That directory is gitignored: the
# cases are source, the answers are output.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
JUDGE=0
CASES=()

for arg in "$@"; do
  case "$arg" in
    --list)  for d in "$HERE"/*/; do [ -f "$d/prompt.md" ] && basename "$d"; done; exit 0 ;;
    --judge) JUDGE=1 ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) CASES+=("$arg") ;;
  esac
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
echo "Answers → $OUT"
echo

for name in "${CASES[@]}"; do
  prompt="$HERE/$name/prompt.md"
  criteria="$HERE/$name/graders/criteria.md"
  if [ ! -f "$prompt" ]; then
    echo "skip  $name (no prompt.md)"
    continue
  fi
  printf 'run   %-22s ' "$name"
  # Run from the repo root so the agent sees the blueprint exactly as a user would.
  # A fresh process per case on purpose: a second question in the same session would
  # be answered from the first answer's context, which proves nothing.
  answer="$(cd "$REPO" && "$CLAUDE" -p "$(cat "$prompt")" 2>&1)"
  status=$?
  printf '%s\n' "$answer" > "$OUT/$name.answer.md"
  if [ "$status" -ne 0 ]; then
    echo "FAILED to run (exit $status) — see $OUT/$name.answer.md"
    continue
  fi
  echo "answered ($(printf '%s' "$answer" | wc -l | tr -d ' ') lines)"

  if [ "$JUDGE" -eq 1 ] && [ -f "$criteria" ]; then
    judge_prompt="You are grading one answer against fixed criteria. Reply with PASS
or FAIL on the first line, then at most three lines saying why. Do not be generous:
the criteria list explicit failure conditions, and a fluent answer that misses a
required element is a FAIL.

=== CRITERIA ===
$(cat "$criteria")

=== ANSWER ===
$answer"
    verdict="$(cd "$REPO" && "$CLAUDE" -p "$judge_prompt" 2>&1)"
    printf '%s\n' "$verdict" > "$OUT/$name.verdict.md"
    printf '      %s\n' "$(printf '%s' "$verdict" | head -1)"
  fi
done

echo
echo "Grade by reading each answer next to its criteria file:"
echo "  evals/<case>/graders/criteria.md   vs   $OUT/<case>.answer.md"
[ "$JUDGE" -eq 1 ] && echo "Model verdicts are in $OUT/*.verdict.md — a second opinion, not a gate."
cat <<'EOF'

Two caveats worth keeping in mind while reading the results:

- These runs are non-deterministic. One pass is a smoke test; a case that matters
  should be run three times (the official runner defaults to that for a reason).
- Running from this repo means the blueprint is active. That is the point, but it
  also means you cannot see its *effect* — for that you need the with/without
  comparison the official runner does via --ablation.
EOF

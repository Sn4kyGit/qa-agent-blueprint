#!/usr/bin/env bash
#
# run-all.sh — the whole port's test battery in one call:
#   1. opencode plugin unit tests (bun:test, opencode/tests/)
#   2. the harness-neutral fixture battery (.claude/hooks/tests/*.sh), which
#      includes the opencode convention checks in manifest-conventions.sh
#
# During the port's red phases this exits non-zero on purpose — the failures
# name the missing artifacts (opencode/plugins/qa-blueprint.ts, agents,
# commands, template). See docs/opencode-port-plan.md §4.
#
# Usage:  bash opencode/tests/run-all.sh
# Exit:   0 = everything green.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 1

fails=0

echo "== bun test opencode/tests =="
if command -v bun >/dev/null 2>&1; then
  bun test opencode/tests || fails=$((fails + 1))
else
  echo "bun not found — opencode plugin tests skipped (brew install oven-sh/bun/bun)" >&2
  fails=$((fails + 1))
fi

echo
echo "== bash fixture battery =="
for t in .claude/hooks/tests/*.sh; do
  if bash "$t" >/dev/null 2>&1; then
    echo "ok    $t"
  else
    echo "FAIL  $t"
    fails=$((fails + 1))
  fi
done

echo
if [ "$fails" -eq 0 ]; then
  echo "all suites passed"
else
  echo "$fails suite(s) failing"
fi
exit "$fails"

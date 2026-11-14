#!/usr/bin/env bash
# Fixtures for compress-tool-output.py — lossless-first, fail-open

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../scripts/compress-tool-output.py"
fails=0

check() {
  local name="$1" want="$2" got
  got="$3"
  if [ "$got" = "$want" ]; then
    printf 'ok    %-50s\n' "$name"
  else
    printf 'FAIL  %-50s want=%s got=%s\n' "$name" "$want" "$got"
    fails=$((fails + 1))
  fi
}

run() {
  python3 "$SCRIPT" --text "$1" --mode "$2" 2>&1
}

echo "== dedupe_lines =="
OUT=$(run $'error: timeout\nerror: timeout\nerror: timeout\nerror: timeout' lossless)
check "collapses 4 identical lines to 1 + marker" $'[... 3x identical ...]
error: timeout' "$OUT"

echo "== lossless =="
OUT=$(run $'echo "a\\nb" stays one line\necho "a\\nb" stays one line' lossless)
check "literal \\n sequences are not rewritten" $'echo "a\\nb" stays one line
echo "a\\nb" stays one line' "$OUT"

echo "== whitespace =="
OUT=$(run $'line1\n\n\n\n\nline2' lossless)
check "collapses 3+ blank lines to one" $'line1

line2' "$OUT"

echo "== JSON arrays =="
OUT=$(run '[{"id":1,"name":"a"},{"id":2,"name":"b"},{"id":3,"name":"c"},{"id":4,"name":"d"},{"id":5,"name":"e"}]' lossless)
check "compacts homogeneous arrays" "[{\"id\":1,\"name\":\"a\"},{\"id\":2,\"name\":\"b\"}, ... 3 more]" "$OUT"

echo "== filter_stale_lines =="
OUT=$(run $'error: A\nerror: A\nerror: A\nerror: A\nother' standard)
check "drops repeated error lines beyond 2" $'error: A
error: A
other' "$OUT"

OUT=$(run $'data row\ndata row\ndata row\nkeep' standard)
check "short repeated lines: marker grows -> fail-open" $'warning: grew — using original
data row
data row
data row
keep' "$OUT"

echo "== fail-open =="
OUT=$(run 'x' lossless)
check "short text passes through unchanged" "x" "$OUT"

echo "== mixed content =="
OUT=$(run $'error: timeout\nerror: timeout\nerror: timeout\nerror: timeout\n\n\n\nsome content\nsome content\nsome content\n[{"id":1,"name":"a"},{"id":2,"name":"b"},{"id":3,"name":"c"},{"id":4,"name":"d"},{"id":5,"name":"e"}]' lossless)
check "handles mixed content" $'[... 3x identical ...]
error: timeout

[... 2x identical ...]
some content
[{"id":1,"name":"a"},{"id":2,"name":"b"}, ... 3 more]' "$OUT"

echo
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) failed"
fi
exit "$fails"

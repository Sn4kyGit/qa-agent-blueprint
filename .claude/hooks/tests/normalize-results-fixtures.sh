#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
[ -f "$ROOT/.claude/scripts/normalize-test-results.py" ] || ROOT="$(cd "$HERE/../../../.." && pwd)"
NORMALIZER="$ROOT/.claude/scripts/normalize-test-results.py"
VALIDATOR="$ROOT/.claude/scripts/validate-evidence.py"
WORK="$(mktemp -d)"
trap 'rm -r "$WORK" 2>/dev/null' EXIT

cat > "$WORK/junit.xml" <<'XML'
<testsuites><testsuite name="checkout">
  <testcase id="TC-FAIL-001" name="fails"><failure message="no"/></testcase>
  <testcase id="TC-FLAKY-001" name="retry"><failure message="first"/></testcase>
  <testcase id="TC-FLAKY-001" name="retry"/>
  <testcase id="TC-SKIP-001" name="skip"><skipped/></testcase>
  <testcase id="TC-FIXME-001" name="fixme"><skipped type="fixme"/></testcase>
</testsuite></testsuites>
XML
cat > "$WORK/playwright.json" <<'JSON'
{"suites":[{"title":"api","specs":[
  {"id":"TC-PASS-001","title":"pass","tests":[{"results":[{"status":"passed"}]}]},
  {"id":"TC-FLAKY-001","title":"retry","tests":[{"results":[{"status":"failed"},{"status":"passed"}]}]},
  {"id":"TC-SKIP-001","title":"skip","tests":[{"results":[{"status":"skipped"}]}]},
  {"id":"TC-FIXME-001","title":"fixme","tests":[{"annotations":[{"type":"fixme"}],"results":[]}]},
  {"id":"TC-FIXME-STARTED","title":"expected failure","tests":[{"annotations":[{"type":"fixme"}],"results":[{"status":"failed"}]}]}
]}]}
JSON

for format in junit playwright; do
  RUN="$WORK/evidence/SHOP/SHOP-1/20261115-100000"
  mkdir -p "$RUN"
  python3 "$NORMALIZER" "$WORK/$format.$([ "$format" = junit ] && printf xml || printf json)" \
    --format "$format" --ticket SHOP-1 --timestamp 2026-11-15T10:00:00Z \
    --require TC-FAIL-001,TC-FLAKY-001,TC-SKIP-001,TC-FIXME-001,TC-FIXME-STARTED,TC-PASS-001,TC-MISSING-001 \
    --qa-home "$WORK" --output "$RUN/run.json"
  python3 "$VALIDATOR" "$RUN/run.json" --kind run-record --qa-home "$WORK" --json >/dev/null
  cp "$RUN/run.json" "$WORK/$format.first.json"
  python3 "$NORMALIZER" "$WORK/$format.$([ "$format" = junit ] && printf xml || printf json)" \
    --format "$format" --ticket SHOP-1 --timestamp 2026-11-15T10:00:00Z \
    --require TC-FAIL-001,TC-FLAKY-001,TC-SKIP-001,TC-FIXME-001,TC-FIXME-STARTED,TC-PASS-001,TC-MISSING-001 \
    --qa-home "$WORK" --output "$RUN/run.json"
  cmp "$WORK/$format.first.json" "$RUN/run.json"
  python3 - "$RUN/run.json" "$format" <<'PY'
import json
import sys
record = json.load(open(sys.argv[1]))
format_name = sys.argv[2]
cases = {case["id"]: case for case in record["test_cases"]}
assert record["schema_version"] == 2
assert len(record["source"]["sha256"]) == 64
assert cases["TC-FLAKY-001"]["outcome"] == "flaky"
assert cases["TC-FLAKY-001"]["attempts"] == 2 and cases["TC-FLAKY-001"]["attempt_results"] == ["fail", "pass"]
assert cases["TC-SKIP-001"]["outcome"] == "skip" and cases["TC-SKIP-001"]["attempts"] == 0 and cases["TC-SKIP-001"]["attempt_results"] == []
assert cases["TC-FIXME-001"]["outcome"] == "fixme" and cases["TC-FIXME-001"]["attempts"] == 0 and cases["TC-FIXME-001"]["attempt_results"] == []
assert "TC-SKIP-001" not in record["coverage"]["executed"] and "TC-FIXME-001" not in record["coverage"]["executed"]
assert cases["TC-MISSING-001"] == {"id": "TC-MISSING-001", "outcome": "not_run", "attempts": 0, "attempt_results": [], "required": True}
assert "TC-MISSING-001" not in record["coverage"]["executed"]
if format_name == "junit":
    assert cases["TC-FAIL-001"]["outcome"] == "fail" and cases["TC-FAIL-001"]["attempt_results"] == ["fail"]
else:
    assert cases["TC-PASS-001"]["outcome"] == "pass" and cases["TC-PASS-001"]["attempt_results"] == ["pass"]
    assert cases["TC-FIXME-STARTED"]["outcome"] == "fixme"
    assert cases["TC-FIXME-STARTED"]["attempts"] == 1 and cases["TC-FIXME-STARTED"]["attempt_results"] == ["fail"]
    assert "TC-FIXME-STARTED" not in record["coverage"]["executed"]
print(f"ok    {format_name}: normalized outcomes, attempts, coverage, provenance, determinism")
PY
done

cat > "$WORK/unknown.json" <<'JSON'
{"suites":[{"specs":[{"id":"TC-UNKNOWN-001","tests":[{"results":[{"status":"mystery"}]}]}]}]}
JSON
if python3 "$NORMALIZER" "$WORK/unknown.json" --ticket SHOP-1 --timestamp 2026-11-15T10:00:00Z --output "$WORK/unknown-run.json" >/dev/null 2>&1; then
  echo "FAIL  unknown runner status was accepted"
  exit 1
fi
echo "ok    unknown runner status rejected"

echo "all fixtures passed"

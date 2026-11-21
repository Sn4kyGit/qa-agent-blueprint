#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
[ -f "$ROOT/.claude/skills/qa-report/aggregate.py" ] || ROOT="$(cd "$HERE/../../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -r "$WORK" 2>/dev/null' EXIT
mkdir -p "$WORK/evidence/SHOP/SHOP-1/20261110-100000" "$WORK/evidence/SHOP/SHOP-1/20261112-100000"
cat > "$WORK/evidence/SHOP/SHOP-1/20261110-100000/execution_summary.json" <<'JSON'
{"ticket":"SHOP-1","project":"SHOP","timestamp":"2026-11-10T10:00:00Z","verdict":"FAIL","test_cases":[{"id":"TC-A","outcome":"pass","attempts":2}],"learnings":{"captured":["selector workaround"],"none_because":null}}
JSON
cat > "$WORK/evidence/SHOP/SHOP-1/20261112-100000/execution_summary.json" <<'JSON'
{"schema_version":2,"ticket":"SHOP-1","project":"SHOP","timestamp":"2026-11-12T10:00:00Z","verdict":"NEEDS_REVIEW","test_cases":[{"id":"TC-A","outcome":"flaky","attempts":2,"required":true},{"id":"TC-B","outcome":"skip","attempts":0,"required":true},{"id":"TC-C","outcome":"not_run","attempts":0,"required":true},{"id":"TC-D","outcome":"fail","attempts":2,"required":true}],"coverage":{"required":["TC-A","TC-B","TC-C","TC-D"],"executed":["TC-A","TC-D"]},"failure_analysis":{"class":"test-brittle","human_decision_required":true},"learnings":{"captured":["selector workaround"],"none_because":null},"skills_used":["test-ticket"]}
JSON

python3 - "$WORK" "$ROOT" <<'PY'
import importlib.util
import json
import pathlib
import subprocess
import sys
from datetime import datetime, timezone

work = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

aggregate = load("aggregate_fixture", root / ".claude/skills/qa-report/aggregate.py")
runs, broken = aggregate.load_summaries(work / "evidence", None, None)
assert not broken
stats = aggregate.summarize(runs)["SHOP (project-wide)"]
assert stats["cases"] == {"total": 5, "outcomes": {"pass": 1, "flaky": 1, "skip": 1, "not_run": 1, "fail": 1}, "required": 5, "required_not_passed": 5, "coverage_missing": 2}
assert stats["flake"]["retried"] == 2
assert stats["awaiting_ruling"] == 1
expected_age = (datetime.now(timezone.utc) - datetime.fromisoformat("2026-11-12T10:00:00+00:00")).days
assert stats["oldest_awaiting_days"] == expected_age, "analysis must stay paired with its own run"
print("ok    aggregate: legacy/v2 cases, retry flakes, coverage, analysis pairing")

history = load("history_fixture", root / ".claude/skills/failure-analysis/tc-history.py")
rows = history.case_rows(runs, "TC-A", None)
facts = history.derive(rows)
assert facts["runs_seen"] == 2 and not facts["never_passed"] and facts["max_attempts"] == 2
print("ok    tc-history: flaky remains a historical pass")

perf = load("perf_fixture", root / ".claude/skills/perf-analysis/perf-analysis.py")
stats = perf.analyze(runs, [], [], [], [])
assert stats["flaky_cases"] == 2
assert stats["case_outcomes"]["fail"] == 1
assert stats["required_not_passed"] == 5
print("ok    perf-analysis: failed retries are not flakes")

review = subprocess.run(["python3", str(root / ".claude/scripts/skill-review.py"), "--evidence", str(work / "evidence"), "--since", "0", "--json"], capture_output=True, text=True, check=True)
report = json.loads(review.stdout)
assert report["coverage"]["schema_v2_runs"] == 1 and report["coverage"]["legacy_runs"] == 1
print("ok    skill-review: legacy/v2 coverage remains readable")

sightings = subprocess.run(["python3", str(root / ".claude/scripts/verify-sightings.py"), "--evidence", str(work / "evidence"), "--since", "0", "--project", "SHOP", "--json"], capture_output=True, text=True, check=True)
report = json.loads(sightings.stdout)
assert report["sightings"][0]["verified"] == 2
print("ok    verify-sightings: distinct legacy/v2 runs and project filter")
PY

echo "all fixtures passed"

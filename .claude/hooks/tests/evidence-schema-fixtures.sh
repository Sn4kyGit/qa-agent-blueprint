#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
[ -f "$ROOT/.claude/scripts/validate-evidence.py" ] || ROOT="$(cd "$HERE/../../../.." && pwd)"
VALIDATOR="$ROOT/.claude/scripts/validate-evidence.py"
WORK="$(mktemp -d)"
trap 'rm -r "$WORK" 2>/dev/null' EXIT
export WORK

python3 - "$VALIDATOR" <<'PY'
import copy
import hashlib
import json
import os
import pathlib
import subprocess
import sys

validator = sys.argv[1]
home = pathlib.Path(os.environ["WORK"])
run = home / "evidence" / "SHOP" / "SHOP-1" / "20261115-100000"
run.mkdir(parents=True)
artifact = run / "screenshots" / "proof.txt"
artifact.parent.mkdir()
artifact.write_bytes(b"proof\n")
summary = {
    "schema_version": 2,
    "run_id": run.name,
    "ticket": "SHOP-1",
    "project": "SHOP",
    "timestamp": "2026-11-15T10:00:00Z",
    "verdict": "PASS",
    "test_type": "regression",
    "mode": "cli-first",
    "channel": "browser",
    "environment": {"name": "stage", "version_or_build": "build-1", "commit": "abc123"},
    "deploy": {"from_version": "build-0", "to_version": "build-1", "pipeline_run": "pipeline-1", "at": "2026-11-15T09:59:00Z"},
    "skills_used": ["test-automation"],
    "steps_executed": ["checkout"],
    "test_cases": [{"id": "TC-CHK-001", "outcome": "pass", "attempts": 1, "attempt_results": ["pass"], "required": True}],
    "findings": [],
    "artifacts": [{"id": "proof-checkout", "kind": "screenshot", "path": "screenshots/proof.txt", "sha256": hashlib.sha256(b"proof\n").hexdigest(), "size_bytes": 6, "covers": ["TC-CHK-001"]}],
    "coverage": {"required": ["TC-CHK-001"], "executed": ["TC-CHK-001"]},
    "evidence_dir": "evidence/SHOP/SHOP-1/20261115-100000",
    "reported_to_jira": False,
    "shadow": False,
    "learnings": {"captured": [], "none_because": "clean run"},
}
path = run / "execution_summary.json"
failures = 0


def check(name, data, valid=True, tool=None, raw=None):
    global failures
    if raw is not None:
        path.write_text(raw)
    else:
        path.write_text(json.dumps(data))
    command = ["python3", validator, str(path), "--qa-home", str(home), "--json"]
    if tool:
        command += ["--jira-write", tool]
    result = subprocess.run(command, capture_output=True, text=True)
    try:
        payload = json.loads(result.stdout)
    except Exception:
        payload = {}
    ok = (result.returncode == 0 and payload.get("valid") is True) if valid else (result.returncode != 0 and payload.get("valid") is False)
    print(("ok    " if ok else "FAIL  ") + name)
    if not ok:
        print(result.stdout + result.stderr)
        failures += 1


check("valid clean PASS", summary)
unversioned = copy.deepcopy(summary)
del unversioned["schema_version"]
check("unversioned new summary rejected", unversioned, False)
check("malformed JSON rejected", None, False, raw="{broken")
for learnings in ({"captured": [], "none_because": None}, {"captured": ["x"], "none_because": "also"}):
    variant = copy.deepcopy(summary)
    variant["learnings"] = learnings
    check("learnings XOR " + str(learnings), variant, False)
variant = copy.deepcopy(summary)
variant["test_cases"][0].update(outcome="pass", attempts=2)
check("retry pass cannot remain pass", variant, False)
variant = copy.deepcopy(summary)
variant["test_cases"][0].update(outcome="flaky", attempts=2, attempt_results=["fail", "pass"])
check("flaky prevents PASS", variant, False)
variant["verdict"] = "BLOCKED"
variant["blocked_reason"] = "retry pass requires quarantine review"
check("flaky without definitive failure is BLOCKED", variant)
variant = copy.deepcopy(summary)
variant["test_cases"][0].update(outcome="skip", attempts=0, attempt_results=[])
variant["coverage"]["executed"] = []
check("required skip prevents PASS", variant, False)
variant["verdict"] = "BLOCKED"
variant["blocked_reason"] = "required test data unavailable"
check("required skip without failure is BLOCKED", variant)
variant = copy.deepcopy(summary)
variant["test_cases"][0].update(outcome="not_run", attempts=0, attempt_results=[])
variant["coverage"]["executed"] = []
variant["verdict"] = "BLOCKED"
variant["blocked_reason"] = "required case unavailable"
check("not_run coverage is explicit", variant)
variant = copy.deepcopy(summary)
variant["ticket"] = "SHOP-2"
check("ticket/path binding", variant, False)
variant = copy.deepcopy(summary)
variant["evidence_dir"] = "evidence/SHOP/SHOP-1/other-run"
check("evidence_dir binding", variant, False)
variant = copy.deepcopy(summary)
variant["artifacts"][0]["sha256"] = "0" * 64
check("artifact digest mismatch", variant, False)
variant = copy.deepcopy(summary)
variant["artifacts"][0]["path"] = "../outside.txt"
check("artifact traversal rejected", variant, False)
for field in ("id", "kind", "size_bytes", "covers"):
    variant = copy.deepcopy(summary)
    del variant["artifacts"][0][field]
    check(f"artifact missing {field} rejected", variant, False)
variant = copy.deepcopy(summary)
variant["artifacts"][0]["size_bytes"] = 5
check("artifact size mismatch rejected", variant, False)
variant = copy.deepcopy(summary)
variant["artifacts"][0]["id"] = "x" * 129
check("artifact id bounds enforced", variant, False)
variant = copy.deepcopy(summary)
variant["artifacts"][0]["kind"] = "unknown"
check("artifact kind enum enforced", variant, False)
variant = copy.deepcopy(summary)
variant["artifacts"][0]["covers"] = []
check("PASS artifact must cover required case", variant, False)
variant = copy.deepcopy(summary)
variant["artifacts"][0]["covers"] = ["TC-OTHER-999"]
check("artifact covers must link to declared coverage", variant, False)
for unsafe_name in ("credentials.json", "session.auth", "auth-state.json", "storageState.json", "cookies.har"):
    unsafe = run / "screenshots" / unsafe_name
    unsafe.write_bytes(b"proof\n")
    variant = copy.deepcopy(summary)
    variant["artifacts"][0]["path"] = f"screenshots/{unsafe_name}"
    check(f"unsafe artifact filename rejected: {unsafe_name}", variant, False)
outside = home / "outside.txt"
outside.write_bytes(b"proof\n")
escape = run / "screenshots" / "escape.txt"
escape.symlink_to(outside)
variant = copy.deepcopy(summary)
variant["artifacts"][0]["path"] = "screenshots/escape.txt"
check("artifact symlink escape rejected", variant, False)
api = copy.deepcopy(summary)
api["channel"] = "api"
api["artifacts"][0]["kind"] = "log"
check("API PASS uses log proof, no screenshot required", api)
ac = copy.deepcopy(summary)
ac["test_type"] = "exploratory"
ac["test_cases"] = []
ac["coverage"] = {"required": ["AC-1"], "executed": ["AC-1"]}
ac["artifacts"][0]["covers"] = ["AC-1"]
check("exploratory AC proof is covered explicitly", ac)
exploratory = copy.deepcopy(summary)
exploratory["channel"] = "browser"
exploratory["test_type"] = "exploratory"
exploratory["test_cases"] = []
exploratory["coverage"] = {"required": [], "executed": []}
exploratory["artifacts"][0]["covers"] = []
check("exploratory run-level proof remains valid", exploratory)
legacy_exploratory = copy.deepcopy(exploratory)
del legacy_exploratory["channel"]
legacy_exploratory["artifacts"] = [{"path": "screenshots/proof.txt", "sha256": hashlib.sha256(b"proof\n").hexdigest()}]
check("legacy run-level exploratory proof compatible", legacy_exploratory)
legacy_exploratory["artifacts"][0]["size_bytes"] = 6
check("partial new exploratory metadata rejected", legacy_exploratory, False)
variant = copy.deepcopy(summary)
variant["test_cases"][0]["attempt_results"] = ["pass", "pass"]
check("attempt result count must equal attempts", variant, False)
variant = copy.deepcopy(summary)
variant["test_cases"][0]["attempt_results"] = ["fail", "pass"]
check("clean pass rejects failure then pass history", variant, False)
variant = copy.deepcopy(summary)
variant["verdict"] = "FAIL"
variant["test_cases"][0].update(outcome="fail", attempts=1, attempt_results=["fail"])
check("definitive final failure supports FAIL", variant)
variant["test_cases"][0].update(attempts=2, attempt_results=["fail", "pass"])
check("fail outcome rejects earlier fail then final pass", variant, False)
variant = copy.deepcopy(summary)
variant["verdict"] = "BLOCKED"
variant["blocked_reason"] = "flake under review"
variant["test_cases"][0].update(outcome="flaky", attempts=2, attempt_results=["pass", "pass"])
check("flaky history requires earlier failure", variant, False)
variant["test_cases"][0].update(outcome="fixme", attempts=1, attempt_results=["fail"])
variant["coverage"]["executed"] = []
check("expected-failure fixme may retain started attempt", variant)
variant["test_cases"][0].update(attempts=0, attempt_results=[])
check("unstarted fixme remains valid BLOCKED", variant)
no_test = copy.deepcopy(summary)
no_test.update(verdict="NO_TEST", no_test_reason="runner aborted", test_cases=[], artifacts=[], coverage={"required": [], "executed": []}, steps_executed=[])
check("NO_TEST closes evidence gate", no_test)
check("NO_TEST denies JIRA comment", no_test, False, "mcp__atlassian__addCommentToJiraIssue")
review = copy.deepcopy(summary)
review.update(verdict="NEEDS_REVIEW", interactive=True)
check("NEEDS_REVIEW proposal comment allowed", review, True, "mcp__atlassian__addCommentToJiraIssue")
check("NEEDS_REVIEW transition denied", review, False, "mcp__atlassian__transitionJiraIssue")
check("NEEDS_REVIEW bug creation denied", review, False, "mcp__atlassian__createJiraIssue")
review["interactive"] = False
check("NEEDS_REVIEW headless rejected", review, False)

if failures:
    print(f"{failures} fixture(s) failed")
    sys.exit(failures)
print("all fixtures passed")
PY

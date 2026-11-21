#!/usr/bin/env python3
# SPDX-License-Identifier: MIT AND Apache-2.0
# Copyright (c) 2026 Ivan Davidov and Agentic Playwright contributors
# Copyright (c) 2026 Sn4kyGit and qa-agent-blueprint contributors
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile
from datetime import datetime, timezone

CANDIDATE_SCHEMA = "qa-healing-candidate/v1"
REVIEW_SCHEMA = "qa-healing-review/v1"
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$")
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
MAX_CANDIDATES = 3
MAX_SELECTED = 1
MAX_CLI_RUNS = 2
MAX_ORIGIN_CASES = 2


class HealingError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


def fail(code, message):
    raise HealingError(code, message)


def now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail("INVALID_JSON", f"duplicate key {key}")
        result[key] = value
    return result


def load(path):
    try:
        return json.loads(Path(path).read_bytes().decode("utf-8"), object_pairs_hook=duplicates, parse_constant=lambda value: fail("INVALID_JSON", value))
    except HealingError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail("INVALID_JSON", f"cannot load {path}: {exc}")


def atomic(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".healing-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def exact(value, required, optional, label):
    if not isinstance(value, dict):
        fail("INVALID_STRUCTURE", f"{label} must be an object")
    missing = set(required) - set(value)
    extra = set(value) - set(required) - set(optional)
    if missing or extra:
        fail("INVALID_STRUCTURE", f"{label} missing={sorted(missing)} unknown={sorted(extra)}")


def text(value, label, limit=1000):
    if not isinstance(value, str) or not value or len(value) > limit:
        fail("INVALID_STRUCTURE", label)
    return value


def identifier(value, label):
    text(value, label, 80)
    if not ID_RE.fullmatch(value):
        fail("INVALID_ID", label)
    return value


def sha(value, label):
    text(value, label, 64)
    if not HASH_RE.fullmatch(value):
        fail("INVALID_HASH", label)
    return value


def safe_path(value, label):
    text(value, label, 300)
    if value.startswith("/") or "\\" in value:
        fail("UNSAFE_PATH", label)
    path = PurePosixPath(value)
    if str(path) != value or any(part in ("", ".", "..") for part in path.parts):
        fail("UNSAFE_PATH", label)
    return value


def file_sha(path):
    try:
        return hashlib.sha256(Path(path).read_bytes()).hexdigest()
    except OSError as exc:
        fail("STALE_ORIGIN", f"cannot hash {path}: {exc}")


def validate_locator(value, label):
    exact(value, {"strategy", "value", "expression"}, {"name", "exact"}, label)
    if value["strategy"] not in ("role", "label", "text", "test_id", "placeholder", "title", "alt"):
        fail("NON_SEMANTIC_LOCATOR", label)
    text(value["value"], label + ".value", 300)
    text(value["expression"], label + ".expression", 500)
    if value["strategy"] == "role" and "name" not in value:
        fail("INVALID_LOCATOR", "role locator needs accessible name")
    if "name" in value:
        text(value["name"], label + ".name", 300)
    if "exact" in value and not isinstance(value["exact"], bool):
        fail("INVALID_LOCATOR", label + ".exact")


def validate_origin(origin):
    exact(origin, {"cases", "build", "build_sha256", "capsule_sha256", "original_verdict"}, set(), "origin")
    if not isinstance(origin["cases"], list) or not 1 <= len(origin["cases"]) <= MAX_ORIGIN_CASES:
        fail("ORIGIN_CASE_BUDGET", "one or two origin cases required")
    seen = set()
    for case in origin["cases"]:
        exact(case, {"case_id", "ac_id", "tc_id", "spec_path", "spec_sha256", "ac_sha256", "tc_sha256", "intent_sha256", "assertion_sha256"}, set(), "origin.cases[]")
        identifier(case["case_id"], "case_id")
        if case["case_id"] in seen:
            fail("DUPLICATE_ORIGIN_CASE", case["case_id"])
        seen.add(case["case_id"])
        text(case["ac_id"], "ac_id", 300)
        text(case["tc_id"], "tc_id", 300)
        safe_path(case["spec_path"], "spec_path")
        for key in ("spec_sha256", "ac_sha256", "tc_sha256", "intent_sha256", "assertion_sha256"):
            sha(case[key], key)
    text(origin["build"], "build", 200)
    sha(origin["build_sha256"], "build_sha256")
    sha(origin["capsule_sha256"], "capsule_sha256")
    if origin["original_verdict"] not in ("FAIL", "BLOCKED", "NEEDS_REVIEW"):
        fail("INVALID_ORIGINAL_VERDICT", "healing candidates require a non-PASS original verdict")


def validate_verification(value):
    exact(value, {"run_id", "kind", "result", "assertion_sha256", "recorded_at", "build", "build_sha256", "capsule_sha256", "spec_sha256"}, set(), "verification")
    identifier(value["run_id"], "run_id")
    if value["kind"] not in ("green", "negative_control"):
        fail("INVALID_VERIFICATION", "kind")
    if value["result"] not in ("passed", "failed"):
        fail("INVALID_VERIFICATION", "result")
    if value["kind"] == "green" and value["result"] != "passed":
        fail("INVALID_GREEN", "green verification must pass")
    if value["kind"] == "negative_control" and value["result"] != "failed":
        fail("INVALID_NEGATIVE_CONTROL", "negative control must fail the same assertion")
    sha(value["assertion_sha256"], "assertion_sha256")
    text(value["recorded_at"], "recorded_at", 40)
    text(value["build"], "build", 200)
    sha(value["build_sha256"], "build_sha256")
    sha(value["capsule_sha256"], "capsule_sha256")
    sha(value["spec_sha256"], "spec_sha256")


def validate_candidate(candidate, check_hunk=True):
    exact(candidate, {"schema_version", "candidate_id", "status", "created_at", "origin", "origin_case_ids", "classification", "failure_kind", "eligible", "score", "original_locator", "replacement_locator", "hunk", "verification"}, set(), "candidate")
    if candidate["schema_version"] != CANDIDATE_SCHEMA:
        fail("WRONG_SCHEMA", "candidate")
    identifier(candidate["candidate_id"], "candidate_id")
    if candidate["status"] not in ("draft", "rejected", "ready_for_human"):
        fail("INVALID_STATUS", candidate["status"])
    text(candidate["created_at"], "created_at", 40)
    validate_origin(candidate["origin"])
    if not isinstance(candidate["origin_case_ids"], list) or not 1 <= len(candidate["origin_case_ids"]) <= MAX_ORIGIN_CASES:
        fail("ORIGIN_CASE_BUDGET", "candidate origin_case_ids")
    origin_ids = {case["case_id"] for case in candidate["origin"]["cases"]}
    if len(set(candidate["origin_case_ids"])) != len(candidate["origin_case_ids"]) or not set(candidate["origin_case_ids"]) <= origin_ids:
        fail("ORIGIN_CASE_MISMATCH", "candidate origin_case_ids")
    if candidate["classification"] != "test-brittle" or candidate["failure_kind"] != "locator_resolution" or candidate["eligible"] is not True:
        fail("INELIGIBLE", "only eligible locator-resolution test-brittle cases")
    if isinstance(candidate["score"], bool) or not isinstance(candidate["score"], (int, float)) or not 0 <= candidate["score"] <= 1:
        fail("INVALID_SCORE", "score")
    validate_locator(candidate["original_locator"], "original_locator")
    validate_locator(candidate["replacement_locator"], "replacement_locator")
    if candidate["original_locator"] == candidate["replacement_locator"]:
        fail("EMPTY_REPAIR", "locators are identical")
    hunk = candidate["hunk"]
    exact(hunk, {"path", "before", "after"}, set(), "hunk")
    safe_path(hunk["path"], "hunk.path")
    if hunk["path"] not in {case["spec_path"] for case in candidate["origin"]["cases"] if case["case_id"] in candidate["origin_case_ids"]}:
        fail("HUNK_ORIGIN_MISMATCH", "hunk path must belong to a selected origin case")
    for key in ("before", "after"):
        text(hunk[key], "hunk." + key, 4000)
        if "\n" in hunk[key] or "\r" in hunk[key]:
            fail("HUNK_BUDGET", "exactly one source line per side")
    if check_hunk:
        old = candidate["original_locator"]["expression"]
        new = candidate["replacement_locator"]["expression"]
        if hunk["before"].count(old) != 1:
            fail("NON_LOCATOR_DIFF", "before must contain the original locator exactly once")
        if hunk["after"] != hunk["before"].replace(old, new):
            fail("NON_LOCATOR_DIFF", "only the locator expression may change")
    if not isinstance(candidate["verification"], list) or len(candidate["verification"]) > MAX_CLI_RUNS:
        fail("CLI_BUDGET", "at most two verification runs")
    run_ids = set()
    for verification in candidate["verification"]:
        validate_verification(verification)
        if verification["run_id"] in run_ids:
            fail("DUPLICATE_RUN", verification["run_id"])
        run_ids.add(verification["run_id"])
        if verification["build"] != candidate["origin"]["build"] or verification["build_sha256"] != candidate["origin"]["build_sha256"] or verification["capsule_sha256"] != candidate["origin"]["capsule_sha256"]:
            fail("STALE_ORIGIN", "verification build/capsule differs from origin")
        origin_case = next(case for case in candidate["origin"]["cases"] if case["spec_path"] == hunk["path"])
        if verification["spec_sha256"] != origin_case["spec_sha256"]:
            fail("STALE_ORIGIN", "verification spec hash differs from original spec")
        if verification["assertion_sha256"] != origin_case["assertion_sha256"]:
            fail("ASSERTION_MISMATCH", "verification must exercise the original assertion")


def validate_review(review):
    exact(review, {"schema_version", "origin", "candidates", "selected_candidate_id", "cli_runs_used", "original_verdict"}, set(), "review")
    if review["schema_version"] != REVIEW_SCHEMA:
        fail("WRONG_SCHEMA", "review")
    validate_origin(review["origin"])
    if review["original_verdict"] != review["origin"]["original_verdict"]:
        fail("ORIGINAL_OUTCOME_CHANGED", "review verdict differs from origin")
    if not isinstance(review["candidates"], list) or len(review["candidates"]) > MAX_CANDIDATES:
        fail("CANDIDATE_BUDGET", "at most three candidates")
    ids = set()
    for entry in review["candidates"]:
        exact(entry, {"candidate_id", "status"}, set(), "review.candidates[]")
        identifier(entry["candidate_id"], "candidate_id")
        if entry["candidate_id"] in ids:
            fail("DUPLICATE_CANDIDATE", entry["candidate_id"])
        ids.add(entry["candidate_id"])
        if entry["status"] not in ("draft", "rejected", "ready_for_human"):
            fail("INVALID_STATUS", entry["status"])
    if review["selected_candidate_id"] is not None:
        identifier(review["selected_candidate_id"], "selected_candidate_id")
        if review["selected_candidate_id"] not in ids:
            fail("UNKNOWN_SELECTION", "selected candidate")
    if isinstance(review["cli_runs_used"], bool) or not isinstance(review["cli_runs_used"], int) or not 0 <= review["cli_runs_used"] <= MAX_CLI_RUNS:
        fail("CLI_BUDGET", "review cli_runs_used")
    if sum(entry["status"] == "ready_for_human" for entry in review["candidates"]) > MAX_SELECTED:
        fail("SELECTION_BUDGET", "only one candidate may be ready")


def validate_ready(candidate, review):
    if candidate["status"] != "ready_for_human":
        return
    if review is None:
        fail("REVIEW_REQUIRED", "ready candidate needs review")
    if review["selected_candidate_id"] != candidate["candidate_id"]:
        fail("NOT_SELECTED", "ready candidate must be the single human-selected candidate")
    if len(candidate["verification"]) != 2:
        fail("MISSING_VERIFICATION", "ready needs green and negative control")
    green = [item for item in candidate["verification"] if item["kind"] == "green"]
    negative = [item for item in candidate["verification"] if item["kind"] == "negative_control"]
    if len(green) != 1 or len(negative) != 1 or green[0]["assertion_sha256"] != negative[0]["assertion_sha256"]:
        fail("MISSING_ORACLE", "green and negative control must bind the same assertion")


def freshness(candidate, spec_root, capsule, build, build_sha256):
    if build is not None and build != candidate["origin"]["build"]:
        fail("STALE_ORIGIN", "build changed")
    if build_sha256 is not None:
        sha(build_sha256, "build_sha256")
        if build_sha256 != candidate["origin"]["build_sha256"]:
            fail("STALE_ORIGIN", "build hash changed")
    if capsule is not None and file_sha(capsule) != candidate["origin"]["capsule_sha256"]:
        fail("STALE_CAPSULE", "capsule hash changed")
    if spec_root is not None:
        for case in candidate["origin"]["cases"]:
            if case["case_id"] in candidate["origin_case_ids"] and file_sha(Path(spec_root) / case["spec_path"]) != case["spec_sha256"]:
                fail("STALE_ORIGIN", f"spec changed: {case['spec_path']}")


def create(candidate_path, review_path):
    candidate = load(candidate_path)
    candidate["status"] = "draft"
    candidate["verification"] = []
    candidate.setdefault("created_at", now())
    validate_candidate(candidate)
    if Path(review_path).exists():
        review = load(review_path)
        validate_review(review)
        if review["origin"] != candidate["origin"] or review["original_verdict"] != candidate["origin"]["original_verdict"]:
            fail("ORIGIN_MISMATCH", "candidate origin differs from review")
    else:
        review = {"schema_version": REVIEW_SCHEMA, "origin": copy.deepcopy(candidate["origin"]), "candidates": [], "selected_candidate_id": None, "cli_runs_used": 0, "original_verdict": candidate["origin"]["original_verdict"]}
    if any(entry["candidate_id"] == candidate["candidate_id"] for entry in review["candidates"]):
        fail("DUPLICATE_CANDIDATE", candidate["candidate_id"])
    if len(review["candidates"]) >= MAX_CANDIDATES:
        fail("CANDIDATE_BUDGET", "at most three candidates")
    review["candidates"].append({"candidate_id": candidate["candidate_id"], "status": "draft"})
    atomic(candidate_path, candidate)
    atomic(review_path, review)
    print(f"draft {candidate['candidate_id']}")


def select(candidate_path, review_path):
    candidate = load(candidate_path)
    review = load(review_path)
    validate_candidate(candidate)
    validate_review(review)
    if candidate["status"] == "rejected" or not any(entry["candidate_id"] == candidate["candidate_id"] for entry in review["candidates"]):
        fail("INELIGIBLE", "rejected or unknown candidate")
    if review["selected_candidate_id"] not in (None, candidate["candidate_id"]):
        fail("SELECTION_BUDGET", "one selected candidate maximum")
    review["selected_candidate_id"] = candidate["candidate_id"]
    atomic(review_path, review)
    print(f"selected {candidate['candidate_id']}")


def verify(candidate_path, review_path, verification_path, status, spec_root, capsule, build, build_sha256):
    candidate = load(candidate_path)
    review = load(review_path)
    incoming = load(verification_path)
    validate_candidate(candidate)
    validate_review(review)
    if candidate["status"] != "draft":
        fail("IMMUTABLE_STATUS", "only draft candidates accept verification")
    if not any(entry["candidate_id"] == candidate["candidate_id"] for entry in review["candidates"]):
        fail("UNKNOWN_CANDIDATE", candidate["candidate_id"])
    if status not in ("draft", "rejected", "ready_for_human"):
        fail("INVALID_STATUS", status)
    if review["cli_runs_used"] >= MAX_CLI_RUNS or len(candidate["verification"]) >= MAX_CLI_RUNS:
        fail("CLI_BUDGET", "two CLI verification runs maximum")
    exact(incoming, {"run_id", "kind", "result", "assertion_sha256"}, {"recorded_at"}, "verification input")
    origin_case = next(case for case in candidate["origin"]["cases"] if case["spec_path"] == candidate["hunk"]["path"])
    verification = copy.deepcopy(incoming)
    verification["recorded_at"] = verification.get("recorded_at", now())
    verification["build"] = candidate["origin"]["build"]
    verification["build_sha256"] = candidate["origin"]["build_sha256"]
    verification["capsule_sha256"] = candidate["origin"]["capsule_sha256"]
    verification["spec_sha256"] = origin_case["spec_sha256"]
    validate_verification(verification)
    freshness(candidate, spec_root, capsule, build, build_sha256)
    candidate["verification"].append(verification)
    candidate["status"] = status
    review["cli_runs_used"] += 1
    validate_candidate(candidate)
    validate_ready(candidate, review)
    validate_review(review)
    for entry in review["candidates"]:
        if entry["candidate_id"] == candidate["candidate_id"]:
            entry["status"] = status
    validate_review(review)
    atomic(candidate_path, candidate)
    atomic(review_path, review)
    print(f"{status} {candidate['candidate_id']} run={verification['run_id']}")


def validate_command(candidate_path, review_path, spec_root, capsule, build, build_sha256):
    candidate = load(candidate_path)
    validate_candidate(candidate)
    review = load(review_path) if review_path else None
    if review:
        validate_review(review)
        if review["origin"] != candidate["origin"] or review["original_verdict"] != candidate["origin"]["original_verdict"]:
            fail("ORIGINAL_OUTCOME_CHANGED", "review origin or verdict differs")
        entry = next((entry for entry in review["candidates"] if entry["candidate_id"] == candidate["candidate_id"]), None)
        if entry is None or entry["status"] != candidate["status"]:
            fail("REVIEW_MISMATCH", "candidate status")
        if review["cli_runs_used"] < len(candidate["verification"]):
            fail("CLI_BUDGET", "review run count")
    validate_ready(candidate, review)
    freshness(candidate, spec_root, capsule, build, build_sha256)
    print(f"valid {candidate['candidate_id']} status={candidate['status']} original_verdict={candidate['origin']['original_verdict']}")


def main(argv=None):
    parser = argparse.ArgumentParser(description="Create and verify locator-only healing candidates without applying them")
    sub = parser.add_subparsers(dest="command", required=True)
    create_parser = sub.add_parser("create")
    create_parser.add_argument("--candidate", required=True)
    create_parser.add_argument("--review", required=True)
    select_parser = sub.add_parser("select")
    select_parser.add_argument("--candidate", required=True)
    select_parser.add_argument("--review", required=True)
    verify_parser = sub.add_parser("verify")
    verify_parser.add_argument("--candidate", required=True)
    verify_parser.add_argument("--review", required=True)
    verify_parser.add_argument("--verification", required=True)
    verify_parser.add_argument("--status", required=True, choices=("draft", "rejected", "ready_for_human"))
    verify_parser.add_argument("--spec-root", required=True)
    verify_parser.add_argument("--capsule", required=True)
    verify_parser.add_argument("--build", required=True)
    verify_parser.add_argument("--build-sha256", required=True)
    validate_parser = sub.add_parser("validate")
    validate_parser.add_argument("--candidate", required=True)
    validate_parser.add_argument("--review")
    validate_parser.add_argument("--spec-root")
    validate_parser.add_argument("--capsule")
    validate_parser.add_argument("--build")
    validate_parser.add_argument("--build-sha256")
    args = parser.parse_args(argv)
    try:
        if args.command == "create":
            create(args.candidate, args.review)
        elif args.command == "select":
            select(args.candidate, args.review)
        elif args.command == "verify":
            verify(args.candidate, args.review, args.verification, args.status, args.spec_root, args.capsule, args.build, args.build_sha256)
        else:
            validate_command(args.candidate, args.review, args.spec_root, args.capsule, args.build, args.build_sha256)
        return 0
    except HealingError as exc:
        print(f"{exc.code}: {exc.message}", file=sys.stderr)
        return 3
    except OSError as exc:
        print(f"IO_ERROR: {exc}", file=sys.stderr)
        return 5


if __name__ == "__main__":
    sys.exit(main())

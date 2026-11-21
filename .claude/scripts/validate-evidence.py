#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit
"""Validate schema-v2 evidence and verdict-specific JIRA write permission."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import sys
from datetime import datetime

OUTCOMES = {"pass", "fail", "flaky", "skip", "fixme", "not_run"}
VERDICTS = {"PASS", "FAIL", "BLOCKED", "NEEDS_REVIEW", "NO_TEST"}
TICKET = re.compile(r"^[A-Z][A-Z0-9]+-\d+$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
ARTIFACT_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
ARTIFACT_KINDS = {"screenshot", "log", "trace", "video", "report", "contract", "other"}
ATTEMPT_RESULTS = {"pass", "fail"}


class DuplicateKey(ValueError):
    pass


def unique_object(pairs):
    out = {}
    for key, value in pairs:
        if key in out:
            raise DuplicateKey(f"duplicate JSON key: {key}")
        out[key] = value
    return out


def parse_timestamp(value):
    if not isinstance(value, str) or not value:
        return False
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed.tzinfo is not None


def is_int(value, minimum=None):
    return isinstance(value, int) and not isinstance(value, bool) and (minimum is None or value >= minimum)


def nonempty_string(value):
    return isinstance(value, str) and bool(value.strip())


def string_list(value, unique=False):
    if not isinstance(value, list) or any(not nonempty_string(item) for item in value):
        return False
    return not unique or len(set(value)) == len(value)


def safe_relative(value):
    if not nonempty_string(value) or "\x00" in value:
        return False
    path = pathlib.PurePath(value)
    return not path.is_absolute() and ".." not in path.parts and str(path) not in ("", ".")


def file_hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def unsafe_artifact_name(path_value):
    lower = path_value.lower()
    name = pathlib.PurePath(lower).name
    return bool(
        re.search(r"(^|/)(\.env(\.|$)|id_rsa|id_ed25519|[^/]*(auth|storage)[._-]?state[^/]*$)", lower)
        or re.search(r"secret|credential", lower)
        or re.match(r"cookies?(\.|$)", name)
        or name.endswith((".auth", ".pem", ".p12", ".pfx"))
    )


def validate_artifacts(value, base, errors, label="artifacts", known_coverage=None, require_metadata=True):
    covered = set()
    if not isinstance(value, list):
        errors.append(f"{label} must be an array")
        return covered
    seen_paths = set()
    seen_ids = set()
    known_coverage = known_coverage or set()
    for index, artifact in enumerate(value):
        prefix = f"{label}[{index}]"
        if not isinstance(artifact, dict):
            errors.append(f"{prefix} must be an object")
            continue
        metadata_keys = {"id", "kind", "size_bytes", "covers"}
        full_metadata = require_metadata or bool(metadata_keys & set(artifact))
        artifact_id = artifact.get("id")
        kind = artifact.get("kind")
        covers = artifact.get("covers")
        size_bytes = artifact.get("size_bytes")
        if full_metadata:
            if not isinstance(artifact_id, str) or not ARTIFACT_ID.fullmatch(artifact_id):
                errors.append(f"{prefix}.id must be a bounded safe identifier")
            if kind not in ARTIFACT_KINDS:
                errors.append(f"{prefix}.kind must be a supported artifact kind")
            if not string_list(covers, unique=True) or any(len(item) > 128 for item in covers or []):
                errors.append(f"{prefix}.covers must be an array of unique bounded case/AC ids")
            if not is_int(size_bytes, 0):
                errors.append(f"{prefix}.size_bytes must be a non-negative integer")
        if artifact_id is not None:
            if artifact_id in seen_ids:
                errors.append(f"{prefix}.id duplicates {artifact_id}")
            seen_ids.add(artifact_id)
        if isinstance(covers, list):
            for covered_id in covers:
                if covered_id not in known_coverage:
                    errors.append(f"{prefix}.covers references undeclared case/AC: {covered_id}")
                covered.add(covered_id)
        path_value = artifact.get("path")
        digest = artifact.get("sha256")
        if not safe_relative(path_value) or len(path_value) > 512:
            errors.append(f"{prefix}.path must be a bounded run-relative path without ..")
            continue
        normalized = pathlib.PurePath(path_value).as_posix().rstrip("/")
        if unsafe_artifact_name(normalized):
            errors.append(f"{prefix}.path names forbidden credential/auth-state evidence")
            continue
        if normalized in seen_paths:
            errors.append(f"{prefix}.path duplicates {normalized}")
        seen_paths.add(normalized)
        if not isinstance(digest, str) or not SHA256.fullmatch(digest):
            errors.append(f"{prefix}.sha256 must be 64 lowercase hex characters")
            continue
        base_resolved = base.resolve()
        unresolved = base / pathlib.PurePath(path_value)
        candidate = unresolved.resolve()
        try:
            candidate.relative_to(base_resolved)
        except ValueError:
            errors.append(f"{prefix}.path escapes the run directory")
            continue
        if unresolved.is_symlink() and candidate == base_resolved:
            errors.append(f"{prefix}.path symlink escape is invalid")
            continue
        if not candidate.is_file():
            errors.append(f"{prefix}.path does not name an existing file: {path_value}")
            continue
        try:
            actual_size = candidate.stat().st_size
            actual = file_hash(candidate)
        except OSError as exc:
            errors.append(f"{prefix}.path is unreadable: {exc}")
            continue
        if full_metadata and size_bytes != actual_size:
            errors.append(f"{prefix}.size_bytes does not match {path_value}")
        if actual != digest:
            errors.append(f"{prefix}.sha256 does not match {path_value}")
    return covered


def validate_coverage(value, errors):
    if not isinstance(value, dict):
        errors.append("coverage must be an object")
        return [], []
    required = value.get("required")
    executed = value.get("executed")
    if not string_list(required, unique=True):
        errors.append("coverage.required must be an array of unique non-empty strings")
        required = []
    if not string_list(executed, unique=True):
        errors.append("coverage.executed must be an array of unique non-empty strings")
        executed = []
    return required, executed


def validate_cases(value, errors):
    if not isinstance(value, list):
        errors.append("test_cases must be an array")
        return [], {}
    ids = []
    by_id = {}
    for index, case in enumerate(value):
        prefix = f"test_cases[{index}]"
        if not isinstance(case, dict):
            errors.append(f"{prefix} must be an object")
            continue
        case_id = case.get("id")
        outcome = case.get("outcome")
        attempts = case.get("attempts")
        required = case.get("required", True)
        if not nonempty_string(case_id):
            errors.append(f"{prefix}.id must be a non-empty string")
            continue
        if case_id in by_id:
            errors.append(f"{prefix}.id duplicates {case_id}")
        ids.append(case_id)
        by_id[case_id] = case
        if outcome not in OUTCOMES:
            errors.append(f"{prefix}.outcome is not a normalized outcome")
        if not isinstance(required, bool):
            errors.append(f"{prefix}.required must be a boolean")
        minimum = 0 if outcome in {"skip", "fixme", "not_run"} else 1
        if not is_int(attempts, minimum):
            errors.append(f"{prefix}.attempts must be an integer >= {minimum}")
        if outcome == "pass" and is_int(attempts) and attempts != 1:
            errors.append(f"{prefix}: a retry pass must be normalized to flaky")
        if outcome == "flaky" and is_int(attempts) and attempts < 2:
            errors.append(f"{prefix}: flaky requires at least two attempts")
        if outcome in {"skip", "not_run"} and attempts != 0:
            errors.append(f"{prefix}: {outcome} requires attempts=0")
        if "attempt_results" in case:
            attempt_results = case.get("attempt_results")
            if not isinstance(attempt_results, list) or any(item not in ATTEMPT_RESULTS for item in attempt_results):
                errors.append(f"{prefix}.attempt_results must contain only pass/fail")
                attempt_results = []
            if is_int(attempts) and len(attempt_results) != attempts:
                errors.append(f"{prefix}.attempt_results length must equal started attempts")
            if outcome == "pass" and attempt_results != ["pass"]:
                errors.append(f"{prefix}: pass requires attempt_results=[pass]")
            elif outcome == "fail" and (not attempt_results or attempt_results[-1] != "fail"):
                errors.append(f"{prefix}: fail requires a final failed attempt")
            elif outcome == "flaky" and (
                len(attempt_results) < 2 or attempt_results[-1] != "pass" or "fail" not in attempt_results[:-1]
            ):
                errors.append(f"{prefix}: flaky requires an earlier fail and final pass")
            elif outcome in {"skip", "not_run"} and attempt_results:
                errors.append(f"{prefix}: {outcome} requires empty attempt_results")
        for key in ("spec", "assertion"):
            if key in case and not isinstance(case[key], str):
                errors.append(f"{prefix}.{key} must be a string")
    return ids, by_id


def validate_case_coverage(data, path, errors):
    ids, by_id = validate_cases(data.get("test_cases"), errors)
    required_coverage, executed_coverage = validate_coverage(data.get("coverage"), errors)
    if ids:
        required_cases = {case_id for case_id in ids if by_id[case_id].get("required", True) is True}
        executed_cases = {case_id for case_id in ids if by_id[case_id].get("outcome") in {"pass", "fail", "flaky"}}
        if set(required_coverage) & set(ids) != required_cases:
            errors.append("coverage.required must include every required test case and no optional case")
        if set(executed_coverage) & set(ids) != executed_cases:
            errors.append("coverage.executed must include exactly started pass/fail/flaky cases")
    return by_id, required_coverage, executed_coverage


def validate_path_binding(data, path, qa_home, errors):
    evidence_dir = data.get("evidence_dir")
    if not safe_relative(evidence_dir):
        errors.append("evidence_dir must be a relative path without ..")
        return
    if qa_home is None:
        return
    root = pathlib.Path(qa_home).resolve()
    expected = (root / pathlib.PurePath(evidence_dir)).resolve()
    actual = path.parent.resolve()
    if expected != actual:
        errors.append("evidence_dir does not match the summary/run-record location")
    try:
        relative = actual.relative_to(root / "evidence")
    except ValueError:
        errors.append("evidence must be inside <qa-home>/evidence")
        return
    parts = relative.parts
    ticket = data.get("ticket")
    project = data.get("project")
    if len(parts) != 3 or parts[0] != project or parts[1] != ticket:
        errors.append("evidence path must be evidence/<project>/<ticket>/<run>")
    run_id = data.get("run_id")
    if run_id is not None and run_id != path.parent.name:
        errors.append("run_id does not match the evidence run directory")


def validate_learnings(value, errors):
    if not isinstance(value, dict):
        errors.append("learnings must be an object")
        return
    captured = value.get("captured")
    none_because = value.get("none_because")
    has_captured = string_list(captured) and bool(captured)
    has_none = nonempty_string(none_because)
    if not string_list(captured):
        errors.append("learnings.captured must be an array of non-empty strings")
    if none_because is not None and not isinstance(none_because, str):
        errors.append("learnings.none_because must be a string or null")
    if has_captured == has_none:
        errors.append("learnings requires exactly one of non-empty captured or none_because")


def validate_verdict(data, by_id, required, executed, artifact_coverage, errors):
    verdict = data.get("verdict")
    outcomes = [case.get("outcome") for case in by_id.values()]
    required_outcomes = [by_id[case_id].get("outcome") for case_id in required if case_id in by_id]
    findings = data.get("findings")
    if not isinstance(findings, list) or any(not isinstance(item, dict) for item in findings):
        errors.append("findings must be an array of objects")
        findings = []
    artifacts = data.get("artifacts")
    steps = data.get("steps_executed")
    if verdict == "PASS":
        if not executed and not steps:
            errors.append("PASS requires executed coverage or executed exploratory steps")
        if set(required) - set(executed):
            errors.append("PASS requires complete required coverage")
        if any(outcome != "pass" for outcome in required_outcomes):
            errors.append("PASS requires every required case to have a clean pass")
        if any(outcome in {"fail", "flaky"} for outcome in outcomes):
            errors.append("PASS cannot contain failed or retry-passed cases")
        if findings:
            errors.append("PASS requires findings to be empty")
        if not artifacts:
            errors.append("PASS requires at least one hashed artifact")
        if set(required) - artifact_coverage:
            errors.append("PASS requires artifact proof covering every required case/AC")
    elif verdict == "FAIL":
        if "fail" not in outcomes and not findings:
            errors.append("FAIL requires a failed case or a finding")
    elif verdict == "BLOCKED":
        if not nonempty_string(data.get("blocked_reason")):
            errors.append("BLOCKED requires blocked_reason")
        if "fail" in outcomes or findings:
            errors.append("BLOCKED is invalid when a definitive failure exists")
    elif verdict == "NEEDS_REVIEW":
        if data.get("interactive") is not True:
            errors.append("NEEDS_REVIEW requires interactive=true")
    elif verdict == "NO_TEST":
        if not nonempty_string(data.get("no_test_reason")):
            errors.append("NO_TEST requires no_test_reason")
        if executed or any(outcome != "not_run" for outcome in outcomes):
            errors.append("NO_TEST cannot contain executed cases")
        if findings or artifacts:
            errors.append("NO_TEST requires empty findings and artifacts")
        if data.get("reported_to_jira") is True:
            errors.append("NO_TEST cannot set reported_to_jira=true")


def validate_summary(data, path, qa_home):
    errors = []
    if not isinstance(data, dict):
        return ["summary must be a JSON object"], None
    if not is_int(data.get("schema_version")) or data.get("schema_version") != 2:
        errors.append("new summaries require schema_version=2")
    ticket = data.get("ticket")
    project = data.get("project")
    verdict = data.get("verdict")
    if not isinstance(ticket, str) or not TICKET.fullmatch(ticket):
        errors.append("ticket must be a JIRA key")
    if not nonempty_string(project) or (isinstance(ticket, str) and ticket.split("-", 1)[0] != project):
        errors.append("project must match the ticket prefix")
    if not parse_timestamp(data.get("timestamp")):
        errors.append("timestamp must be RFC3339 with a timezone")
    if verdict not in VERDICTS:
        errors.append("verdict is invalid")
    validate_learnings(data.get("learnings"), errors)
    validate_path_binding(data, path, qa_home, errors)
    if not string_list(data.get("steps_executed")):
        errors.append("steps_executed must be an array of strings")
    if "reported_to_jira" in data and not isinstance(data.get("reported_to_jira"), bool):
        errors.append("reported_to_jira must be a boolean")
    if verdict != "NO_TEST":
        if data.get("test_type") not in {"exploratory", "regression", "mixed"}:
            errors.append("test_type is invalid")
        if data.get("mode") not in {"mcp-only", "hybrid", "cli-first"}:
            errors.append("mode is invalid")
        environment = data.get("environment")
        if not isinstance(environment, dict):
            errors.append("environment must be an object")
        else:
            for key in ("name", "version_or_build", "commit"):
                if not nonempty_string(environment.get(key)):
                    errors.append(f"environment.{key} must be a non-empty string")
        deploy = data.get("deploy")
        if not isinstance(deploy, dict):
            errors.append("deploy must be an object")
        else:
            for key in ("from_version", "to_version", "pipeline_run", "at"):
                if not nonempty_string(deploy.get(key)):
                    errors.append(f"deploy.{key} must be a non-empty string")
        if not string_list(data.get("skills_used")):
            errors.append("skills_used must be an array of strings")
        for key in ("reported_to_jira", "shadow"):
            if not isinstance(data.get(key), bool):
                errors.append(f"{key} must be a boolean")
    channel = data.get("channel")
    if channel is not None and channel not in {"browser", "api", "mixed"}:
        errors.append("channel must be browser, api, or mixed")
    by_id, required, executed = validate_case_coverage(data, path, errors)
    known_coverage = set(required) | set(executed) | set(by_id)
    require_metadata = bool(channel or by_id or required or executed or data.get("test_type") != "exploratory")
    artifact_coverage = validate_artifacts(
        data.get("artifacts"), path.parent, errors,
        known_coverage=known_coverage, require_metadata=require_metadata,
    )
    validate_verdict(data, by_id, required, executed, artifact_coverage, errors)
    return errors, verdict


def validate_run_record(data, path, qa_home):
    errors = []
    if not isinstance(data, dict):
        return ["run record must be a JSON object"]
    if not is_int(data.get("schema_version")) or data.get("schema_version") != 2:
        errors.append("run records require schema_version=2")
    ticket = data.get("ticket")
    if not isinstance(ticket, str) or not TICKET.fullmatch(ticket):
        errors.append("ticket must be a JIRA key")
    if not nonempty_string(data.get("project")) or (isinstance(ticket, str) and ticket.split("-", 1)[0] != data.get("project")):
        errors.append("project must match the ticket prefix")
    if not parse_timestamp(data.get("timestamp")):
        errors.append("timestamp must be RFC3339 with a timezone")
    if not nonempty_string(data.get("run_id")):
        errors.append("run_id must be a non-empty string")
    validate_path_binding(data, path, qa_home, errors)
    source = data.get("source")
    if not isinstance(source, dict) or source.get("format") not in {"junit", "playwright"} or not nonempty_string(source.get("path")):
        errors.append("source must contain format=junit|playwright and path")
    elif not isinstance(source.get("sha256"), str) or not SHA256.fullmatch(source.get("sha256")):
        errors.append("source.sha256 must be 64 lowercase hex characters")
    else:
        source_path = pathlib.Path(source["path"])
        if not source_path.is_absolute():
            source_path = path.parent / source_path
        if not source_path.is_file():
            errors.append("source.path does not name an existing result file")
        elif file_hash(source_path) != source["sha256"]:
            errors.append("source.sha256 does not match the exact input bytes")
    channel = data.get("channel")
    if channel is not None and channel not in {"browser", "api", "mixed"}:
        errors.append("channel must be browser, api, or mixed")
    by_id, required, executed = validate_case_coverage(data, path, errors)
    known_coverage = set(required) | set(executed) | set(by_id)
    validate_artifacts(
        data.get("artifacts"), path.parent, errors,
        known_coverage=known_coverage,
        require_metadata=bool(channel or by_id or required or executed or data.get("artifacts")),
    )
    return errors


def validate_file(filename, qa_home=None, kind="auto"):
    path = pathlib.Path(filename).resolve()
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = json.load(handle, object_pairs_hook=unique_object)
    except Exception as exc:
        return {"valid": False, "path": str(path), "errors": [f"malformed JSON: {exc}"], "verdict": None}
    if kind == "auto":
        kind = "summary" if path.name == "execution_summary.json" or (isinstance(data, dict) and "verdict" in data) else "run-record"
    if kind == "summary":
        errors, verdict = validate_summary(data, path, pathlib.Path(qa_home).resolve() if qa_home else None)
    else:
        errors, verdict = validate_run_record(data, path, pathlib.Path(qa_home).resolve() if qa_home else None), None
    return {"valid": not errors, "path": str(path), "kind": kind, "errors": errors, "verdict": verdict}


def validate_jira_write(result, tool):
    errors = list(result["errors"])
    verdict = result.get("verdict")
    if verdict == "NO_TEST":
        errors.append("NO_TEST forbids every JIRA write")
    if verdict == "NEEDS_REVIEW" and re.search(r"transition|create[_A-Za-z]*(?:issue|bug)", tool or "", re.IGNORECASE):
        errors.append("NEEDS_REVIEW forbids transitions and bug creation")
    result = dict(result)
    result["errors"] = errors
    result["valid"] = not errors
    result["jira_write"] = tool
    return result


def latest_ticket_summary(qa_home, ticket):
    if not isinstance(ticket, str) or not TICKET.fullmatch(ticket):
        return None
    directory = pathlib.Path(qa_home).resolve() / "evidence" / ticket.split("-", 1)[0] / ticket
    candidates = []
    try:
        for path in directory.rglob("execution_summary.json"):
            try:
                candidates.append((path.stat().st_mtime_ns, str(path), path))
            except OSError:
                continue
    except OSError:
        return None
    return max(candidates)[2] if candidates else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", help="execution_summary.json or run.json")
    parser.add_argument("--kind", choices=("auto", "summary", "run-record"), default="auto")
    parser.add_argument("--qa-home", help="QA home used for evidence path binding")
    parser.add_argument("--jira-ticket", help="validate the freshest summary for this ticket")
    parser.add_argument("--jira-write", help="also enforce verdict-specific JIRA write rules")
    parser.add_argument("--json", action="store_true", help="emit a stable JSON result")
    args = parser.parse_args()
    if bool(args.path) == bool(args.jira_ticket):
        parser.error("provide exactly one path or --jira-ticket")
    if args.jira_ticket and not args.qa_home:
        parser.error("--jira-ticket requires --qa-home")
    if args.jira_ticket:
        path = latest_ticket_summary(args.qa_home, args.jira_ticket)
        if path is None:
            result = {"valid": True, "path": None, "kind": "summary", "errors": [], "verdict": None}
        else:
            result = validate_file(path, args.qa_home, "summary")
    else:
        result = validate_file(args.path, args.qa_home, args.kind)
    if args.jira_write:
        result = validate_jira_write(result, args.jira_write)
    if args.json:
        print(json.dumps(result, sort_keys=True))
    elif result["valid"]:
        print(f"valid: {result.get('path') or args.jira_ticket}")
    else:
        for error in result["errors"]:
            print(error, file=sys.stderr)
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    sys.exit(main())

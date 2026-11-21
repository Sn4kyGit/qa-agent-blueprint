#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit
"""Normalize JUnit XML or Playwright JSON into a schema-v2 run record."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

OUTCOMES = {"pass", "fail", "flaky", "skip", "fixme", "not_run"}


def sha256_bytes(value):
    return hashlib.sha256(value).hexdigest()


def parse_time(value):
    if not isinstance(value, str) or not value:
        raise ValueError("timestamp must be RFC3339 with a timezone")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp must include a timezone")
    return parsed


def default_run_id(timestamp):
    return parse_time(timestamp).astimezone(timezone.utc).strftime("%Y%m%d-%H%M%S")


def case_id(value):
    text = re.sub(r"\s+", " ", str(value or "")).strip()
    if not text:
        raise ValueError("runner result contains a test without an id or name")
    return text


def empty_case(identifier, required):
    return {"id": identifier, "outcome": "not_run", "attempts": 0, "attempt_results": [], "required": required}


def finalize_case(identifier, observations, required, fixme=False):
    if not observations:
        if fixme:
            return {"id": identifier, "outcome": "fixme", "attempts": 0, "attempt_results": [], "required": required}
        return empty_case(identifier, required)
    started = [item for item in observations if item in {"pass", "fail"}]
    final = observations[-1]
    if fixme:
        outcome = "fixme"
    elif final == "skip":
        if started:
            raise ValueError(f"non-executed final status follows started attempts for {identifier}")
        outcome = "skip"
    elif final == "fail":
        outcome = "fail"
    elif final == "pass":
        if "fail" in started[:-1]:
            outcome = "flaky"
        elif started == ["pass"]:
            outcome = "pass"
        else:
            raise ValueError(f"final pass without exactly one clean start or an earlier failure for {identifier}")
    else:
        raise ValueError(f"cannot normalize outcome {final!r} for {identifier}")
    attempts = 0 if outcome == "skip" else len(started)
    attempt_results = [] if outcome == "skip" else started
    return {
        "id": identifier,
        "outcome": outcome,
        "attempts": attempts,
        "attempt_results": attempt_results,
        "required": required,
    }


def parse_junit(raw):
    root = ET.fromstring(raw)
    if root.tag.split("}")[-1] not in {"testsuite", "testsuites"}:
        raise ValueError("JUnit input must have a testsuite or testsuites root")
    observations = {}
    order = []
    fixme_ids = set()
    for element in root.iter():
        if element.tag.split("}")[-1] != "testcase":
            continue
        identifier = case_id(element.get("id") or element.get("name") or element.get("classname"))
        if identifier not in observations:
            observations[identifier] = []
            order.append(identifier)
        skipped = next((child for child in element if child.tag.split("}")[-1] == "skipped"), None)
        failed = any(child.tag.split("}")[-1] in {"failure", "error"} for child in element)
        if skipped is not None:
            label = f"{skipped.get('type', '')} {skipped.get('message', '')}".lower()
            outcome = "skip"
            if "fixme" in label:
                fixme_ids.add(identifier)
        elif failed:
            outcome = "fail"
        else:
            outcome = "pass"
        observations[identifier].append(outcome)
    return order, observations, fixme_ids


def playwright_status(status):
    mapping = {
        "passed": "pass",
        "expected": "pass",
        "failed": "fail",
        "unexpected": "fail",
        "timedout": "fail",
        "interrupted": "fail",
        "skipped": "skip",
        "fixme": "fixme",
    }
    normalized = str(status or "").lower()
    if normalized not in mapping:
        raise ValueError(f"unsupported Playwright status: {status!r}")
    return mapping[normalized]


def parse_playwright(raw):
    data = json.loads(raw)
    observations = {}
    order = []
    fixme_ids = set()

    def add(identifier, outcome):
        identifier = case_id(identifier)
        if identifier not in observations:
            observations[identifier] = []
            order.append(identifier)
        observations[identifier].append(outcome)

    def walk_suite(suite):
        for spec in suite.get("specs") or []:
            if not isinstance(spec, dict):
                continue
            identifier = spec.get("id") or spec.get("title")
            tests = spec.get("tests") or []
            if not tests:
                add(identifier, playwright_status(spec.get("status") or ("pass" if spec.get("ok") else "fail")))
            for test in tests:
                if not isinstance(test, dict):
                    continue
                annotations = test.get("annotations") or spec.get("annotations") or []
                fixme = any(isinstance(item, dict) and str(item.get("type", "")).lower() == "fixme" for item in annotations)
                results = test.get("results") or []
                if fixme:
                    fixme_ids.add(identifier)
                if fixme and not results:
                    add(identifier, "skip")
                    continue
                for result in results:
                    if isinstance(result, dict):
                        add(identifier, playwright_status(result.get("status")))
                if not results:
                    add(identifier, playwright_status(test.get("status") or test.get("outcome") or spec.get("status")))
        for child in suite.get("suites") or []:
            if isinstance(child, dict):
                walk_suite(child)

    suites = data.get("suites") if isinstance(data, dict) else None
    if not isinstance(suites, list):
        raise ValueError("Playwright input must contain a suites array")
    for suite in suites:
        if isinstance(suite, dict):
            walk_suite(suite)
    return order, observations, fixme_ids


def normalize(args):
    source = pathlib.Path(args.input).resolve()
    raw = source.read_bytes()
    input_format = args.format
    if input_format == "auto":
        stripped = raw.lstrip()
        input_format = "junit" if stripped.startswith(b"<") else "playwright"
    if input_format == "junit":
        order, observations, fixme_ids = parse_junit(raw)
    else:
        order, observations, fixme_ids = parse_playwright(raw)
    required = []
    for value in args.require or []:
        for identifier in value.split(","):
            identifier = identifier.strip()
            if identifier and identifier not in required:
                required.append(identifier)
    if not required:
        required = list(order)
    for identifier in required:
        if identifier not in observations:
            order.append(identifier)
            observations[identifier] = []
    cases = [
        finalize_case(identifier, observations.get(identifier, []), identifier in required, identifier in fixme_ids)
        for identifier in order
    ]
    timestamp = args.timestamp
    parse_time(timestamp)
    ticket = args.ticket.upper()
    project = args.project or ticket.split("-", 1)[0]
    if not re.fullmatch(r"[A-Z][A-Z0-9]+-\d+", ticket) or project != ticket.split("-", 1)[0]:
        raise ValueError("ticket/project must be a matching JIRA key and prefix")
    run_id = args.run_id or default_run_id(timestamp)
    output = pathlib.Path(args.output).resolve()
    evidence_dir = args.evidence_dir
    if evidence_dir is None:
        try:
            evidence_dir = output.parent.relative_to(args.qa_home.resolve()).as_posix()
        except (ValueError, AttributeError):
            evidence_dir = f"evidence/{project}/{ticket}/{run_id}"
    record = {
        "schema_version": 2,
        "run_id": run_id,
        "ticket": ticket,
        "project": project,
        "timestamp": timestamp,
        "evidence_dir": evidence_dir.rstrip("/"),
        "source": {"format": input_format, "path": str(source), "sha256": sha256_bytes(raw)},
        "test_cases": cases,
        "coverage": {
            "required": required,
            "executed": [case["id"] for case in cases if case["outcome"] in {"pass", "fail", "flaky"}],
        },
        "artifacts": [],
    }
    if args.duration_s is not None:
        if args.duration_s < 0:
            raise ValueError("duration_s must be non-negative")
        record["duration_s"] = args.duration_s
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input", help="JUnit XML or Playwright JSON result file")
    parser.add_argument("-o", "--output", required=True, help="destination run.json")
    parser.add_argument("--format", choices=("auto", "junit", "playwright"), default="auto")
    parser.add_argument("--ticket", required=True)
    parser.add_argument("--project")
    parser.add_argument("--timestamp", required=True)
    parser.add_argument("--run-id")
    parser.add_argument("--evidence-dir")
    parser.add_argument("--qa-home", type=pathlib.Path)
    parser.add_argument("--require", action="append", help="required case id or comma-separated ids; repeatable")
    parser.add_argument("--duration-s", type=float)
    args = parser.parse_args()
    try:
        record = normalize(args)
        output = pathlib.Path(args.output)
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(json.dumps(record, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except Exception as exc:
        print(f"normalize-test-results: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

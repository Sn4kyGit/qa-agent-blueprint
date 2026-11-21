#!/usr/bin/env python3
# SPDX-License-Identifier: MIT AND Apache-2.0
# Copyright (c) 2026 Ivan Davidov and Agentic Playwright contributors
# Copyright (c) 2026 Sn4kyGit and qa-agent-blueprint contributors
import argparse
import contextlib
import copy
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile
from datetime import datetime, timezone

EVENT_SCHEMA = "qa-action-journal-event/v1"
INDEX_SCHEMA = "qa-action-journal-index/v1"
HANDOFF_SCHEMA = "qa-automation-handoff/v1"
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$")
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
EVENT_RE = re.compile(r"^evt-([0-9]{8})$")
SECRET_RE = re.compile(r"(?:SECRET|TOKEN|PASSWORD)[_-]?CANARY|CANARY[_-]?(?:SECRET|TOKEN|PASSWORD)", re.I)
FORBIDDEN_KEYS = {"ref", "element_ref", "mcp_ref", "snapshot", "snapshot_ref", "raw_log", "console_log", "network_log", "password", "token", "secret", "headers"}
MAX_EVENT_BYTES = 16384
MAX_CASE_EVENTS = 200
MAX_STREAM_EVENTS = 2000


class JournalError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = message if code is None else code
        self.message = message


def fail(code, message):
    raise JournalError(code, message)


def now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail("INVALID_JSON", f"duplicate key {key}")
        result[key] = value
    return result


def load_json(path):
    try:
        raw = Path(path).read_bytes()
        return json.loads(raw.decode("utf-8"), object_pairs_hook=duplicates, parse_constant=lambda value: fail("INVALID_JSON", value))
    except JournalError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        fail("INVALID_JSON", f"cannot load {path}: {exc}")


def read_jsonl(path):
    events = []
    try:
        raw = Path(path).read_bytes()
    except OSError as exc:
        fail("IO_ERROR", str(exc))
    if raw and not raw.endswith(b"\n"):
        fail("TRUNCATED_SHARD", f"{path} has no final newline")
    for number, line in enumerate(raw.splitlines(), 1):
        if not line:
            fail("INVALID_SHARD", f"blank line at {path}:{number}")
        try:
            events.append(json.loads(line.decode("utf-8"), object_pairs_hook=duplicates, parse_constant=lambda value: fail("INVALID_JSON", value)))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            fail("INVALID_SHARD", f"{path}:{number}: {exc}")
    return events


def exact(value, required, optional, label):
    if not isinstance(value, dict):
        fail("INVALID_STRUCTURE", f"{label} must be an object")
    missing = set(required) - set(value)
    extra = set(value) - set(required) - set(optional)
    if missing or extra:
        fail("INVALID_STRUCTURE", f"{label} missing={sorted(missing)} unknown={sorted(extra)}")


def text(value, label, limit=1000):
    if not isinstance(value, str) or not value or len(value) > limit:
        fail("INVALID_STRUCTURE", f"{label} must be a non-empty string of at most {limit} characters")
    if SECRET_RE.search(value):
        fail("SECRET_CANARY", label)
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


def boolean(value, label):
    if not isinstance(value, bool):
        fail("INVALID_STRUCTURE", label)
    return value


def safe_path(value, label):
    text(value, label, 300)
    if "\\" in value or value.startswith("/"):
        fail("UNSAFE_PATH", label)
    path = PurePosixPath(value)
    if str(path) != value or any(part in ("", ".", "..") for part in path.parts):
        fail("UNSAFE_PATH", label)
    return value


def scan_curated(value, label="$"):
    if isinstance(value, dict):
        for key, child in value.items():
            normalized = key.lower().replace("-", "_")
            if normalized in FORBIDDEN_KEYS:
                fail("UNCURATED_FIELD", f"{label}.{key}")
            if normalized == "path" or normalized.endswith("_path"):
                safe_path(child, f"{label}.{key}")
            scan_curated(child, f"{label}.{key}")
    elif isinstance(value, list):
        if len(value) > 100:
            fail("UNBOUNDED_DATA", label)
        for index, child in enumerate(value):
            scan_curated(child, f"{label}[{index}]")
    elif isinstance(value, str):
        text(value, label, 4000)
        if "../" in value or "..\\" in value:
            fail("TRAVERSAL_PATH", label)


def locator(value, label="locator"):
    exact(value, {"strategy", "value", "expression"}, {"name", "exact"}, label)
    if value["strategy"] not in ("role", "label", "text", "test_id", "placeholder", "title", "alt"):
        fail("NON_SEMANTIC_LOCATOR", label)
    text(value["value"], label + ".value", 300)
    text(value["expression"], label + ".expression", 500)
    if "name" in value:
        text(value["name"], label + ".name", 300)
    if value["strategy"] == "role" and "name" not in value:
        fail("INVALID_LOCATOR", "role locator needs accessible name")
    if "exact" in value:
        boolean(value["exact"], label + ".exact")
    return copy.deepcopy(value)


def seed(value):
    exact(value, {"start_url", "state", "fixtures"}, set(), "seed")
    text(value["start_url"], "seed.start_url", 1000)
    if not value["start_url"].startswith(("https://", "http://", "/")) or value["start_url"].startswith("//"):
        fail("INVALID_SEED", "start_url must be HTTP(S) or an application-relative path")
    text(value["state"], "seed.state", 1000)
    if not isinstance(value["fixtures"], list) or not value["fixtures"]:
        fail("INVALID_SEED", "seed.fixtures must be a non-empty array")
    for item in value["fixtures"]:
        text(item, "seed.fixtures[]", 200)
    return copy.deepcopy(value)


def validate_payload(event, stored=False):
    kind = event["type"]
    payload = event["payload"]
    if kind == "stream_start":
        exact(payload, {"framework", "seed", "build", "capsule_sha256"}, set(), "stream_start")
        if payload["framework"] not in ("playwright", "webdriverio"):
            fail("INVALID_FRAMEWORK", "framework")
        seed(payload["seed"])
        text(payload["build"], "build", 200)
        sha(payload["capsule_sha256"], "capsule_sha256")
        if event["case_id"] is not None:
            fail("CASE_BOUNDARY", "stream_start has no case")
    elif kind == "case_start":
        exact(payload, {"title", "ac_id", "ac_sha256", "tc_id", "tc_sha256", "intent", "intent_sha256"}, set(), "case_start")
        for key in ("title", "ac_id", "tc_id"):
            text(payload[key], key, 300)
        text(payload["intent"], "intent", 2000)
        for key in ("ac_sha256", "tc_sha256", "intent_sha256"):
            sha(payload[key], key)
        if hashlib.sha256(payload["intent"].encode("utf-8")).hexdigest() != payload["intent_sha256"]:
            fail("INTENT_MISMATCH", "intent_sha256 must hash the literal UTF-8 intent")
        require_case(event)
    elif kind == "action":
        exact(payload, {"action"}, {"locator", "url", "value", "input_ref"}, "action")
        if payload["action"] not in ("navigate", "click", "fill", "select", "check", "uncheck", "press", "wait_for"):
            fail("INVALID_ACTION", payload["action"])
        if payload["action"] == "navigate":
            if set(payload) != {"action", "url"}:
                fail("INVALID_ACTION", "navigate requires only url")
            text(payload["url"], "action.url", 1000)
            if not payload["url"].startswith(("https://", "http://", "/")) or payload["url"].startswith("//"):
                fail("INVALID_ACTION", "navigate url")
        else:
            if "locator" not in payload:
                fail("MISSING_LOCATOR", "action")
            locator(payload["locator"])
            if "url" in payload:
                fail("INVALID_ACTION", "url only belongs to navigate")
            if "value" in payload and "input_ref" in payload:
                fail("INVALID_ACTION", "use value or input_ref, not both")
            if "input_ref" in payload and not re.fullmatch(r"[A-Z][A-Z0-9_]*", payload["input_ref"]):
                fail("INVALID_ACTION", "input_ref must name an environment variable")
            if "value" in payload:
                text(payload["value"], "action.value", 1000)
        require_case(event)
    elif kind == "assertion":
        exact(payload, {"ac_id", "ac_sha256", "intent_sha256", "assertion_sha256", "oracle", "locator", "expected", "outcome"}, set(), "assertion")
        text(payload["ac_id"], "ac_id", 300)
        for key in ("ac_sha256", "intent_sha256", "assertion_sha256"):
            sha(payload[key], key)
        if payload["oracle"] not in ("positive", "negative_control", "observation"):
            fail("INVALID_ORACLE", "oracle")
        locator(payload["locator"])
        text(payload["expected"], "expected", 1000)
        if payload["outcome"] not in ("passed", "failed", "observed"):
            fail("INVALID_OUTCOME", "assertion outcome")
        require_case(event)
    elif kind == "red_check":
        exact(payload, {"assertion_event_id", "outcome", "method"}, set(), "red_check")
        text(payload["assertion_event_id"], "assertion_event_id", 80)
        if payload["outcome"] not in ("failed", "passed"):
            fail("INVALID_RED_CHECK", "outcome")
        if payload["method"] not in ("data_state", "assertion_inversion"):
            fail("INVALID_RED_CHECK", "method")
        require_case(event)
    elif kind == "case_end":
        exact(payload, {"status", "replayable", "original_verdict"}, set(), "case_end")
        if payload["status"] not in ("complete", "incomplete"):
            fail("INVALID_CASE_STATUS", "status")
        boolean(payload["replayable"], "replayable")
        if payload["status"] == "complete" and not payload["replayable"]:
            fail("NOT_REPLAYABLE", "complete cases must be replayable")
        if payload["status"] == "incomplete" and payload["replayable"]:
            fail("INVALID_CASE_STATUS", "incomplete cases cannot be replayable")
        if payload["original_verdict"] not in ("PASS", "FAIL", "BLOCKED", "NEEDS_REVIEW"):
            fail("INVALID_VERDICT", "original_verdict")
        require_case(event)
    elif kind == "stream_end":
        exact(payload, set(), set(), "stream_end")
        if event["case_id"] is not None:
            fail("CASE_BOUNDARY", "stream_end has no case")
    else:
        fail("UNKNOWN_EVENT", kind)
    if stored:
        encoded = json.dumps(event, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        if len(encoded) > MAX_EVENT_BYTES:
            fail("EVENT_TOO_LARGE", str(len(encoded)))


def require_case(event):
    if event["case_id"] is None:
        fail("CASE_BOUNDARY", f"{event['type']} requires case_id")
    identifier(event["case_id"], "case_id")


def validate_event(event, stored=False):
    required = {"schema_version", "stream_id", "case_id", "type", "recorded_at", "payload"}
    optional = {"seq", "event_id"} if not stored else set()
    exact(event, required | ({"seq", "event_id"} if stored else set()), optional, "event")
    if not stored and ("seq" in event or "event_id" in event):
        fail("WRITER_FIELD", "seq and event_id are assigned by append")
    if event["schema_version"] != EVENT_SCHEMA:
        fail("WRONG_SCHEMA", "event schema_version")
    identifier(event["stream_id"], "stream_id")
    if event["case_id"] is not None:
        identifier(event["case_id"], "case_id")
    text(event["type"], "type", 40)
    text(event["recorded_at"], "recorded_at", 40)
    scan_curated(event)
    validate_payload(event, stored)


def paths(root, stream, case=None):
    base = root / "streams" / stream
    return base / "stream.jsonl" if case is None else base / "cases" / f"{case}.jsonl"


def empty_index(journal_id):
    timestamp = now()
    return {"schema_version": INDEX_SCHEMA, "journal_id": journal_id, "created_at": timestamp, "updated_at": timestamp, "next_seq": 1, "next_event": 1, "status": "open", "streams": {}}


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=".journal-", dir=path.parent)
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


@contextlib.contextmanager
def locked(root):
    root.mkdir(parents=True, exist_ok=True)
    with (root / ".writer.lock").open("a+") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def all_events(root):
    result = []
    for path in sorted((root / "streams").glob("**/*.jsonl")):
        for event in read_jsonl(path):
            validate_event(event, True)
            result.append((path, event))
    result.sort(key=lambda item: item[1]["seq"])
    return result


def case_ready(events, require_pass=False):
    if not events or events[0]["type"] != "case_start" or events[-1]["type"] != "case_end":
        return False
    end = events[-1]["payload"]
    if end["status"] != "complete" or not end["replayable"]:
        return False
    if require_pass and end["original_verdict"] != "PASS":
        return False
    start = events[0]["payload"]
    positives = [event for event in events if event["type"] == "assertion" and event["payload"]["oracle"] == "positive" and event["payload"]["outcome"] == "passed"]
    checks = [event for event in events if event["type"] == "red_check" and event["payload"]["outcome"] == "failed"]
    for assertion in positives:
        payload = assertion["payload"]
        if payload["ac_id"] != start["ac_id"] or payload["ac_sha256"] != start["ac_sha256"] or payload["intent_sha256"] != start["intent_sha256"]:
            return False
        if not any(check["payload"]["assertion_event_id"] == assertion["event_id"] for check in checks):
            return False
    return bool(positives)


def validate_journal(root):
    index_path = root / "index.json"
    index = load_json(index_path)
    exact(index, {"schema_version", "journal_id", "created_at", "updated_at", "next_seq", "next_event", "status", "streams"}, set(), "index")
    if index["schema_version"] != INDEX_SCHEMA or index["status"] not in ("open", "finalized"):
        fail("INVALID_INDEX", "schema or status")
    identifier(index["journal_id"], "journal_id")
    events = all_events(root)
    previous = 0
    seen_streams = {}
    case_events = {}
    positive_by_id = {}
    red_targets = set()
    for path, event in events:
        if event["seq"] != previous + 1 or event["event_id"] != f"evt-{event['seq']:08d}":
            fail("NON_MONOTONIC", f"{event['event_id']} seq={event['seq']}")
        previous = event["seq"]
        stream = event["stream_id"]
        case = event["case_id"]
        state = seen_streams.setdefault(stream, {"start": None, "end": None, "cases": {}})
        if state["end"] is not None:
            fail("FINALIZED_APPEND", stream)
        if event["type"] == "stream_start":
            if state["start"] is not None or event["seq"] != 1 and stream not in {item[1]["stream_id"] for item in events[:previous-1]}:
                fail("STREAM_BOUNDARY", stream)
            state["start"] = event
        elif state["start"] is None:
            fail("STREAM_BOUNDARY", f"{stream} has no stream_start")
        if event["type"] == "stream_end":
            state["end"] = event
            continue
        if case is not None:
            history = state["cases"].setdefault(case, [])
            if history and history[-1]["type"] == "case_end":
                fail("CASE_BOUNDARY", f"{stream}/{case} already ended")
            if event["type"] == "case_start":
                if history:
                    fail("CASE_BOUNDARY", f"duplicate case_start {case}")
            elif not history:
                fail("CASE_BOUNDARY", f"{case} must start with case_start")
            history.append(event)
            case_events[(stream, case)] = history
            if len(history) > MAX_CASE_EVENTS:
                fail("CASE_BUDGET", case)
            if event["type"] == "assertion":
                if event["payload"]["oracle"] == "positive":
                    positive_by_id[event["event_id"]] = event
            if event["type"] == "red_check":
                target = event["payload"]["assertion_event_id"]
                if target in red_targets or target not in positive_by_id:
                    fail("INVALID_RED_CHECK", f"unknown or duplicate target {target}")
                assertion = positive_by_id[target]
                if assertion["stream_id"] != stream or assertion["case_id"] != case:
                    fail("INVALID_RED_CHECK", "red check crosses case boundary")
                red_targets.add(target)
        if len([item for item in events if item[1]["stream_id"] == stream]) > MAX_STREAM_EVENTS:
            fail("STREAM_BUDGET", stream)
    for (stream, case), history in case_events.items():
        start = history[0]["payload"]
        for event in history[1:]:
            payload = event["payload"]
            if event["type"] == "assertion":
                if payload["ac_id"] != start["ac_id"] or payload["ac_sha256"] != start["ac_sha256"] or payload["intent_sha256"] != start["intent_sha256"]:
                    fail("CONTRACT_MISMATCH", f"{stream}/{case}")
        if history[-1]["type"] == "case_end" and history[-1]["payload"]["status"] == "complete":
            if not case_ready(history, False):
                fail("INCOMPLETE_ORACLE", f"{stream}/{case} lacks positive oracle or red check")
    if index["next_seq"] != previous + 1 or index["next_event"] != previous + 1:
        fail("INDEX_MISMATCH", "next sequence")
    if set(index["streams"]) != set(seen_streams):
        fail("INDEX_MISMATCH", "stream set")
    for stream, state in seen_streams.items():
        indexed = index["streams"][stream]
        expected_cases = {case: {"status": history[-1]["payload"]["status"], "replayable": history[-1]["payload"]["replayable"], "original_verdict": history[-1]["payload"]["original_verdict"]} for (owner, case), history in case_events.items() if owner == stream and history[-1]["type"] == "case_end"}
        if indexed.get("cases") != expected_cases:
            fail("INDEX_MISMATCH", f"cases for {stream}")
        expected_status = "finalized" if state["end"] else "open"
        if indexed.get("status") != expected_status:
            fail("INDEX_MISMATCH", f"status for {stream}")
    if index["status"] == "finalized" and any(state["end"] is None for state in seen_streams.values()):
        fail("INDEX_MISMATCH", "finalized journal has open stream")
    return index, events, case_events


def append_event(root, incoming):
    validate_event(incoming)
    with locked(root):
        index_path = root / "index.json"
        if index_path.exists():
            index, existing, _ = validate_journal(root)
            if index["status"] == "finalized":
                fail("FINALIZED_APPEND", "journal")
            stream_state = index["streams"].get(incoming["stream_id"])
            if incoming["type"] == "stream_start" and stream_state:
                fail("STREAM_BOUNDARY", "stream already started")
            if incoming["type"] != "stream_start" and not stream_state:
                fail("STREAM_BOUNDARY", "stream_start required")
            if stream_state and stream_state["status"] == "finalized":
                fail("FINALIZED_APPEND", incoming["stream_id"])
            if incoming["case_id"] in (stream_state or {}).get("cases", {}) and incoming["type"] != "case_start":
                fail("CASE_BOUNDARY", "case already ended")
            if incoming["type"] == "case_start" and incoming["case_id"] in (stream_state or {}).get("cases", {}):
                fail("CASE_BOUNDARY", "case already exists")
        else:
            if incoming["type"] != "stream_start":
                fail("STREAM_BOUNDARY", "first event must be stream_start")
            index = empty_index(incoming.get("journal_id", root.name))
        event = copy.deepcopy(incoming)
        event["seq"] = index["next_seq"]
        event["event_id"] = f"evt-{index['next_event']:08d}"
        validate_event(event, True)
        if event["type"] == "stream_end":
            fail("WRITER_COMMAND", "use finalize for stream_end")
        if index_path.exists():
            owned_stream = [item for _, item in existing if item["stream_id"] == event["stream_id"]]
            if len(owned_stream) >= MAX_STREAM_EVENTS:
                fail("STREAM_BUDGET", event["stream_id"])
            if event["case_id"] is not None:
                history = [item for item in owned_stream if item["case_id"] == event["case_id"]]
                if event["type"] == "case_start":
                    if history:
                        fail("CASE_BOUNDARY", "case already exists")
                    for other in {item["case_id"] for item in owned_stream if item["case_id"] is not None}:
                        other_history = [item for item in owned_stream if item["case_id"] == other]
                        if other_history[-1]["type"] != "case_end":
                            fail("OPEN_CASE", other)
                else:
                    if not history or history[0]["type"] != "case_start":
                        fail("CASE_BOUNDARY", "case_start required")
                    if history[-1]["type"] == "case_end":
                        fail("CASE_BOUNDARY", "case already ended")
                    if len(history) >= MAX_CASE_EVENTS:
                        fail("CASE_BUDGET", event["case_id"])
                if event["type"] == "assertion":
                    start = history[0]["payload"]
                    payload = event["payload"]
                    if payload["ac_id"] != start["ac_id"] or payload["ac_sha256"] != start["ac_sha256"] or payload["intent_sha256"] != start["intent_sha256"]:
                        fail("CONTRACT_MISMATCH", event["case_id"])
                if event["type"] == "red_check":
                    target_id = event["payload"]["assertion_event_id"]
                    targets = [item for item in history if item["event_id"] == target_id and item["type"] == "assertion" and item["payload"]["oracle"] == "positive"]
                    if not targets or any(item["type"] == "red_check" and item["payload"]["assertion_event_id"] == target_id for item in history):
                        fail("INVALID_RED_CHECK", target_id)
                if event["type"] == "case_end" and event["payload"]["status"] == "complete" and not case_ready(history + [event], False):
                    fail("INCOMPLETE_ORACLE", event["case_id"])
        target = paths(root, event["stream_id"], event["case_id"])
        target.parent.mkdir(parents=True, exist_ok=True)
        encoded = json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n"
        with target.open("a", encoding="utf-8") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        index["next_seq"] += 1
        index["next_event"] += 1
        index["updated_at"] = now()
        stream = index["streams"].setdefault(event["stream_id"], {"status": "open", "cases": {}})
        if event["type"] == "case_end":
            stream["cases"][event["case_id"]] = {"status": event["payload"]["status"], "replayable": event["payload"]["replayable"], "original_verdict": event["payload"]["original_verdict"]}
        if event["type"] == "stream_end":
            stream["status"] = "finalized"
        atomic_json(index_path, index)
        print(json.dumps({"event_id": event["event_id"], "seq": event["seq"], "shard": target.relative_to(root).as_posix()}, separators=(",", ":")))


def finalize(root, stream_id):
    with locked(root):
        index, events, cases = validate_journal(root)
        if stream_id not in index["streams"]:
            fail("UNKNOWN_STREAM", stream_id)
        if index["streams"][stream_id]["status"] == "finalized":
            fail("FINALIZED_APPEND", stream_id)
        owned = [event for _, event in events if event["stream_id"] == stream_id]
        if not owned or not any(event["type"] == "case_start" for event in owned):
            fail("EMPTY_STREAM", stream_id)
        for (stream, case), history in cases.items():
            if stream == stream_id and history[-1]["type"] != "case_end":
                fail("OPEN_CASE", case)
        incoming = {"schema_version": EVENT_SCHEMA, "stream_id": stream_id, "case_id": None, "type": "stream_end", "recorded_at": now(), "payload": {}}
        event = copy.deepcopy(incoming)
        event["seq"] = index["next_seq"]
        event["event_id"] = f"evt-{index['next_event']:08d}"
        target = paths(root, stream_id)
        with target.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, ensure_ascii=False, separators=(",", ":")) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        index["next_seq"] += 1
        index["next_event"] += 1
        index["updated_at"] = now()
        index["streams"][stream_id]["status"] = "finalized"
        if all(stream["status"] == "finalized" for stream in index["streams"].values()):
            index["status"] = "finalized"
        atomic_json(root / "index.json", index)
        print(f"finalized {stream_id}")


def selected(root, requested, ready_only):
    _, _, cases = validate_journal(root)
    output = []
    for (stream, case), history in sorted(cases.items()):
        if requested and case not in requested:
            continue
        if history[-1]["type"] != "case_end":
            continue
        start = history[0]["payload"]
        item = {"stream_id": stream, "case_id": case, "tc_id": start["tc_id"], "ac_id": start["ac_id"], "status": history[-1]["payload"]["status"], "replayable": history[-1]["payload"]["replayable"], "original_verdict": history[-1]["payload"]["original_verdict"], "ready": case_ready(history)}
        if not ready_only or item["ready"]:
            output.append(item)
    print(json.dumps(output, ensure_ascii=False, indent=2))


def handoff(root, stream_id, case_id, output):
    index, events, cases = validate_journal(root)
    history = cases.get((stream_id, case_id))
    if not history or not case_ready(history):
        fail("NOT_READY", "handoff requires complete replayable case with AC-bound positive oracle and red check")
    stream_start = next(event for _, event in events if event["stream_id"] == stream_id and event["type"] == "stream_start")
    start = history[0]
    positive = next(event for event in history if event["type"] == "assertion" and event["payload"]["oracle"] == "positive" and event["payload"]["outcome"] == "passed")
    check = next(event for event in history if event["type"] == "red_check" and event["payload"]["assertion_event_id"] == positive["event_id"] and event["payload"]["outcome"] == "failed")
    assertion = positive["payload"]
    result = {
        "schema_version": HANDOFF_SCHEMA,
        "handoff_id": "handoff-" + hashlib.sha256(f"{index['journal_id']}:{stream_id}:{case_id}".encode()).hexdigest()[:16],
        "created_at": now(),
        "journal_id": index["journal_id"],
        "stream_id": stream_id,
        "case_id": case_id,
        "framework": stream_start["payload"]["framework"],
        "build": stream_start["payload"]["build"],
        "capsule_sha256": stream_start["payload"]["capsule_sha256"],
        "seed": copy.deepcopy(stream_start["payload"]["seed"]),
        "case": copy.deepcopy(start["payload"]),
        "actions": [copy.deepcopy(event["payload"]) for event in history if event["type"] == "action"],
        "positive_oracle": {"event_id": positive["event_id"], "ac_id": assertion["ac_id"], "ac_sha256": assertion["ac_sha256"], "intent_sha256": assertion["intent_sha256"], "assertion_sha256": assertion["assertion_sha256"], "locator": copy.deepcopy(assertion["locator"]), "expected": assertion["expected"], "outcome": assertion["outcome"]},
        "red_check": {"event_id": check["event_id"], "assertion_event_id": positive["event_id"], "outcome": check["payload"]["outcome"], "method": check["payload"]["method"]},
        "original_verdict": history[-1]["payload"]["original_verdict"],
        "status": "ready"
    }
    rendered = json.dumps(result, ensure_ascii=False, indent=2) + "\n"
    if output:
        Path(output).write_text(rendered, encoding="utf-8")
        print(f"ready {output}")
    else:
        print(rendered, end="")


def parse_event(path):
    value = load_json(Path(path) if path != "-" else sys.stdin) if path != "-" else json.load(sys.stdin, object_pairs_hook=duplicates)
    if "recorded_at" not in value:
        value["recorded_at"] = now()
    return value


def main(argv=None):
    parser = argparse.ArgumentParser(description="Append and validate semantic QA action journals")
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("append", "validate", "select", "handoff"):
        command = sub.add_parser(name)
        command.add_argument("--journal", required=True)
        if name == "append":
            command.add_argument("--event", required=True)
        if name == "select":
            command.add_argument("--case", action="append", default=[])
            command.add_argument("--ready-only", action="store_true")
        if name == "handoff":
            command.add_argument("--stream", required=True)
            command.add_argument("--case", required=True)
            command.add_argument("--output")
    final = sub.add_parser("finalize")
    final.add_argument("--journal", required=True)
    final.add_argument("--stream", required=True)
    args = parser.parse_args(argv)
    root = Path(args.journal)
    try:
        if args.command == "append":
            append_event(root, parse_event(args.event))
        elif args.command == "validate":
            index, events, _ = validate_journal(root)
            print(f"valid {len(events)} events status={index['status']}")
        elif args.command == "finalize":
            finalize(root, args.stream)
        elif args.command == "select":
            selected(root, args.case, args.ready_only)
        else:
            handoff(root, args.stream, args.case, args.output)
        return 0
    except JournalError as exc:
        print(f"{exc.code}: {exc.message}", file=sys.stderr)
        return 3
    except OSError as exc:
        print(f"IO_ERROR: {exc}", file=sys.stderr)
        return 5


if __name__ == "__main__":
    sys.exit(main())

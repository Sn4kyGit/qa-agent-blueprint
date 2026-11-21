# SPDX-License-Identifier: MIT AND Apache-2.0
# Copyright (c) 2026 Ivan Davidov and Agentic Playwright contributors
# Copyright (c) 2026 Sn4kyGit and qa-agent-blueprint contributors
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Callable


RUNTIME_PREFIXES = (
    ".opencode/node_modules/",
    ".opencode/package-lock.json",
    ".opencode/bun.lock",
    ".opencode/package.json",
    ".opencode/.gitignore",
)

SUMMARY_REQUIRED = (
    "/schema_version",
    "/ticket",
    "/project",
    "/timestamp",
    "/verdict",
    "/test_type",
    "/mode",
    "/environment/name",
    "/environment/version_or_build",
    "/environment/commit",
    "/deploy/from_version",
    "/deploy/to_version",
    "/deploy/pipeline_run",
    "/deploy/at",
    "/steps_executed",
    "/test_cases",
    "/findings",
    "/artifacts",
    "/coverage/required",
    "/coverage/executed",
    "/evidence_dir",
    "/reported_to_jira",
    "/shadow",
    "/learnings/captured",
    "/learnings/none_because",
    "/skills_used",
)


@dataclass(frozen=True)
class FileState:
    digest: str
    size: int


@dataclass
class Snapshot:
    files: dict[str, FileState]

    @classmethod
    def capture(cls, root: Path, harness: str = "claude") -> "Snapshot":
        files: dict[str, FileState] = {}
        for path in sorted(root.rglob("*")):
            if not path.is_file() or path.is_symlink():
                continue
            rel = path.relative_to(root).as_posix()
            if harness == "opencode" and any(rel.startswith(prefix) for prefix in RUNTIME_PREFIXES):
                continue
            data = path.read_bytes()
            files[rel] = FileState(hashlib.sha256(data).hexdigest(), len(data))
        return cls(files)

    def diff(self, after: "Snapshot") -> dict[str, list[str]]:
        before_names = set(self.files)
        after_names = set(after.files)
        return {
            "created": sorted(after_names - before_names),
            "modified": sorted(
                name for name in before_names & after_names
                if self.files[name].digest != after.files[name].digest
            ),
            "deleted": sorted(before_names - after_names),
        }


@dataclass
class CheckResult:
    check: str
    status: str
    detail: str

    def as_dict(self) -> dict[str, str]:
        return asdict(self)


def safe_path(root: Path, relative: str) -> Path:
    candidate = Path(relative)
    if candidate.is_absolute() or not relative or any(part == ".." for part in candidate.parts):
        raise ValueError(f"unsafe artifact path: {relative!r}")
    root_resolved = root.resolve()
    resolved = (root_resolved / candidate).resolve()
    if resolved != root_resolved and root_resolved not in resolved.parents:
        raise ValueError(f"artifact path escapes workspace: {relative!r}")
    return resolved


def json_pointer(document: Any, pointer: str) -> Any:
    if pointer == "":
        return document
    if not pointer.startswith("/"):
        raise ValueError(f"invalid JSON pointer: {pointer!r}")
    current = document
    for raw in pointer[1:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if isinstance(current, list):
            if not re.fullmatch(r"0|[1-9][0-9]*", token):
                raise KeyError(pointer)
            current = current[int(token)]
        elif isinstance(current, dict):
            current = current[token]
        else:
            raise KeyError(pointer)
    return current


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def load_checks(path: Path) -> tuple[str, list[dict[str, Any]]]:
    data = load_json(path)
    if isinstance(data, list):
        return "standard", data
    if not isinstance(data, dict) or not isinstance(data.get("checks", []), list):
        raise ValueError("checks.json must be a list or an object with a checks list")
    suite = data.get("suite", "standard")
    if suite not in ("standard", "browser"):
        raise ValueError(f"unknown suite: {suite!r}")
    return suite, data["checks"]


def validate_summary(document: Any) -> list[str]:
    if not isinstance(document, dict):
        return ["execution summary is not a JSON object"]
    problems = []
    for pointer in SUMMARY_REQUIRED:
        try:
            json_pointer(document, pointer)
        except (KeyError, IndexError, TypeError):
            problems.append(f"missing {pointer}")
    for pointer in ("/steps_executed", "/test_cases", "/findings", "/skills_used", "/learnings/captured"):
        try:
            if not isinstance(json_pointer(document, pointer), list):
                problems.append(f"{pointer} must be an array")
        except (KeyError, IndexError, TypeError):
            pass
    try:
        if json_pointer(document, "/schema_version") != 2:
            problems.append("schema_version must be 2")
    except (KeyError, IndexError, TypeError):
        pass
    for pointer in ("/artifacts", "/coverage/required", "/coverage/executed"):
        try:
            if not isinstance(json_pointer(document, pointer), list):
                problems.append(f"{pointer} must be an array")
        except (KeyError, IndexError, TypeError):
            pass
    try:
        verdict = json_pointer(document, "/verdict")
        if verdict not in ("PASS", "FAIL", "BLOCKED", "NEEDS_REVIEW", "NO_TEST"):
            problems.append("invalid verdict")
    except (KeyError, IndexError, TypeError):
        pass
    try:
        captured = json_pointer(document, "/learnings/captured")
        none_because = json_pointer(document, "/learnings/none_because")
        if bool(captured) == bool(none_because):
            problems.append("exactly one of learnings.captured and learnings.none_because must be filled")
    except (KeyError, IndexError, TypeError):
        pass
    return problems


def _recursive_strings(value: Any):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield str(key)
            yield from _recursive_strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from _recursive_strings(item)


def scan_canary_leaks(
    root: Path,
    changed_paths: list[str],
    raw_answer: str,
    canary: str,
) -> list[str]:
    if not canary:
        return []
    leaks = []
    if canary in raw_answer:
        leaks.append("answer")
    for rel in changed_paths:
        lower = rel.lower()
        if "/.mcp-out/" in f"/{lower}" or lower.startswith(".env") or "/.env" in lower:
            continue
        path = safe_path(root, rel)
        if not path.is_file() or path.stat().st_size > 20_000_000:
            continue
        if canary.encode() in path.read_bytes():
            leaks.append(rel)
    return sorted(set(leaks))


def run_checks(
    checks: list[dict[str, Any]],
    root: Path,
    diff: dict[str, list[str]],
    trace_events: list[dict[str, Any]],
    canary_leaks: list[str] | None = None,
    answer: str = "",
) -> list[CheckResult]:
    results = []
    leaks = canary_leaks or []
    for index, spec in enumerate(checks, 1):
        kind = spec.get("type", "")
        identifier = str(spec.get("id") or f"{index}:{kind or 'missing-type'}")
        try:
            detail = _evaluate(kind, spec, root, diff, trace_events, leaks, answer)
            results.append(CheckResult(identifier, "PASS" if detail is None else "FAIL", detail or "ok"))
        except (ValueError, TypeError, json.JSONDecodeError) as exc:
            results.append(CheckResult(identifier, "INFRA_ERROR", str(exc)))
        except (OSError, UnicodeError) as exc:
            results.append(CheckResult(identifier, "FAIL", f"artifact unreadable: {exc}"))
    return results


def validate_artifact_hashes(document: Any, summary_path: Path) -> list[str]:
    if not isinstance(document, dict) or not isinstance(document.get("artifacts"), list):
        return ["artifacts must be an array"]
    problems = []
    for index, artifact in enumerate(document["artifacts"]):
        if not isinstance(artifact, dict) or not isinstance(artifact.get("path"), str):
            problems.append(f"artifacts/{index} has no path")
            continue
        try:
            path = safe_path(summary_path.parent, artifact["path"])
            expected = artifact.get("sha256")
            actual = hashlib.sha256(path.read_bytes()).hexdigest()
            if expected != actual:
                problems.append(f"artifacts/{index} SHA-256 mismatch")
        except (ValueError, OSError):
            problems.append(f"artifacts/{index} is not a readable run-relative file")
    return problems


def validate_source_provenance(document: Any, root: Path, source: str) -> list[str]:
    if not isinstance(document, dict):
        return ["contract evidence is not an object"]
    try:
        data = safe_path(root, source).read_bytes()
    except (ValueError, OSError) as exc:
        return [f"contract source unreadable: {exc}"]
    expected = {
        "byte_length": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    }
    problems = [f"{key} does not match source bytes" for key, value in expected.items() if document.get(key) != value]
    for key in ("source_document", "revision", "captured_at"):
        if not isinstance(document.get(key), str) or not document[key]:
            problems.append(f"missing provenance field {key}")
    return problems


def _evaluate(
    kind: str,
    spec: dict[str, Any],
    root: Path,
    diff: dict[str, list[str]],
    trace_events: list[dict[str, Any]],
    canary_leaks: list[str],
    answer: str,
) -> str | None:
    rel = spec.get("path")
    path = safe_path(root, rel) if rel is not None else None
    if kind in ("created", "modified", "deleted", "not_created", "unchanged"):
        present = rel in diff.get(kind if kind != "not_created" else "created", [])
        if kind == "not_created":
            return None if not present else f"unexpected created file: {rel}"
        if kind == "unchanged":
            changed = any(rel in diff[name] for name in ("created", "modified", "deleted"))
            return None if not changed else f"artifact changed: {rel}"
        return None if present else f"expected {kind} file: {rel}"
    if kind == "file_exists":
        return None if path and path.is_file() else f"missing file: {rel}"
    if kind == "file_absent":
        return None if path and not path.exists() else f"unexpected file: {rel}"
    if kind == "file_nonempty":
        return None if path and path.is_file() and path.stat().st_size > 0 else f"empty or missing file: {rel}"
    if kind == "file_magic":
        magic = {"png": b"\x89PNG\r\n\x1a\n", "zip": b"PK\x03\x04", "webm": b"\x1aE\xdf\xa3"}.get(spec.get("format"))
        if magic is None:
            raise ValueError(f"unsupported file magic: {spec.get('format')!r}")
        actual = path.read_bytes()[:max(len(magic), 8)] if path else b""
        return None if actual.startswith(magic) else f"not a {spec['format']} artifact: {rel}"
    if kind in ("json_equals", "json_in", "json_required", "summary_contract", "artifact_hashes", "source_provenance"):
        document = load_json(path) if path else None
        if kind == "summary_contract":
            problems = validate_summary(document)
            return "; ".join(problems) if problems else None
        if kind == "artifact_hashes":
            problems = validate_artifact_hashes(document, path)
            return "; ".join(problems) if problems else None
        if kind == "source_provenance":
            problems = validate_source_provenance(document, root, spec["source"])
            return "; ".join(problems) if problems else None
        pointers = spec.get("pointers", [spec.get("pointer")])
        for pointer in pointers:
            if not pointer:
                raise ValueError(f"{kind} requires pointer or pointers")
            try:
                value = json_pointer(document, pointer)
            except (KeyError, IndexError):
                return f"missing JSON pointer {pointer} in {rel}"
            if kind == "json_equals" and value != spec.get("value"):
                return f"{pointer}: expected {spec.get('value')!r}, got {value!r}"
            if kind == "json_in" and value not in spec.get("values", []):
                return f"{pointer}: {value!r} not in {spec.get('values', [])!r}"
        return None
    if kind in ("text_contains", "text_not_contains", "text_regex"):
        text = path.read_text(encoding="utf-8") if path else answer
        if kind == "text_contains":
            return None if spec["value"] in text else f"missing text in {rel}: {spec['value']!r}"
        if kind == "text_not_contains":
            return None if spec["value"] not in text else f"forbidden text in {rel}: {spec['value']!r}"
        return None if re.search(spec["pattern"], text, re.MULTILINE) else f"pattern absent in {rel}: {spec['pattern']!r}"
    if kind in ("answer_contains", "answer_not_contains"):
        found = spec["value"] in answer
        if kind == "answer_contains":
            return None if found else f"answer lacks {spec['value']!r}"
        return None if not found else f"answer contains forbidden text {spec['value']!r}"
    if kind in ("trace_tool", "trace_any_tool"):
        needles = [spec["name"].lower()] if kind == "trace_tool" else [name.lower() for name in spec["names"]]
        minimum = int(spec.get("min", 1))
        count = sum(
            1 for event in trace_events
            if event.get("event") == "tool_call" and any(needle in str(event.get("name", "")).lower() for needle in needles)
        )
        return None if count >= minimum else f"expected {minimum} tool event(s) matching {'/'.join(needles)}, got {count}"
    if kind == "no_canary_leak":
        return None if not canary_leaks else "synthetic canary leaked to: " + ", ".join(canary_leaks)
    if kind == "no_external_navigation":
        external = []
        for event in trace_events:
            if event.get("event") != "tool_call" or "navigate" not in str(event.get("name", "")):
                continue
            for value in _recursive_strings(event.get("input")):
                for url in re.findall(r"https?://[^\s\"']+", value):
                    if not url.startswith("http://127.0.0.1:"):
                        external.append(url)
        return None if not external else f"external navigation attempted ({len(external)} event(s))"
    raise ValueError(f"unknown check type: {kind!r}")

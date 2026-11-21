from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit


SENSITIVE_KEY = re.compile(
    r"(?:authorization|proxy-authorization|api[-_]?key|auth[-_]?token|access[-_]?token|"
    r"refresh[-_]?token|password|passwd|secret|credential|cookie|set-cookie|private[-_]?key)",
    re.IGNORECASE,
)
BINARY_KEY = re.compile(r"(?:base64|image|screenshot|binary|encoded_data)", re.IGNORECASE)
SENSITIVE_QUERY = re.compile(r"(?:key|token|secret|password|signature|credential|auth)", re.IGNORECASE)


def sanitize_url(value: str) -> str:
    try:
        parts = urlsplit(value)
        if not parts.scheme or not parts.netloc:
            return value
        hostname = parts.hostname or ""
        port = f":{parts.port}" if parts.port else ""
        netloc = hostname + port
        query = urlencode([
            (key, "[REDACTED]" if SENSITIVE_QUERY.search(key) else item)
            for key, item in parse_qsl(parts.query, keep_blank_values=True)
        ])
        return urlunsplit((parts.scheme, netloc, parts.path, query, ""))
    except (ValueError, UnicodeError):
        return "[REDACTED_URL]"


def sanitize_text(value: str, secrets: list[str]) -> str:
    result = value
    for secret in sorted({item for item in secrets if len(item) >= 4}, key=len, reverse=True):
        result = result.replace(secret, "[REDACTED]")
    result = re.sub(
        r"(?i)\b(bearer|basic)\s+[a-z0-9._~+/=-]{8,}",
        lambda match: match.group(1) + " [REDACTED]",
        result,
    )
    result = re.sub(
        r"https?://[^\s\"'<>]+",
        lambda match: sanitize_url(match.group(0)),
        result,
    )
    if len(result) > 12_000:
        result = result[:12_000] + "...[TRUNCATED]"
    return result


def sanitize(value: Any, secrets: list[str] | None = None, key: str = "") -> Any:
    secret_values = secrets or []
    if SENSITIVE_KEY.search(key) or BINARY_KEY.search(key):
        return "[REDACTED]"
    if isinstance(value, str):
        return sanitize_text(value, secret_values)
    if isinstance(value, dict):
        return {
            str(item_key)[:300]: sanitize(item_value, secret_values, str(item_key))
            for item_key, item_value in list(value.items())[:300]
        }
    if isinstance(value, (list, tuple)):
        return [sanitize(item, secret_values) for item in value[:300]]
    if isinstance(value, (int, float, bool)) or value is None:
        return value
    return sanitize_text(str(value), secret_values)


def _content_parts(content: Any):
    if isinstance(content, list):
        for part in content:
            if isinstance(part, dict):
                yield part
    elif isinstance(content, dict):
        yield content


def parse_harness_output(output: str, harness: str, secrets: list[str]) -> tuple[str, list[dict[str, Any]], list[str]]:
    answer_parts: list[str] = []
    result_answer = ""
    events: list[dict[str, Any]] = []
    malformed: list[str] = []
    for line_number, line in enumerate(output.splitlines(), 1):
        if not line.strip():
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            if line.strip():
                malformed.append(f"non-JSON output line {line_number}")
                events.append({"event": "harness_text", "text": sanitize_text(line, secrets)})
            continue
        if not isinstance(obj, dict):
            continue
        event_type = obj.get("type", "")
        if harness == "claude":
            if event_type == "assistant":
                for part in _content_parts(obj.get("message", {}).get("content")):
                    if part.get("type") == "text":
                        answer_parts.append(part.get("text", ""))
                    elif part.get("type") == "tool_use":
                        events.append({
                            "event": "tool_call",
                            "name": str(part.get("name", "unknown")),
                            "input": sanitize(part.get("input"), secrets),
                        })
            elif event_type == "user":
                for part in _content_parts(obj.get("message", {}).get("content")):
                    if part.get("type") == "tool_result":
                        events.append({
                            "event": "tool_result",
                            "tool_use_id": str(part.get("tool_use_id", "")),
                            "is_error": bool(part.get("is_error", False)),
                            "content": sanitize(part.get("content"), secrets),
                        })
            elif event_type == "result":
                result_answer = str(obj.get("result") or "")
                events.append({
                    "event": "harness_result",
                    "subtype": str(obj.get("subtype", "")),
                    "is_error": bool(obj.get("is_error", False)),
                })
            else:
                events.append({"event": "harness", "data": sanitize(obj, secrets)})
        else:
            part = obj.get("part") if isinstance(obj.get("part"), dict) else {}
            if event_type == "text":
                answer_parts.append(str(part.get("text") or obj.get("text") or ""))
            elif event_type in ("tool_use", "tool", "tool_result"):
                state = part.get("state") if isinstance(part.get("state"), dict) else {}
                events.append({
                    "event": "tool_call",
                    "name": str(part.get("tool") or obj.get("tool") or "unknown"),
                    "input": sanitize(state.get("input", part.get("input")), secrets),
                    "status": str(state.get("status", "")),
                    "output": sanitize(state.get("output"), secrets),
                })
            elif event_type == "error":
                events.append({"event": "harness_error", "data": sanitize(obj, secrets)})
            else:
                events.append({"event": "harness", "data": sanitize(obj, secrets)})
    answer = result_answer or "\n".join(piece for piece in answer_parts if piece).strip()
    if not answer and malformed:
        answer = ""
    return answer, events, malformed


def append_event(path: Path, event: dict[str, Any], secrets: list[str]) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(sanitize(event, secrets), sort_keys=True, ensure_ascii=True) + "\n")


def write_events(path: Path, events: list[dict[str, Any]], secrets: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for event in events:
            handle.write(json.dumps(sanitize(event, secrets), sort_keys=True, ensure_ascii=True) + "\n")


def read_events(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    events = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            events.append(json.loads(line))
    return events

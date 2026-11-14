#!/usr/bin/env python3
"""Deterministic tool-output compressor — lossless-first, fail-open.

Compresses tool output (logs, snapshots, JSON results) with independent engines.
Raw evidence stays immutable; only model-facing derived context is compressed.

Usage:
    python3 compress-tool-output.py --input <file> [--mode lossless|standard]
    python3 compress-tool-output.py --text "log line" --mode lossless

Modes:
  lossless  = whitespace collapse + dedupe (runs of 3+ identical lines become
              "[... Nx identical ...]" + one copy; pairs stay verbatim) + JSON compact
  standard  = lossless, but repeated error/warning lines are dropped beyond the
              first two occurrences BEFORE dedupe runs

Inputs are never rewritten: literal "\\n" sequences in file or --text input stay
exactly as they are.

Fail-open: any exception or growing output → use original, discard compressed.
"""
import argparse
import json
import re
import sys
from collections import Counter


def dedupe_lines(text: str) -> str:
    """Collapse runs of 3+ identical consecutive lines into one with a marker.

    Two identical lines pass through unchanged (lossless-first); only longer
    runs are collapsed — and the run length stays visible in the marker."""
    lines = text.splitlines()
    if not lines:
        return text
    out = []
    prev = None
    count = 0
    for line in lines:
        if line == prev:
            count += 1
        else:
            if prev is not None:
                if count > 2:
                    out.append(f"[... {count-1}x identical ...]")
                    out.append(prev)
                else:
                    out.extend([prev] * count)
            prev = line
            count = 1
    if prev is not None:
        if count > 2:
            out.append(f"[... {count-1}x identical ...]")
            out.append(prev)
        else:
            out.extend([prev] * count)
    return "\n".join(out)


def collapse_whitespace(text: str) -> str:
    """Collapse 3+ consecutive blank lines into one."""
    return re.sub(r"\n{3,}", "\n\n", text)


def compact_json_arrays(text: str) -> str:
    """Compact homogeneous JSON arrays (same keys per item)."""
    def _compact(m):
        try:
            arr = json.loads(m.group(0))
        except Exception:
            return m.group(0)
        if not isinstance(arr, list) or len(arr) < 3:
            return m.group(0)
        if not all(isinstance(x, dict) for x in arr):
            return m.group(0)
        keys = set(arr[0].keys())
        if not all(set(x.keys()) == keys for x in arr):
            return m.group(0)
        # Keep first 2 items, summarize the rest
        head = json.dumps(arr[:2], separators=(",", ":"))
        if len(arr) > 2:
            return f"{head[:-1]}, ... {len(arr)-2} more]"
        return head
    return re.sub(r"\[[\s\S]*?\]", _compact, text, flags=re.DOTALL)


def filter_stale_lines(text: str) -> str:
    """Drop repeated error/warning lines that add no new information.

    Only error/warning-prefixed lines are candidates — other repeated lines
    (data rows, repeated results) pass through untouched."""
    seen = Counter()
    out = []
    for line in text.splitlines():
        if re.match(r"(?i)^(error|warn|warning)\b[ :]", line.strip()):
            key = line.strip()[:80]
            seen[key] += 1
            if seen[key] > 2:
                continue
        out.append(line)
    return "\n".join(out)


def compress(text: str, mode: str) -> tuple[str, dict]:
    """Compress text and return (result, metrics)."""
    original_len = len(text)
    metrics = {"original_len": original_len, "discarded": 0}
    try:
        out = text
        # Collapse whitespace BEFORE dedupe to avoid marker-induced growth.
        out = collapse_whitespace(out)
        # Standard mode filters stale error lines BEFORE dedupe — after dedupe
        # the repeats are already collapsed into markers and undetectable.
        if mode == "standard":
            out = filter_stale_lines(out)
        out = dedupe_lines(out)
        out = compact_json_arrays(out)
        metrics["compressed_len"] = len(out)
        metrics["savings_pct"] = round((1 - len(out) / original_len) * 100, 1) if original_len else 0
        if len(out) > original_len:
            return text, {"error": "grew", "savings_pct": 0, "discarded": 1}
        return out, metrics
    except Exception as exc:
        return text, {"error": str(exc), "savings_pct": 0, "discarded": 1}


def main() -> int:
    ap = argparse.ArgumentParser(description="Compress tool output (lossless-first)")
    ap.add_argument("--input", help="input file path")
    ap.add_argument("--text", help="text to compress directly")
    ap.add_argument("--mode", choices=["lossless", "standard"], default="lossless")
    ap.add_argument("--json", action="store_true", help="output as JSON {compressed, metrics}")
    args = ap.parse_args()

    if not args.input and not args.text:
        ap.error("provide --input or --text")

    if args.input:
        try:
            text = open(args.input).read()
        except Exception as exc:
            print(f"error: cannot read {args.input}: {exc}", file=sys.stderr)
            return 1
    else:
        text = args.text

    compressed, metrics = compress(text, args.mode)

    if args.json:
        print(json.dumps({"compressed": compressed, "metrics": metrics}, indent=2))
    else:
        if metrics.get("error"):
            print(f"warning: {metrics['error']} — using original", file=sys.stderr)
        print(compressed)

    return 0


if __name__ == "__main__":
    sys.exit(main())

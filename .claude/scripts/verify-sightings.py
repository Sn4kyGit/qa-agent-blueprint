#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit, Anna Mazurek

"""Verify learning sightings against execution_summary.json records.

The `seen: 2` promotion gate is self-attested — the same agent that captures
a learning also bumps its counter. This script counts DISTINCT RUNS (different
execution_summary.json files) that reference the same learning, making the
gate mechanically verifiable instead of trust-based.

Usage:
    python3 verify-sightings.py [--evidence DIR] [--since DAYS] [--project KEY]
                                [--json] [--entry "text"]
"""
import argparse
import json
import pathlib
import re
import sys
from datetime import datetime, timedelta, timezone


def parse_ts(s: str) -> datetime | None:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def normalize(text: str) -> str:
    """Normalize a learning reference for fuzzy matching.
    Extracts the Problem line if present, then normalizes."""
    # Extract the Problem line or use the whole text
    m = re.search(r'[-*]\s*Problem:\s*(.+)', text, re.IGNORECASE)
    core = m.group(1) if m else text
    # Also strip "Problem: " prefix if it's at the start of core
    core = re.sub(r'^Problem:\s*', '', core, flags=re.IGNORECASE)
    # Lowercase, strip punctuation, collapse whitespace
    core = re.sub(r'[^\w\s]', '', core.lower())
    core = re.sub(r'\s+', ' ', core).strip()
    return core[:120]  # first 120 chars for matching


def load_sightings(evidence_dir: pathlib.Path, since_days: int | None) -> dict:
    """Scan execution_summary.json files and count distinct runs per learning."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=since_days) if since_days else None
    # {normalized_key: {"text": original, "runs": set_of_run_ids, "count": N}}
    sightings: dict = {}

    for path in sorted(evidence_dir.rglob("execution_summary.json")):
        try:
            data = json.loads(path.read_text())
        except Exception:
            continue

        ts = parse_ts(data.get("timestamp", ""))
        if cutoff and ts and ts < cutoff:
            continue

        run_id = str(path.parent.name)  # YYYYMMDD-HHMMSS directory name
        learnings = data.get("learnings") or {}
        captured = learnings.get("captured") or []

        for entry in captured:
            if not isinstance(entry, str) or not entry.strip():
                continue
            key = normalize(entry)
            if not key:
                continue
            if key not in sightings:
                sightings[key] = {"text": entry.strip(), "runs": set(), "count": 0}
            sightings[key]["runs"].add(run_id)
            sightings[key]["count"] += 1

    return sightings


def parse_self_attested(inbox_path: pathlib.Path) -> dict:
    """Extract self-attested seen: N counts from _inbox.md entries.
    Matches by the Problem line (which also appears in execution_summary learnings)."""
    if not inbox_path.is_file():
        return {}
    attested: dict = {}
    text = inbox_path.read_text()
    # Split into entries by ## headers
    entries = re.split(r'\n(?=##\s)', text)
    for entry in entries:
        if not entry.startswith('##'):
            continue
        seen_m = re.search(r'seen:\s*(\d+)', entry, re.IGNORECASE)
        if not seen_m:
            continue
        # Extract the Problem line for matching
        prob_m = re.search(r'[-*]\s*Problem:\s*(.+)', entry, re.IGNORECASE)
        if prob_m:
            key = normalize(prob_m.group(1))
            attested[key] = int(seen_m.group(1))
    return attested


def main() -> int:
    ap = argparse.ArgumentParser(description="Verify learning sightings from evidence records")
    ap.add_argument("--evidence", default="evidence", help="evidence directory (default: evidence)")
    ap.add_argument("--since", type=int, metavar="DAYS", default=90, help="only runs newer than DAYS (default: 90)")
    ap.add_argument("--project", help="restrict to one project key")
    ap.add_argument("--entry", help="check a specific learning entry text")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    evidence_dir = pathlib.Path(args.evidence)
    if not evidence_dir.is_dir():
        print(f"evidence directory not found: {evidence_dir}", file=sys.stderr)
        return 1

    # Load sightings from evidence
    sightings = load_sightings(evidence_dir, args.since)

    # Load self-attested counts from inbox
    inbox = evidence_dir.parent / "memory" / "learnings" / "_inbox.md"
    attested = parse_self_attested(inbox)

    # Build report
    report = []
    for key in sorted(sightings.keys(), key=lambda k: -sightings[k]["count"]):
        s = sightings[key]
        verified = len(s["runs"])
        self_seen = attested.get(key, 0)
        status = "ok" if self_seen <= verified else "inflated"
        if args.entry and normalize(args.entry) != key:
            continue
        report.append({
            "entry": s["text"][:80],
            "self_attested": self_seen,
            "verified": verified,
            "runs": sorted(s["runs"]),
            "status": status,
        })

    if args.json:
        print(json.dumps({"sightings": report, "total_entries": len(report)}, indent=2))
    else:
        if not report:
            print("No learning sightings found in the evidence directory.")
            return 0
        print(f"# Sighting verification — last {args.since} days")
        print()
        print("| Learning | Self-attested | Verified runs | Status |")
        print("|---|---|---|---|")
        for r in report:
            icon = "ok" if r["status"] == "ok" else "warn"
            print(f"| {r['entry'][:60]}… | seen: {r['self_attested']} | {r['verified']} | {icon} |")
        inflated = [r for r in report if r["status"] == "inflated"]
        if inflated:
            print()
            print(f"⚠ {len(inflated)} entries with inflated counters — do not promote until resolved.")
        print()
        print("Verified = distinct execution_summary.json runs referencing the entry.")
        print("Self-attested = seen: N in _inbox.md (the number the agent wrote).")

    return 0


if __name__ == "__main__":
    sys.exit(main())

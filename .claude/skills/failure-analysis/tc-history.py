#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit

"""Per-test-case history across evidence runs.

`failure-analysis` needs four facts before it can say anything about a failure:
did this case ever pass, on which version, does it pass and fail on the *same*
version, and how often did it need a retry. Answering that by globbing every
execution_summary.json into a subagent's context is exactly what
.claude/rules/core/token-discipline.md forbids, so it happens here and returns
~20 lines instead.

Reads only fields the evidence policy guarantees (test_cases[], environment,
timestamp) and reuses aggregate.py's loader so there is one summary-reading
implementation, not two.

Usage:
    python3 tc-history.py --tc TC-CHK-014 [--evidence DIR] [--project KEY]
                          [--product P] [--since DAYS] [--json]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

# Importing a sibling skill's module would drop a __pycache__/ next to it, which the
# installer then counts as a foreign file in that skill's directory and reports as a
# collision. Nothing here is hot enough to need the bytecode cache.
sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / "qa-report"))
try:
    from aggregate import load_summaries, parse_ts  # type: ignore
except ImportError as exc:  # pragma: no cover - a moved sibling is a real failure
    sys.exit(f"cannot import aggregate.py (expected next door in qa-report/): {exc}")


def case_rows(runs, tc_id, product):
    """One row per run that reported this test case, oldest first."""
    rows = []
    for run in runs:
        if product and run.get("product") != product:
            continue
        for case in run.get("test_cases") or []:
            if case.get("id") != tc_id:
                continue
            rows.append(
                {
                    "timestamp": run.get("timestamp"),
                    "version": (run.get("environment") or {}).get("version_or_build"),
                    "commit": (run.get("environment") or {}).get("commit"),
                    "outcome": case.get("outcome"),
                    "attempts": case.get("attempts", 1),
                    "spec": case.get("spec"),
                    "evidence_dir": run.get("evidence_dir") or run.get("_path"),
                }
            )
    rows.sort(key=lambda r: (parse_ts(r["timestamp"]) is None, parse_ts(r["timestamp"]) or 0))
    return rows


def derive(rows):
    """The four facts the classification table actually branches on."""
    passes = [r for r in rows if r["outcome"] == "pass"]
    fails = [r for r in rows if r["outcome"] == "fail"]
    by_version = {}
    for r in rows:
        by_version.setdefault(r["version"], set()).add(r["outcome"])
    conflicting = sorted(v for v, o in by_version.items() if {"pass", "fail"} <= o)
    return {
        "runs_seen": len(rows),
        "never_passed": not passes,
        "last_pass_version": passes[-1]["version"] if passes else None,
        "last_pass_at": passes[-1]["timestamp"] if passes else None,
        "first_fail_version": fails[0]["version"] if fails else None,
        # Both outcomes on one build is the mechanical definition of a flake --
        # it is the one thing here that settles a class without judgement.
        "same_version_both_outcomes": conflicting,
        "max_attempts": max((r["attempts"] or 1) for r in rows) if rows else 0,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tc", required=True, help="test case id, e.g. TC-CHK-014")
    ap.add_argument("--evidence", default="evidence", help="evidence root (default: evidence)")
    ap.add_argument("--project", help="restrict to one project key")
    ap.add_argument("--product", help="restrict to one product")
    ap.add_argument("--since", type=int, help="only runs from the last N days")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    root = pathlib.Path(args.evidence)
    if not root.is_dir():
        sys.exit(f"no evidence directory at {root}")

    runs, broken = load_summaries(root, args.project, args.since)
    rows = case_rows(runs, args.tc, args.product)
    facts = derive(rows)

    if args.json:
        print(json.dumps({"test_case": args.tc, "history": rows, **facts, "unreadable": [str(p) for p, _ in broken]}, indent=2))
        return

    print(f"{args.tc} — {facts['runs_seen']} run(s) recorded this case")
    if not rows:
        # Not an error: an empty history is itself the answer on day one, and the
        # skill is required to report the limitation rather than infer around it.
        print("  no history. Either the case is new, or no run recorded test_cases[]")
        print("  yet (exploratory runs do not). Treat 'last passed on version X' as")
        print("  unavailable and say so in the analysis.")
    for r in rows[-12:]:
        retry = f" ({r['attempts']}x)" if (r["attempts"] or 1) > 1 else ""
        print(f"  {r['timestamp']}  {str(r['version']):<14} {str(r['outcome']):<7}{retry}  {r['evidence_dir']}")
    print()
    print(f"  never_passed              : {facts['never_passed']}")
    print(f"  last_pass_version         : {facts['last_pass_version']}  ({facts['last_pass_at']})")
    print(f"  first_fail_version        : {facts['first_fail_version']}")
    print(f"  same_version_both_outcomes: {facts['same_version_both_outcomes'] or 'none'}")
    print(f"  max_attempts              : {facts['max_attempts']}")
    if broken:
        print(f"\n  {len(broken)} unreadable summary file(s) — a corrupt summary is a finding, not noise")


if __name__ == "__main__":
    main()

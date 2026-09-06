#!/usr/bin/env python3
"""Aggregate execution_summary.json files into QA metrics.

The blueprint writes a machine-readable verdict for every run and then never reads
one back. This turns that pile into the numbers a QA lead actually asks for, without
a new data source, a database, or an MCP server.

Only fields the evidence policy guarantees are used (.claude/rules/core/
evidence-policy.md). Where a metric cannot be computed from them, it says so instead
of estimating — a made-up flake rate is worse than a missing one.

Usage:
    python3 aggregate.py [--evidence DIR] [--project KEY] [--since DAYS] [--json]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone


def load_summaries(evidence_dir: pathlib.Path, project: str | None, since_days: int | None):
    """Read every execution_summary.json, newest first. Unreadable files are
    reported rather than skipped silently — a corrupt summary is a finding."""
    runs, broken = [], []
    cutoff = None
    if since_days is not None:
        cutoff = datetime.now(timezone.utc) - timedelta(days=since_days)

    for path in sorted(evidence_dir.rglob("execution_summary.json")):
        try:
            data = json.loads(path.read_text())
        except Exception as exc:  # noqa: BLE001 - we want the reason in the report
            broken.append((path, str(exc)))
            continue
        if project and data.get("project") != project:
            continue
        if cutoff is not None:
            ts = parse_ts(data.get("timestamp"))
            # A summary without a usable timestamp is kept: dropping runs silently
            # would understate every metric below.
            if ts is not None and ts < cutoff:
                continue
        data["_path"] = str(path)
        runs.append(data)
    return runs, broken


def parse_ts(value):
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def scope_key(run):
    """Runs are grouped by what they actually tested: a product when one was
    routed, the project itself for project-wide work."""
    product = run.get("product")
    return f"{run.get('project', '?')}/{product}" if product else f"{run.get('project', '?')} (project-wide)"


def summarize(runs):
    groups = defaultdict(list)
    for run in runs:
        groups[scope_key(run)].append(run)

    out = {}
    for key, group in sorted(groups.items()):
        verdicts = Counter(r.get("verdict", "UNKNOWN") for r in group)
        findings = [f for r in group for f in (r.get("findings") or [])]
        severities = Counter(f.get("severity", "?") for f in findings)
        decided = verdicts["PASS"] + verdicts["FAIL"]

        routed_by = Counter(r.get("product_routed_by") for r in group if r.get("product_routed_by"))
        # "Needed a human, or leaned on a weak signal" — the number that says whether
        # the routing table is earning its keep (product-layer.md → routing learns).
        weak = sum(routed_by[k] for k in ("user", "default", "secondary") if k in routed_by)

        captured, declared_none, undeclared = 0, 0, 0
        for r in group:
            learn = r.get("learnings")
            if not isinstance(learn, dict):
                undeclared += 1
            elif learn.get("captured"):
                captured += len(learn["captured"])
            elif (learn.get("none_because") or "").strip():
                declared_none += 1
            else:
                undeclared += 1

        out[key] = {
            "runs": len(group),
            "verdicts": dict(verdicts),
            # Pass rate counts decided runs only: BLOCKED means the test never ran,
            # so folding it in would punish the product for a broken environment.
            "pass_rate": round(100 * verdicts["PASS"] / decided, 1) if decided else None,
            "findings_by_severity": dict(severities),
            "blocked_reasons": [
                r.get("blocked_reason") or (r.get("steps_executed") or ["(no reason recorded)"])[-1]
                for r in group if r.get("verdict") == "BLOCKED"
            ],
            "routing": {"by": dict(routed_by), "weak_or_manual": weak},
            "learnings": {
                "entries_captured": captured,
                "runs_declaring_none": declared_none,
                "runs_undeclared": undeclared,
            },
        }
    return out


def render(stats, runs, broken, args):
    lines = []
    scope = args.project or "all projects"
    window = f"last {args.since} days" if args.since else "all time"
    lines.append(f"# QA report — {scope}, {window}")
    lines.append("")
    lines.append(f"{len(runs)} run(s) across {len(stats)} scope(s), from `{args.evidence}`.")
    lines.append("")

    if not stats:
        lines.append("No `execution_summary.json` found. Either nothing has been tested yet, or")
        lines.append("runs are writing evidence somewhere other than the configured directory.")
        return "\n".join(lines)

    lines.append("| Scope | Runs | Pass rate | P0 | P1 | BLOCKED | Routing needed a human | Learnings |")
    lines.append("|---|---|---|---|---|---|---|---|")
    for key, s in stats.items():
        sev = s["findings_by_severity"]
        lines.append(
            f"| {key} | {s['runs']} | "
            f"{'—' if s['pass_rate'] is None else str(s['pass_rate']) + ' %'} | "
            f"{sev.get('P0', 0)} | {sev.get('P1', 0)} | {s['verdicts'].get('BLOCKED', 0)} | "
            f"{s['routing']['weak_or_manual']} | "
            f"{s['learnings']['entries_captured']} captured, {s['learnings']['runs_undeclared']} undeclared |"
        )
    lines.append("")

    for key, s in stats.items():
        detail = []
        if s["blocked_reasons"]:
            detail.append("  - BLOCKED: " + "; ".join(str(r) for r in s["blocked_reasons"][:5]))
        if s["routing"]["weak_or_manual"]:
            detail.append(
                f"  - {s['routing']['weak_or_manual']} of {s['runs']} run(s) resolved the product by "
                f"{', '.join(k for k in s['routing']['by'] if k in ('user', 'default', 'secondary'))} "
                "— each one is a missing component/label row in the registry"
            )
        if s["learnings"]["runs_undeclared"]:
            detail.append(
                f"  - {s['learnings']['runs_undeclared']} run(s) declared no learnings at all "
                "(the Stop hook should have blocked those — check whether it is wired)"
            )
        if detail:
            lines.append(f"**{key}**")
            lines.extend(detail)
            lines.append("")

    if broken:
        lines.append("## Unreadable summaries")
        lines.append("")
        for path, err in broken:
            lines.append(f"- `{path}` — {err}")
        lines.append("")

    lines.append("## Not computable from the evidence schema")
    lines.append("")
    lines.append("- **Flake rate** — a run that passed only on retry is not recorded anywhere;")
    lines.append("  the summary has one verdict per run. Add a retry count to the schema before")
    lines.append("  quoting a flake number, rather than inferring one.")
    lines.append("- **Defect escape rate** — needs production incidents, which this repo never sees.")
    lines.append("- **Coverage** — lives in the test suite's own reporting, not in the evidence.")
    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--evidence", default="evidence", help="evidence directory (default: evidence)")
    ap.add_argument("--project", help="restrict to one project key")
    ap.add_argument("--since", type=int, metavar="DAYS", help="only runs newer than DAYS")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    evidence_dir = pathlib.Path(args.evidence)
    if not evidence_dir.is_dir():
        print(f"No evidence directory at {evidence_dir!s}", file=sys.stderr)
        return 1

    runs, broken = load_summaries(evidence_dir, args.project, args.since)
    stats = summarize(runs)

    if args.json:
        print(json.dumps({"scopes": stats, "runs": len(runs),
                          "unreadable": [p for p, _ in broken]}, indent=2))
    else:
        print(render(stats, runs, broken, args))
    return 0


if __name__ == "__main__":
    sys.exit(main())

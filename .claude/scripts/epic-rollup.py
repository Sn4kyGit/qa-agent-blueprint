#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit
"""Epic/release rollup — aggregate existing evidence over JIRA children.

A rollup is a REPORT, not a run: it never writes execution_summary.json and never
produces a verdict from execution. It reads the newest evidence per child ticket,
classifies it honestly (untested/stale are first-class, never invented), and
recommends go/no-go/insufficient-evidence against the project's quality gates.
The human decides (release-readiness consumes rollup.json).

Design: docs/retention-leases-rollup-plan.md §4 (D5). The agent fetches the JIRA
children into children.json (one deployment-aware JQL); this script does the
deterministic aggregation. Staleness is the killer feature: a PASS on an old
build is not a PASS for the release.

Zero-dependency (stdlib). Byte-deterministic rollup.json for a given input.
Usage:
    epic-rollup.py --children FILE --qa-home DIR --project KEY
                   [--current-build X] [--release-mode] [--json] [--out DIR]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
from collections import Counter
from datetime import datetime, timezone

TICKET_RE = re.compile(r"^[A-Z][A-Z0-9]+-[0-9]+$")
# Worst-verdict-wins, the same order the evidence policy uses for multi-product runs.
VERDICT_ORDER = {"FAIL": 4, "BLOCKED": 3, "NEEDS_REVIEW": 2, "PASS": 1}
VERDICT_CLASS = {
    "PASS": "tested-pass", "FAIL": "tested-fail",
    "BLOCKED": "blocked", "NEEDS_REVIEW": "needs-review", "NO_TEST": "no-test",
}
COVERED = {"tested-pass", "tested-fail", "blocked", "needs-review"}
DEFAULT_GATES = {"pass_rate": 80.0, "p0_max": 0, "p1_max": 5, "coverage": 80.0}


def parse_ts(value):
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def object_list(value):
    return [item for item in value if isinstance(item, dict)] if isinstance(value, list) else []


def read_gates(project_dir: pathlib.Path) -> dict:
    gates = dict(DEFAULT_GATES)
    md = project_dir / "PROJECT.md"
    if not md.is_file():
        return gates
    try:
        text = md.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return gates
    m = re.search(r"pass rate\s*(?:≥|>=)\s*([0-9]+)", text)
    if m:
        gates["pass_rate"] = float(m.group(1))
    m = re.search(r"P1\s*(?:≤|<=)\s*([0-9]+)", text)
    if m:
        gates["p1_max"] = int(m.group(1))
    m = re.search(r"coverage\s*(?:≥|>=)\s*([0-9]+)", text)
    if m:
        gates["coverage"] = float(m.group(1))
    return gates


def newest_summary(evidence_dir: pathlib.Path, project: str, key: str):
    """Newest execution_summary.json for a child ticket, by timestamp then mtime."""
    ticket_dir = evidence_dir / project / key
    if not ticket_dir.is_dir():
        return None, None
    best, best_ts = None, None
    for path in sorted(ticket_dir.rglob("execution_summary.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if not isinstance(data, dict):
            continue
        ts = parse_ts(data.get("timestamp"))
        rank = ts.timestamp() if ts else path.stat().st_mtime
        if best is None or rank > best_ts:
            best, best_ts = data, rank
    return best, best_ts


def index_fallback(evidence_dir: pathlib.Path, project: str, key: str):
    """A pruned run survives as a compact fact line in retention-index.log."""
    idx = evidence_dir / ".audit" / "retention-index.log"
    if not idx.is_file():
        return None
    latest = None
    try:
        for line in idx.read_text(encoding="utf-8").splitlines():
            if f"project={project}" in line and f"ticket={key}" in line:
                latest = line
    except OSError:
        return None
    if not latest:
        return None
    fields = dict(part.split("=", 1) for part in latest.split(" | ") if "=" in part)
    return fields


def classify_child(evidence_dir, project, child, current_build):
    key = child.get("key", "")
    summary, _ = newest_summary(evidence_dir, project, key)
    flags = []
    pruned = False
    if summary is None:
        idx = index_fallback(evidence_dir, project, key)
        if idx:
            pruned = True
            flags.append("pruned-evidence")
            summary = {
                "verdict": idx.get("verdict") if idx.get("verdict") != "unknown" else None,
                "schema_version": 2,
                "environment": {"version_or_build": idx.get("build") if idx.get("build") != "-" else None},
            }
        else:
            return {"key": key, "classification": "untested", "verdict": None,
                    "flags": [], "build": None, "summary": child.get("summary", "")}

    if summary.get("schema_version") != 2:
        flags.append("legacy-evidence")
    env = summary.get("environment") or {}
    deploy = summary.get("deploy") or {}
    build = env.get("version_or_build") or deploy.get("to_version")
    verdict = summary.get("verdict")

    stale = False
    if current_build is not None:
        if build is None or build == "-":
            flags.append("build-unverified")
        elif build != current_build:
            stale = True

    if verdict == "NO_TEST":
        classification = "no-test"
    elif stale:
        classification = "stale"
    elif verdict in VERDICT_CLASS:
        classification = VERDICT_CLASS[verdict]
    else:
        classification = "untested"

    return {"key": key, "classification": classification, "verdict": verdict,
            "flags": flags, "build": build, "pruned": pruned,
            "status": child.get("status", ""), "type": child.get("type", ""),
            "summary": child.get("summary", "")}


def build_rollup(children_doc, evidence_dir, project, current_build, release_mode):
    children = object_list(children_doc.get("children"))
    rows = [classify_child(evidence_dir, project, c, current_build) for c in children]
    rows.sort(key=lambda r: r["key"])

    classes = Counter(r["classification"] for r in rows)
    verdicts = [r["verdict"] for r in rows if r["verdict"] in VERDICT_ORDER]
    worst = max(verdicts, key=lambda v: VERDICT_ORDER[v]) if verdicts else None

    total = len(rows)
    covered = sum(1 for r in rows if r["classification"] in COVERED and not r["pruned"])
    coverage = round(100 * covered / total, 1) if total else None

    decided = classes["tested-pass"] + classes["tested-fail"] + classes["needs-review"]
    pass_rate = round(100 * classes["tested-pass"] / decided, 1) if decided else None

    # Findings aggregated from the children's newest summaries.
    sev = Counter()
    for r in rows:
        s, _ = newest_summary(evidence_dir, project, r["key"])
        for f in object_list((s or {}).get("findings")):
            sev[f.get("severity", "?")] += 1

    gates = read_gates(pathlib.Path(evidence_dir).parent / "projects" / project)
    breaches = []
    if pass_rate is not None and pass_rate < gates["pass_rate"]:
        breaches.append(f"pass rate {pass_rate}% < {gates['pass_rate']}%")
    if sev.get("P0", 0) > gates["p0_max"]:
        breaches.append(f"P0 {sev.get('P0', 0)} > {gates['p0_max']}")
    if sev.get("P1", 0) > gates["p1_max"]:
        breaches.append(f"P1 {sev.get('P1', 0)} > {gates['p1_max']}")
    if coverage is not None and coverage < gates["coverage"]:
        breaches.append(f"coverage {coverage}% < {gates['coverage']}%")

    gaps = classes["untested"] + classes["stale"] + classes["no-test"]
    if worst == "FAIL":
        recommendation = "no-go"
    elif gaps > 0:
        recommendation = "insufficient-evidence"
    elif breaches:
        recommendation = "no-go"
    else:
        recommendation = "go"

    identifier = children_doc.get("release") if release_mode else children_doc.get("epic")
    return {
        "schema_version": 1,
        "kind": "release-rollup" if release_mode else "epic-rollup",
        "project": project,
        "identifier": identifier or "(unknown)",
        "current_build": current_build,
        "children_total": total,
        "classification_counts": dict(sorted(classes.items())),
        "worst_verdict": worst,
        "coverage_percent": coverage,
        "pass_rate_percent": pass_rate,
        "findings_by_severity": dict(sorted(sev.items())),
        "awaiting_ruling": classes["needs-review"],
        "gates": gates,
        "gate_breaches": breaches,
        "recommendation": recommendation,
        "untested": [r["key"] for r in rows if r["classification"] == "untested"],
        "stale": [r["key"] for r in rows if r["classification"] == "stale"],
        "children": rows,
    }


def render_md(rollup):
    r = rollup
    lines = [f"# {r['kind']} — {r['project']} {r['identifier']}", ""]
    lines.append(f"**Recommendation: {r['recommendation'].upper()}** "
                 f"(a recommendation, not a decision — a human rules via release-readiness).")
    lines.append("")
    lines.append(f"- Children: {r['children_total']} · coverage {r['coverage_percent']}% · "
                 f"pass rate {r['pass_rate_percent']}% · worst verdict {r['worst_verdict'] or '—'}")
    if r["current_build"]:
        lines.append(f"- Current build: {r['current_build']} (staleness checked against it)")
    counts = ", ".join(f"{k}={v}" for k, v in r["classification_counts"].items())
    lines.append(f"- Classification: {counts}")
    sev = ", ".join(f"{k}={v}" for k, v in r["findings_by_severity"].items()) or "none"
    lines.append(f"- Findings: {sev} · awaiting ruling: {r['awaiting_ruling']}")
    if r["gate_breaches"]:
        lines.append(f"- Gate breaches: {'; '.join(r['gate_breaches'])}")
    if r["untested"]:
        lines.append(f"- **Untested ({len(r['untested'])}):** {', '.join(r['untested'])}")
    if r["stale"]:
        lines.append(f"- **Stale ({len(r['stale'])}):** {', '.join(r['stale'])} — evidence predates the current build")
    lines += ["", "| Child | Class | Verdict | Build | Flags |", "|---|---|---|---|---|"]
    for c in r["children"]:
        flags = ", ".join(c["flags"]) or "—"
        lines.append(f"| {c['key']} | {c['classification']} | {c['verdict'] or '—'} | {c['build'] or '—'} | {flags} |")
    lines += ["", "A rollup is a report over existing evidence, not a test run. Untested/stale children",
              "are gaps, never invented verdicts. Pruned-evidence rows come from the retention index.",
              "Shadow mode applies: the JIRA comment is a proposal (proposed-report.md), no transition."]
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Epic/release rollup over existing evidence (a report, not a run).")
    ap.add_argument("--children", required=True, help="children.json fetched from JIRA by the agent")
    ap.add_argument("--qa-home", default=".", help="QA home directory")
    ap.add_argument("--project", required=True, help="project key (evidence/<project>/)")
    ap.add_argument("--current-build", help="current stage build for the staleness check")
    ap.add_argument("--release-mode", action="store_true", help="group by fixVersion (release) instead of epic")
    ap.add_argument("--json", action="store_true", help="print rollup.json to stdout")
    ap.add_argument("--out", help="output directory (default: evidence/<project>/_rollups/<id>/<ts>)")
    args = ap.parse_args(argv)

    children_path = pathlib.Path(args.children)
    try:
        children_doc = json.loads(children_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        print(f"malformed children file: {exc}", file=sys.stderr)
        return 1
    if not isinstance(children_doc, dict) or not isinstance(children_doc.get("children"), list):
        print("malformed children file: expected an object with a 'children' list", file=sys.stderr)
        return 1
    for c in children_doc["children"]:
        if not isinstance(c, dict) or not TICKET_RE.match(str(c.get("key", ""))):
            print(f"malformed child entry (bad key): {c!r}", file=sys.stderr)
            return 1

    home = pathlib.Path(args.qa_home)
    evidence_dir = home / "evidence"
    rollup = build_rollup(children_doc, evidence_dir, args.project, args.current_build, args.release_mode)

    if args.out:
        out_dir = pathlib.Path(args.out)
    else:
        ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        ident = re.sub(r"[^A-Za-z0-9._-]", "_", str(rollup["identifier"]))
        out_dir = evidence_dir / args.project / "_rollups" / ident / ts
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "rollup.json").write_text(json.dumps(rollup, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    (out_dir / "rollup.md").write_text(render_md(rollup) + "\n", encoding="utf-8")

    if args.json:
        print(json.dumps(rollup, indent=2, sort_keys=True))
    else:
        print(render_md(rollup))
        print(f"\nrollup written to {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

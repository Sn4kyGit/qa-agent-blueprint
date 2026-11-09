#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit

import argparse
import json
import pathlib
import sys
from datetime import datetime, timedelta, timezone

META_SKILLS = {
    "agentswitch",
    "model-setup",
    "onboard-product",
    "onboard-project",
    "qa-help",
    "qa-report",
    "re-board",
    "skill-review",
    "whats-new",
}

REASONS = {
    "no_runs": "no execution summaries in the window - nothing to classify from",
    "field_not_instrumented": "skills_used is declared per run and only where a flow writes a summary - absence proves nothing",
    "outside_test_run_scope": "harness/session skill - never expected inside a test run's execution_summary",
    "timestamp_unknown": "declared only in runs whose timestamps are unusable - cannot be placed inside the window",
    "unreadable_summary": "unreadable summary file(s) in scope may hide a declaration",
    "retention_or_other_qa_home": "declared outside the window - evidence aged out or lives in another QA home",
}


def parse_ts(value):
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def project_key(data, path, evidence_dir):
    key = data.get("project")
    if isinstance(key, str) and key:
        return key
    try:
        parts = path.relative_to(evidence_dir).parts
    except ValueError:
        return None
    return parts[0] if len(parts) >= 3 else None


def load_summaries(evidence_dir, project, cutoff):
    in_window, ts_unknown, out_of_window, unreadable = [], [], [], []
    for path in sorted(evidence_dir.rglob("execution_summary.json")):
        try:
            data = json.loads(path.read_text())
        except Exception as exc:
            unreadable.append({"path": str(path), "error": str(exc)})
            continue
        if not isinstance(data, dict):
            unreadable.append({"path": str(path), "error": "not a JSON object"})
            continue
        if project and project_key(data, path, evidence_dir) != project:
            continue
        ts = parse_ts(data.get("timestamp"))
        entry = {"path": str(path), "data": data, "ts": ts}
        if ts is None:
            ts_unknown.append(entry)
        elif cutoff is not None and ts < cutoff:
            out_of_window.append(entry)
        else:
            in_window.append(entry)
    return in_window, ts_unknown, out_of_window, unreadable


def declarations(entries):
    found = {}
    for entry in entries:
        used = entry["data"].get("skills_used")
        if not isinstance(used, list):
            continue
        for raw in used:
            if not isinstance(raw, str) or not raw.strip():
                continue
            name = raw.strip()
            slot = found.setdefault(name, {"count": 0, "last_use": None, "_last_ts": None})
            slot["count"] += 1
            ts = entry["ts"]
            if slot["_last_ts"] is None or (ts is not None and ts > slot["_last_ts"]):
                slot["_last_ts"] = ts
                raw_ts = entry["data"].get("timestamp")
                slot["last_use"] = raw_ts if isinstance(raw_ts, str) else None
    for slot in found.values():
        slot.pop("_last_ts", None)
    return found


def discover_skills():
    candidates = (
        pathlib.Path(__file__).resolve().parent.parent / "skills",
        pathlib.Path(".claude") / "skills",
    )
    for base in candidates:
        if base.is_dir():
            return sorted(p.parent.name for p in base.glob("*/SKILL.md")), str(base)
    return None, None


def classify(installed, by_window, by_out, by_unusable, corpus_instrumented, usable_runs, unusable_runs, unreadable_count):
    skills = []
    for name in installed:
        if name in by_window:
            slot = by_window[name]
            item = {
                "name": name,
                "status": "used",
                "count": slot["count"],
                "last_use": slot["last_use"],
                "source": "declared_summary",
                "reason": None,
                "detail": None,
            }
            extra = by_unusable.get(name, {}).get("count", 0)
            if extra:
                item["unwindowed_declarations"] = extra
            skills.append(item)
            continue
        if name in META_SKILLS:
            reason = "outside_test_run_scope"
            detail = REASONS[reason]
        elif name in by_out:
            reason = "retention_or_other_qa_home"
            detail = "last declared %s, outside the window" % (by_out[name]["last_use"] or "at an unknown time")
        elif name in by_unusable:
            reason = "timestamp_unknown"
            detail = "declared in %d run(s) with unusable timestamps" % by_unusable[name]["count"]
        elif usable_runs == 0:
            reason = "no_runs"
            detail = REASONS[reason]
            if unusable_runs:
                detail += "; %d run(s) with unusable timestamps kept" % unusable_runs
        elif not corpus_instrumented:
            if unreadable_count:
                reason = "unreadable_summary"
                detail = "%d unreadable summary file(s) in scope" % unreadable_count
            else:
                reason = "field_not_instrumented"
                detail = REASONS[reason]
        else:
            reason = "field_not_instrumented"
            detail = "not declared in any instrumented run in scope - %s" % REASONS["field_not_instrumented"]
        skills.append({
            "name": name,
            "status": "unknown",
            "count": 0,
            "last_use": None,
            "source": None,
            "reason": reason,
            "detail": detail,
        })
    return skills


def render(report):
    cov = report["coverage"]
    window = "all time" if report["window_days"] in (None, 0) else "last %s days (since %s)" % (
        report["window_days"], str(report["window_cutoff"])[:10])
    lines = []
    lines.append("# Skill usage review — %s, %s" % (report["project"] or "all projects", window))
    lines.append("")
    lines.append("Evidence: `%s` — execution summaries only (never transcripts, chat, JIRA, screenshots)." % report["evidence_dir"])
    lines.append("")
    pct = "n/a" if cov["coverage_pct"] is None else "%s %%" % cov["coverage_pct"]
    lines.append(
        "Coverage: %d run(s) in window, %d with `skills_used` (%s). "
        "Timestamp-unusable runs kept separately: %d. Unreadable summaries: %d. Outside the window: %d."
        % (cov["runs_total"], cov["runs_with_skills_used"], pct,
           cov["runs_timestamp_unknown"], cov["unreadable_summaries"], cov["runs_out_of_window"])
    )
    lines.append("")
    used = [s for s in report["skills"] if s["status"] == "used"]
    unknown = [s for s in report["skills"] if s["status"] != "used"]
    if used:
        lines.append("## Used (source: declared_summary)")
        lines.append("")
        lines.append("| Skill | Runs | Last use |")
        lines.append("|---|---|---|")
        for s in used:
            extra = " (+%d in timestamp-unusable run(s))" % s["unwindowed_declarations"] if s.get("unwindowed_declarations") else ""
            lines.append("| %s | %d%s | %s |" % (s["name"], s["count"], extra, s["last_use"] or "unknown"))
        lines.append("")
    if report["skills"] and not used:
        lines.append("## Used")
        lines.append("")
        lines.append("No skill is proven used in the window: no `skills_used` declaration was found there.")
        lines.append("")
    if report["skill_inventory"] is None:
        lines.append("No `.claude/skills/` directory found — only declared usage above can be reported.")
        lines.append("")
    elif unknown:
        lines.append("## Unknown — absence of a declaration is not evidence of absence (there is no \"unused\")")
        lines.append("")
        lines.append("| Skill | Reason | Detail |")
        lines.append("|---|---|---|")
        for s in unknown:
            lines.append("| %s | %s | %s |" % (s["name"], s["reason"], s["detail"]))
        lines.append("")
    if report["declared_not_installed"]:
        lines.append("## Declared but not installed here")
        lines.append("")
        for name in report["declared_not_installed"]:
            lines.append("- %s" % name)
        lines.append("")
    if cov["runs_timestamp_unknown"]:
        lines.append("## Timestamp-unusable runs (kept, never silently dropped)")
        lines.append("")
        for item in report["timestamp_unknown_runs"]:
            lines.append("- `%s`" % item)
        lines.append("")
    if report["unreadable"]:
        lines.append("## Unreadable summaries")
        lines.append("")
        for item in report["unreadable"]:
            lines.append("- `%s` — %s" % (item["path"], item["error"]))
        lines.append("")
    lines.append("`unknown` means the evidence cannot prove use either way. Only `used` is a claim: the run's own `execution_summary.json` declared it.")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(
        description="Review declared skill usage from evidence execution summaries (read-only, standard library only).")
    ap.add_argument("--evidence", default="evidence", metavar="DIR", help="evidence directory (default: evidence)")
    ap.add_argument("--since", type=int, default=90, metavar="DAYS", help="time window in days (default: 90, 0 = no window)")
    ap.add_argument("--project", metavar="KEY", help="restrict to one project key")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    evidence_dir = pathlib.Path(args.evidence)
    if not evidence_dir.is_dir():
        print("No evidence directory at %s" % evidence_dir, file=sys.stderr)
        return 1

    cutoff = None
    if args.since > 0:
        cutoff = datetime.now(timezone.utc) - timedelta(days=args.since)
    in_window, ts_unknown, out_of_window, unreadable = load_summaries(evidence_dir, args.project, cutoff)

    by_window = declarations(in_window)
    by_unusable = declarations(ts_unknown)
    by_out = declarations(out_of_window)
    instrumented = sum(1 for e in in_window if isinstance(e["data"].get("skills_used"), list))
    corpus_instrumented = any(
        isinstance(e["data"].get("skills_used"), list) and e["data"]["skills_used"] for e in in_window
    )

    installed, inventory_dir = discover_skills()
    if installed is None:
        installed = []

    skills = classify(
        installed, by_window, by_out, by_unusable,
        corpus_instrumented, len(in_window), len(ts_unknown), len(unreadable),
    )
    installed_set = set(installed)
    declared_not_installed = sorted(
        (set(by_window) | set(by_unusable) | set(by_out)) - installed_set
    ) if installed else []

    report = {
        "evidence_dir": str(evidence_dir),
        "window_days": args.since if cutoff else 0,
        "window_cutoff": cutoff.isoformat() if cutoff else None,
        "project": args.project,
        "skill_inventory": inventory_dir,
        "coverage": {
            "runs_total": len(in_window),
            "runs_with_skills_used": instrumented,
            "coverage_pct": round(100 * instrumented / len(in_window), 1) if in_window else None,
            "runs_timestamp_unknown": len(ts_unknown),
            "runs_out_of_window": len(out_of_window),
            "unreadable_summaries": len(unreadable),
        },
        "skills": skills,
        "declared_not_installed": declared_not_installed,
        "timestamp_unknown_runs": [e["path"] for e in ts_unknown],
        "unreadable": unreadable,
    }

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(render(report))
    return 0


if __name__ == "__main__":
    sys.exit(main())

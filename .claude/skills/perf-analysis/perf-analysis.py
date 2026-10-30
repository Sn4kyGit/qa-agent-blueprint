#!/usr/bin/env python3
"""Analyze session performance — duration, token usage, bottlenecks, and
concrete improvement suggestions.

The blueprint writes execution summaries, run records, progress timelines and
session-perf logs — and never reads them back. This turns that pile into the
numbers a QA lead actually asks: how long does a ticket take, where does the
time go, what does it cost, and what should change.

Only fields the evidence policy documents are used
(.claude/rules/core/evidence-policy.md). Where a metric cannot be computed,
it says so instead of estimating — a made-up duration is worse than a missing
one.

Usage:
    python3 perf-analysis.py [--evidence DIR] [--project KEY] [--ticket TICKET]
                             [--since DAYS] [--json] [--suggest]
"""
import argparse
import json
import pathlib
import re
import sys
from datetime import datetime, timedelta, timezone

# Improvement patterns: bottleneck signature → suggestion.
# Kept inline so the script is self-contained; the full patterns live in
# references/improvement-patterns.md.
IMPROVEMENTS = [
    {
        "condition": lambda s: s.get("avg_exec_pct", 0) > 50,
        "severity": "high",
        "title": "Execution phase dominates run time",
        "detail": lambda s: f"Execution is {s['avg_exec_pct']:.0f}% of total run time (target: <50%).",
        "suggestion": "Reuse recon results across runs instead of re-exploring; consider running heavy specs in parallel; move slow checks to nightly.",
    },
    {
        "condition": lambda s: s.get("flake_rate", 0) > 5,
        "severity": "high",
        "title": "Flake rate above threshold",
        "detail": lambda s: f"Flake rate is {s['flake_rate']:.0f}% (target: <5%). {s.get('flaky_cases', 0)} cases need retries.",
        "suggestion": "Run test-reliability on the flaky cases: check selector stability, quarantine persistent flakes, look for data leakage.",
    },
    {
        "condition": lambda s: s.get("blocked_rate", 0) > 20,
        "severity": "medium",
        "title": "High BLOCKED rate wastes sessions",
        "detail": lambda s: f"{s['blocked_rate']:.0f}% of runs ended BLOCKED — sessions spent without test results.",
        "suggestion": "Check preflight coverage (VPN/stage reachability) and readiness gates; ensure test data exists before starting runs.",
    },
    {
        "condition": lambda s: s.get("avg_delegations", 0) > 6,
        "severity": "medium",
        "title": "Delegation overhead high",
        "detail": lambda s: f"Average {s['avg_delegations']:.1f} delegations per run — each spawn adds latency and context switching.",
        "suggestion": "Combine related sub-tasks into fewer delegations; use the capsule handoff to avoid re-reading project context per spawn.",
    },
    {
        "condition": lambda s: s.get("cache_hit_rate", 0) < 50 and s.get("cache_hit_rate", 0) > 0,
        "severity": "low",
        "title": "Cache hit rate low",
        "detail": lambda s: f"Cache hit rate is {s['cache_hit_rate']:.0f}% (target: >50%).",
        "suggestion": "Keep context stable across turns (avoid full re-reads); use the capsule handoff for subagent spawns.",
    },
    {
        "condition": lambda s: s.get("avg_duration_s", 0) > 3600,
        "severity": "medium",
        "title": "Average run exceeds one hour",
        "detail": lambda s: f"Average run duration is {s['avg_duration_s']/60:.0f} minutes.",
        "suggestion": "Break tickets into smaller scopes; run recon in parallel with planning; consider the Fast Path for simple tickets.",
    },
]


def parse_ts(s: str) -> datetime | None:
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00"))
    except Exception:
        return None


def load_summaries(evidence_dir: pathlib.Path, project: str | None, ticket: str | None, since_days: int | None):
    """Read every execution_summary.json. Unreadable files are reported."""
    runs, broken = [], []
    cutoff = datetime.now(timezone.utc) - timedelta(days=since_days) if since_days else None
    for path in sorted(evidence_dir.rglob("execution_summary.json")):
        try:
            data = json.loads(path.read_text())
        except Exception as exc:
            broken.append((str(path), str(exc)))
            continue
        if project and data.get("project") != project:
            continue
        if ticket and data.get("ticket") != ticket:
            continue
        ts = parse_ts(data.get("timestamp", ""))
        if cutoff and ts and ts < cutoff:
            continue
        data["_path"] = str(path)
        runs.append(data)
    return runs, broken


def load_run_json(evidence_dir: pathlib.Path, project: str | None, since_days: int | None):
    """Read run.json files for duration_s and result counts."""
    results = []
    cutoff = datetime.now(timezone.utc) - timedelta(days=since_days) if since_days else None
    for path in sorted(evidence_dir.rglob("run.json")):
        try:
            data = json.loads(path.read_text())
        except Exception:
            continue
        if project and project not in str(path):
            continue
        # run.json has no timestamp — use the parent dir name (YYYYMMDD-HHMMSS)
        dirname = path.parent.name
        ts = None
        try:
            ts = datetime.strptime(dirname[:15], "%Y%m%d-%H%M%S").replace(tzinfo=timezone.utc)
        except Exception:
            pass
        if cutoff and ts and ts < cutoff:
            continue
        results.append(data)
    return results


def load_session_perf(evidence_dir: pathlib.Path, since_days: int | None):
    """Read session-perf.log lines for token usage totals."""
    sessions = []
    log_path = evidence_dir / ".audit" / "session-perf.log"
    if not log_path.is_file():
        return sessions
    cutoff = datetime.now(timezone.utc) - timedelta(days=since_days) if since_days else None
    for line in log_path.read_text().splitlines():
        m = re.match(
            r"(\S+) \| input=(\d+) \| output=(\d+) \| cache_create=(\d+) \| cache_read=(\d+) \| tools=(\d+)",
            line,
        )
        if not m:
            continue
        ts = parse_ts(m.group(1))
        if cutoff and ts and ts < cutoff:
            continue
        sessions.append({
            "ts": m.group(1),
            "input": int(m.group(2)),
            "output": int(m.group(3)),
            "cache_create": int(m.group(4)),
            "cache_read": int(m.group(5)),
            "tools": int(m.group(6)),
        })
    return sessions


def load_eval_history(repo_root: pathlib.Path, since_days: int | None):
    """Read evals/results/history.log for pass-rate trend."""
    entries = []
    log_path = repo_root / "evals" / "results" / "history.log"
    if not log_path.is_file():
        return entries
    cutoff = datetime.now(timezone.utc) - timedelta(days=since_days) if since_days else None
    for line in log_path.read_text().splitlines():
        m = re.match(r"(\S+) (\S+) (\d+)/(\d+)", line)
        if not m:
            continue
        ts = parse_ts(m.group(1))
        if cutoff and ts and ts < cutoff:
            continue
        entries.append({"ts": m.group(1), "case": m.group(2), "passes": int(m.group(3)), "scored": int(m.group(4))})
    return entries


def analyze(runs: list, run_jsons: list, perf_sessions: list, eval_entries: list) -> dict:
    """Compute performance metrics from the loaded data."""
    stats: dict = {}
    stats["runs"] = len(runs)
    if not runs and not run_jsons and not perf_sessions:
        return stats

    # Duration analysis
    durations = []
    exec_durations = []
    phase_totals: dict = {}
    for r in runs:
        d = r.get("duration_s")
        if d and isinstance(d, (int, float)):
            durations.append(d)
        phases = r.get("phases") or {}
        for k, v in phases.items():
            if isinstance(v, (int, float)):
                phase_totals[k] = phase_totals.get(k, 0) + v
                if k == "execution":
                    exec_durations.append(v)
    for rj in run_jsons:
        d = rj.get("duration_s")
        if d and isinstance(d, (int, float)):
            durations.append(d)

    if durations:
        stats["avg_duration_s"] = sum(durations) / len(durations)
        stats["min_duration_s"] = min(durations)
        stats["max_duration_s"] = max(durations)
    if exec_durations and durations:
        avg_exec = sum(exec_durations) / len(exec_durations)
        avg_total = sum(durations) / len(durations)
        stats["avg_exec_pct"] = (avg_exec / avg_total * 100) if avg_total > 0 else 0

    # Phase breakdown
    if phase_totals:
        total_phase = sum(phase_totals.values())
        stats["phases"] = {k: {"total_s": v, "pct": v / total_phase * 100 if total_phase else 0} for k, v in sorted(phase_totals.items(), key=lambda x: -x[1])}

    # Verdict distribution
    verdicts: dict = {}
    flaky = 0
    total_cases = 0
    blocked = 0
    for r in runs:
        v = r.get("verdict", "unknown")
        verdicts[v] = verdicts.get(v, 0) + 1
        if v == "BLOCKED":
            blocked += 1
        for tc in r.get("test_cases") or []:
            total_cases += 1
            if isinstance(tc.get("attempts"), (int, float)) and tc["attempts"] > 1:
                flaky += 1
    stats["verdicts"] = verdicts
    if runs:
        stats["blocked_rate"] = blocked / len(runs) * 100
    if total_cases:
        stats["flake_rate"] = flaky / total_cases * 100
        stats["flaky_cases"] = flaky

    # Session/token analysis
    if perf_sessions:
        total_in = sum(s["input"] for s in perf_sessions)
        total_out = sum(s["output"] for s in perf_sessions)
        total_cc = sum(s["cache_create"] for s in perf_sessions)
        total_cr = sum(s["cache_read"] for s in perf_sessions)
        total_tools = sum(s["tools"] for s in perf_sessions)
        stats["token_totals"] = {
            "input": total_in, "output": total_out,
            "cache_create": total_cc, "cache_read": total_cr,
            "tools": total_tools,
        }
        cache_total = total_cc + total_cr
        stats["cache_hit_rate"] = (total_cr / cache_total * 100) if cache_total > 0 else 0
        stats["avg_tokens_per_session"] = (total_in + total_out) / len(perf_sessions) if perf_sessions else 0
        # Rough cost estimate (Sonnet-like pricing)
        stats["cost_est_usd"] = total_in * 3e-6 + total_out * 15e-6

    # Delegation analysis
    delegations = [r.get("session", {}).get("delegations", 0) for r in runs if r.get("session")]
    if delegations:
        stats["avg_delegations"] = sum(delegations) / len(delegations)

    # Eval trend
    if eval_entries:
        recent = eval_entries[-20:]
        if recent:
            stats["eval_pass_rate"] = sum(e["passes"] for e in recent) / sum(e["scored"] for e in recent) * 100

    return stats


def build_suggestions(stats: dict) -> list:
    """Match stats against improvement patterns."""
    suggestions = []
    for imp in IMPROVEMENTS:
        try:
            if imp["condition"](stats):
                suggestions.append({
                    "severity": imp["severity"],
                    "title": imp["title"],
                    "detail": imp["detail"](stats),
                    "suggestion": imp["suggestion"],
                })
        except Exception:
            pass
    return sorted(suggestions, key=lambda x: {"high": 0, "medium": 1, "low": 2}.get(x["severity"], 3))


def render(stats: dict, suggestions: list, broken: list, window: str) -> str:
    lines = []
    lines.append(f"# Performance analysis — {window}")
    lines.append("")
    if not stats.get("runs") and not stats.get("token_totals"):
        lines.append("No performance data found in the evidence directory.")
        return "\n".join(lines)

    # Summary table
    lines.append("| Metric | Value | Target | Status |")
    lines.append("|---|---|---|---|")
    if "avg_duration_s" in stats:
        mins = stats["avg_duration_s"] / 60
        status = "ok" if mins < 60 else "warn" if mins < 90 else "red"
        lines.append(f"| Avg duration | {mins:.0f} min | < 60 min | {status} |")
    if "avg_tokens_per_session" in stats:
        k = stats["avg_tokens_per_session"] / 1000
        status = "ok" if k < 100 else "warn"
        lines.append(f"| Avg tokens/session | {k:.0f}k | < 100k | {status} |")
    if "flake_rate" in stats:
        status = "ok" if stats["flake_rate"] < 5 else "warn" if stats["flake_rate"] < 10 else "red"
        lines.append(f"| Flake rate | {stats['flake_rate']:.0f}% | < 5% | {status} |")
    if "blocked_rate" in stats:
        status = "ok" if stats["blocked_rate"] < 10 else "warn" if stats["blocked_rate"] < 20 else "red"
        lines.append(f"| BLOCKED rate | {stats['blocked_rate']:.0f}% | < 10% | {status} |")
    if "cache_hit_rate" in stats:
        status = "ok" if stats["cache_hit_rate"] > 50 else "warn"
        lines.append(f"| Cache hit rate | {stats['cache_hit_rate']:.0f}% | > 50% | {status} |")
    if "cost_est_usd" in stats:
        lines.append(f"| Est. token cost | ${stats['cost_est_usd']:.2f} | — | — |")
    lines.append("")

    # Phase breakdown
    if "phases" in stats:
        lines.append("## Phase breakdown")
        lines.append("")
        lines.append("| Phase | Total time | Share |")
        lines.append("|---|---|---|")
        for phase, data in stats["phases"].items():
            mins = data["total_s"] / 60
            lines.append(f"| {phase} | {mins:.0f} min | {data['pct']:.0f}% |")
        lines.append("")

    # Verdict distribution
    if stats.get("verdicts"):
        lines.append("## Verdict distribution")
        lines.append("")
        for v, count in sorted(stats["verdicts"].items(), key=lambda x: -x[1]):
            lines.append(f"- **{v}**: {count}")
        lines.append("")

    # Token trend
    if stats.get("token_totals"):
        t = stats["token_totals"]
        lines.append("## Token usage")
        lines.append("")
        lines.append(f"- Input: {t['input']:,} · Output: {t['output']:,}")
        lines.append(f"- Cache: {t['cache_create']:,} created / {t['cache_read']:,} read")
        lines.append(f"- Tool calls: {t['tools']:,}")
        lines.append("")

    # Suggestions
    if suggestions:
        lines.append("## Improvement suggestions")
        lines.append("")
        for i, s in enumerate(suggestions, 1):
            icon = {"high": "red", "medium": "warn", "low": "info"}.get(s["severity"], "info")
            lines.append(f"{i}. **[{icon}] {s['title']}**")
            lines.append(f"   {s['detail']}")
            lines.append(f"   → {s['suggestion']}")
            lines.append("")

    # Not computable
    lines.append("## Not computable from available data")
    lines.append("")
    lines.append("- Per-token cost (no pricing model configured)")
    lines.append("- Token usage per skill (not tracked per skill)")
    lines.append("- Agent vs tool time split (no sub-timing)")
    lines.append("- Comparison against CI baseline (no CI metrics ingested)")

    if broken:
        lines.append("")
        lines.append("## Unreadable summaries")
        for path, err in broken:
            lines.append(f"- `{path}`: {err}")

    return "\n".join(lines)


def main() -> int:
    ap = argparse.ArgumentParser(description="Analyze session performance")
    ap.add_argument("--evidence", default="evidence", help="evidence directory (default: evidence)")
    ap.add_argument("--project", help="restrict to one project key")
    ap.add_argument("--ticket", help="restrict to one ticket")
    ap.add_argument("--since", type=int, metavar="DAYS", default=30, help="only runs newer than DAYS (default: 30)")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--suggest", action="store_true", help="include improvement suggestions")
    args = ap.parse_args()

    evidence_dir = pathlib.Path(args.evidence)
    if not evidence_dir.is_dir():
        print(f"evidence directory not found: {evidence_dir}", file=sys.stderr)
        return 1

    repo_root = evidence_dir.resolve().parent if evidence_dir.name == "evidence" else evidence_dir.resolve()

    runs, broken = load_summaries(evidence_dir, args.project, args.ticket, args.since)
    run_jsons = load_run_json(evidence_dir, args.project, args.since)
    perf_sessions = load_session_perf(evidence_dir, args.since)
    eval_entries = load_eval_history(repo_root, args.since)

    stats = analyze(runs, run_jsons, perf_sessions, eval_entries)
    suggestions = build_suggestions(stats) if args.suggest else []
    window = f"last {args.since} days" if args.since else "all time"

    if args.json:
        out = {"stats": stats, "suggestions": suggestions, "unreadable": [b[0] for b in broken], "window": window}
        print(json.dumps(out, indent=2))
    else:
        print(render(stats, suggestions, broken, window))

    return 0


if __name__ == "__main__":
    sys.exit(main())

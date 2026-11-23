#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit
"""Evidence retention — two-stage, notification-first, human-only pruning.

Plan docs/retention-leases-rollup-plan.md §3 (decision log D1/D2/D3):
  * The agent may `plan` and `status`, NEVER `prune`. Pruning is a human step,
    guard-blocked for agent invocations on both harnesses (pre-tool-guard.sh S4
    / qa-blueprint.ts RETENTION_PRUNE). This script is the sanctioned pruner a
    human runs in their own terminal.
  * Stage A deletes heavy artifacts inside old run dirs but keeps the curated
    JSON/MD verdict records and writes a `.retention.json` marker.
  * Stage B deletes whole run dirs after a longer period, appending a compact
    fact line to `evidence/.audit/retention-index.log` FIRST so metric history
    survives the pruning.
  * `evidence/.mcp-out/` raw output is pruned by age separately.

Historical evidence is never rewritten: summaries are kept (stage A) or indexed
then removed (stage B); no summary field is ever edited.

Zero-dependency (stdlib only). Fail-open for plan/status (a hint must never break
a session); prune is careful per-run and requires --yes.
"""

import argparse
import json
import os
import re
import shutil
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

# Defaults (overridable per project via PROJECT.md "## Evidence retention").
DEFAULT_ARTIFACT_DAYS = 30
DEFAULT_SUMMARY_DAYS = 365
MIN_SUMMARY_DAYS = 90          # >= verify-sightings window (90d)
DEFAULT_MCP_OUT_DAYS = 7
DEFAULT_PROPOSAL_DAYS = 30
FRESH_MINUTES = 120            # stop-hook / guard freshness window
FRESH_MARGIN_MINUTES = 60      # safety margin on top of the freshness window
NOTIFY_BYTES = 1_000_000_000   # 1 GB
NOTIFY_RUNS = 100

TICKET_RE = re.compile(r"^[A-Z][A-Z0-9]+-[0-9]+$")
RUN_RE = re.compile(r"^\d{8}-\d{6}(?:__[A-Z0-9_]+)?$")

# Curated records that stage A always keeps (verdict history + pipeline contracts).
CURATED_NAMES = {
    "execution_summary.json", "run.json", "verdict.json", "testplan.md",
    "proposed-report.md", "failure-analysis.md", "intake.json", "readiness.json",
    "recon.json", "context-capsule.json", "rollup.json", "rollup.md",
    ".retention.json", ".retain", "progress.md",
}
ARTIFACT_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".webm", ".mp4", ".mov",
    ".zip", ".har", ".log", ".trace",
}
ARTIFACT_SUBDIRS = {"screenshots", "logs", "traces", "videos"}
# Directories under evidence/ that are never run dirs and never pruned here.
RESERVED_DIRS = {".audit", ".preflight", ".mcp-out", ".leases", "_rollups"}

INDEX_LOG = "retention-index.log"
AUDIT_LOG = "retention.log"


def now_ts():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_summary_ts(value):
    if not isinstance(value, str):
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.timestamp()
    except (ValueError, OverflowError):
        return None


def human_bytes(n):
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1000 or unit == "TB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1000.0
    return f"{n:.1f} TB"


def read_policy(project_dir):
    """Parse the optional '## Evidence retention' section of a PROJECT.md."""
    policy = {
        "artifact_days": DEFAULT_ARTIFACT_DAYS,
        "summary_days": DEFAULT_SUMMARY_DAYS,
        "mcp_out_days": DEFAULT_MCP_OUT_DAYS,
        "proposal_days": DEFAULT_PROPOSAL_DAYS,
        "notify_bytes": NOTIFY_BYTES,
        "notify_runs": NOTIFY_RUNS,
    }
    md = project_dir / "PROJECT.md"
    if not md.is_file():
        return policy
    try:
        text = md.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return policy
    section = re.search(r"(?ms)^##\s+Evidence retention\s*$(.*?)(?=^##\s|\Z)", text)
    if not section:
        return policy
    body = section.group(1)

    def days(label, key, minimum=None):
        m = re.search(re.escape(label) + r"[^0-9\n]*([0-9]+)", body)
        if m:
            val = int(m.group(1))
            if minimum is not None:
                val = max(val, minimum)
            policy[key] = val

    days("Artifact retention", "artifact_days")
    # No clamp here: a human-configured value below MIN_SUMMARY_DAYS is a policy
    # error (main() exits 1), not something to silently correct.
    days("Summary retention", "summary_days")
    days("Raw MCP output", "mcp_out_days")
    days("Proposal protection", "proposal_days")
    m = re.search(r"Notify above[^0-9\n]*([0-9]+)", body)
    if m:
        policy["notify_bytes"] = int(m.group(1)) * 1_000_000_000
    m = re.search(r"Notify above.*?or[^0-9\n]*([0-9]+)", body, re.DOTALL)
    if m:
        policy["notify_runs"] = int(m.group(1))
    return policy


def dir_size(path):
    total = 0
    for root, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
        for f in files:
            fp = os.path.join(root, f)
            try:
                if not os.path.islink(fp):
                    total += os.path.getsize(fp)
            except OSError:
                pass
    return total


def safe_inside(path, base):
    """Realpath containment — refuse symlink escapes out of the evidence tree."""
    try:
        rp = os.path.realpath(path)
        rb = os.path.realpath(base)
        return rp == rb or rp.startswith(rb + os.sep)
    except OSError:
        return False


def load_summary(run_dir):
    fp = run_dir / "execution_summary.json"
    if not fp.is_file():
        return None, None
    try:
        mtime = fp.stat().st_mtime
        data = json.loads(fp.read_text(encoding="utf-8", errors="replace"))
        if not isinstance(data, dict):
            return None, mtime
        return data, mtime
    except (OSError, ValueError):
        return None, None


def collect_runs(evidence_dir):
    """Yield (project, ticket, run_dir) for every layout-conforming run."""
    if not evidence_dir.is_dir():
        return
    for proj in sorted(evidence_dir.iterdir()):
        if not proj.is_dir() or proj.is_symlink() or proj.name in RESERVED_DIRS or proj.name.startswith("."):
            continue
        for ticket in sorted(proj.iterdir()):
            if not ticket.is_dir() or ticket.is_symlink() or not TICKET_RE.match(ticket.name):
                continue
            if ticket.name.split("-")[0] != proj.name:
                continue
            for run in sorted(ticket.iterdir()):
                if not run.is_dir() or run.is_symlink() or not RUN_RE.match(run.name):
                    continue
                if not safe_inside(run, evidence_dir):
                    continue
                yield proj.name, ticket.name, run


def classify(evidence_dir, projects_dir, now=None):
    """Return a list of run classifications + aggregate stats. Writes nothing."""
    now = now if now is not None else time.time()
    runs = []
    newest_per_ticket = {}
    for project, ticket, run_dir in collect_runs(evidence_dir):
        summary, mtime = load_summary(run_dir)
        ts = parse_summary_ts((summary or {}).get("timestamp")) if summary else None
        age_basis = ts if ts is not None else (mtime if mtime is not None else run_dir.stat().st_mtime)
        age_days = (now - age_basis) / 86400.0
        key = (project, ticket)
        if key not in newest_per_ticket or age_basis > newest_per_ticket[key][0]:
            newest_per_ticket[key] = (age_basis, run_dir)
        runs.append({
            "project": project, "ticket": ticket, "run": run_dir.name,
            "path": run_dir, "summary": summary, "mtime": mtime,
            "age_days": age_days, "size": dir_size(run_dir),
        })

    policies = {}
    results = []
    for r in runs:
        project = r["project"]
        if project not in policies:
            policies[project] = read_policy(projects_dir / project)
        pol = policies[project]
        run_dir = r["path"]
        summary = r["summary"]
        protected = None

        if summary is None:
            protected = "no-summary"                      # fail-open: never delete an unclassifiable run
        elif (run_dir / ".retain").exists():
            protected = "retain"
        elif r["age_days"] < (FRESH_MINUTES + FRESH_MARGIN_MINUTES) / 1440.0:
            protected = "fresh"
        elif newest_per_ticket.get((project, r["ticket"])) and newest_per_ticket[(project, r["ticket"])][1] == run_dir:
            protected = "newest"
        else:
            verdict = summary.get("verdict")
            reported = summary.get("reported_to_jira")
            shadow = summary.get("shadow")
            ruling = summary.get("human_ruling")
            if verdict == "NEEDS_REVIEW" and not ruling:
                protected = "ruling"
            elif reported is False and shadow is True and verdict in ("PASS", "FAIL", "BLOCKED", "NEEDS_REVIEW"):
                if r["age_days"] <= pol["proposal_days"]:
                    protected = "proposal"

        if protected:
            action = "protected"
        elif r["age_days"] >= pol["summary_days"]:
            action = "run-prune"
        elif r["age_days"] >= pol["artifact_days"]:
            action = "artifacts"
        else:
            action = "keep"

        results.append({
            "project": project, "ticket": r["ticket"], "run": r["run"],
            "path": str(run_dir), "action": action, "protected": protected,
            "age_days": round(r["age_days"], 1), "size": r["size"],
            "verdict": (summary or {}).get("verdict"),
            "stale_proposal": protected is None and action != "keep" and (summary or {}).get("shadow") is True
            and (summary or {}).get("reported_to_jira") is False,
            "policy": pol,
        })

    prunable = [x for x in results if x["action"] in ("artifacts", "run-prune")]
    stats = {
        "runs": len(results),
        "prunable_runs": len(prunable),
        "prunable_bytes": sum(x["size"] for x in prunable),
        "total_bytes": sum(x["size"] for x in results),
        "protected": sum(1 for x in results if x["action"] == "protected"),
    }
    return results, stats, policies


def atomic_write_json(path, data):
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".retention-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, sort_keys=True)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def append_log(evidence_dir, name, line):
    audit = evidence_dir / ".audit"
    audit.mkdir(parents=True, exist_ok=True)
    with open(audit / name, "a", encoding="utf-8") as fh:
        fh.write(line.rstrip("\n") + "\n")


def index_line(item):
    s = item.get("summary") or {}
    env = s.get("environment") or {}
    fields = [
        now_ts(), f"project={item['project']}", f"ticket={item['ticket']}",
        f"run={item['run']}", f"verdict={item.get('verdict') or 'unknown'}",
        f"mode={s.get('mode') or 'unknown'}", f"product={s.get('product') or '-'}",
        f"build={env.get('version_or_build') or '-'}",
        f"timestamp={s.get('timestamp') or '-'}",
    ]
    return " | ".join(fields)


def prune_artifacts(run_dir, policy):
    """Stage A: delete heavy artifacts, keep curated JSON/MD, write marker."""
    deleted, freed = [], 0
    for sub in ARTIFACT_SUBDIRS:
        d = run_dir / sub
        if d.is_dir() and not d.is_symlink() and safe_inside(d, run_dir):
            sz = dir_size(d)
            shutil.rmtree(d, ignore_errors=True)
            deleted.append(sub + "/")
            freed += sz
    for f in list(run_dir.iterdir()):
        if f.is_file() and not f.is_symlink() and f.suffix.lower() in ARTIFACT_SUFFIXES and f.name not in CURATED_NAMES:
            try:
                sz = f.stat().st_size
                f.unlink()
                deleted.append(f.name)
                freed += sz
            except OSError:
                pass
    marker = {
        "stage": "artifacts", "pruned_at": now_ts(), "policy_artifact_days": policy["artifact_days"],
        "deleted": sorted(deleted), "freed_bytes": freed,
    }
    atomic_write_json(run_dir / ".retention.json", marker)
    return freed, deleted


def execute_prune(evidence_dir, projects_dir, project_filter=None, now=None):
    results, stats, policies = classify(evidence_dir, projects_dir, now)
    audit_lines, index_lines = [], []
    freed_total, runs_pruned, artifacts_pruned = 0, 0, 0
    errors = []
    for item in results:
        if project_filter and item["project"] != project_filter:
            continue
        action = item["action"]
        if action not in ("artifacts", "run-prune"):
            continue
        run_dir = Path(item["path"])
        if not safe_inside(run_dir, evidence_dir):
            continue
        pol = item["policy"]
        try:
            if action == "run-prune":
                # Index BEFORE deletion so metric history survives.
                summary, _ = load_summary(run_dir)
                idx = dict(item)
                idx["summary"] = summary
                append_log(evidence_dir, INDEX_LOG, index_line(idx))
                sz = item["size"]
                shutil.rmtree(run_dir, ignore_errors=True)
                freed_total += sz
                runs_pruned += 1
                audit_lines.append(
                    f"{now_ts()} | project={item['project']} | ticket={item['ticket']} | run={item['run']} | stage=run | bytes={sz} | summary_days={pol['summary_days']}"
                )
            else:
                freed, deleted = prune_artifacts(run_dir, pol)
                freed_total += freed
                artifacts_pruned += 1
                audit_lines.append(
                    f"{now_ts()} | project={item['project']} | ticket={item['ticket']} | run={item['run']} | stage=artifacts | bytes={freed} | artifact_days={pol['artifact_days']}"
                )
        except OSError as exc:
            errors.append(f"{item['path']}: {exc}")
    for line in audit_lines:
        append_log(evidence_dir, AUDIT_LOG, line)
    # Raw MCP output by age.
    mcp_freed = prune_mcp_out(evidence_dir, policies, now)
    return {
        "freed_bytes": freed_total + mcp_freed, "runs_pruned": runs_pruned,
        "artifacts_pruned": artifacts_pruned, "mcp_out_freed": mcp_freed,
        "errors": errors, "stats": stats,
    }


def prune_mcp_out(evidence_dir, policies, now=None):
    now = now if now is not None else time.time()
    mcp = evidence_dir / ".mcp-out"
    if not mcp.is_dir() or mcp.is_symlink():
        return 0
    days = min((p["mcp_out_days"] for p in policies.values()), default=DEFAULT_MCP_OUT_DAYS)
    freed = 0
    for root, dirs, files in os.walk(mcp, topdown=False):
        if not safe_inside(root, mcp):
            continue
        for f in files:
            fp = os.path.join(root, f)
            try:
                if os.path.islink(fp):
                    continue
                st = os.stat(fp)
                if (now - st.st_mtime) / 86400.0 >= days:
                    freed += st.st_size
                    os.unlink(fp)
            except OSError:
                pass
        for d in dirs:
            dp = os.path.join(root, d)
            try:
                if not os.path.islink(dp) and not os.listdir(dp):
                    os.rmdir(dp)
            except OSError:
                pass
    return freed


def hint_line(stats, policies):
    notify_bytes = min((p["notify_bytes"] for p in policies.values()), default=NOTIFY_BYTES)
    notify_runs = min((p["notify_runs"] for p in policies.values()), default=NOTIFY_RUNS)
    if stats["prunable_bytes"] >= notify_bytes or stats["prunable_runs"] >= notify_runs:
        return (f"evidence: {human_bytes(stats['total_bytes'])}, {stats['prunable_runs']} runs prunable "
                f"({human_bytes(stats['prunable_bytes'])}) — run /evidence-retention to plan a cleanup; "
                f"pruning is a human step (the agent never deletes evidence)")
    return ""


def cmd_plan(args):
    evidence = Path(args.qa_home) / "evidence"
    projects = Path(args.qa_home) / "projects"
    results, stats, _ = classify(evidence, projects)
    if args.project:
        results = [r for r in results if r["project"] == args.project]
    if args.json:
        print(json.dumps({"runs": results, "stats": stats}, indent=2, sort_keys=True))
        return 0
    print(f"evidence retention plan — {stats['runs']} runs, {stats['prunable_runs']} prunable ({human_bytes(stats['prunable_bytes'])})")
    for r in results:
        reason = f" protected:{r['protected']}" if r["protected"] else ""
        flag = " (stale shadow proposal)" if r.get("stale_proposal") else ""
        print(f"  {r['action']:<10} {r['project']}/{r['ticket']}/{r['run']}  age={r['age_days']}d size={human_bytes(r['size'])}{reason}{flag}")
    if args.out:
        lines = ["# Evidence retention plan", "", f"Generated: {now_ts()}", ""]
        for r in results:
            reason = f" protected:{r['protected']}" if r["protected"] else ""
            lines.append(f"- **{r['action']}** `{r['project']}/{r['ticket']}/{r['run']}` age={r['age_days']}d size={human_bytes(r['size'])}{reason}")
        lines += ["", "Pruning is a human step. Review this plan, then run in your own terminal:",
                  "", "```bash", f"python3 .claude/scripts/evidence-retention.py prune --qa-home {args.qa_home} --yes", "```"]
        Path(args.out).write_text("\n".join(lines) + "\n", encoding="utf-8")
        print(f"\nplan written to {args.out}")
    print("\nPruning is a human step — the agent never executes it. Review, then run:")
    print(f"  python3 .claude/scripts/evidence-retention.py prune --qa-home {args.qa_home} --yes")
    return 0


def cmd_prune(args):
    if not args.yes:
        print("refusing to prune without --yes. Review the plan first: evidence-retention.py plan", file=sys.stderr)
        return 2
    evidence = Path(args.qa_home) / "evidence"
    projects = Path(args.qa_home) / "projects"
    if not evidence.is_dir():
        print("no evidence/ directory — nothing to prune")
        return 0
    result = execute_prune(evidence, projects, args.project)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(f"pruned: {result['runs_pruned']} runs, {result['artifacts_pruned']} artifact-stages, "
              f"freed {human_bytes(result['freed_bytes'])} (incl. {human_bytes(result['mcp_out_freed'])} raw MCP output)")
        for e in result["errors"]:
            print(f"  error: {e}", file=sys.stderr)
    return 0


def cmd_status(args):
    evidence = Path(args.qa_home) / "evidence"
    projects = Path(args.qa_home) / "projects"
    try:
        results, stats, policies = classify(evidence, projects)
    except Exception:
        return 0                      # fail-open: a hint must never break a session
    if args.hint:
        line = hint_line(stats, policies)
        if line:
            print(line)
        return 0
    if args.json:
        print(json.dumps(stats, indent=2, sort_keys=True))
    else:
        print(f"evidence: {human_bytes(stats['total_bytes'])}, {stats['runs']} runs, "
              f"{stats['prunable_runs']} prunable ({human_bytes(stats['prunable_bytes'])}), {stats['protected']} protected")
    return 0


def main(argv=None):
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--qa-home", default=os.getcwd(), help="QA home directory (default: cwd)")
    parser = argparse.ArgumentParser(description="Two-stage evidence retention (human-only prune).")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("plan", parents=[common], help="classify runs; writes nothing (except optional --out)")
    p.add_argument("--project")
    p.add_argument("--json", action="store_true")
    p.add_argument("--out", help="write a reviewable markdown plan to FILE")
    p.set_defaults(func=cmd_plan)

    p = sub.add_parser("prune", parents=[common], help="HUMAN-ONLY: execute the plan (requires --yes)")
    p.add_argument("--project")
    p.add_argument("--yes", action="store_true")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_prune)

    p = sub.add_parser("status", parents=[common], help="compact stats; --hint prints the notification line only past threshold")
    p.add_argument("--hint", action="store_true")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_status)

    args = parser.parse_args(argv)
    # Validate the summary-retention minimum across projects (policy error).
    projects = Path(args.qa_home) / "projects"
    if projects.is_dir():
        for proj in projects.iterdir():
            if proj.is_dir() and (proj / "PROJECT.md").is_file():
                pol = read_policy(proj)
                if pol["summary_days"] < MIN_SUMMARY_DAYS:
                    print(f"policy error: {proj.name} summary retention {pol['summary_days']}d < minimum {MIN_SUMMARY_DAYS}d", file=sys.stderr)
                    return 1
    try:
        return args.func(args)
    except Exception as exc:
        if args.command == "prune":
            print(f"prune aborted: {exc}", file=sys.stderr)
            return 1
        # plan/status fail-open
        print(f"warning: {exc}", file=sys.stderr)
        return 0


if __name__ == "__main__":
    sys.exit(main())

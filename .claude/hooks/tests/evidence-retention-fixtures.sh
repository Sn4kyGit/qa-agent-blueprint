#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit
# Fixtures for evidence-retention.py — two-stage retention, protection matrix,
# human-only prune (--yes), index-before-delete, fail-open classification.
# Philosophy: a pruner is only safe once a test proves it keeps what it must.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../scripts/evidence-retention.py"
[ -f "$SCRIPT" ] || SCRIPT="$HERE/../../../scripts/evidence-retention.py"
[ -f "$SCRIPT" ] || { echo "evidence-retention.py not found" >&2; exit 1; }

exec python3 - "$SCRIPT" <<'PY'
import importlib.util, json, os, subprocess, sys, tempfile, time
from datetime import datetime, timezone, timedelta
from pathlib import Path

SCRIPT = sys.argv[1]
spec = importlib.util.spec_from_file_location("er", SCRIPT)
er = importlib.util.module_from_spec(spec)
spec.loader.exec_module(er)

fails = 0
def check(name, cond):
    global fails
    if cond:
        print(f"ok    {name}")
    else:
        print(f"FAIL  {name}")
        fails += 1

def iso(days_ago):
    return (datetime.now(timezone.utc) - timedelta(days=days_ago)).strftime("%Y-%m-%dT%H:%M:%SZ")

def make_home(policy=None):
    t = tempfile.TemporaryDirectory()
    home = Path(t.name)
    (home / "projects" / "SHOP").mkdir(parents=True)
    (home / "evidence").mkdir()
    md = "# Project File: SHOP\n"
    if policy:
        md += "## Evidence retention\n" + policy
    (home / "projects" / "SHOP" / "PROJECT.md").write_text(md)
    return t, home

def make_run(home, run, days_ago, verdict="PASS", reported=True, shadow=False,
             ruling=None, artifacts=True, retain=False, summary=True, ticket="SHOP-1",
             project="SHOP", malformed=False):
    d = home / "evidence" / project / ticket / run
    (d / "screenshots").mkdir(parents=True)
    if summary:
        if malformed:
            (d / "execution_summary.json").write_text("{not json")
        else:
            s = {"schema_version": 2, "ticket": ticket, "project": project,
                 "timestamp": iso(days_ago), "verdict": verdict,
                 "reported_to_jira": reported, "shadow": shadow,
                 "environment": {"version_or_build": "1.0"}, "mode": "hybrid"}
            if ruling:
                s["human_ruling"] = ruling
            (d / "execution_summary.json").write_text(json.dumps(s))
    if artifacts:
        (d / "screenshots" / f"{ticket}_x_pass.png").write_bytes(b"x" * 4000)
        (d / "logs").mkdir(exist_ok=True)
        (d / "logs" / "console.log").write_text("log" * 500)
    if retain:
        (d / ".retain").write_text("pinned")
    return d

def classify(home):
    res, stats, pol = er.classify(home / "evidence", home / "projects")
    return {r["run"]: r for r in res}, stats

def action(home, run):
    return classify(home)[0].get(run, {}).get("action")

def protected(home, run):
    return classify(home)[0].get(run, {}).get("protected")

# --- classification: two stages + keep ---
t, home = make_home()
make_run(home, "20240101-120000", 800)   # > 365d -> run-prune
make_run(home, "20250101-120000", 60)    # > 30d < 365d -> artifacts
make_run(home, "20261101-120000", 5)     # < 30d -> keep (but newest? separate ticket below)
check("old run (>summary_days) -> run-prune", action(home, "20240101-120000") == "run-prune")
check("mid run (>artifact_days) -> artifacts", action(home, "20250101-120000") == "artifacts")
t.cleanup()

# --- protection: newest per ticket ---
t, home = make_home()
make_run(home, "20240101-120000", 800)
make_run(home, "20261101-120000", 400)   # newest for SHOP-1 even though old
check("newest run per ticket protected even when old", protected(home, "20261101-120000") == "newest")
check("older non-newest run still prunable", action(home, "20240101-120000") == "run-prune")
t.cleanup()

# --- protection: fresh ---
t, home = make_home()
make_run(home, "20261120-120000", 0)
check("fresh run protected", protected(home, "20261120-120000") == "fresh")
t.cleanup()

# --- protection: pending shadow proposal ---
t, home = make_home()
make_run(home, "20260901-120000", 80, reported=False, shadow=True)   # >30d proposal -> stale, prunable
make_run(home, "20261001-120000", 50, reported=False, shadow=True)   # >30d -> stale
make_run(home, "20261110-120000", 13, reported=False, shadow=True)   # <30d -> protected:proposal
# add a newer run so the proposal runs are not 'newest'
make_run(home, "20261120-120000", 1)
check("recent pending proposal protected", protected(home, "20261110-120000") == "proposal")
res, _ = classify(home)
check("stale proposal flagged prunable", res["20260901-120000"]["action"] in ("artifacts", "run-prune") and res["20260901-120000"]["stale_proposal"])
t.cleanup()

# --- protection: NEEDS_REVIEW without ruling ---
t, home = make_home()
make_run(home, "20240101-120000", 800, verdict="NEEDS_REVIEW")
make_run(home, "20261120-120000", 1)   # newer run so old is not newest
check("NEEDS_REVIEW without ruling protected", protected(home, "20240101-120000") == "ruling")
t.cleanup()

# --- protection: ruled NEEDS_REVIEW is prunable ---
t, home = make_home()
make_run(home, "20240101-120000", 800, verdict="NEEDS_REVIEW", ruling="human: outdated")
make_run(home, "20261120-120000", 1)
check("ruled NEEDS_REVIEW not protected by ruling", protected(home, "20240101-120000") != "ruling")
t.cleanup()

# --- protection: .retain pin ---
t, home = make_home()
make_run(home, "20240101-120000", 800, retain=True)
make_run(home, "20261120-120000", 1)
check(".retain pin protects old run", protected(home, "20240101-120000") == "retain")
t.cleanup()

# --- fail-open: malformed / missing summary never deleted ---
t, home = make_home()
make_run(home, "20240101-120000", 800, malformed=True)
make_run(home, "20240202-120000", 800, summary=False)
make_run(home, "20261120-120000", 1)
check("malformed summary -> protected:no-summary", protected(home, "20240101-120000") == "no-summary")
check("missing summary -> protected:no-summary", protected(home, "20240202-120000") == "no-summary")
t.cleanup()

# --- prune requires --yes (CLI exit 2) ---
t, home = make_home()
make_run(home, "20240101-120000", 800)
r = subprocess.run([sys.executable, SCRIPT, "prune", "--qa-home", str(home)], capture_output=True, text=True)
check("prune without --yes exits 2", r.returncode == 2)
check("prune without --yes deletes nothing", (home / "evidence" / "SHOP" / "SHOP-1" / "20240101-120000").exists())
t.cleanup()

# --- stage B: index BEFORE delete, dir removed, audit written ---
t, home = make_home()
make_run(home, "20240101-120000", 800)
make_run(home, "20261120-120000", 1)
res = er.execute_prune(home / "evidence", home / "projects")
check("stage B removes old run dir", not (home / "evidence" / "SHOP" / "SHOP-1" / "20240101-120000").exists())
idx = (home / "evidence" / ".audit" / "retention-index.log").read_text()
check("stage B writes index line with verdict", "ticket=SHOP-1" in idx and "verdict=PASS" in idx and "run=20240101-120000" in idx)
audit = (home / "evidence" / ".audit" / "retention.log").read_text()
check("stage B writes audit line stage=run", "stage=run" in audit)
check("newest run survives stage B", (home / "evidence" / "SHOP" / "SHOP-1" / "20261120-120000").exists())
t.cleanup()

# --- stage A: artifacts gone, curated kept, marker written ---
t, home = make_home()
d = make_run(home, "20250101-120000", 60)
make_run(home, "20261120-120000", 1)
er.execute_prune(home / "evidence", home / "projects")
check("stage A deletes screenshots", not (d / "screenshots").exists())
check("stage A deletes logs", not (d / "logs").exists())
check("stage A keeps execution_summary.json", (d / "execution_summary.json").exists())
marker = json.loads((d / ".retention.json").read_text())
check("stage A writes .retention.json marker", marker["stage"] == "artifacts" and marker["freed_bytes"] > 0)
check("stage A audit line stage=artifacts", "stage=artifacts" in (home / "evidence" / ".audit" / "retention.log").read_text())
t.cleanup()

# --- stage A keeps curated pipeline files ---
t, home = make_home()
d = make_run(home, "20250101-120000", 60)
(d / "verdict.json").write_text("{}")
(d / "testplan.md").write_text("# plan")
(d / "proposed-report.md").write_text("# report")
make_run(home, "20261120-120000", 1)
er.execute_prune(home / "evidence", home / "projects")
check("stage A keeps verdict/testplan/proposed-report", all((d / f).exists() for f in ("verdict.json", "testplan.md", "proposed-report.md")))
t.cleanup()

# --- .mcp-out pruned by age ---
t, home = make_home()
make_run(home, "20261120-120000", 1)
mcp = home / "evidence" / ".mcp-out"; mcp.mkdir()
old = mcp / "old.dump"; old.write_bytes(b"z" * 1000)
os.utime(old, (time.time() - 8 * 86400, time.time() - 8 * 86400))
fresh = mcp / "fresh.dump"; fresh.write_bytes(b"y" * 1000)
er.execute_prune(home / "evidence", home / "projects")
check("mcp-out old file pruned", not old.exists())
check("mcp-out fresh file kept", fresh.exists())
t.cleanup()

# --- custom policy parsing ---
t, home = make_home(policy="- **Artifact retention**: `10` days\n- **Summary retention**: `100` days\n- **Raw MCP output**: `3` days\n")
make_run(home, "20260101-120000", 15)   # >10d artifact, <100d summary -> artifacts
make_run(home, "20261120-120000", 1)
check("custom artifact_days honored", action(home, "20260101-120000") == "artifacts")
pol = er.read_policy(home / "projects" / "SHOP")
check("custom summary_days parsed", pol["summary_days"] == 100)
check("custom mcp_out_days parsed", pol["mcp_out_days"] == 3)
t.cleanup()

# --- summary_days < 90 -> CLI policy error exit 1 ---
t, home = make_home(policy="- **Summary retention**: `30` days\n")
r = subprocess.run([sys.executable, SCRIPT, "plan", "--qa-home", str(home)], capture_output=True, text=True)
check("summary retention below 90 exits 1", r.returncode == 1)
t.cleanup()

# --- reserved / foreign dirs untouched ---
t, home = make_home()
make_run(home, "20240101-120000", 800)
make_run(home, "20261120-120000", 1)
ev = home / "evidence"
(ev / ".audit").mkdir(); (ev / ".audit" / "keep.log").write_text("audit")
(ev / "_rollups" / "SHOP-900" / "20240101-120000").mkdir(parents=True)
(ev / "_rollups" / "SHOP-900" / "20240101-120000" / "rollup.json").write_text("{}")
(ev / "NOTATICKET").mkdir(); (ev / "NOTATICKET" / "old").mkdir()
er.execute_prune(ev, home / "projects")
check(".audit never pruned", (ev / ".audit" / "keep.log").exists())
check("_rollups never pruned", (ev / "_rollups" / "SHOP-900" / "20240101-120000" / "rollup.json").exists())
check("non-ticket dir untouched", (ev / "NOTATICKET" / "old").exists())
t.cleanup()

# --- symlink escape refused ---
t, home = make_home()
make_run(home, "20261120-120000", 1)
outside = Path(t.name) / "outside"; outside.mkdir(); (outside / "secret.png").write_bytes(b"s")
link = home / "evidence" / "SHOP" / "SHOP-1" / "20240101-120000"
link.parent.mkdir(parents=True, exist_ok=True)
os.symlink(outside, link)
er.execute_prune(home / "evidence", home / "projects")
check("symlinked run dir not followed/deleted", (outside / "secret.png").exists())
t.cleanup()

# --- status --hint threshold ---
t, home = make_home()
make_run(home, "20261120-120000", 1)
res, stats, pol = er.classify(home / "evidence", home / "projects")
check("hint silent below threshold", er.hint_line(stats, pol) == "")
t.cleanup()

# --- hint fires above threshold; notify policy parses despite backticks ---
t, home = make_home(policy="- **Notify above**: `0` GB or `1` prunable runs\n")
make_run(home, "20240101-120000", 800)
make_run(home, "20261120-120000", 1)
res, stats, pol = er.classify(home / "evidence", home / "projects")
check("notify policy parsed despite backticks", pol["SHOP"]["notify_runs"] == 1 and pol["SHOP"]["notify_bytes"] == 0)
check("hint fires above threshold", "prunable" in er.hint_line(stats, pol))
t.cleanup()

# --- plan writes nothing (except --out) ---
t, home = make_home()
make_run(home, "20240101-120000", 800)
before = sorted(str(p) for p in (home / "evidence").rglob("*"))
subprocess.run([sys.executable, SCRIPT, "plan", "--qa-home", str(home)], capture_output=True, text=True)
after = sorted(str(p) for p in (home / "evidence").rglob("*"))
check("plan writes nothing", before == after)
t.cleanup()

print()
if fails == 0:
    print("all fixtures passed")
else:
    print(f"{fails} fixture(s) failed")
sys.exit(fails)
PY

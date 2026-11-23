#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit
# Fixtures for epic-rollup.py — classification matrix, staleness, worst-verdict,
# coverage/gates, retention-index fallback, determinism, fail-closed children.
# A rollup is a report: it must never invent a verdict or write a run summary.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../scripts/epic-rollup.py"
[ -f "$SCRIPT" ] || SCRIPT="$HERE/../../../scripts/epic-rollup.py"
[ -f "$SCRIPT" ] || { echo "epic-rollup.py not found" >&2; exit 1; }

exec python3 - "$SCRIPT" <<'PY'
import importlib.util, json, os, subprocess, sys, tempfile
from pathlib import Path

SCRIPT = sys.argv[1]
spec = importlib.util.spec_from_file_location("er", SCRIPT)
er = importlib.util.module_from_spec(spec)
spec.loader.exec_module(er)

fails = 0
def check(name, cond):
    global fails
    if cond: print(f"ok    {name}")
    else: print(f"FAIL  {name}"); fails += 1

def make_home(gates=None):
    t = tempfile.TemporaryDirectory()
    home = Path(t.name)
    (home / "projects" / "SHOP").mkdir(parents=True)
    (home / "evidence").mkdir()
    md = "# Project File: SHOP\n"
    if gates:
        md += "## Pipelines / quality gates\n- **Gate overrides**: " + gates + "\n"
    (home / "projects" / "SHOP" / "PROJECT.md").write_text(md)
    return t, home

def make_run(home, key, verdict, build="2.0", schema=2, findings=None, ts="2026-11-01T12:00:00Z", run="20261101-120000"):
    d = home / "evidence" / "SHOP" / key / run
    d.mkdir(parents=True)
    s = {"schema_version": schema, "ticket": key, "project": "SHOP", "timestamp": ts,
         "verdict": verdict, "environment": {"version_or_build": build}, "findings": findings or []}
    (d / "execution_summary.json").write_text(json.dumps(s))
    return d

def doc(keys, epic="SHOP-900"):
    return {"epic": epic, "project": "SHOP",
            "children": [{"key": k, "status": "Done", "type": "Story", "summary": k} for k in keys]}

def rollup(home, keys, current_build="2.0", release_mode=False, epic="SHOP-900"):
    return er.build_rollup(doc(keys, epic), home / "evidence", "SHOP", current_build, release_mode)

def cls(r, key):
    return next(c["classification"] for c in r["children"] if c["key"] == key)

# --- classification matrix ---
t, home = make_home()
make_run(home, "SHOP-1", "PASS"); make_run(home, "SHOP-2", "FAIL")
make_run(home, "SHOP-3", "BLOCKED"); make_run(home, "SHOP-4", "NEEDS_REVIEW")
make_run(home, "SHOP-5", "NO_TEST")
r = rollup(home, ["SHOP-1","SHOP-2","SHOP-3","SHOP-4","SHOP-5","SHOP-6"])
check("PASS -> tested-pass", cls(r,"SHOP-1")=="tested-pass")
check("FAIL -> tested-fail", cls(r,"SHOP-2")=="tested-fail")
check("BLOCKED -> blocked", cls(r,"SHOP-3")=="blocked")
check("NEEDS_REVIEW -> needs-review", cls(r,"SHOP-4")=="needs-review")
check("NO_TEST -> no-test", cls(r,"SHOP-5")=="no-test")
check("no evidence -> untested", cls(r,"SHOP-6")=="untested")
t.cleanup()

# --- staleness ---
t, home = make_home()
make_run(home, "SHOP-1", "PASS", build="1.0")   # current 2.0 -> stale
make_run(home, "SHOP-2", "PASS", build="2.0")   # current -> tested-pass
r = rollup(home, ["SHOP-1","SHOP-2"], current_build="2.0")
check("PASS on old build -> stale", cls(r,"SHOP-1")=="stale")
check("PASS on current build -> tested-pass", cls(r,"SHOP-2")=="tested-pass")
check("stale listed", r["stale"]==["SHOP-1"])
# no current-build -> no staleness check
r2 = rollup(home, ["SHOP-1"], current_build=None)
check("without current-build PASS stays tested-pass", cls(r2,"SHOP-1")=="tested-pass")
t.cleanup()

# --- build-unverified flag ---
t, home = make_home()
d = make_run(home, "SHOP-1", "PASS", build="2.0")
s = json.loads((d/"execution_summary.json").read_text()); s["environment"]={}; (d/"execution_summary.json").write_text(json.dumps(s))
r = rollup(home, ["SHOP-1"], current_build="2.0")
check("missing build -> build-unverified flag", "build-unverified" in next(c["flags"] for c in r["children"] if c["key"]=="SHOP-1"))
t.cleanup()

# --- legacy + pruned flags ---
t, home = make_home()
make_run(home, "SHOP-1", "PASS", schema=1)
r = rollup(home, ["SHOP-1"])
check("schema v1 -> legacy-evidence flag", "legacy-evidence" in next(c["flags"] for c in r["children"] if c["key"]=="SHOP-1"))
# pruned: no run dir, but index line
idx = home/"evidence"/".audit"; idx.mkdir(parents=True)
(idx/"retention-index.log").write_text("2026-11-23T00:00:00Z | project=SHOP | ticket=SHOP-9 | run=20240101-120000 | verdict=PASS | mode=hybrid | product=- | build=2.0 | timestamp=2024-01-01T12:00:00Z\n")
r = rollup(home, ["SHOP-9"])
check("pruned run -> pruned-evidence flag", "pruned-evidence" in next(c["flags"] for c in r["children"] if c["key"]=="SHOP-9"))
check("pruned PASS not counted as covered", r["coverage_percent"]==0.0)
t.cleanup()

# --- worst-verdict order ---
t, home = make_home()
make_run(home, "SHOP-1", "PASS"); make_run(home, "SHOP-2", "BLOCKED"); make_run(home, "SHOP-3", "NEEDS_REVIEW")
check("worst BLOCKED > NEEDS_REVIEW > PASS", rollup(home,["SHOP-1","SHOP-2","SHOP-3"])["worst_verdict"]=="BLOCKED")
make_run(home, "SHOP-4", "FAIL")
check("worst FAIL dominates", rollup(home,["SHOP-1","SHOP-2","SHOP-3","SHOP-4"])["worst_verdict"]=="FAIL")
t.cleanup()

# --- coverage + pass rate math ---
t, home = make_home()
make_run(home, "SHOP-1", "PASS"); make_run(home, "SHOP-2", "FAIL"); make_run(home, "SHOP-3", "NEEDS_REVIEW")
r = rollup(home, ["SHOP-1","SHOP-2","SHOP-3","SHOP-4"])  # SHOP-4 untested
check("coverage 3/4 = 75%", r["coverage_percent"]==75.0)
check("pass rate 1/3 decided = 33.3%", r["pass_rate_percent"]==33.3)
t.cleanup()

# --- recommendation logic ---
t, home = make_home()
make_run(home, "SHOP-1", "PASS"); make_run(home, "SHOP-2", "PASS")
check("all pass + covered -> go", rollup(home,["SHOP-1","SHOP-2"])["recommendation"]=="go")
check("untested gap -> insufficient-evidence", rollup(home,["SHOP-1","SHOP-2","SHOP-3"])["recommendation"]=="insufficient-evidence")
make_run(home, "SHOP-3", "FAIL")
check("FAIL -> no-go", rollup(home,["SHOP-1","SHOP-2","SHOP-3"])["recommendation"]=="no-go")
t.cleanup()

# --- gate breach -> no-go (all covered, no FAIL, but P0 present) ---
t, home = make_home()
make_run(home, "SHOP-1", "PASS", findings=[{"severity":"P0","summary":"blocker"}])
make_run(home, "SHOP-2", "PASS")
r = rollup(home,["SHOP-1","SHOP-2"])
check("P0 finding breaches gate -> no-go", r["recommendation"]=="no-go")
check("gate breach names P0", any("P0" in b for b in r["gate_breaches"]))
t.cleanup()

# --- determinism ---
t, home = make_home()
make_run(home, "SHOP-1", "PASS"); make_run(home, "SHOP-2", "FAIL")
a = json.dumps(rollup(home,["SHOP-1","SHOP-2"]), sort_keys=True)
b = json.dumps(rollup(home,["SHOP-1","SHOP-2"]), sort_keys=True)
check("byte-deterministic rollup", a==b)
t.cleanup()

# --- CLI: malformed children -> exit 1, no summary written ---
t, home = make_home()
bad = home/"bad.json"; bad.write_text("{not json")
p = subprocess.run([sys.executable, SCRIPT, "--children", str(bad), "--qa-home", str(home), "--project", "SHOP"], capture_output=True, text=True)
check("malformed children exits 1", p.returncode==1)
good = home/"children.json"; good.write_text(json.dumps(doc(["SHOP-1"])))
make_run(home, "SHOP-1", "PASS")
p = subprocess.run([sys.executable, SCRIPT, "--children", str(good), "--qa-home", str(home), "--project", "SHOP"], capture_output=True, text=True)
check("valid children exits 0", p.returncode==0)
check("rollup never writes execution_summary.json", not list((home/"evidence"/"SHOP"/"_rollups").rglob("execution_summary.json")))
check("rollup writes rollup.json + rollup.md", list((home/"evidence"/"SHOP"/"_rollups").rglob("rollup.json")) and list((home/"evidence"/"SHOP"/"_rollups").rglob("rollup.md")))
t.cleanup()

# --- release mode ---
t, home = make_home()
make_run(home, "SHOP-1", "PASS")
d = {"release":"2.14.0","project":"SHOP","children":[{"key":"SHOP-1","status":"Done","type":"Story","summary":"x","fixVersions":["2.14.0"]}]}
r = er.build_rollup(d, home/"evidence", "SHOP", "2.0", True)
check("release-mode kind + identifier", r["kind"]=="release-rollup" and r["identifier"]=="2.14.0")
t.cleanup()

print()
if fails==0: print("all fixtures passed")
else: print(f"{fails} fixture(s) failed")
sys.exit(fails)
PY

#!/usr/bin/env bash
#
# manifest-conventions.sh — guards the manifest against the bug class that
# killed v0.2.0 in the field: a component-path key in plugin.json pointing at
# the SAME file Claude Code already auto-discovers by convention. The loader
# then registers the component twice and the plugin fails to load at all
# ("Duplicate hooks file detected") — while `claude plugin validate` happily
# passes it. Loud failure, deterministic check: belongs to a fixture.
#
# Convention locations (plugin root, auto-discovered):
#   hooks/hooks.json, .mcp.json, .lsp.json, skills/, agents/, commands/
# Declaring any of these via plugin.json is at best redundant, at worst a
# duplicate load. Custom paths (e.g. skills → ./.claude/skills) are fine.
#
# Also asserted here: plugin.json and marketplace.json versions must agree —
# the tag command checks it, this fixture catches it earlier.
#
# Usage:  bash .claude/hooks/tests/manifest-conventions.sh
# Exit:   0 = all fixtures pass, otherwise the number of failures.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MANIFEST="$ROOT/.claude-plugin/plugin.json"
MARKETPLACE="$ROOT/.claude-plugin/marketplace.json"

[ -f "$MANIFEST" ] || { echo "plugin.json not found at $MANIFEST" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || { echo "python3 required" >&2; exit 1; }

python3 - "$MANIFEST" "$MARKETPLACE" <<'PY'
import json, os, sys

manifest_path, marketplace_path = sys.argv[1], sys.argv[2]
root = os.path.dirname(os.path.dirname(manifest_path))

with open(manifest_path) as fh:
    manifest = json.load(fh)

fails = 0

def ok(name):
    print(f"ok    {name}")

def fail(name, why):
    global fails
    fails += 1
    print(f"FAIL  {name}\n      {why}")

# key in plugin.json -> convention path (relative to plugin root) that the
# loader auto-discovers. A declared path resolving to one of these duplicates
# (hooks/mcpServers/lspServers: additive) or pointlessly restates (agents/
# commands: replace-semantics) the convention load.
CONVENTIONS = {
    "hooks": ["hooks/hooks.json"],
    "mcpServers": [".mcp.json"],
    "lspServers": [".lsp.json"],
    "skills": ["skills", "skills/"],
    "agents": ["agents", "agents/"],
    "commands": ["commands", "commands/"],
    "outputStyles": ["output-styles", "output-styles/"],
}

def norm(p):
    return os.path.normpath(p).replace(os.sep, "/")

declared_any = False
for key, conv_paths in CONVENTIONS.items():
    value = manifest.get(key)
    if value is None:
        continue
    # Inline config (object) cannot collide with a file path.
    if isinstance(value, dict):
        ok(f"'{key}' is inline config — no path collision possible")
        continue
    paths = value if isinstance(value, list) else [value]
    for p in paths:
        if not isinstance(p, str):
            continue
        declared_any = True
        n = norm(p)
        if n in [norm(c) for c in conv_paths]:
            fail(f"'{key}' must not declare convention path '{p}'",
                 f"'{n}' is auto-discovered by the loader — declaring it loads the "
                 f"component TWICE (v0.2.0 shipped 'hooks: ./hooks/hooks.json' and the "
                 f"plugin failed to load anywhere). Drop the key; keep the file.")
        else:
            ok(f"'{key}' points at custom path '{p}' (not the convention path)")

if not declared_any:
    ok("no component-path keys declare file paths (all convention loading)")

# Version agreement between the two manifests (the tag command enforces this
# at release time; catch drift earlier, here).
if os.path.exists(marketplace_path):
    with open(marketplace_path) as fh:
        marketplace = json.load(fh)
    mv = None
    for plugin in marketplace.get("plugins", []):
        if plugin.get("name") == manifest.get("name"):
            mv = plugin.get("version")
            break
    pv = manifest.get("version")
    if mv is None:
        fail("marketplace lists the plugin", f"no entry named '{manifest.get('name')}' in marketplace.json")
    elif mv != pv:
        fail("manifest versions agree", f"plugin.json={pv} but marketplace.json={mv}")
    else:
        ok(f"manifest versions agree ({pv})")

print()
if fails:
    print(f"{fails} fixture(s) failed")
else:
    print("all fixtures passed")
sys.exit(fails)
PY

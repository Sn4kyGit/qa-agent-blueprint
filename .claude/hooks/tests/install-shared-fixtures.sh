#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
INSTALL="$REPO/install.sh"
[ -x "$INSTALL" ] || { echo "install.sh not executable at $INSTALL" >&2; exit 1; }

fails=0
WORK="$(mktemp -d)"
if [ "${QA_KEEP:-0}" = "1" ]; then
  echo "work dir kept: $WORK"
else
  trap 'rm -r "$WORK" 2>/dev/null' EXIT
fi

pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }
assert_file() { [ -f "$2" ] && pass "$1" || fail "$1" "missing file: $2"; }
assert_no_file() { [ ! -e "$2" ] && [ ! -L "$2" ] && pass "$1" || fail "$1" "should not exist: $2"; }
assert_link_to() { [ "$(readlink "$2" 2>/dev/null)" = "$3" ] && pass "$1" || fail "$1" "$2 -> $(readlink "$2" 2>/dev/null || echo MISSING), expected $3"; }
assert_real_dir() { [ -d "$2" ] && [ ! -L "$2" ] && pass "$1" || fail "$1" "not a real directory: $2"; }
assert_grep() { grep -qF -- "$3" "$2" 2>/dev/null && pass "$1" || fail "$1" "not found in $2: $3"; }
assert_no_grep() { grep -qF -- "$3" "$2" 2>/dev/null && fail "$1" "should not appear in $2: $3" || pass "$1"; }

json_check() {
  python3 - "$2" "$3" <<'PY' >/dev/null 2>&1 && pass "$1" || fail "$1" "JSON check failed: $3"
import json, sys
cfg = json.load(open(sys.argv[1]))
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
}

cfg_check() {
  python3 - "$2" "$3" <<'PY' >/dev/null 2>&1 && pass "$1" || fail "$1" "config check failed: $3"
import json, sys
text = open(sys.argv[1]).read()
out, i, n, in_str = [], 0, len(text), False
while i < n:
    c = text[i]
    if in_str:
        out.append(c)
        if c == '"': in_str = False
        i += 1
    elif c == '"':
        in_str = True
        out.append(c)
        i += 1
    elif c == "/" and i + 1 < n and text[i+1] == "/":
        while i < n and text[i] != "\n": i += 1
    elif c == "/" and i + 1 < n and text[i+1] == "*":
        end = text.find("*/", i + 2)
        i = n if end == -1 else end + 2
    else:
        out.append(c)
        i += 1
cfg = json.loads("".join(out))
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
}

settings_hooks_check() {
  python3 - "$1" "$REPO/.claude/settings.json" "$2" <<'PY' >/dev/null 2>&1
import json, sys
actual = json.load(open(sys.argv[1]))
bp = json.load(open(sys.argv[2]))
def pairs(cfg):
    return {(ev, e.get("matcher"), h.get("command")) for ev, entries in cfg.get("hooks", {}).items() for e in entries for h in e.get("hooks", [])}
a = pairs(actual)
b = pairs(bp)
ok = b <= a and not any("/hooks/qa-blueprint/" in command for _, _, command in a)
if sys.argv[3] == "exact":
    ok = ok and a == b
sys.exit(0 if ok else 1)
PY
  if [ $? -eq 0 ]; then pass "$3"; else fail "$3" "blueprint hook pairs missing, duplicated, or namespaced"; fi
}

router_block_check() {
  python3 - "$1" "$REPO/CLAUDE.md" <<'PY' >/dev/null 2>&1
import sys
text = open(sys.argv[1]).read()
router = open(sys.argv[2]).read().strip()
start = "<!-- >>> qa-agent-blueprint (managed, do not edit) -->"
end = "<!-- <<< qa-agent-blueprint -->"
sys.exit(0 if text.count(start) == 1 and text.count(end) == 1 and text.split(start, 1)[1].split(end, 1)[0].strip() == router else 1)
PY
  if [ $? -eq 0 ]; then pass "$2"; else fail "$2" "managed block does not contain exactly the current full router"; fi
}

echo "== fresh shared install =="
FRESH="$WORK/fresh"
mkdir -p "$FRESH"
OUT="$("$INSTALL" --mode shared --target "$FRESH" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "fresh install exits 0" "$(printf '%s' "$OUT" | tail -4)"; else pass "fresh install exits 0"; fi
assert_real_dir "consumer .claude is real" "$FRESH/.claude"
for item in rules skills agents hooks scripts; do
  assert_link_to ".claude/$item linked selectively" "$FRESH/.claude/$item" "$REPO/.claude/$item"
done
assert_link_to "opencode router linked" "$FRESH/.opencode/ROUTER.md" "$REPO/opencode/ROUTER.md"
assert_link_to "opencode agents linked" "$FRESH/.opencode/agents" "$REPO/opencode/agents"
assert_link_to "opencode commands linked" "$FRESH/.opencode/commands" "$REPO/opencode/commands"
assert_link_to "opencode plugins linked" "$FRESH/.opencode/plugins" "$REPO/opencode/plugins"
assert_no_file "no additional opencode .claude compatibility link" "$FRESH/.opencode/.claude"
assert_link_to "docs support link" "$FRESH/docs" "$REPO/docs"
assert_link_to "project template support link" "$FRESH/projects/_template" "$REPO/projects/_template"
assert_link_to "project example support link" "$FRESH/projects/EXAMPLE" "$REPO/projects/EXAMPLE"
assert_link_to "plugin manifest support link" "$FRESH/.claude-plugin" "$REPO/.claude-plugin"
assert_link_to "changelog support link" "$FRESH/CHANGELOG.md" "$REPO/CHANGELOG.md"
assert_real_dir "projects is consumer-owned" "$FRESH/projects"
assert_real_dir "memory is consumer-owned" "$FRESH/memory"
assert_real_dir "evidence is consumer-owned" "$FRESH/evidence"
assert_real_dir ".agents is consumer-owned" "$FRESH/.agents"
assert_file "QA home marker" "$FRESH/.qa-home"
assert_file "secrets placeholder" "$FRESH/.env.playwright-secrets"
assert_file "browser preferences" "$FRESH/.playwright-mcp.config.json"
assert_file "Claude settings" "$FRESH/.claude/settings.json"
assert_file "Claude MCP config" "$FRESH/.mcp.json"
assert_file "opencode config" "$FRESH/opencode.json"
cmp -s "$FRESH/CLAUDE.md" "$REPO/CLAUDE.md" && pass "fresh router is the full blueprint router" || fail "fresh router is the full blueprint router"
json_check "project plugin explicitly disabled" "$FRESH/.claude/settings.json" "cfg['enabledPlugins']['qa-agent-blueprint@qa-agent-blueprint-marketplace'] is False"
settings_hooks_check "$FRESH/.claude/settings.json" exact "all Claude hook events and matchers installed"
json_check "Claude MCP contract names" "$FRESH/.mcp.json" "set(['playwright','atlassian']) <= set(cfg.get('mcpServers',{}))"
cfg_check "opencode MCP contract names" "$FRESH/opencode.json" "set(['playwright','atlassian']) <= set(cfg.get('mcp',{}))"
cfg_check "opencode router instructions and depth" "$FRESH/opencode.json" "any('ROUTER.md' in str(i) for i in cfg.get('instructions',[])) and cfg.get('subagent_depth') == 2"
cfg_check "opencode playwright contract flags" "$FRESH/opencode.json" "all(f in cfg['mcp']['playwright']['command'] for f in ['--config','--secrets','--output-dir','--image-responses'])"
mkdir -p "$FRESH/.agents/qa-project-context" "$FRESH/projects/TA" "$FRESH/evidence/TA"
printf 'consumer bridge\n' > "$FRESH/.agents/qa-project-context/SHARED-FIXTURE.md"
printf 'consumer memory\n' > "$FRESH/memory/SHARED-FIXTURE.md"
printf '# TA\n' > "$FRESH/projects/TA/PROJECT.md"
printf 'evidence\n' > "$FRESH/evidence/TA/SHARED-FIXTURE.txt"
assert_no_file "bridge data never lands in blueprint" "$REPO/.agents/qa-project-context/SHARED-FIXTURE.md"
assert_no_file "memory data never lands in blueprint" "$REPO/memory/SHARED-FIXTURE.md"

echo
echo "== plugin migration and foreign settings =="
PLUGIN="$WORK/plugin-migration"
mkdir -p "$PLUGIN/.claude"
cat > "$PLUGIN/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": ["Bash(ls:*)", "Bash(git status:*)"],
    "deny": ["Read(foreign-secret)"]
  },
  "enabledPlugins": {
    "qa-agent-blueprint@qa-agent-blueprint-marketplace": true,
    "foreign@marketplace": true
  },
  "extraKnownMarketplaces": {
    "qa-agent-blueprint": {"source": {"source": "local", "path": "/keep/me"}},
    "foreign": {"keep": true}
  },
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/session-start.sh"}]}
    ],
    "PreToolUse": [
      {"matcher": "ForeignTool", "hooks": [{"type": "command", "command": "foreign-hook"}]}
    ]
  },
  "foreignTopLevel": {"keep": "yes"}
}
JSON
printf '%s\n' '{"instructions":[".opencode/ROUTER.md",".claude/rules/core/*.md","docs/consumer.md"]}' > "$PLUGIN/opencode.json"
printf '%s\n' '{"enabledPlugins":{"foreign-local@marketplace":true},"foreignLocal":42}' > "$PLUGIN/.claude/settings.local.json"
cp "$PLUGIN/.claude/settings.local.json" "$WORK/settings-local-before.json"
OUT="$("$INSTALL" --mode shared --target "$PLUGIN" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "plugin migration exits 0" "$(printf '%s' "$OUT" | tail -4)"; else pass "plugin migration exits 0"; fi
assert_real_dir "plugin migration keeps real .claude" "$PLUGIN/.claude"
json_check "migrated plugin disabled only at project scope" "$PLUGIN/.claude/settings.json" "cfg['enabledPlugins']['qa-agent-blueprint@qa-agent-blueprint-marketplace'] is False"
json_check "foreign plugin remains enabled" "$PLUGIN/.claude/settings.json" "cfg['enabledPlugins']['foreign@marketplace'] is True"
json_check "marketplace metadata preserved" "$PLUGIN/.claude/settings.json" "cfg['extraKnownMarketplaces']['qa-agent-blueprint']['source']['path'] == '/keep/me' and cfg['extraKnownMarketplaces']['foreign']['keep'] is True"
json_check "foreign permissions preserved" "$PLUGIN/.claude/settings.json" "'Bash(ls:*)' in cfg['permissions']['allow'] and 'Read(foreign-secret)' in cfg['permissions']['deny']"
json_check "foreign top-level settings preserved" "$PLUGIN/.claude/settings.json" "cfg['foreignTopLevel']['keep'] == 'yes'"
json_check "foreign hook preserved beside blueprint hooks" "$PLUGIN/.claude/settings.json" "any(e.get('matcher') == 'ForeignTool' and any(h.get('command') == 'foreign-hook' for h in e.get('hooks',[])) for e in cfg['hooks']['PreToolUse'])"
settings_hooks_check "$PLUGIN/.claude/settings.json" subset "plugin migration merges every hook matcher without namespacing"
cmp -s "$PLUGIN/.claude/settings.local.json" "$WORK/settings-local-before.json" && pass "settings.local.json untouched" || fail "settings.local.json untouched"

echo
echo "== opencode migration =="
OCTARGET="$WORK/opencode-migration"
mkdir -p "$OCTARGET"
"$INSTALL" --mode opencode --target "$OCTARGET" --yes >/dev/null 2>&1
mkdir -p "$OCTARGET/memory" "$OCTARGET/projects/OC" "$OCTARGET/evidence/OC"
printf 'keep memory\n' > "$OCTARGET/memory/keep.md"
printf '# OC\n' > "$OCTARGET/projects/OC/PROJECT.md"
printf 'keep evidence\n' > "$OCTARGET/evidence/OC/keep.txt"
OUT="$("$INSTALL" --mode shared --target "$OCTARGET" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "opencode migration exits 0" "$(printf '%s' "$OUT" | tail -4)"; else pass "opencode migration exits 0"; fi
assert_real_dir "whole .claude compatibility link migrated" "$OCTARGET/.claude"
assert_real_dir "whole .agents compatibility link migrated" "$OCTARGET/.agents"
assert_link_to "migrated selective skills link" "$OCTARGET/.claude/skills" "$REPO/.claude/skills"
assert_grep "opencode migration memory preserved" "$OCTARGET/memory/keep.md" "keep memory"
assert_grep "opencode migration project preserved" "$OCTARGET/projects/OC/PROJECT.md" "# OC"
assert_grep "opencode migration evidence preserved" "$OCTARGET/evidence/OC/keep.txt" "keep evidence"
cfg_check "opencode instructions not duplicated by migration" "$OCTARGET/opencode.json" "len([i for i in cfg['instructions'] if 'ROUTER.md' in str(i)]) == 1"
assert_link_to "opencode migration adds template support" "$OCTARGET/projects/_template" "$REPO/projects/_template"

echo
echo "== shared migrates existing opencode.jsonc =="
JSONC="$WORK/shared-jsonc"
mkdir -p "$JSONC"
cat > "$JSONC/opencode.jsonc" <<'JSONC'
{
  // consumer settings survive migration
  "model": "openrouter/consumer-\"model\"",
  "note": "escaped quotes and trailing commas stay valid",
  "instructions": ["docs/consumer.md",],
  "mcp": {
    "consumer": {"type": "local", "command": ["consumer-mcp"]}
  }
}
JSONC
OUT="$("$INSTALL" --mode shared --target "$JSONC" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "shared JSONC migration exits 0" "$(printf '%s' "$OUT" | tail -4)"; else pass "shared JSONC migration exits 0"; fi
assert_file "JSONC migrated to opencode.json" "$JSONC/opencode.json"
assert_no_file "old opencode.jsonc no longer active" "$JSONC/opencode.jsonc"
assert_file "JSONC original backup kept" "$(ls "$JSONC"/opencode.jsonc.bak-* 2>/dev/null | head -1)"
cfg_check "JSONC escaped model preserved" "$JSONC/opencode.json" "cfg.get('model') == 'openrouter/consumer-\"model\"'"
cfg_check "JSONC consumer instruction preserved beside blueprint" "$JSONC/opencode.json" "'docs/consumer.md' in cfg['instructions'] and any('ROUTER.md' in str(i) for i in cfg['instructions'])"
cfg_check "JSONC consumer MCP preserved beside blueprint" "$JSONC/opencode.json" "cfg['mcp']['consumer']['command'] == ['consumer-mcp'] and 'playwright' in cfg['mcp'] and 'atlassian' in cfg['mcp']"

echo
echo "== existing router gets a current full managed block =="
ROUTER="$WORK/router"
mkdir -p "$ROUTER"
printf '# Consumer\n\nKeep this router content.\n' > "$ROUTER/CLAUDE.md"
"$INSTALL" --mode shared --target "$ROUTER" --yes >/dev/null 2>&1
assert_grep "foreign router content kept" "$ROUTER/CLAUDE.md" "Keep this router content."
router_block_check "$ROUTER/CLAUDE.md" "managed block is the full shared router"
assert_no_grep "managed router is not integrate namespace" "$ROUTER/CLAUDE.md" ".claude/rules/qa-blueprint/"
cp "$ROUTER/CLAUDE.md" "$WORK/router-before-rerun.md"
OLD_ROUTER="$WORK/old-integrate-router"
mkdir -p "$OLD_ROUTER"
cat > "$OLD_ROUTER/CLAUDE.md" <<'EOF'
# Consumer

Keep this too.

<!-- >>> qa-agent-blueprint (managed, do not edit) -->

## QA Agent Blueprint (integrated)

Old namespaced router.

<!-- <<< qa-agent-blueprint -->
EOF
"$INSTALL" --mode shared --target "$OLD_ROUTER" --yes >/dev/null 2>&1
assert_grep "old integrate router foreign content kept" "$OLD_ROUTER/CLAUDE.md" "Keep this too."
router_block_check "$OLD_ROUTER/CLAUDE.md" "old integrate managed block replaced by full shared router"
assert_no_grep "old integrate router text removed" "$OLD_ROUTER/CLAUDE.md" "Old namespaced router."

echo
echo "== idempotent re-run =="
cp "$FRESH/.claude/settings.json" "$WORK/fresh-settings-before.json"
cp "$FRESH/opencode.json" "$WORK/fresh-opencode-before.json"
cp "$FRESH/.mcp.json" "$WORK/fresh-mcp-before.json"
OUT="$("$INSTALL" --mode shared --target "$FRESH" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "shared re-run exits 0" "$(printf '%s' "$OUT" | tail -4)"; else pass "shared re-run exits 0"; fi
cmp -s "$FRESH/.claude/settings.json" "$WORK/fresh-settings-before.json" && pass "settings unchanged on re-run" || fail "settings unchanged on re-run"
cmp -s "$FRESH/opencode.json" "$WORK/fresh-opencode-before.json" && pass "opencode config unchanged on re-run" || fail "opencode config unchanged on re-run"
cmp -s "$FRESH/.mcp.json" "$WORK/fresh-mcp-before.json" && pass "MCP config unchanged on re-run" || fail "MCP config unchanged on re-run"
settings_hooks_check "$FRESH/.claude/settings.json" exact "re-run does not duplicate hooks"
assert_grep "consumer memory survives re-run" "$FRESH/memory/SHARED-FIXTURE.md" "consumer memory"
"$INSTALL" --mode shared --target "$ROUTER" --yes >/dev/null 2>&1
cmp -s "$ROUTER/CLAUDE.md" "$WORK/router-before-rerun.md" && pass "managed router block unchanged on re-run" || fail "managed router block unchanged on re-run"
router_block_check "$ROUTER/CLAUDE.md" "managed router block not duplicated"

echo
echo "== integrate collisions block before writes =="
COLLIDE="$WORK/integrate-collision"
mkdir -p "$COLLIDE/.claude/rules/qa-blueprint/core" "$COLLIDE/docs/qa-blueprint"
printf 'foreign integrated rule\n' > "$COLLIDE/.claude/rules/qa-blueprint/core/keep.md"
printf 'foreign docs\n' > "$COLLIDE/docs/qa-blueprint/keep.md"
printf 'foreign changelog\n' > "$COLLIDE/CHANGELOG.md"
cp -R "$COLLIDE" "$WORK/collision-before"
OUT="$("$INSTALL" --mode shared --target "$COLLIDE" --yes 2>&1)"
if [ $? -eq 0 ]; then fail "integrate collision exits nonzero" "installer unexpectedly succeeded"; else pass "integrate collision exits nonzero"; fi
printf '%s' "$OUT" | grep -q "BLOCKED" && pass "collision reports BLOCKED migration plan" || fail "collision reports BLOCKED migration plan" "$OUT"
diff -r "$WORK/collision-before" "$COLLIDE" >/dev/null 2>&1 && pass "collision run writes nothing" || fail "collision run writes nothing"
assert_no_file "collision run creates no opencode surface" "$COLLIDE/.opencode"
assert_no_file "collision run creates no QA marker" "$COLLIDE/.qa-home"
DUAL="$WORK/dual-opencode-config"
mkdir -p "$DUAL"
printf '%s\n' '{"instructions":["json.md"]}' > "$DUAL/opencode.json"
printf '%s\n' '{"instructions":["jsonc.md"]}' > "$DUAL/opencode.jsonc"
cp -R "$DUAL" "$WORK/dual-before"
OUT="$("$INSTALL" --mode shared --target "$DUAL" --yes 2>&1)"
if [ $? -eq 0 ]; then fail "dual opencode config exits nonzero" "installer unexpectedly succeeded"; else pass "dual opencode config exits nonzero"; fi
printf '%s' "$OUT" | grep -q "BLOCKED" && pass "dual opencode config reports BLOCKED" || fail "dual opencode config reports BLOCKED" "$OUT"
diff -r "$WORK/dual-before" "$DUAL" >/dev/null 2>&1 && pass "dual opencode collision writes nothing" || fail "dual opencode collision writes nothing"
FOREIGN="$WORK/foreign-symlink"
mkdir -p "$FOREIGN/.claude" "$WORK/foreign-target/skills"
ln -s "$WORK/foreign-target/skills" "$FOREIGN/.claude/skills"
OUT="$("$INSTALL" --mode shared --target "$FOREIGN" --yes 2>&1)"
[ "$(readlink "$FOREIGN/.claude/skills")" = "$WORK/foreign-target/skills" ] && pass "foreign selective symlink never repointed" || fail "foreign selective symlink never repointed"
printf '%s' "$OUT" | grep -q "BLOCKED" && pass "foreign selective symlink blocks safely" || fail "foreign selective symlink blocks safely"

echo
echo "== dry-run and move rejection =="
DRY="$WORK/dry-run"
mkdir -p "$DRY"
OUT="$("$INSTALL" --mode shared --target "$DRY" --yes --dry-run 2>&1)"
if [ $? -ne 0 ]; then fail "shared dry-run exits 0" "$(printf '%s' "$OUT" | tail -4)"; else pass "shared dry-run exits 0"; fi
[ -z "$(find "$DRY" -mindepth 1 -print -quit)" ] && pass "dry-run writes nothing" || fail "dry-run writes nothing" "$(find "$DRY" -mindepth 1 -print -quit)"
MOVE="$WORK/move-reject"
mkdir -p "$MOVE"
OUT="$("$INSTALL" --mode shared --target "$MOVE" --move "$WORK/move-destination" --yes 2>&1)"
if [ $? -eq 0 ]; then fail "shared --move rejected" "installer unexpectedly accepted --move"; else pass "shared --move rejected"; fi
printf '%s' "$OUT" | grep -q "shared is not movable" && pass "shared move rejection is explicit" || fail "shared move rejection is explicit" "$OUT"
assert_no_file "rejected move writes nothing" "$MOVE/.opencode"

echo
echo "== user-scope plugin is read only =="
FAKEHOME="$WORK/fake-home"
USERTARGET="$WORK/user-scope"
mkdir -p "$FAKEHOME/.claude" "$USERTARGET"
printf '%s\n' '{"enabledPlugins":{"qa-agent-blueprint@qa-agent-blueprint-marketplace":true,"foreign@marketplace":true},"keep":"global"}' > "$FAKEHOME/.claude/settings.json"
cp "$FAKEHOME/.claude/settings.json" "$WORK/user-settings-before.json"
OUT="$(HOME="$FAKEHOME" "$INSTALL" --mode shared --target "$USERTARGET" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "user-scope fixture install exits 0" "$(printf '%s' "$OUT" | tail -4)"; else pass "user-scope fixture install exits 0"; fi
cmp -s "$FAKEHOME/.claude/settings.json" "$WORK/user-settings-before.json" && pass "global settings unchanged" || fail "global settings unchanged"
printf '%s' "$OUT" | grep -q "user-scope plugin" && pass "user-scope plugin warning reported" || fail "user-scope plugin warning reported" "$OUT"
printf '%s' "$OUT" | grep -q "Human step" && pass "user-scope human step reported" || fail "user-scope human step reported" "$OUT"
json_check "project false still written with user-scope plugin" "$USERTARGET/.claude/settings.json" "cfg['enabledPlugins']['qa-agent-blueprint@qa-agent-blueprint-marketplace'] is False"

echo
echo "== uninstall removes shared links and dead references =="
python3 - "$FRESH/.claude/settings.json" <<'PY'
import json, sys
path = sys.argv[1]
cfg = json.load(open(path))
cfg.setdefault("permissions", {}).setdefault("allow", []).append("Bash(foreign-uninstall:*)")
cfg.setdefault("hooks", {}).setdefault("PreToolUse", []).append({"matcher": "ForeignTool", "hooks": [{"type": "command", "command": "foreign-uninstall-hook"}]})
cfg["foreignUninstall"] = {"keep": True}
with open(path, "w") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
PY
python3 - "$FRESH/opencode.json" <<'PY'
import json, sys
path = sys.argv[1]
text = open(path).read()
out, i, n, in_str = [], 0, len(text), False
while i < n:
    c = text[i]
    if in_str:
        out.append(c)
        if c == '"': in_str = False
        i += 1
    elif c == '"':
        in_str = True
        out.append(c)
        i += 1
    elif c == "/" and i + 1 < n and text[i+1] == "/":
        while i < n and text[i] != "\n": i += 1
    elif c == "/" and i + 1 < n and text[i+1] == "*":
        end = text.find("*/", i + 2)
        i = n if end == -1 else end + 2
    else:
        out.append(c)
        i += 1
cfg = json.loads("".join(out))
cfg.setdefault("instructions", []).append("docs/foreign-uninstall.md")
cfg.setdefault("mcp", {})["foreign"] = {"type": "local", "command": ["foreign-mcp"]}
cfg["foreignUninstall"] = {"keep": True}
with open(path, "w") as fh:
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
PY
cp "$FRESH/.mcp.json" "$WORK/uninstall-mcp.json"
cp "$FRESH/.env.playwright-secrets" "$WORK/uninstall-secrets.env"
cp "$FRESH/.playwright-mcp.config.json" "$WORK/uninstall-browser.json"
OUT="$("$INSTALL" --mode shared --target "$FRESH" --uninstall --yes 2>&1)"
if [ $? -ne 0 ]; then fail "shared uninstall exits 0" "$(printf '%s' "$OUT" | tail -4)"; else pass "shared uninstall exits 0"; fi
for item in .claude/rules .claude/skills .claude/agents .claude/hooks .claude/scripts .opencode/ROUTER.md .opencode/agents .opencode/commands .opencode/plugins docs projects/_template projects/EXAMPLE .claude-plugin CHANGELOG.md; do
  assert_no_file "uninstall removes $item link" "$FRESH/$item"
done
assert_real_dir "uninstall leaves real .claude" "$FRESH/.claude"
assert_real_dir "uninstall leaves real .agents" "$FRESH/.agents"
assert_no_file "uninstall deletes exact fresh router copy" "$FRESH/CLAUDE.md"
json_check "uninstall removes dead Claude hook references" "$FRESH/.claude/settings.json" "not any('/.claude/hooks/' in str(h.get('command','')) for entries in cfg.get('hooks',{}).values() for e in entries for h in e.get('hooks',[]))"
json_check "uninstall removes blueprint permissions" "$FRESH/.claude/settings.json" "'Bash(git status:*)' not in cfg.get('permissions',{}).get('allow',[])"
json_check "uninstall keeps foreign settings and hook" "$FRESH/.claude/settings.json" "cfg['foreignUninstall']['keep'] is True and 'Bash(foreign-uninstall:*)' in cfg['permissions']['allow'] and any(e.get('matcher') == 'ForeignTool' and any(h.get('command') == 'foreign-uninstall-hook' for h in e.get('hooks',[])) for e in cfg['hooks']['PreToolUse'])"
json_check "uninstall leaves project plugin false" "$FRESH/.claude/settings.json" "cfg['enabledPlugins']['qa-agent-blueprint@qa-agent-blueprint-marketplace'] is False"
cfg_check "uninstall removes blueprint opencode instructions" "$FRESH/opencode.json" "not any('ROUTER.md' in str(i) or '.claude/rules/core/' in str(i) for i in cfg.get('instructions',[]))"
cfg_check "uninstall keeps foreign opencode config and MCP" "$FRESH/opencode.json" "cfg['foreignUninstall']['keep'] is True and 'docs/foreign-uninstall.md' in cfg['instructions'] and cfg['mcp']['foreign']['command'] == ['foreign-mcp'] and 'playwright' in cfg['mcp'] and 'atlassian' in cfg['mcp']"
cmp -s "$FRESH/.mcp.json" "$WORK/uninstall-mcp.json" && pass "uninstall leaves MCP config untouched" || fail "uninstall leaves MCP config untouched"
cmp -s "$FRESH/.env.playwright-secrets" "$WORK/uninstall-secrets.env" && pass "uninstall leaves secrets seed untouched" || fail "uninstall leaves secrets seed untouched"
cmp -s "$FRESH/.playwright-mcp.config.json" "$WORK/uninstall-browser.json" && pass "uninstall leaves browser preferences untouched" || fail "uninstall leaves browser preferences untouched"
printf '%s' "$OUT" | grep -q "Re-enable qa-agent-blueprint" && pass "uninstall names manual plugin reactivation" || fail "uninstall names manual plugin reactivation" "$OUT"
assert_grep "uninstall keeps consumer memory" "$FRESH/memory/SHARED-FIXTURE.md" "consumer memory"
assert_grep "uninstall keeps consumer bridge" "$FRESH/.agents/qa-project-context/SHARED-FIXTURE.md" "consumer bridge"
assert_grep "uninstall keeps consumer project" "$FRESH/projects/TA/PROJECT.md" "# TA"
assert_grep "uninstall keeps consumer evidence" "$FRESH/evidence/TA/SHARED-FIXTURE.txt" "evidence"
assert_file "uninstall keeps QA home marker" "$FRESH/.qa-home"
OUT="$("$INSTALL" --mode shared --target "$ROUTER" --uninstall --yes 2>&1)"
if [ $? -ne 0 ]; then fail "managed router uninstall exits 0" "$(printf '%s' "$OUT" | tail -4)"; else pass "managed router uninstall exits 0"; fi
assert_file "managed foreign router file remains" "$ROUTER/CLAUDE.md"
assert_grep "managed foreign router content remains" "$ROUTER/CLAUDE.md" "Keep this router content."
assert_no_grep "managed shared router block removed" "$ROUTER/CLAUDE.md" "qa-agent-blueprint (managed, do not edit)"
OUT="$("$INSTALL" --mode shared --target "$PLUGIN" --uninstall --yes 2>&1)"
if [ $? -ne 0 ]; then fail "plugin migration uninstall exits 0" "$(printf '%s' "$OUT" | tail -4)"; else pass "plugin migration uninstall exits 0"; fi
json_check "preexisting identical permission survives uninstall" "$PLUGIN/.claude/settings.json" "'Bash(git status:*)' in cfg['permissions']['allow'] and 'Bash(ls:*)' in cfg['permissions']['allow']"
json_check "only newly added blueprint permission removed" "$PLUGIN/.claude/settings.json" "'Bash(shasum:*)' not in cfg['permissions']['allow']"
json_check "plugin migration foreign settings survive uninstall" "$PLUGIN/.claude/settings.json" "cfg['foreignTopLevel']['keep'] == 'yes' and cfg['enabledPlugins']['foreign@marketplace'] is True and any(e.get('matcher') == 'ForeignTool' for e in cfg['hooks']['PreToolUse'])"
json_check "preexisting identical hook survives uninstall" "$PLUGIN/.claude/settings.json" "any(h.get('command') == '\${CLAUDE_PROJECT_DIR}/.claude/hooks/session-start.sh' for e in cfg['hooks']['SessionStart'] for h in e.get('hooks',[]))"
cfg_check "preexisting blueprint instructions survive uninstall" "$PLUGIN/opencode.json" "'.opencode/ROUTER.md' in cfg['instructions'] and '.claude/rules/core/*.md' in cfg['instructions'] and 'docs/consumer.md' in cfg['instructions']"

echo
if [ "$fails" -eq 0 ]; then echo "all fixtures passed"; else echo "$fails fixture(s) failed"; fi
exit "$fails"

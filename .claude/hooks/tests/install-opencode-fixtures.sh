#!/usr/bin/env bash
#
# install-opencode-fixtures.sh — end-to-end fixtures for `install.sh --mode
# opencode`, run against throwaway dirs in $TMPDIR.
#
# Contract under test (docs/opencode-port-plan.md, Phase 6 + D10):
#   - .opencode/{ROUTER.md,agents,commands,plugins} are SYMLINKS into the
#     blueprint checkout (updates = git pull, nothing is copied)
#   - compat symlinks .claude, docs, .agents resolve the literal path
#     references inside skill/rule/agent bodies
#   - opencode.json merges the template: existing mcp names win, the
#     playwright contract flags are force-upgraded, existing keys survive
#   - seed files (.env.playwright-secrets, .playwright-mcp.config.json) exist
#     after install (both MCP flags hard-fail on ENOENT)
#   - foreign content is never overwritten; uninstall removes only our links
#
# Usage:  bash .claude/hooks/tests/install-opencode-fixtures.sh
# Exit:   0 = all fixtures pass, otherwise the number of failures.
#
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

assert_link()    { [ -L "$2" ] && pass "$1" || fail "$1" "not a symlink: $2"; }
assert_link_to() { [ "$(readlink "$2" 2>/dev/null)" = "$3" ] && pass "$1" || fail "$1" "$2 -> $(readlink "$2" 2>/dev/null || echo MISSING), expected $3"; }
assert_file()    { [ -f "$2" ] && pass "$1" || fail "$1" "missing file: $2"; }
assert_no_file() { [ ! -e "$2" ] && [ ! -L "$2" ] && pass "$1" || fail "$1" "should not exist: $2"; }
assert_grep()    { grep -qF -- "$3" "$2" 2>/dev/null && pass "$1" || fail "$1" "not found in $2: $3"; }
assert_no_grep() { grep -qF -- "$3" "$2" 2>/dev/null && fail "$1" "should not appear in $2: $3" || pass "$1"; }

# JSONC-tolerant config reader: $1=file $2=python expression on `cfg`
cfg_check() { # <label> <file> <python-expression>
  python3 - "$2" "$3" <<'PY' >/dev/null 2>&1 && pass "$1" || fail "$1" "config check failed: $3"
import json, re, sys
text = open(sys.argv[1]).read()
out, i, n, in_str = [], 0, len(text), False
while i < n:
    c = text[i]
    if in_str:
        out.append(c)
        if c == '"': in_str = False
        i += 1
    elif c == '"':
        in_str = True; out.append(c); i += 1
    elif c == "/" and i + 1 < n and text[i+1] == "/":
        while i < n and text[i] != "\n": i += 1
    elif c == "/" and i + 1 < n and text[i+1] == "*":
        end = text.find("*/", i + 2)
        i = n if end == -1 else end + 2
    else:
        out.append(c); i += 1
cfg = json.loads("".join(out))
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
}

echo "== opencode install into an empty target =="
TARGET="$WORK/consumer"
mkdir -p "$TARGET"
OUT="$("$INSTALL" --mode opencode --target "$TARGET" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "installer exits 0" "$(printf '%s' "$OUT" | tail -3)"; else pass "installer exits 0"; fi

assert_link_to "ROUTER.md linked"   "$TARGET/.opencode/ROUTER.md" "$REPO/opencode/ROUTER.md"
assert_link_to "agents linked"      "$TARGET/.opencode/agents"    "$REPO/opencode/agents"
assert_link_to "commands linked"    "$TARGET/.opencode/commands"  "$REPO/opencode/commands"
assert_link_to "plugins linked"     "$TARGET/.opencode/plugins"   "$REPO/opencode/plugins"
assert_link_to "compat .claude"     "$TARGET/.claude"             "$REPO/.claude"
assert_link_to "compat docs"        "$TARGET/docs"                "$REPO/docs"
assert_link_to "compat .agents"     "$TARGET/.agents"             "$REPO/.agents"
assert_file    "opencode.json written"      "$TARGET/opencode.json"
assert_file    "secrets placeholder seeded" "$TARGET/.env.playwright-secrets"
assert_file    "browser config seeded"      "$TARGET/.playwright-mcp.config.json"
cfg_check "config has both MCP contract names" "$TARGET/opencode.json" \
  "'playwright' in cfg.get('mcp',{}) and 'atlassian' in cfg.get('mcp',{})"
cfg_check "config carries instructions + subagent_depth 2" "$TARGET/opencode.json" \
  "any('ROUTER.md' in str(i) for i in cfg.get('instructions',[])) and cfg.get('subagent_depth') == 2"
cfg_check "config has no model key (D6)" "$TARGET/opencode.json" \
  "'model' not in cfg and 'small_model' not in cfg"
cfg_check "playwright contract flags present" "$TARGET/opencode.json" \
  "'--secrets' in cfg['mcp']['playwright']['command'] and '--config' in cfg['mcp']['playwright']['command']"

echo
echo "== merge into an existing opencode.json =="
TARGET2="$WORK/consumer-existing"
mkdir -p "$TARGET2"
cat > "$TARGET2/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "openrouter/z-ai/glm-5.3-flash",
  "mcp": {
    "my-own": { "type": "local", "command": ["my-mcp"] },
    "atlassian": { "type": "local", "command": ["uvx", "mcp-atlassian"], "environment": { "JIRA_URL": "https://jira.example.com" } },
    "playwright": { "type": "local", "command": ["npx", "@playwright/mcp@latest"] }
  }
}
JSON
OUT="$("$INSTALL" --mode opencode --target "$TARGET2" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "merge install exits 0" "$(printf '%s' "$OUT" | tail -3)"; else pass "merge install exits 0"; fi
cfg_check "own mcp server kept"        "$TARGET2/opencode.json" "'my-own' in cfg['mcp']"
cfg_check "own model key kept"         "$TARGET2/opencode.json" "cfg.get('model') == 'openrouter/z-ai/glm-5.3-flash'"
cfg_check "existing atlassian wins (DC entry survives)" "$TARGET2/opencode.json" \
  "cfg['mcp']['atlassian'].get('type') == 'local'"
cfg_check "playwright contract flags force-upgraded" "$TARGET2/opencode.json" \
  "'--secrets' in cfg['mcp']['playwright']['command'] and '.env.playwright-secrets' in cfg['mcp']['playwright']['command']"
cfg_check "subagent_depth raised to 2" "$TARGET2/opencode.json" "cfg.get('subagent_depth') == 2"

echo
echo "== foreign content is never overwritten =="
TARGET3="$WORK/consumer-own-claude"
mkdir -p "$TARGET3/.claude/skills/mine"
printf '%s\n' '---' 'name: mine' '---' 'Mine.' > "$TARGET3/.claude/skills/mine/SKILL.md"
OUT="$("$INSTALL" --mode opencode --target "$TARGET3" --yes 2>&1)"
[ -L "$TARGET3/.claude" ] && fail "own .claude not replaced by symlink" ".claude became a symlink" || pass "own .claude not replaced by symlink"
assert_grep "own skill intact" "$TARGET3/.claude/skills/mine/SKILL.md" "Mine."
printf '%s' "$OUT" | grep -qi "claude" && pass "conflict is reported" || fail "conflict is reported" "no .claude warning in output"

echo
echo "== idempotent re-install =="
OUT="$("$INSTALL" --mode opencode --target "$TARGET" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "re-install exits 0" "$(printf '%s' "$OUT" | tail -3)"; else pass "re-install exits 0"; fi
cfg_check "instructions not duplicated" "$TARGET/opencode.json" \
  "len([i for i in cfg['instructions'] if 'ROUTER.md' in str(i)]) == 1"

echo
echo "== uninstall removes our links, keeps foreign content =="
OUT="$("$INSTALL" --mode opencode --target "$TARGET3" --uninstall --yes 2>&1)"
if [ $? -ne 0 ]; then fail "uninstall exits 0" "$(printf '%s' "$OUT" | tail -3)"; else pass "uninstall exits 0"; fi
assert_no_file "plugins link removed" "$TARGET3/.opencode/plugins"
assert_no_file "ROUTER link removed"  "$TARGET3/.opencode/ROUTER.md"
assert_grep     "own .claude kept"    "$TARGET3/.claude/skills/mine/SKILL.md" "Mine."
OUT="$("$INSTALL" --mode opencode --target "$TARGET" --uninstall --yes 2>&1)"
assert_no_file "compat .claude link removed" "$TARGET/.claude"
assert_no_file "compat docs link removed"    "$TARGET/docs"
assert_file    "seeded secrets file kept (user data)" "$TARGET/.env.playwright-secrets"

echo
if [ "$fails" -eq 0 ]; then echo "all fixtures passed"; else echo "$fails fixture(s) failed"; fi
exit "$fails"

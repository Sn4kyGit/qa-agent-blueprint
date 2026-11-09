#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit, Anna Mazurek

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
#     playwright contract flags are upgraded additively, existing keys survive
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
# A symlink whose TARGET is missing passes assert_link_to but breaks every
# write through it (the 0.6.0 dangling .agents bug) — always pair the link
# check with this resolution check.
assert_dir()     { [ -d "$2" ] && pass "$1" || fail "$1" "not a resolvable directory: $2"; }
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
for agent in test-executor test-executor-cheap test-executor-deep test-automator test-automator-cheap test-automator-deep qa-manager failure-analyst bug-reporter; do
  assert_file "agent $agent readable via .opencode/agents" "$TARGET/.opencode/agents/$agent.md"
done
assert_link_to "compat .claude"     "$TARGET/.claude"             "$REPO/.claude"
assert_link_to "compat docs"        "$TARGET/docs"                "$REPO/docs"
assert_link_to "compat .agents"     "$TARGET/.agents"             "$REPO/.agents"
assert_dir     "compat .agents resolves" "$TARGET/.agents"
assert_link_to "projects/_template linked" "$TARGET/projects/_template" "$REPO/projects/_template"
assert_link_to "projects/EXAMPLE linked"   "$TARGET/projects/EXAMPLE"   "$REPO/projects/EXAMPLE"
assert_link_to ".claude-plugin linked"     "$TARGET/.claude-plugin"     "$REPO/.claude-plugin"
assert_link_to "CHANGELOG.md linked"       "$TARGET/CHANGELOG.md"       "$REPO/CHANGELOG.md"
assert_dir     "projects/_template resolves" "$TARGET/projects/_template"
assert_dir     "projects/EXAMPLE resolves"   "$TARGET/projects/EXAMPLE"
assert_dir     ".claude-plugin resolves"     "$TARGET/.claude-plugin"
assert_file    "CHANGELOG.md resolves"       "$TARGET/CHANGELOG.md"
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
  "'--secrets' in cfg['mcp']['playwright']['command'] and '--config' in cfg['mcp']['playwright']['command'] and cfg['mcp']['playwright']['command'][-2:] == ['--image-responses', 'omit']"
cfg_check "browser config seed sets console warning" "$TARGET/.playwright-mcp.config.json" \
  "cfg.get('console',{}).get('level') == 'warning'"
cfg_check "opencode evidence denies are raw-artifact only" "$TARGET/opencode.json" \
  "all(k in cfg['permission']['read'] for k in ['**/evidence/.mcp-out/**','**/evidence/**/*.png','**/evidence/**/*.zip','**/evidence/**/*.har']) and not any(k in cfg['permission']['read'] for k in ['**/evidence/**','**/evidence/**/screenshots/**','**/evidence/**/traces/**','**/evidence/**/videos/**']) and not any(k.endswith('.json') or k.endswith('.md') or 'execution_summary' in k for k in cfg['permission']['read'])"

echo
echo "== merge into an existing opencode.json =="
TARGET2="$WORK/consumer-existing"
mkdir -p "$TARGET2"
cat > "$TARGET2/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "model": "openrouter/z-ai/glm-5.3-flash",
  "agent": {
    "test-executor-deep": { "model": "openrouter/consumer-deep", "variant": "max" },
    "test-automator-cheap": { "model": "openrouter/consumer-cheap", "variant": "low" }
  },
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
cfg_check "playwright contract flags upgraded additively" "$TARGET2/opencode.json" \
  "'--secrets' in cfg['mcp']['playwright']['command'] and '.env.playwright-secrets' in cfg['mcp']['playwright']['command']"
cfg_check "subagent_depth raised to 2" "$TARGET2/opencode.json" "cfg.get('subagent_depth') == 2"
cfg_check "consumer agent model/variant overrides survive merge" "$TARGET2/opencode.json" \
  "cfg['agent']['test-executor-deep'] == {'model':'openrouter/consumer-deep','variant':'max'} and cfg['agent']['test-automator-cheap'] == {'model':'openrouter/consumer-cheap','variant':'low'}"
OUT="$("$INSTALL" --mode opencode --target "$TARGET2" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "override re-install exits 0" "$(printf '%s' "$OUT" | tail -3)"; else pass "override re-install exits 0"; fi
cfg_check "consumer agent model/variant overrides survive re-install" "$TARGET2/opencode.json" \
  "cfg['agent']['test-executor-deep'] == {'model':'openrouter/consumer-deep','variant':'max'} and cfg['agent']['test-automator-cheap'] == {'model':'openrouter/consumer-cheap','variant':'low'}"

JSONCTARGET="$WORK/consumer-jsonc"
mkdir -p "$JSONCTARGET"
cat > "$JSONCTARGET/opencode.jsonc" <<'JSONC'
{
  // consumer comment
  "model": "openrouter/consumer-\"jsonc\"",
  "instructions": ["docs/consumer.md",],
  "mcp": {"consumer": {"type": "local", "command": ["consumer-mcp"]}}
}
JSONC
OUT="$("$INSTALL" --mode opencode --target "$JSONCTARGET" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "JSONC migration exits 0" "$(printf '%s' "$OUT" | tail -3)"; else pass "JSONC migration exits 0"; fi
assert_file "JSONC migrated to opencode.json" "$JSONCTARGET/opencode.json"
assert_no_file "JSONC source retired" "$JSONCTARGET/opencode.jsonc"
assert_file "JSONC backup retained" "$(ls "$JSONCTARGET"/opencode.jsonc.bak-* 2>/dev/null | head -1)"
cfg_check "JSONC model and instruction retained" "$JSONCTARGET/opencode.json" "cfg.get('model') == 'openrouter/consumer-\"jsonc\"' and 'docs/consumer.md' in cfg['instructions'] and any('ROUTER.md' in str(i) for i in cfg['instructions'])"
cfg_check "JSONC consumer MCP retained" "$JSONCTARGET/opencode.json" "cfg['mcp']['consumer']['command'] == ['consumer-mcp'] and 'playwright' in cfg['mcp']"

DUALTARGET="$WORK/consumer-dual-config"
mkdir -p "$DUALTARGET"
printf '%s\n' '{"instructions":["json.md"]}' > "$DUALTARGET/opencode.json"
printf '%s\n' '{"instructions":["jsonc.md"]}' > "$DUALTARGET/opencode.jsonc"
cp -R "$DUALTARGET" "$WORK/dual-config-before"
OUT="$("$INSTALL" --mode opencode --target "$DUALTARGET" --yes 2>&1)"
if [ $? -eq 0 ]; then fail "dual config exits nonzero" "installer unexpectedly succeeded"; else pass "dual config exits nonzero"; fi
printf '%s' "$OUT" | grep -q "BLOCKED" && pass "dual config reports BLOCKED" || fail "dual config reports BLOCKED" "$OUT"
diff -r "$WORK/dual-config-before" "$DUALTARGET" >/dev/null 2>&1 && pass "dual config collision writes nothing" || fail "dual config collision writes nothing"

WRAPTARGET="$WORK/consumer-wrapper"
mkdir -p "$WRAPTARGET"
cat > "$WRAPTARGET/opencode.json" <<'JSON'
{
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["node", ".claude/scripts/qa-secrets.mjs", "mcp", "STAGE_PASSWORD", "--", "custom-pw", "serve"]
    }
  }
}
JSON
"$INSTALL" --mode opencode --target "$WRAPTARGET" --yes >/dev/null 2>&1
cfg_check "opencode wrapper and custom executable preserved" "$WRAPTARGET/opencode.json" \
  "cfg['mcp']['playwright']['command'][:7] == ['node','.claude/scripts/qa-secrets.mjs','mcp','STAGE_PASSWORD','--','custom-pw','serve']"
cfg_check "opencode wrapper receives missing contract flags" "$WRAPTARGET/opencode.json" \
  "all(f in cfg['mcp']['playwright']['command'] for f in ['--config','--output-dir','--image-responses'])"
cfg_check "opencode wrapper secrets source not replaced" "$WRAPTARGET/opencode.json" \
  "'--secrets' not in cfg['mcp']['playwright']['command'] and '.env.playwright-secrets' not in cfg['mcp']['playwright']['command']"

CUSTOMTARGET="$WORK/consumer-pre-010-custom"
mkdir -p "$CUSTOMTARGET"
cat > "$CUSTOMTARGET/opencode.json" <<'JSON'
{
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["custom-pw", "serve", "--channel", "firefox", "--secrets", "vault.env", "--output-dir", "evidence/custom", "--image-responses", "allow"]
    }
  }
}
JSON
"$INSTALL" --mode opencode --target "$CUSTOMTARGET" --yes >/dev/null 2>&1
cfg_check "pre-0.10 custom command and channel preserved" "$CUSTOMTARGET/opencode.json" \
  "cfg['mcp']['playwright']['command'][:4] == ['custom-pw','serve','--channel','firefox']"
cfg_check "pre-0.10 custom secrets and output preserved" "$CUSTOMTARGET/opencode.json" \
  "'vault.env' in cfg['mcp']['playwright']['command'] and 'evidence/custom' in cfg['mcp']['playwright']['command']"
cfg_check "pre-0.10 config added and image value fixed" "$CUSTOMTARGET/opencode.json" \
  "'--config' in cfg['mcp']['playwright']['command'] and cfg['mcp']['playwright']['command'][cfg['mcp']['playwright']['command'].index('--image-responses') + 1] == 'omit' and 'allow' not in cfg['mcp']['playwright']['command']"

TRAVTARGET="$WORK/consumer-output-traversal"
mkdir -p "$TRAVTARGET"
printf '%s' '{"mcp":{"playwright":{"type":"local","command":["npx","@playwright/mcp@latest","--config",".playwright-mcp.config.json","--secrets",".env.playwright-secrets","--output-dir","evidence/../outside","--image-responses","omit"]}}}' > "$TRAVTARGET/opencode.json"
"$INSTALL" --mode opencode --target "$TRAVTARGET" --yes >/dev/null 2>&1
cfg_check "traversal output-dir corrected to evidence" "$TRAVTARGET/opencode.json" \
  "'evidence/.mcp-out' in cfg['mcp']['playwright']['command'] and 'evidence/../outside' not in cfg['mcp']['playwright']['command']"

REMOTETARGET="$WORK/consumer-remote"
mkdir -p "$REMOTETARGET"
printf '%s' '{"mcp":{"playwright":{"type":"remote","url":"https://pw.example.invalid/mcp"}}}' > "$REMOTETARGET/opencode.json"
"$INSTALL" --mode opencode --target "$REMOTETARGET" --yes >/dev/null 2>&1
cfg_check "remote playwright not replaced by a local command" "$REMOTETARGET/opencode.json" \
  "cfg['mcp']['playwright'].get('url') == 'https://pw.example.invalid/mcp' and 'command' not in cfg['mcp']['playwright']"

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
echo "== foreign symlinks are never re-pointed =="
# opencode_link used to ln -sfn over ANY existing symlink — a consumer's own
# link (e.g. .opencode/plugins -> their dotfiles) was silently re-pointed at
# the blueprint. Foreign content wins for symlinks exactly as for files
# (field report 2026-09-18).
TARGET3B="$WORK/consumer-foreign-symlink"
mkdir -p "$TARGET3B/.opencode" "$WORK/their-dotfiles/plugins"
printf 'theirs\n' > "$WORK/their-dotfiles/plugins/keep.txt"
ln -s "$WORK/their-dotfiles/plugins" "$TARGET3B/.opencode/plugins"
OUT="$("$INSTALL" --mode opencode --target "$TARGET3B" --yes 2>&1)"
[ "$(readlink "$TARGET3B/.opencode/plugins")" = "$WORK/their-dotfiles/plugins" ] \
  && pass "foreign symlink untouched" \
  || fail "foreign symlink untouched" "plugins now points at: $(readlink "$TARGET3B/.opencode/plugins")"
assert_file "foreign link target intact" "$TARGET3B/.opencode/plugins/keep.txt"
printf '%s' "$OUT" | grep -qi "foreign symlink" && pass "foreign symlink warned" || fail "foreign symlink warned" "no warning in output"

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
echo "== move relocates a QA home (--move) =="
TARGET4="$WORK/move-old"; TARGET5="$WORK/move-new"
mkdir -p "$TARGET4"
printf '%s\n' '{"agent":{"test-executor-deep":{"model":"openrouter/move-deep","variant":"max"},"test-automator-cheap":{"model":"openrouter/move-cheap","variant":"low"}}}' > "$TARGET4/opencode.json"
"$INSTALL" --mode opencode --target "$TARGET4" --yes >/dev/null 2>&1 \
  && pass "move: install into old home" || fail "move: install into old home" "exit $?"
# user data accumulates over time
mkdir -p "$TARGET4/projects/TA" "$TARGET4/memory" "$TARGET4/evidence/TA/TA-1/run1"
echo "# TA" > "$TARGET4/projects/TA/PROJECT.md"
echo "learning" > "$TARGET4/memory/learnings.md"
echo '{}' > "$TARGET4/evidence/TA/TA-1/run1/execution_summary.json"
echo "custom-key" >> "$TARGET4/.env.playwright-secrets"
OUT="$("$INSTALL" --mode opencode --target "$TARGET4" --move "$TARGET5" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "move exits 0" "$(printf '%s' "$OUT" | tail -3)"; else pass "move exits 0"; fi
assert_link_to "move: router linked in new home" "$TARGET5/.opencode/ROUTER.md" "$REPO/opencode/ROUTER.md"
assert_file "move: project file moved"  "$TARGET5/projects/TA/PROJECT.md"
assert_file "move: memory moved"        "$TARGET5/memory/learnings.md"
assert_file "move: evidence moved"      "$TARGET5/evidence/TA/TA-1/run1/execution_summary.json"
assert_grep "move: secrets content intact" "$TARGET5/.env.playwright-secrets" "custom-key"
assert_file "move: opencode.json moved" "$TARGET5/opencode.json"
cfg_check  "move: instructions in moved config" "$TARGET5/opencode.json" \
  "len([i for i in cfg['instructions'] if 'ROUTER.md' in str(i)]) == 1"
cfg_check  "move: consumer agent model/variant overrides survive" "$TARGET5/opencode.json" \
  "cfg['agent']['test-executor-deep'] == {'model':'openrouter/move-deep','variant':'max'} and cfg['agent']['test-automator-cheap'] == {'model':'openrouter/move-cheap','variant':'low'}"
assert_no_file "move: old router link removed" "$TARGET4/.opencode/ROUTER.md"
assert_no_file "move: old compat link removed" "$TARGET4/.claude"
assert_no_file "move: old data gone"           "$TARGET4/projects"
assert_no_file "move: old opencode.json gone"  "$TARGET4/opencode.json"

echo
echo "== move never overwrites in the new home =="
TARGET6="$WORK/move-merge"
mkdir -p "$TARGET6/projects"
echo "existing" > "$TARGET6/projects/marker.txt"
OUT2="$("$INSTALL" --mode opencode --target "$TARGET5" --move "$TARGET6" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "move-merge exits 0" "$(printf '%s' "$OUT2" | tail -3)"; else pass "move-merge exits 0"; fi
assert_file "move-merge: existing projects kept"  "$TARGET6/projects/marker.txt"
assert_file "move-merge: skipped data stays put"  "$TARGET5/projects/TA/PROJECT.md"
assert_file "move-merge: memory still moved"      "$TARGET6/memory/learnings.md"
printf '%s' "$OUT2" | grep -qi "merge by hand" \
  && pass "move-merge: skip reported" || fail "move-merge: skip reported" "no 'merge by hand' in output"

echo
if [ "$fails" -eq 0 ]; then echo "all fixtures passed"; else echo "$fails fixture(s) failed"; fi
exit "$fails"

#!/usr/bin/env bash
#
# guard-fixtures.sh — fixture test for pre-tool-guard.sh (PreToolUse).
#
# Why this exists: the guard is advertised as *mechanical* enforcement, but it is
# a shell script parsing a JSON payload — and it can fail silently. It did: until
# 2026-09-05 the python expressions were passed with escaped quotes (`\"`), which
# survive single quotes and reach python as a SyntaxError. With stderr swallowed,
# every field came back empty, every check was skipped, and the guard returned
# exit 0 for `rm -rf`, force pushes and .env writes alike — while looking correct
# in review. A guard is only enforcement once a test proves it blocks.
#
# Usage:  bash .claude/hooks/tests/guard-fixtures.sh
# Exit:   0 = all fixtures pass, otherwise the number of failures.
#
# Convention: exit 0 = tool call allowed, exit 2 = blocked (Claude Code's
# PreToolUse contract). Payloads mirror the real hook input shape.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="$HERE/../pre-tool-guard.sh"

if [ ! -f "$GUARD" ]; then
  echo "pre-tool-guard.sh not found at $GUARD" >&2
  exit 1
fi

fails=0

check() {
  local name="$1" want="$2" json="$3" got
  printf '%s' "$json" | bash "$GUARD" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    printf 'ok    %-46s exit=%s\n' "$name" "$got"
  else
    printf 'FAIL  %-46s want=%s got=%s\n' "$name" "$want" "$got"
    fails=$((fails + 1))
  fi
}

echo "== allowed: the .env.example placeholder template =="
# .env.example holds no values, is whitelisted in .gitignore/.claudeignore, and is
# what install.sh copies .env from — the guard exempts it explicitly.
check "Write .env.example"            0 '{"tool_name":"Write","tool_input":{"file_path":".env.example"}}'
check "Write /repo/.env.example"      0 '{"tool_name":"Write","tool_input":{"file_path":"/repo/.env.example"}}'
check "Bash redirect > .env.example"  0 '{"tool_name":"Bash","tool_input":{"command":"cat > .env.example"}}'
check "Bash read .env.example"        0 '{"tool_name":"Bash","tool_input":{"command":"cat .env.example"}}'
check "Bash grep .env.example"        0 '{"tool_name":"Bash","tool_input":{"command":"grep KEY .env.example"}}'

echo
echo "== blocked: secrets files (.claude/rules/core/security.md) =="
check "Write .env"                    2 '{"tool_name":"Write","tool_input":{"file_path":".env"}}'
check "Write .env.local"              2 '{"tool_name":"Write","tool_input":{"file_path":".env.local"}}'
check "Write .env.playwright-secrets" 2 '{"tool_name":"Write","tool_input":{"file_path":".env.playwright-secrets"}}'
check "Edit deep/.env.production"     2 '{"tool_name":"Edit","tool_input":{"file_path":"/srv/app/.env.production"}}'
check "Write id_rsa"                  2 '{"tool_name":"Write","tool_input":{"file_path":"/home/u/.ssh/id_rsa"}}'
check "Bash redirect > .env"          2 '{"tool_name":"Bash","tool_input":{"command":"echo X >> .env"}}'
check "Bash cat .env"                 2 '{"tool_name":"Bash","tool_input":{"command":"cat .env"}}'
# The exemption strips only the literal ".env.example": copying the template INTO
# .env is still a write to a secrets file and must stay blocked.
check "Bash cp template INTO .env"    2 '{"tool_name":"Bash","tool_input":{"command":"cp .env.example .env"}}'
check "Bash cat .env.playwright-secrets" 2 '{"tool_name":"Bash","tool_input":{"command":"cat .env.playwright-secrets"}}'
# grep/sed/awk/jq are readers too — field report 0.6.1: `grep -o '^[A-Z_]*='`
# on the secrets file bypassed the old cat-only list. Key-name checks go
# through resolve-secrets.sh --status, never through the file itself.
check "Bash grep keys from .env.playwright-secrets" 2 '{"tool_name":"Bash","tool_input":{"command":"grep -o ^[A-Z_0-9]*= .env.playwright-secrets"}}'
check "Bash grep .env.local"           2 '{"tool_name":"Bash","tool_input":{"command":"grep PASSWORD .env.local"}}'
check "Bash sed reads .env"            2 '{"tool_name":"Bash","tool_input":{"command":"sed -n 1p .env"}}'
check "Bash awk reads .env"            2 '{"tool_name":"Bash","tool_input":{"command":"awk -F= \"{print $1}\" .env"}}'
check "Bash jq reads .env"             2 '{"tool_name":"Bash","tool_input":{"command":"jq . .env"}}'
check "Bash source .env"               2 '{"tool_name":"Bash","tool_input":{"command":"source .env"}}'
# Interpreter one-liners that OPEN the file (audit 2026-09-18, F4)
check "python3 open().read() .env"     2 '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"print(open(\".env\").read())\""}}'
check "ruby File.read .env"            2 '{"tool_name":"Bash","tool_input":{"command":"ruby -e \"puts File.read(\".env\")\""}}'
# ...but merely MENTIONING the name in a string is not a read
check "python string mentions .env"    0 '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"note=\".env.template\"; print(note)\""}}'

echo
echo "== fail closed: unparsable payloads (audit 2026-09-18, F1/F4) =="
check "unparsable call touching .env"  2 'not json at all .env.production'
check "unparsable call touching a pem" 2 'garbage {{ cert.pem'

echo
echo "== shadow mode: JIRA writes blocked by default (security.md; audit F1) =="
SHADOW_TMP="$(mktemp -d)"
trap 'rm -r "$SHADOW_TMP" 2>/dev/null' EXIT
mkdir -p "$SHADOW_TMP/projects/SHOP"
printf '# SHOP\nShadow mode: off\n' > "$SHADOW_TMP/projects/SHOP/PROJECT.md"

check "JIRA write blocked, shadow default"      2 '{"tool_name":"mcp__atlassian__createJiraIssue","tool_input":{"issueKey":"SHOP-123"}}'
check "JIRA write blocked, plugin-namespaced"   2 '{"tool_name":"mcp__plugin_qa-agent-blueprint_atlassian__editJiraIssue","tool_input":{"issueKey":"SHOP-123"}}'
check "JIRA write, unresolvable key → blocked"  2 '{"tool_name":"mcp__atlassian__transitionJiraIssue","tool_input":{}}'
check "unparsable atlassian write → blocked"    2 'garbage mcp__atlassian__createJiraIssue payload'
check "JIRA read is not a write"                0 '{"tool_name":"mcp__atlassian__getJiraIssue","tool_input":{"issueKey":"SHOP-123"},"cwd":"/tmp"}'
# Atlassian v2 meta-tools (0.10.0): executeWrite/executeDestructive run
# DEFERRED tools and are writes by definition; executeRead stays open.
check "executeWrite blocked, shadow default"    2 '{"tool_name":"mcp__atlassian__executeWrite","tool_input":{"tool":"uploadAttachmentToJiraIssue","arguments":{"issueKey":"SHOP-123"}}}'
check "executeDestructive blocked, shadow def." 2 '{"tool_name":"mcp__atlassian__executeDestructive","tool_input":{"tool":"deleteJiraIssue","arguments":{"issueKey":"SHOP-123"}}}'
check "unparsable executeWrite → blocked"       2 'garbage mcp__atlassian__executeWrite payload'
check "executeRead is not a write"              0 '{"tool_name":"mcp__atlassian__executeRead","tool_input":{"tool":"listJiraIssueChangelogs","arguments":{"issueKey":"SHOP-123"}},"cwd":"/tmp"}'
# Shadow-off fixtures run against a temp project — which trips the preflight
# gate unless a fresh pass artifact exists (the gate covers JIRA reads too).
mkdir -p "$SHADOW_TMP/evidence/.preflight"
printf '{"key":"SHOP","checked_at":%s,"ok":true}\n' "$(date +%s)" > "$SHADOW_TMP/evidence/.preflight/ok.json"
check "shadow off via PROJECT.md"               0 '{"tool_name":"mcp__atlassian__createJiraIssue","tool_input":{"issueKey":"SHOP-123"},"cwd":"'"$SHADOW_TMP"'"}'
check "executeWrite allowed when shadow off"    0 '{"tool_name":"mcp__atlassian__executeWrite","tool_input":{"tool":"uploadAttachmentToJiraIssue","arguments":{"issueKey":"SHOP-123"}},"cwd":"'"$SHADOW_TMP"'"}'

printf '%s' '{"tool_name":"mcp__atlassian__createJiraIssue","tool_input":{"issueKey":"SHOP-123"},"cwd":"'"$SHADOW_TMP"'"}' | QA_AGENT_SHADOW=0 bash "$GUARD" >/dev/null 2>&1
if [ $? -eq 0 ]; then
  printf 'ok    %-46s exit=%s\n' "shadow off via QA_AGENT_SHADOW=0" 0
else
  printf 'FAIL  %-46s want=%s got=%s\n' "shadow off via QA_AGENT_SHADOW=0" 0 2
  fails=$((fails + 1))
fi
rm -r "$SHADOW_TMP" 2>/dev/null

echo
echo "== blocked: reserved product-key names (case-insensitive) =="
# product-layer.md tells users these names are blocked by this guard. Until
# 2026-09-06 that was false: bash `case` is case-sensitive and the patterns were
# plural, so a product directory named SECRET matched nothing.
check "Write products/SECRET/PRODUCT.md"  2 '{"tool_name":"Write","tool_input":{"file_path":"projects/SHOP/products/SECRET/PRODUCT.md"}}'
check "Write products/CREDENTIALS/..."    2 '{"tool_name":"Write","tool_input":{"file_path":"projects/SHOP/products/CREDENTIALS/PRODUCT.md"}}'
check "Write mixed-case Credentials dir"  2 '{"tool_name":"Write","tool_input":{"file_path":"/tmp/My-Credentials/notes.md"}}'
check "Write lowercase secrets dir"       2 '{"tool_name":"Write","tool_input":{"file_path":"config/secrets/app.yml"}}'

echo
echo "== allowed: prose mentioning a secrets filename is not a read of it =="
# The reader must sit at a command position and the filename must belong to that
# command. Without that bound, any pipeline followed by an echo that names the file
# was blocked — a guard that blocks ordinary work gets switched off.
check "pipeline + unrelated echo naming it"  0 '{"tool_name":"Bash","tool_input":{"command":"ls projects | head -3; echo \"note: the dot-env file is a template\""}}'
check "grep is not a reader we block"        0 '{"tool_name":"Bash","tool_input":{"command":"grep -c KEY README.md"}}'

echo
echo "== allowed: the sanctioned resolver path stays open =="
# resolve-secrets.sh (re)generates .env.playwright-secrets from the keychain
# without ever printing a value — the agent may run it. Its name contains
# "secrets", so this fixture is the contract that future guard tightening must
# not kill the sanctioned path.
check "Bash resolve-secrets.sh"       0 '{"tool_name":"Bash","tool_input":{"command":"bash .claude/hooks/resolve-secrets.sh"}}'
check "Bash resolve-secrets.sh arg"   0 '{"tool_name":"Bash","tool_input":{"command":"bash .claude/hooks/resolve-secrets.sh . --status"}}'
check "Bash resolver --import"        0 '{"tool_name":"Bash","tool_input":{"command":"bash .claude/hooks/resolve-secrets.sh . --import"}}'
check "Bash resolver --capture"       0 '{"tool_name":"Bash","tool_input":{"command":"bash .claude/hooks/resolve-secrets.sh . --capture"}}'
check "Bash plugin-root resolver"     0 '{"tool_name":"Bash","tool_input":{"command":"bash $CLAUDE_PLUGIN_ROOT/.claude/hooks/resolve-secrets.sh"}}'

echo
echo "== blocked: destructive commands =="
check "Bash rm -rf"                   2 '{"tool_name":"Bash","tool_input":{"command":"rm -rf build/"}}'
check "Bash git push --force"         2 '{"tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'

echo
echo "== preflight gate: browser/JIRA MCP calls need a fresh pass =="
# The gate refuses playwright/atlassian MCP calls until evidence/.preflight/
# ok.json exists and is younger than the TTL — the mechanical backstop against
# "VPN forgotten" false positives. Fixture CWD carries one onboarded project.
PFWORK="$(mktemp -d)"
trap 'rm -rf "$PFWORK"' EXIT
mkdir -p "$PFWORK/projects/SHOP" "$PFWORK/evidence/.preflight"
echo '# SHOP' > "$PFWORK/projects/SHOP/PROJECT.md"
PW_CALL='{"tool_name":"mcp__playwright__browser_navigate","tool_input":{"url":"https://stage.corp.example.com"},"cwd":"'"$PFWORK"'"}'
PW_PLUGIN_CALL='{"tool_name":"mcp__plugin_qa-agent-blueprint_playwright__browser_navigate","tool_input":{"url":"https://stage.corp.example.com"},"cwd":"'"$PFWORK"'"}'
AT_READ='{"tool_name":"mcp__atlassian__getJiraIssue","tool_input":{"issueKey":"SHOP-1"},"cwd":"'"$PFWORK"'"}'

check "playwright, no artifact"       2 "$PW_CALL"
check "playwright (plugin-ns), none"  2 "$PW_PLUGIN_CALL"
check "atlassian read, no artifact"   2 "$AT_READ"

NOW="$(date +%s)"
printf '{"key":"SHOP","checked_at":%s,"ok":true}\n' "$NOW" > "$PFWORK/evidence/.preflight/ok.json"
check "playwright, fresh artifact"    0 "$PW_CALL"
check "atlassian read, fresh"         0 "$AT_READ"

OLD=$(( NOW - 7200 ))
printf '{"key":"SHOP","checked_at":%s,"ok":true}\n' "$OLD" > "$PFWORK/evidence/.preflight/ok.json"
check "playwright, stale artifact"    2 "$PW_CALL"
QA_PREFLIGHT_TTL_MIN=180 bash -c 'printf %s "$1" | bash "$2" >/dev/null 2>&1' _ "$PW_CALL" "$GUARD"
if [ $? -eq 0 ]; then
  printf 'ok    %-46s exit=0\n' "stale vs. wider TTL env"
else
  printf 'FAIL  %-46s want=0\n' "stale vs. wider TTL env"
  fails=$((fails + 1))
fi

QA_PREFLIGHT=0 bash -c 'printf %s "$1" | bash "$2" >/dev/null 2>&1' _ "$PW_CALL" "$GUARD"
if [ $? -eq 0 ]; then
  printf 'ok    %-46s exit=0\n' "QA_PREFLIGHT=0 escape hatch"
else
  printf 'FAIL  %-46s want=0\n' "QA_PREFLIGHT=0 escape hatch"
  fails=$((fails + 1))
fi

rm -rf "$PFWORK/projects"
check "no projects → nothing to gate" 0 "$PW_CALL"

echo
echo "== foreign MCP gate: global-only servers blocked (field report 2026-09-22) =="
# A gitlab server configured only in the GLOBAL config (~/.claude.json) may
# point at another project's credentials — blocked until declared in the
# project's own .mcp.json. HOME is faked so the fixture touches nothing real.
FM_HOME="$(mktemp -d)"; FM_PROJ="$(mktemp -d)"; FM_PROJ_DECL="$(mktemp -d)"
trap 'rm -rf "$FM_HOME" "$FM_PROJ" "$FM_PROJ_DECL" 2>/dev/null' EXIT
printf '%s' '{"mcpServers":{"gitlab":{"command":"x"},"playwright":{"command":"x"}}}' > "$FM_HOME/.claude.json"
printf '%s' '{"mcpServers":{}}' > "$FM_PROJ/.mcp.json"
printf '%s' '{"mcpServers":{"gitlab":{"command":"x"}}}' > "$FM_PROJ_DECL/.mcp.json"
fm_call() { printf '{"tool_name":"%s","tool_input":{},"cwd":"%s"}' "$1" "$2"; }
check_home() { # <name> <want> <json> [extra env]
  local name="$1" want="$2" json="$3" got
  if [ $# -ge 4 ]; then
    printf '%s' "$json" | env HOME="$FM_HOME" "$4" bash "$GUARD" >/dev/null 2>&1
  else
    printf '%s' "$json" | HOME="$FM_HOME" bash "$GUARD" >/dev/null 2>&1
  fi
  got=$?
  if [ "$got" = "$want" ]; then printf 'ok    %-46s exit=%s\n' "$name" "$got"
  else printf 'FAIL  %-46s want=%s got=%s\n' "$name" "$want" "$got"; fails=$((fails + 1)); fi
}
check_home "mcp gitlab global-only → blocked"          2 "$(fm_call mcp__gitlab__getIssue "$FM_PROJ")"
check_home "mcp gitlab declared in project → allowed"  0 "$(fm_call mcp__gitlab__getIssue "$FM_PROJ_DECL")"
check_home "mcp playwright (blueprint) w/o decl → ok"  0 "$(fm_call mcp__playwright__browser_navigate "$FM_PROJ")"
check_home "mcp plugin-namespaced atlassian read → ok" 0 "$(fm_call mcp__plugin_qa-agent-blueprint_atlassian__getIssue "$FM_PROJ")"
check_home "QA_ALLOW_GLOBAL_MCP=1 escape hatch"        0 "$(fm_call mcp__gitlab__getIssue "$FM_PROJ")" QA_ALLOW_GLOBAL_MCP=1
check_home "mcp server nowhere configured → allowed"   0 "$(fm_call mcp__nonexistent__x "$FM_PROJ")"

echo
echo "== global MCP config writes blocked; project config writable =="
mkdir -p "$FM_HOME/.config/opencode"
printf '{}' > "$FM_HOME/.config/opencode/opencode.json"
check_home "Write ~/.claude.json → blocked"            2 "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FM_HOME/.claude.json\"}}"
check_home "Edit ~/.config/opencode/opencode.json → blocked" 2 "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$FM_HOME/.config/opencode/opencode.json\"}}"
check_home "Bash sed -i global config → blocked"       2 "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sed -i 's/a/b/' $FM_HOME/.claude.json\"}}"
check_home "Bash redirect > global config → blocked"   2 "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo '{}' > $FM_HOME/.config/opencode/opencode.json\"}}"
check_home "Write project .mcp.json → allowed"         0 "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$FM_PROJ/.mcp.json\"}}"
check_home "Bash redirect > project .mcp.json → ok"    0 "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo '{}' > $FM_PROJ/.mcp.json\"}}"

echo
echo "== secrets_read toggle: .qa-guard.json (tdd 0.11.0 §7–§11) =="
# The toggle lives in the QA home (resolved by walk-up from the payload cwd).
# Default/missing/invalid = block; only the exact value "allow" opens direct
# reads — and even then only for the READER_CORE commands.
TOG="$(mktemp -d)"; trap 'rm -rf "$TOG" 2>/dev/null' EXIT
touch "$TOG/.qa-home"
tog_bash() { printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":"%s"}' "$1" "$TOG"; }
tog_write() { printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$TOG"; }

# --- default: no config file → block (existing behaviour preserved)
check "toggle: no config, cat .env"        2 "$(tog_bash '"cat .env"')"
# --- missing key / wrong value / invalid JSON → block
printf '{}' > "$TOG/.qa-guard.json"
check "toggle: empty config, cat .env"     2 "$(tog_bash '"cat .env"')"
printf '{"secrets_read":"yes"}' > "$TOG/.qa-guard.json"
check "toggle: wrong value, cat .env"      2 "$(tog_bash '"cat .env"')"
printf 'not json' > "$TOG/.qa-guard.json"
check "toggle: invalid JSON, cat .env"     2 "$(tog_bash '"cat .env"')"
check "toggle: invalid JSON, grep .env"    2 "$(tog_bash '"grep PASSWORD .env"')"

# --- allow: READER_CORE follows the toggle
printf '{"secrets_read":"allow"}' > "$TOG/.qa-guard.json"
check "toggle: allow, cat .env"            0 "$(tog_bash '"cat .env"')"
check "toggle: allow, less .env"           0 "$(tog_bash '"less .env"')"
check "toggle: allow, head .env"           0 "$(tog_bash '"head .env"')"
check "toggle: allow, tail .env"           0 "$(tog_bash '"tail .env"')"
check "toggle: allow, grep .env"           0 "$(tog_bash '"grep PASSWORD .env"')"
check "toggle: allow, sed read .env"       0 "$(tog_bash '"sed -n 1p .env"')"
check "toggle: allow, awk read .env"       0 "$(tog_bash '"awk -F= \"{print $1}\" .env"')"
check "toggle: allow, jq .env"             0 "$(tog_bash '"jq . .env"')"
check "toggle: allow, source .env"         0 "$(tog_bash '"source .env"')"

# --- allow: cp/mv/sed -i/awk -i are NOT readers (§8) — always blocked
check "toggle: allow, cp .env"             2 "$(tog_bash '"cp .env /tmp/secrets"')"
check "toggle: allow, mv .env"             2 "$(tog_bash '"mv .env /tmp/secrets"')"
check "toggle: allow, sed -i .env"         2 "$(tog_bash '"sed -i s/a/b/ .env"')"
check "toggle: allow, sed -i.bak .env"     2 "$(tog_bash '"sed -i.bak s/a/b/ .env"')"
check "toggle: allow, sed --in-place"      2 "$(tog_bash '"sed --in-place s/a/b/ .env"')"
check "toggle: allow, awk -i inplace"      2 "$(tog_bash '"awk -i inplace \"{print}\" .env"')"
# --- allow: writes stay blocked (§9)
check "toggle: allow, redirect >> .env"    2 "$(tog_bash '"echo PASSWORD=x >> .env"')"
check "toggle: allow, Write .env"          2 "$(tog_write "$TOG/.env")"
# --- allow: interpreter reads stay blocked (fail closed — a regex cannot tell
#     open('.env') from open('.env','w'), so this class never opens, §10/§11)
check "toggle: allow, python read .env"    2 "$(tog_bash '"python3 -c \"print(open(\".env\").read())\""')"

# --- rm hardening (§9/F2): deleting a secrets file is a human task, both modes
check "toggle: default, rm .env"           2 "$(tog_bash '"rm .env"')"
check "toggle: allow, rm .env"             2 "$(tog_bash '"rm .env"')"
check "toggle: allow, rm -f .env"          2 "$(tog_bash '"rm -f .env"')"
check "toggle: allow, rm .env.local"       2 "$(tog_bash '"rm .env.local"')"
check "toggle: allow, rm plain file ok"    0 "$(tog_bash '"rm scratch-output.txt"')"
check "toggle: allow, rm .env.example ok"  0 "$(tog_bash '"rm .env.example"')"

# --- the toggle file itself is a human task: an agent that can write
#     .qa-guard.json can grant itself secrets_read=allow (self-escalation)
check "toggle: Write .qa-guard.json"       2 "$(tog_write "$TOG/.qa-guard.json")"
check "toggle: Edit .qa-guard.json"        2 '{"tool_name":"Edit","tool_input":{"file_path":"'"$TOG"'/.qa-guard.json"},"cwd":"'"$TOG"'"}'
check "toggle: redirect > .qa-guard.json"  2 "$(tog_bash '"echo \"{}\" > .qa-guard.json"')"
check "toggle: sed -i .qa-guard.json"      2 "$(tog_bash '"sed -i s/block/allow/ .qa-guard.json"')"
check "toggle: rm .qa-guard.json"          2 "$(tog_bash '"rm .qa-guard.json"')"
rm -rf "$TOG" 2>/dev/null

echo
echo "== allowed: ordinary work is unaffected =="
check "Write a normal file"           0 '{"tool_name":"Write","tool_input":{"file_path":"README.md"}}'
check "Bash normal command"           0 '{"tool_name":"Bash","tool_input":{"command":"npx playwright test"}}'

echo
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) failed"
fi
exit "$fails"

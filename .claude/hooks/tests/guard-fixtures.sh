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
check "JIRA read is not a write"                0 '{"tool_name":"mcp__atlassian__getJiraIssue","tool_input":{"issueKey":"SHOP-123"}}'
check "shadow off via PROJECT.md"               0 '{"tool_name":"mcp__atlassian__createJiraIssue","tool_input":{"issueKey":"SHOP-123"},"cwd":"'"$SHADOW_TMP"'"}'

printf '%s' '{"tool_name":"mcp__atlassian__createJiraIssue","tool_input":{"issueKey":"SHOP-123"}}' | QA_AGENT_SHADOW=0 bash "$GUARD" >/dev/null 2>&1
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

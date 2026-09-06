#!/usr/bin/env bash
#
# session-start-fixtures.sh — fixture test for session-start.sh's project/product
# listing. Companion to guard-fixtures.sh, and for the same reason: this hook is
# the only executable piece of the product layer, and its failure modes are silent
# (a literal '*' as a product name, a lost "none yet" branch, a scaffold directory
# listed as a real product).
#
# Usage:  bash .claude/hooks/tests/session-start-fixtures.sh
# Exit:   0 = all fixtures pass, otherwise the number of failures.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../session-start.sh"
[ -f "$HOOK" ] || { echo "session-start.sh not found at $HOOK" >&2; exit 1; }

fails=0
WORK="$(mktemp -d)"
trap 'rm -r "$WORK" 2>/dev/null' EXIT

# Render the hook's additionalContext for a given cwd.
context_for() {
  printf '{"cwd":"%s"}' "$1" | bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
'
}

check_contains() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    printf 'ok    %s\n' "$name"
  else
    printf 'FAIL  %s\n      expected to find: %s\n' "$name" "$needle"
    fails=$((fails + 1))
  fi
}

check_absent() {
  local name="$1" haystack="$2" needle="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    printf 'FAIL  %s\n      should NOT contain: %s\n' "$name" "$needle"
    fails=$((fails + 1))
  else
    printf 'ok    %s\n' "$name"
  fi
}

# --- fixture tree -------------------------------------------------------------
# AAA: two products plus the scaffold directory that must never be listed.
mkdir -p "$WORK/repo/projects/AAA/products/"{STOREFRONT,ADMIN,_template}
# BBB: no products at all — must render exactly as before the product layer.
mkdir -p "$WORK/repo/projects/BBB"
# CCC: products/ exists but is empty — the unguarded-glob trap.
mkdir -p "$WORK/repo/projects/CCC/products"
# The scaffold and the reference project must stay hidden, as always.
mkdir -p "$WORK/repo/projects/_template" "$WORK/repo/projects/EXAMPLE"
mkdir -p "$WORK/empty/projects"

CTX="$(context_for "$WORK/repo")"

echo "== a project with products lists them inline =="
# Glob order, i.e. alphabetical — deterministic, so assert it exactly.
check_contains "AAA lists both products inline" "$CTX" "- AAA (products: ADMIN, STOREFRONT)"
check_absent   "scaffold _template is not a product" "$CTX" "_template"

echo
echo "== a project without products renders exactly as before =="
check_contains "BBB is a plain row" "$CTX" "- BBB"
check_absent   "BBB has no empty product parens" "$CTX" "- BBB (products:"

echo
echo "== an empty products/ directory prints no product, and never a literal '*' =="
check_contains "CCC is a plain row" "$CTX" "- CCC"
check_absent   "no unexpanded glob leaked in" "$CTX" "products: *"

echo
echo "== scaffold and reference project stay hidden =="
check_absent "projects/_template not listed" "$CTX" "- _template"
check_absent "projects/EXAMPLE not listed"  "$CTX" "- EXAMPLE"

echo
echo "== the 'none yet' branch survives =="
EMPTY_CTX="$(context_for "$WORK/empty")"
check_contains "empty projects/ prompts onboarding" "$EMPTY_CTX" "(none yet — run /onboard-project)"

echo
echo "== plugin mode injects the plugin's CLAUDE.md verbatim =="
# The plugin router used to be a hand-maintained summary inside session-start.sh
# — a second source of truth that drifted from CLAUDE.md. The hook now cats the
# file, so a marker written into the plugin's CLAUDE.md must surface verbatim.
PLUGIN="$WORK/plugin"; CONSUMER="$WORK/consumer"
mkdir -p "$PLUGIN" "$CONSUMER"
printf '# QA Agent Blueprint — Router\n\nFIXTURE_ROUTER_MARKER_7f3a\n' > "$PLUGIN/CLAUDE.md"
PCTX="$(printf '{"cwd":"%s"}' "$CONSUMER" | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_contains "plugin CLAUDE.md content is injected" "$PCTX" "FIXTURE_ROUTER_MARKER_7f3a"
check_contains "plugin preamble names the plugin root" "$PCTX" "$PLUGIN"
# A plugin session must not double-print the router: the consumer repo's own
# (non-existent) CLAUDE.md contributes nothing.
[ -f "$CONSUMER/.env.playwright-secrets" ] \
  && printf 'ok    %s\n' "plugin bootstrap seeds .env.playwright-secrets" \
  || { printf 'FAIL  %s\n' "plugin bootstrap seeds .env.playwright-secrets"; fails=$((fails + 1)); }
# Without CLAUDE_PLUGIN_ROOT the same consumer repo gets no router injection.
NPCTX="$(context_for "$CONSUMER")"
check_absent "no injection without CLAUDE_PLUGIN_ROOT" "$NPCTX" "FIXTURE_ROUTER_MARKER_7f3a"

echo
echo "== MCP config scan: concrete hints instead of a generic one =="
# Both servers configured (project scope), playwright WITH --secrets → confirm-live hint.
M1="$WORK/mcp-ok"; mkdir -p "$M1/projects"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--secrets",".env.playwright-secrets"]},"atlassian":{"type":"sse","url":"https://mcp.atlassian.com/v1/sse"}}}' > "$M1/.mcp.json"
check_contains "both servers configured → confirm-live hint" "$(context_for "$M1")" "MCP config for playwright + atlassian found"

# A playwright config WITHOUT --secrets → passwords would be unmasked: warning.
M2="$WORK/mcp-unmasked"; mkdir -p "$M2/projects"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest"]}}}' > "$M2/.mcp.json"
check_contains "unmasked playwright config → warning" "$(context_for "$M2")" "no --secrets flag"

# Plugin mode + a local duplicate → dedupe note.
M3="$WORK/mcp-dupe"; mkdir -p "$M3/projects"
printf '%s' '{"mcpServers":{"atlassian":{"type":"sse","url":"https://mcp.atlassian.com/v1/sse"}}}' > "$M3/.mcp.json"
PCTX3="$(printf '{"cwd":"%s"}' "$M3" | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_contains "plugin + local duplicate → dedupe note" "$PCTX3" "dedupe to one source"

# User scope (~/.claude.json) must be found too — via a fake HOME.
M4="$WORK/mcp-userscope"; FAKEHOME="$WORK/fakehome"; mkdir -p "$M4/projects" "$FAKEHOME"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--secrets",".env.playwright-secrets"]},"atlassian":{"type":"sse","url":"https://mcp.atlassian.com/v1/sse"}}}' > "$FAKEHOME/.claude.json"
CTX4="$(printf '{"cwd":"%s"}' "$M4" | HOME="$FAKEHOME" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_contains "user-scope servers detected via HOME" "$CTX4" "MCP config for playwright + atlassian found"

echo
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) failed"
fi
exit "$fails"

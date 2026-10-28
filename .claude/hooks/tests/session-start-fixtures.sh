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
echo "== the preamble points at the command overview =="
# Discoverability is a mechanism too: the qa-help skill is only findable on
# day one if the preamble names it in every session, in every mode.
check_contains "preamble names the qa-help skill" "$CTX" "qa-help"

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

# …but an entry launched through qa-secrets.mjs mcp satisfies the secrets
# contract by construction (ephemeral mask file) — no warning there.
M7="$WORK/mcp-wrapper"; mkdir -p "$M7/projects"
printf '%s' '{"mcpServers":{"playwright":{"command":"node","args":[".claude/scripts/qa-secrets.mjs","mcp","STAGE_PASSWORD","--","npx","@playwright/mcp@latest","--output-dir","evidence/.mcp-out","--image-responses=omit"]}}}' > "$M7/.mcp.json"
M7CTX="$(context_for "$M7")"
check_absent "qa-secrets wrapper entry → no unmasked warning" "$M7CTX" "no --secrets flag"
check_absent "wrapped output-dir is analyzed" "$M7CTX" "no --output-dir flag"
check_absent "wrapped image-responses=omit is analyzed" "$M7CTX" "no --image-responses omit"

# Plugin mode + a local duplicate → duplicate warning (verified behavior: a
# project .mcp.json does NOT override a plugin server of the same name).
M3="$WORK/mcp-dupe"; mkdir -p "$M3/projects"
printf '%s' '{"mcpServers":{"atlassian":{"type":"sse","url":"https://mcp.atlassian.com/v1/sse"}}}' > "$M3/.mcp.json"
PCTX3="$(printf '{"cwd":"%s"}' "$M3" | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_contains "plugin + local duplicate → no-override note" "$PCTX3" "no override"

# Contract check, not taste check: a playwright config WITHOUT --output-dir
# breaks the evidence policy → warning. Headful (no --headless) must stay
# silent — it is a preference, not a violation.
M5="$WORK/mcp-no-outdir"; mkdir -p "$M5/projects"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--secrets",".env.playwright-secrets"]}}}' > "$M5/.mcp.json"
M5CTX="$(context_for "$M5")"
check_contains "playwright without --output-dir → warning" "$M5CTX" "no --output-dir flag"
check_absent   "headful is a preference, not a warning" "$M5CTX" "--headless"

# Same shape for the token contract: no --image-responses omit → every screenshot
# lands in the context as an image → warning (0.10.0).
M6="$WORK/mcp-no-imageomit"; mkdir -p "$M6/projects/SHOP"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--secrets",".env.playwright-secrets","--output-dir","evidence/.mcp-out"]}}}' > "$M6/.mcp.json"
check_contains "onboarded project without --image-responses omit → warning" "$(context_for "$M6")" "no --image-responses omit"

MIMGALLOW="$WORK/mcp-image-allow"; mkdir -p "$MIMGALLOW/projects"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--secrets",".env.playwright-secrets","--output-dir","evidence/.mcp-out","--image-responses","allow"]}}}' > "$MIMGALLOW/.mcp.json"
check_contains "--image-responses allow is a contract violation" "$(context_for "$MIMGALLOW")" "no --image-responses omit"

MIMGEQ="$WORK/mcp-image-equals"; mkdir -p "$MIMGEQ/projects"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--secrets",".env.playwright-secrets","--output-dir=evidence/custom","--image-responses=omit"]}}}' > "$MIMGEQ/.mcp.json"
MIMGEQCTX="$(context_for "$MIMGEQ")"
check_absent "--image-responses=omit satisfies the contract" "$MIMGEQCTX" "no --image-responses omit"
check_absent "custom evidence output-dir satisfies the contract" "$MIMGEQCTX" "no --output-dir flag"

MOUTBAD="$WORK/mcp-output-outside"; mkdir -p "$MOUTBAD/projects"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--secrets",".env.playwright-secrets","--output-dir","/tmp/pw-out","--image-responses","omit"]}}}' > "$MOUTBAD/.mcp.json"
check_contains "output-dir outside evidence is a contract violation" "$(context_for "$MOUTBAD")" "no --output-dir flag"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--secrets",".env.playwright-secrets","--output-dir","evidence/../outside","--image-responses","omit"]}}}' > "$MOUTBAD/.mcp.json"
check_contains "output-dir traversal is a contract violation" "$(context_for "$MOUTBAD")" "no --output-dir flag"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--secrets",".env.playwright-secrets","--output-dir","/tmp/evidence","--image-responses","omit"]}}}' > "$MOUTBAD/.mcp.json"
check_contains "foreign absolute evidence root is a contract violation" "$(context_for "$MOUTBAD")" "no --output-dir flag"

MCOMP="$WORK/mcp-complementary"; MCOMPHOME="$WORK/mcp-complementary-home"; mkdir -p "$MCOMP/projects" "$MCOMPHOME"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--secrets",".env.playwright-secrets"]}}}' > "$MCOMPHOME/.claude.json"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--output-dir","evidence/.mcp-out","--image-responses","omit"]}}}' > "$MCOMP/.mcp.json"
MCOMPCTX="$(printf '{"cwd":"%s"}' "$MCOMP" | HOME="$MCOMPHOME" bash "$HOOK" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')"
check_contains "complementary entries do not share secrets health" "$MCOMPCTX" "no --secrets flag"
check_contains "complementary entries do not share output health" "$MCOMPCTX" "no --output-dir flag"
check_contains "complementary entries do not share image health" "$MCOMPCTX" "no --image-responses omit"

MREMOTE="$WORK/mcp-remote"; mkdir -p "$MREMOTE/projects"
printf '%s' '{"mcpServers":{"playwright":{"type":"http","url":"https://pw.example.invalid/mcp"}}}' > "$MREMOTE/.mcp.json"
MREMOTECTX="$(context_for "$MREMOTE")"
check_absent "remote playwright gets no secrets warning" "$MREMOTECTX" "no --secrets flag"
check_absent "remote playwright gets no output-dir warning" "$MREMOTECTX" "no --output-dir flag"
check_absent "remote playwright gets no image warning" "$MREMOTECTX" "no --image-responses omit"

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

# A server that exists ONLY in user scope (leftover from another project) is a
# trap: the PreToolUse guard blocks its use — session start says so up front.
M6="$WORK/mcp-foreign"; FH2="$WORK/fakehome2"; mkdir -p "$M6/projects" "$FH2"
printf '%s' '{"mcpServers":{"gitlab":{"command":"x"}}}' > "$FH2/.claude.json"
printf '%s' '{"mcpServers":{"playwright":{"command":"npx","args":["@playwright/mcp@latest","--secrets",".env.playwright-secrets"]}}}' > "$M6/.mcp.json"
CTX6="$(printf '{"cwd":"%s"}' "$M6" | HOME="$FH2" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_contains "global-only server → foreign warning" "$CTX6" "NOT declared in this project"
check_contains "foreign warning names the server"     "$CTX6" "gitlab"

# Declared in the project too → no warning (deliberate, project-scoped).
M7="$WORK/mcp-foreign-declared"; mkdir -p "$M7/projects"
printf '%s' '{"mcpServers":{"gitlab":{"command":"x"}}}' > "$M7/.mcp.json"
CTX7="$(printf '{"cwd":"%s"}' "$M7" | HOME="$FH2" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_absent "declared in project → no foreign warning" "$CTX7" "NOT declared in this project"

echo
echo "== browser preference file: seeded once, mode rendered, never overwritten =="
# Plugin bootstrap already seeded it into $CONSUMER above (secrets fixture block).
[ -f "$CONSUMER/.playwright-mcp.config.json" ] \
  && printf 'ok    %s\n' "plugin bootstrap seeds .playwright-mcp.config.json" \
  || { printf 'FAIL  %s\n' "plugin bootstrap seeds .playwright-mcp.config.json"; fails=$((fails + 1)); }
check_contains "browser mode rendered in preamble" "$PCTX" "Browser: headless, isolated"
check_contains "freshly seeded → transparent note" "$PCTX" "Created .playwright-mcp.config.json"
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("console",{}).get("level") == "warning" else 1)' "$CONSUMER/.playwright-mcp.config.json" \
  && printf 'ok    %s\n' "browser config seed sets console warning" \
  || { printf 'FAIL  %s\n' "browser config seed sets console warning"; fails=$((fails + 1)); }
# A user-edited file (headful) must survive the next session start untouched,
# and the mode line must follow the user's choice.
printf '%s' '{"browser":{"isolated":true,"launchOptions":{"headless":false}}}' > "$CONSUMER/.playwright-mcp.config.json"
PCTX2="$(printf '{"cwd":"%s"}' "$CONSUMER" | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_contains "headful choice rendered" "$PCTX2" "Browser: headful (visible)"
check_absent   "existing config not re-seeded" "$PCTX2" "Created .playwright-mcp.config.json"
check_contains "user file content untouched" "$(cat "$CONSUMER/.playwright-mcp.config.json")" '"headless":false'
check_contains "existing config without console warning gets a non-destructive hint" "$PCTX2" 'Set `"console": { "level": "warning" }` manually'

echo
echo "== plugin update notice: offline, newer-only, silent on doubt =="
# Fake plugin install (version 0.3.0) + fake marketplace advertising 0.4.0.
UP_PLUG="$WORK/up-plugin"; UP_MP="$WORK/up-marketplace"; UP_HOME="$WORK/up-home"
mkdir -p "$UP_PLUG/.claude-plugin" "$UP_MP/.claude-plugin" "$UP_HOME/.claude/plugins" "$WORK/up-consumer"
printf '%s' '{"name":"qa-agent-blueprint","version":"0.3.0"}' > "$UP_PLUG/.claude-plugin/plugin.json"
printf '%s' '{"name":"mp","plugins":[{"name":"qa-agent-blueprint","version":"0.4.0"}]}' > "$UP_MP/.claude-plugin/marketplace.json"
printf '%s' "{\"mp\":{\"installLocation\":\"$UP_MP\"}}" > "$UP_HOME/.claude/plugins/known_marketplaces.json"
UPCTX="$(printf '{"cwd":"%s"}' "$WORK/up-consumer" | HOME="$UP_HOME" CLAUDE_PLUGIN_ROOT="$UP_PLUG" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_contains "newer marketplace version → update hint" "$UPCTX" "UPDATE: qa-agent-blueprint 0.4.0 is available (running 0.3.0)"
# Same version → silent.
printf '%s' '{"name":"mp","plugins":[{"name":"qa-agent-blueprint","version":"0.3.0"}]}' > "$UP_MP/.claude-plugin/marketplace.json"
UPCTX2="$(printf '{"cwd":"%s"}' "$WORK/up-consumer" | HOME="$UP_HOME" CLAUDE_PLUGIN_ROOT="$UP_PLUG" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_absent "same version → no hint" "$UPCTX2" "UPDATE:"
# No marketplace knowledge at all → silent (never block a session on a hint).
UPCTX3="$(printf '{"cwd":"%s"}' "$WORK/up-consumer" | HOME="$WORK/no-such-home" CLAUDE_PLUGIN_ROOT="$UP_PLUG" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_absent "unknown marketplace state → no hint" "$UPCTX3" "UPDATE:"

echo
echo "== keychain secrets: the agent sees what it has, never a value =="
# A mock `security` CLI: fixture values for known services, error otherwise —
# the same contract as macOS find-generic-password -w, without touching a real
# keychain.
MOCKBIN="$WORK/mockbin"; mkdir -p "$MOCKBIN"
cat > "$MOCKBIN/security" <<'MOCK'
#!/usr/bin/env bash
svc=""
while [ $# -gt 0 ]; do [ "$1" = "-s" ] && svc="$2"; shift; done
case "$svc" in
  KC_A_PASSWORD) echo "fixture-value-AAA" ;;
  KC_B_PASSWORD) echo "fixture-value-BBB" ;;
  JIRA_PAT_jira.fixture.invalid) echo "fixture-pat-999" ;;
  *) echo "could not be found" >&2; exit 44 ;;
esac
MOCK
chmod +x "$MOCKBIN/security"

mk_kc_project() {  # mk_kc_project <dir> — one keychain project, three declared keys
  mkdir -p "$1/projects/KC"
  cat > "$1/projects/KC/PROJECT.md" <<'EOF'
# Project File: KC
- **Secrets source**: `keychain`
## Test users
| Role | Purpose | Vault path (relative) | Env/secret key |
|---|---|---|---|
| `a` | x | `<key>/a` | `KC_A_PASSWORD` |
| `b` | x | `<key>/b` | `KC_B_PASSWORD` |
| `c` | x | `<key>/c` | `KC_C_PASSWORD` |
EOF
}

# Status line: 2 of 3 keys present in the file → agent sees the count AND the
# missing key's NAME (that visibility is the fix for "the agent invents
# credentials"). No security call involved — pure file inspection.
KC1="$WORK/kc-status"; mk_kc_project "$KC1"
cat > "$KC1/.env.playwright-secrets" <<'EOF'
# --- qa-blueprint managed block (resolve-secrets.sh) ---
KC_A_PASSWORD=fixture-value-AAA
KC_B_PASSWORD=fixture-value-BBB
# --- end qa-blueprint managed block ---
EOF
KC1CTX="$(context_for "$KC1")"
check_contains "status line counts present keys" "$KC1CTX" "keychain secrets: 2/3 present"
check_contains "missing key is NAMED" "$KC1CTX" "KC_C_PASSWORD"
check_absent   "resolved values never reach context" "$KC1CTX" "fixture-value-AAA"
check_absent   "resolved values never reach context (2)" "$KC1CTX" "fixture-value-BBB"

# No declaration → no keychain line at all (env-file projects stay silent).
check_absent "env-file projects get no keychain line" "$CTX" "keychain secrets"

# Auto-resolve on missing file: hook must create the file via the resolver,
# context names keys, values stay out of context but land in the file.
KC2="$WORK/kc-resolve"; mk_kc_project "$KC2"
KC2CTX="$(printf '{"cwd":"%s"}' "$KC2" | PATH="$MOCKBIN:$PATH" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
if [ -f "$KC2/.env.playwright-secrets" ] \
   && grep -q "KC_A_PASSWORD=fixture-value-AAA" "$KC2/.env.playwright-secrets" \
   && grep -q "KC_B_PASSWORD=fixture-value-BBB" "$KC2/.env.playwright-secrets"; then
  printf 'ok    %s\n' "auto-resolve writes the file when it was missing"
else
  printf 'FAIL  %s\n' "auto-resolve writes the file when it was missing"; fails=$((fails + 1))
fi
check_contains "auto-resolve reports key names" "$KC2CTX" "resolve-secrets: 2/3 keychain keys resolved"
check_contains "auto-resolve names the missing key + one-time command" "$KC2CTX" "security add-generic-password -s KC_C_PASSWORD -a qa -w"
check_absent   "auto-resolve leaks no value into context" "$KC2CTX" "fixture-value-AAA"
check_absent   "auto-resolve leaks no value into context (2)" "$KC2CTX" "fixture-value-BBB"

echo
echo "== JIRA Data Center PAT: keychain → session env, never a file =="
DC1="$WORK/dc-pat"; mkdir -p "$DC1/projects"
printf '%s' '{"mcpServers":{"atlassian":{"command":"uvx","args":["mcp-atlassian"],"env":{"JIRA_URL":"https://jira.fixture.invalid"}}}}' > "$DC1/.mcp.json"
ENVFILE="$WORK/dc-envfile"; : > "$ENVFILE"
DC1CTX="$(printf '{"cwd":"%s"}' "$DC1" | PATH="$MOCKBIN:$PATH" CLAUDE_ENV_FILE="$ENVFILE" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
if grep -q "export JIRA_PERSONAL_TOKEN=fixture-pat-999" "$ENVFILE"; then
  printf 'ok    %s\n' "PAT exported into CLAUDE_ENV_FILE"
else
  printf 'FAIL  %s\n' "PAT exported into CLAUDE_ENV_FILE"; fails=$((fails + 1))
fi
check_contains "PAT resolution announced by service name" "$DC1CTX" "service JIRA_PAT_jira.fixture.invalid"
check_absent   "PAT value never reaches context" "$DC1CTX" "fixture-pat-999"

# PAT already in the environment → no keychain access, no env write.
ENVFILE2="$WORK/dc-envfile2"; : > "$ENVFILE2"
DC2CTX="$(printf '{"cwd":"%s"}' "$DC1" | PATH="$MOCKBIN:$PATH" CLAUDE_ENV_FILE="$ENVFILE2" JIRA_PERSONAL_TOKEN="already-set" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
[ -s "$ENVFILE2" ] \
  && { printf 'FAIL  %s\n' "existing PAT env var is left alone"; fails=$((fails + 1)); } \
  || printf 'ok    %s\n' "existing PAT env var is left alone"
check_absent "no resolution note when PAT already set" "$DC2CTX" "JIRA PAT"

# DC configured but nothing resolvable → the one-time store command is named.
DC3="$WORK/dc-missing"; mkdir -p "$DC3/projects"
printf '%s' '{"mcpServers":{"atlassian":{"command":"uvx","args":["mcp-atlassian"],"env":{"JIRA_URL":"https://other.fixture.invalid"}}}}' > "$DC3/.mcp.json"
DC3CTX="$(printf '{"cwd":"%s"}' "$DC3" | PATH="$MOCKBIN:$PATH" CLAUDE_ENV_FILE="$WORK/dc-envfile3" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_contains "unresolvable PAT names the one-time command" "$DC3CTX" "security add-generic-password -s JIRA_PAT_other.fixture.invalid -a jira -w"

# Cloud entries (no env.JIRA_URL) never trigger the DC path — covered by the
# existing MCP fixtures above, which assert no JIRA lines appear.

echo
echo "== degraded machine: no security CLI → note, never a crash =="
NOSEC="$WORK/nosec-bin"; mkdir -p "$NOSEC"
for t in python3 python bash sh sed grep cat dirname basename tr uname mkdir npx git head; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$NOSEC/$t" 2>/dev/null
done
DC4="$WORK/dc-nosec"; mkdir -p "$DC4/projects"
printf '%s' '{"mcpServers":{"atlassian":{"command":"uvx","args":["mcp-atlassian"],"env":{"JIRA_URL":"https://jira.fixture.invalid"}}}}' > "$DC4/.mcp.json"
DC4CTX="$(printf '{"cwd":"%s"}' "$DC4" | PATH="$NOSEC" CLAUDE_ENV_FILE="$WORK/dc-envfile4" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
')"
check_contains "missing security CLI is a note, not a crash" "$DC4CTX" "security CLI is unavailable"

echo
echo "== QA home walk-up: no dual scaffold in subfolders (0.9.1 field report) =="
# A session starting in a SUBFOLDER of the QA home (a product repo inside the
# customer workspace) must resolve the home upwards — data (projects/, memory/,
# evidence/) lives at the root, harness-scoped seeds stay with the session cwd.
plug_ctx_for() {
  printf '{"cwd":"%s"}' "$1" | CLAUDE_PLUGIN_ROOT="$PLUGIN" bash "$HOOK" 2>/dev/null | python3 -c '
import json, sys
try:
    print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])
except Exception:
    print("")
'
}
ok_file()    { [ -f "$2" ] && printf 'ok    %s\n' "$1" || { printf 'FAIL  %s\n      missing: %s\n' "$1" "$2"; fails=$((fails + 1)); }; }
ok_no_file() { [ ! -e "$2" ] && printf 'ok    %s\n' "$1" || { printf 'FAIL  %s\n      should not exist: %s\n' "$1" "$2"; fails=$((fails + 1)); }; }

QH="$WORK/qh-home"; QSUB="$QH/test-automation"
mkdir -p "$QH/projects/TA" "$QH/memory" "$QH/evidence" "$QSUB"
printf '# TA\n' > "$QH/projects/TA/PROJECT.md"
QCTX="$(plug_ctx_for "$QSUB")"
check_contains "subfolder session resolves the QA home" "$QCTX" "QA home: $QH"
check_contains "home line says paths are home-relative" "$QCTX" "relative to the QA home, not to cwd"
check_contains "projects listed from the home"          "$QCTX" "- TA"
ok_no_file "no dual projects/ scaffolded in subfolder" "$QSUB/projects"
ok_no_file "no dual memory/ scaffolded in subfolder"   "$QSUB/memory"
ok_no_file "no dual evidence/ scaffolded in subfolder" "$QSUB/evidence"
ok_file    "legacy-trio home got the .qa-home marker"  "$QH/.qa-home"
ok_file    "secrets seed stays at the session cwd"     "$QSUB/.env.playwright-secrets"
ok_file    "browser config seed stays at session cwd"  "$QSUB/.playwright-mcp.config.json"
ok_no_file "no harness seed duplicated into the home"  "$QH/.env.playwright-secrets"

# The marker alone resolves as well (no trio needed).
QH2="$WORK/qh-marker"; QSUB2="$QH2/repo/sub"
mkdir -p "$QH2/projects" "$QSUB2"
printf 'marker\n' > "$QH2/.qa-home"
QCTX2="$(plug_ctx_for "$QSUB2")"
check_contains "marker-only home resolves from two levels down" "$QCTX2" "QA home: $QH2"

echo
echo "== ungroomed-learnings backlog: hint below the auto-groom threshold, directive above =="
# The auto-groom threshold (5+ entries, oldest entry > 14 days, or 16 KB) turns
# the human hint into an agent directive. Dates computed relative to today, so
# the fixture never rots.
RECENT="$(python3 -c 'import datetime; print((datetime.date.today() - datetime.timedelta(days=3)).isoformat())')"
OLD="$(python3 -c 'import datetime; print((datetime.date.today() - datetime.timedelta(days=30)).isoformat())')"

# A small, fresh backlog stays a hint to the human.
G1="$WORK/groom-hint"; mkdir -p "$G1/projects" "$G1/memory/learnings"
printf '# Inbox\n\n## %s — one\n\n## %s — two\n' "$RECENT" "$RECENT" > "$G1/memory/learnings/_inbox.md"
G1CTX="$(context_for "$G1")"
check_contains "2 fresh entries → human hint" "$G1CTX" "2 ungroomed learnings"
check_absent   "2 fresh entries → no directive" "$G1CTX" "AUTO-GROOM"

# Five fresh entries cross the count threshold on their own.
G2="$WORK/groom-count"; mkdir -p "$G2/projects" "$G2/memory/learnings"
{ printf '# Inbox\n\n'; for i in 1 2 3 4 5; do printf '## %s — entry %s\n\n' "$RECENT" "$i"; done; } > "$G2/memory/learnings/_inbox.md"
G2CTX="$(context_for "$G2")"
check_contains "5 fresh entries → AUTO-GROOM directive" "$G2CTX" "AUTO-GROOM: 5 ungroomed learnings"
check_contains "directive orders end-of-session grooming" "$G2CTX" "at the end of this session"

# Two entries, but the oldest is over 14 days — the age trigger fires alone.
G3="$WORK/groom-age"; mkdir -p "$G3/projects" "$G3/memory/learnings"
printf '# Inbox\n\n## %s — stale\n\n## %s — fresh\n' "$OLD" "$RECENT" > "$G3/memory/learnings/_inbox.md"
G3CTX="$(context_for "$G3")"
check_contains "2 entries with stale oldest → directive" "$G3CTX" "AUTO-GROOM: 2 ungroomed learnings"
check_contains "directive names the oldest entry date" "$G3CTX" "oldest: $OLD"

# One real entry counts; the retired dated template example does not.
G4="$WORK/groom-single"; mkdir -p "$G4/projects" "$G4/memory/learnings"
printf '# Inbox\n\n## %s — one real entry\n' "$RECENT" > "$G4/memory/learnings/_inbox.md"
check_contains "single fresh entry gets a hint" "$(context_for "$G4")" "1 ungroomed learnings"
printf '# Inbox\n\n## %s — one stale entry\n' "$OLD" > "$G4/memory/learnings/_inbox.md"
check_contains "single stale entry triggers grooming" "$(context_for "$G4")" "AUTO-GROOM: 1 ungroomed learnings"
printf '# Inbox\n\n## 2026-09-05 — SHOP-1234\n' > "$G4/memory/learnings/_inbox.md"
check_absent "legacy dated template example stays silent" "$(context_for "$G4")" "ungroomed learnings"

G5="$WORK/groom-bytes"; mkdir -p "$G5/projects" "$G5/memory/learnings"
python3 -c 'import sys; open(sys.argv[1], "w").write("# Inbox\n\n## '"$RECENT"' — one\n\n" + "x" * 17000 + "\n\n## '"$RECENT"' — two\n")' "$G5/memory/learnings/_inbox.md"
check_contains "16 KB with fewer than five entries triggers grooming" "$(context_for "$G5")" "AUTO-GROOM: 2 ungroomed learnings"
check_contains "directive includes the byte threshold" "$(context_for "$G5")" "16 KB"

echo
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) failed"
fi
exit "$fails"

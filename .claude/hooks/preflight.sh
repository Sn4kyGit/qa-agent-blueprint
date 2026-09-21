#!/usr/bin/env bash
#
# preflight.sh — pre-requirements probe before any browser/JIRA action of a
# test run. Exists because the classic false-positive factory is a forgotten
# VPN: stage and JIRA are unreachable, the agent walks into confusing errors,
# and the "result" says something about the environment, not the product.
#
# Usage:  preflight.sh <KEY> [CWD]     CWD defaults to $PWD (the consumer repo)
# Exit:   0 = all checks passed, 1 = at least one FAIL
#
# Checks (projects/<KEY>/PROJECT.md is the source of truth):
#   1. every URL in the project's Environments table answers (curl, any HTTP
#      status counts — even 401/403 means the host is reachable)
#   2. the declared JIRA base URL answers (projects with JIRA access: browser
#      rely on this probe alone — the atlassian MCP is intentionally absent)
#   3. VPN posture (macOS): more than one connected VPN service → FAIL — two
#      VPNs collide on routes/DNS and produce exactly the flaky half-reachable
#      state this script exists to catch. Override (a setup that legitimately
#      needs two): QA_PREFLIGHT_ALLOW_MULTI_VPN=1
#   4. declared keychain secrets are present (resolve-secrets.sh --status,
#      names only — never values)
#
# On full pass the script writes evidence/.preflight/ok.json; the PreToolUse
# gate in pre-tool-guard.sh refuses playwright/atlassian MCP calls without a
# fresh artifact (TTL: QA_PREFLIGHT_TTL_MIN, default 60). A FAILED run REMOVES
# the artifact, so the gate closes again instead of riding on a stale pass.
# Escape hatch for the whole mechanism: QA_PREFLIGHT=0.
#
# MCP liveness is NOT probed here — a bash script cannot call MCP servers.
# The agent-side norm (qa-manager step 0) covers that half with one trivial
# call per server in the loop.
#
set -uo pipefail

KEY="${1:-}"
CWD="${2:-$PWD}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$KEY" ]; then
  echo "usage: preflight.sh <KEY> [CWD]" >&2
  exit 1
fi

PROJECT_FILE="$CWD/projects/$KEY/PROJECT.md"
if [ ! -f "$PROJECT_FILE" ]; then
  echo "FAIL project projects/$KEY/PROJECT.md not found — run /onboard-project first."
  exit 1
fi

OK_JSON="$CWD/evidence/.preflight/ok.json"
fails=0

# URL extraction is a whitelist character class on purpose: markdown table
# pipes, wrapping <…>, and trailing punctuation stay out without quoting games.
env_urls() {
  awk '/^## Environments/{f=1;next} /^## /{f=0} f' "$PROJECT_FILE" \
    | grep -oE 'https?://[A-Za-z0-9./_:?=&%#~+-]+' \
    | grep -v 'example\.invalid' | sort -u
}
jira_url() {
  grep -iE 'JIRA base URL' "$PROJECT_FILE" \
    | grep -oE 'https?://[A-Za-z0-9./_:?=&%#~+-]+' \
    | grep -v 'example\.invalid' | head -1
}

probe() { # probe <label> <url>
  local label="$1" url="$2" code
  code="$(curl -s -o /dev/null -m "${QA_PREFLIGHT_TIMEOUT:-6}" -w '%{http_code}' "$url" 2>/dev/null)"
  if [ -z "$code" ] || [ "$code" = "000" ]; then
    echo "FAIL $label $url — unreachable (VPN off? proxy? DNS?)"
    fails=$((fails + 1))
  else
    echo "OK   $label $url (HTTP $code)"
  fi
}

TARGETS="$(env_urls)"
JIRA_URL="$(jira_url)"
if [ -z "$TARGETS" ] && [ -z "$JIRA_URL" ]; then
  echo "FAIL project projects/$KEY/PROJECT.md declares no probe targets (Environments table, JIRA base URL) — run /onboard-project or /re-board."
  exit 1
fi

# 1+2. reachability
while IFS= read -r url; do
  [ -n "$url" ] && probe "env " "$url"
done <<< "$TARGETS"
[ -n "$JIRA_URL" ] && probe "jira" "$JIRA_URL"

if grep -qiE 'JIRA access:[[:space:]]*`?browser' "$PROJECT_FILE"; then
  echo "note jira access: browser — atlassian MCP intentionally absent; the URL probe above covers JIRA."
fi

# 3. VPN posture (macOS). scutil lists network-extension VPN services and
# their state; utun counting is noise (Private Relay et al.), so this is the
# one signal that means "a VPN the user switched on".
if command -v scutil >/dev/null 2>&1; then
  CONNECTED="$(scutil --nc list 2>/dev/null | grep -c '(Connected)')"
  CONNECTED="${CONNECTED:-0}"
  if [ "$CONNECTED" -gt 1 ] && [ "${QA_PREFLIGHT_ALLOW_MULTI_VPN:-0}" != "1" ]; then
    echo "FAIL vpn $CONNECTED VPN services connected — multiple VPNs collide on routes/DNS; disconnect all but one (override: QA_PREFLIGHT_ALLOW_MULTI_VPN=1)"
    fails=$((fails + 1))
  else
    echo "OK   vpn $CONNECTED connected VPN service(s)"
  fi
else
  echo "note vpn check skipped (no scutil — non-macOS host)"
fi

# 4. declared secrets present (names only — status never touches the keychain
# and never prints a value).
SECRETS_STATUS="$("$SCRIPT_DIR/resolve-secrets.sh" "$CWD" --status 2>/dev/null)"
if printf '%s' "$SECRETS_STATUS" | grep -q '— missing:'; then
  MISSING="$(printf '%s' "$SECRETS_STATUS" | sed -n 's/.*— missing: \(.*\) (resolve:.*/\1/p' | head -1)"
  echo "FAIL secrets missing: $MISSING — run the blueprint's resolve-secrets.sh once the human can type into the keychain dialog."
  fails=$((fails + 1))
elif [ -n "$SECRETS_STATUS" ]; then
  echo "OK   secrets $(printf '%s' "$SECRETS_STATUS" | head -1)"
else
  echo "OK   secrets (no keychain keys declared)"
fi

# artifact: pass → write, fail → remove (the gate must close again)
if [ "$fails" -eq 0 ]; then
  mkdir -p "$(dirname "$OK_JSON")"
  printf '{"key":"%s","checked_at":%s,"ok":true}\n' "$KEY" "$(date +%s)" > "$OK_JSON"
  echo "preflight OK — gate open for ${QA_PREFLIGHT_TTL_MIN:-60}m (evidence/.preflight/ok.json)"
  exit 0
else
  rm -f "$OK_JSON"
  echo "preflight FAILED ($fails) — fix the cause, then re-run. Do NOT start testing: a result collected in this state says something about the environment, not the product."
  exit 1
fi

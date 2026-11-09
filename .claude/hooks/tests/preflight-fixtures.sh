#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit

#
# preflight-fixtures.sh — fixture test for preflight.sh.
#
# Same philosophy as guard-fixtures.sh: a preflight that cannot prove it
# fails when the VPN is off is a decoration, not a check. curl and scutil are
# PATH-shimmed; resolve-secrets.sh --status runs for real (status mode never
# touches the keychain — it compares declared keys against the file).
#
# Usage:  bash .claude/hooks/tests/preflight-fixtures.sh
# Exit:   0 = all fixtures pass, otherwise the number of failures.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFLIGHT="$HERE/../preflight.sh"
fails=0

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- PATH shims -------------------------------------------------------------
SHIM="$WORK/shim"
mkdir -p "$SHIM"

# curl: prints MOCK_CURL_CODE as the http_code, unless the URL matches
# MOCK_CURL_DOWN_SUBSTR — then 000 (unreachable).
cat > "$SHIM/curl" <<'EOF'
#!/usr/bin/env bash
url=""
for a in "$@"; do case "$a" in http*://*) url="$a" ;; esac; done
if [ -n "${MOCK_CURL_DOWN_SUBSTR:-}" ] && printf '%s' "$url" | grep -q "$MOCK_CURL_DOWN_SUBSTR"; then
  printf '000'
else
  printf '%s' "${MOCK_CURL_CODE:-200}"
fi
EOF
chmod +x "$SHIM/curl"

# scutil: prints canned `scutil --nc list` output — MOCK_VPN_CONNECTED entries.
cat > "$SHIM/scutil" <<'EOF'
#!/usr/bin/env bash
n="${MOCK_VPN_CONNECTED:-0}"
i=0
while [ "$i" -lt "$n" ]; do
  i=$((i + 1))
  echo "* (Connected)           00000000-0000-0000-0000-00000000000$i VPN-$i [IKEv2]"
done
echo "* (Disconnected)        11111111-1111-1111-1111-111111111111 OldVPN [IPSec]"
EOF
chmod +x "$SHIM/scutil"

# --- consumer scaffolding -----------------------------------------------------
PROJECT="$WORK/consumer"
mkdir -p "$PROJECT/projects/SHOP" "$PROJECT/evidence"
cat > "$PROJECT/projects/SHOP/PROJECT.md" <<'EOF'
# SHOP
- **JIRA base URL**: `https://jira.corp.example.com`
## Environments
| Environment | URL | Purpose |
|---|---|---|
| stage | `https://stage.corp.example.com` | all agent testing |
## Secrets
EOF

run() { # run <name> <want-exit> [env assignments...]
  local name="$1" want="$2"; shift 2
  local got
  env -i PATH="$SHIM:/usr/bin:/bin" HOME="$WORK" "$@" \
    bash "$PREFLIGHT" SHOP "$PROJECT" > "$WORK/out.txt" 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    printf 'ok    %-46s exit=%s\n' "$name" "$got"
  else
    printf 'FAIL  %-46s want=%s got=%s\n' "$name" "$want" "$got"
    sed 's/^/      /' "$WORK/out.txt"
    fails=$((fails + 1))
  fi
}

expect_out() { # expect_out <name> <grep-pattern>
  local name="$1" pat="$2"
  if grep -qE "$pat" "$WORK/out.txt"; then
    printf 'ok    %-46s output\n' "$name"
  else
    printf 'FAIL  %-46s missing /%s/\n' "$name" "$pat"
    sed 's/^/      /' "$WORK/out.txt"
    fails=$((fails + 1))
  fi
}

artifact() { # artifact <name> <present|absent>
  if [ "$2" = present ] && [ -f "$PROJECT/evidence/.preflight/ok.json" ]; then
    printf 'ok    %-46s artifact\n' "$1"
  elif [ "$2" = absent ] && [ ! -f "$PROJECT/evidence/.preflight/ok.json" ]; then
    printf 'ok    %-46s artifact\n' "$1"
  else
    printf 'FAIL  %-46s artifact %s expected\n' "$1" "$2"
    fails=$((fails + 1))
  fi
}

echo "== all green: reachable, one VPN, no declared secrets =="
run "all reachable + 1 VPN"            0 MOCK_CURL_CODE=200 MOCK_VPN_CONNECTED=1
expect_out "env probe OK"               '^OK   env  https://stage\.corp\.example\.com \(HTTP 200\)'
expect_out "jira probe OK"              '^OK   jira https://jira\.corp\.example\.com \(HTTP 200\)'
artifact "gate artifact written"        present

echo
echo "== VPN off: stage unreachable =="
run "stage unreachable"                1 MOCK_CURL_DOWN_SUBSTR=stage MOCK_VPN_CONNECTED=0
expect_out "VPN hint in output"         'FAIL env .*unreachable \(VPN off\? proxy\? DNS\?\)'
expect_out "jira still probed"          '^OK   jira'
artifact "artifact removed on failure"  absent

echo
echo "== JIRA unreachable (jira-only outage) =="
run "jira unreachable"                 1 MOCK_CURL_DOWN_SUBSTR=jira MOCK_VPN_CONNECTED=1
expect_out "jira FAIL named"            '^FAIL jira'
artifact "artifact stays removed"       absent

echo
echo "== multiple VPNs =="
run "two VPNs connected"               1 MOCK_CURL_CODE=200 MOCK_VPN_CONNECTED=2
expect_out "multi-VPN named"            'FAIL vpn 2 VPN services connected'
run "two VPNs, override set"           0 MOCK_CURL_CODE=200 MOCK_VPN_CONNECTED=2 QA_PREFLIGHT_ALLOW_MULTI_VPN=1
expect_out "override notes count"       '^OK   vpn 2 connected VPN service'
artifact "artifact written again"       present

echo
echo "== secrets: declared key missing =="
cat > "$PROJECT/projects/SHOP/PROJECT.md" <<'EOF'
# SHOP
- **JIRA base URL**: `https://jira.corp.example.com`
## Environments
| Environment | URL | Purpose |
|---|---|---|
| stage | `https://stage.corp.example.com` | all agent testing |
## Test users
- **Secrets source**: `keychain`
| Role | Purpose | Vault path (relative) | Env/secret key |
|---|---|---|---|
| `qa-standard` | default journey | `shop/qa-standard` | `SHOP_QA_STANDARD_PASSWORD` |
EOF
run "declared key missing"             1 MOCK_CURL_CODE=200 MOCK_VPN_CONNECTED=1
expect_out "missing key named"          'FAIL secrets missing: .*SHOP_QA_STANDARD_PASSWORD'
if grep -q 'hunter2' "$WORK/out.txt"; then
  printf 'FAIL  %-46s a value leaked into output\n' "no value ever printed"
  fails=$((fails + 1))
else
  printf 'ok    %-46s output\n' "no value ever printed"
fi
artifact "artifact removed"             absent

echo
echo "== no probe targets declared =="
cat > "$PROJECT/projects/SHOP/PROJECT.md" <<'EOF'
# SHOP
## Environments
| Environment | URL | Purpose |
|---|---|---|
| stage | `TODO:` | all agent testing |
EOF
run "no URLs declared"                 1 MOCK_CURL_CODE=200 MOCK_VPN_CONNECTED=0
expect_out "onboard pointer"            'no probe targets'

echo
echo "== missing project file =="
env -i PATH="$SHIM:/usr/bin:/bin" bash "$PREFLIGHT" NOPE "$PROJECT" > "$WORK/out.txt" 2>&1
if [ $? -eq 1 ] && grep -q 'onboard-project' "$WORK/out.txt"; then
  printf 'ok    %-46s exit=1\n' "unknown key → onboard pointer"
else
  printf 'FAIL  %-46s\n' "unknown key → onboard pointer"
  fails=$((fails + 1))
fi

echo
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) FAILED" >&2
fi
exit "$fails"

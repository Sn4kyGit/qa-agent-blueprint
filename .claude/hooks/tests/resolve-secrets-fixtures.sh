#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit, Anna Mazurek

#
# resolve-secrets-fixtures.sh — fixture test for resolve-secrets.sh modes
# (resolve, --status, --import, --capture).
#
# Why: this script is the ONLY sanctioned writer of .env.playwright-secrets and
# the only agent-runnable path that touches the keychain. Its failure modes are
# silent and security-relevant: a value leaking into stdout (it would land in
# the transcript), an undeclared key swept into the vault, a locked keychain
# downgrading the file. Mocking `security`/`osascript` keeps the real keychain
# out of the test while preserving the exact CLI contract.
#
# Usage:  bash .claude/hooks/tests/resolve-secrets-fixtures.sh
# Exit:   0 = all fixtures pass, otherwise the number of failures.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$HERE/../resolve-secrets.sh"
[ -f "$RESOLVER" ] || { echo "resolve-secrets.sh not found at $RESOLVER" >&2; exit 1; }

fails=0
WORK="$(mktemp -d)"
trap 'rm -r "$WORK" 2>/dev/null' EXIT

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

# --- mock toolchain -----------------------------------------------------------
# `security` backed by a plain store file (service<TAB>value per line); honors
# the real contract: find → value on stdout / rc 44; add with bare -w → reads
# the password TWICE from stdin; logs every add to $MOCK_LOG.
MOCKBIN="$WORK/bin"; mkdir -p "$MOCKBIN"
export MOCK_STORE="$WORK/store" MOCK_LOG="$WORK/log"
: > "$MOCK_STORE"; : > "$MOCK_LOG"
cat > "$MOCKBIN/security" <<'MOCK'
#!/usr/bin/env bash
# Faithful to the real CLI: a token following -w IS the password (so `-w -U`
# stores "-U" — a real bug this mock exists to catch); bare -w at the end
# reads the password twice from stdin.
cmd="$1"; shift
svc=""; upd=0; pw=""; have_pw=0
while [ $# -gt 0 ]; do
  case "$1" in
    -s) svc="$2"; shift 2 ;;
    -U) upd=1; shift ;;
    -w)
      shift
      if [ $# -gt 0 ]; then pw="$1"; have_pw=1; shift; fi
      ;;
    *) shift ;;
  esac
done
case "$cmd" in
  find-generic-password)
    line="$(grep "^$svc	" "$MOCK_STORE" 2>/dev/null | head -1)"
    if [ -n "$line" ]; then printf '%s\n' "${line#*	}"; else echo "not found" >&2; exit 44; fi
    ;;
  add-generic-password)
    [ "$upd" -eq 1 ] && echo "USED_UPDATE_FLAG $svc" >> "$MOCK_LOG"
    if [ "$have_pw" -eq 0 ]; then
      IFS= read -r pw1; IFS= read -r pw2
      [ "$pw1" = "$pw2" ] || { echo "mismatch" >&2; exit 1; }
      pw="$pw1"
    fi
    grep -v "^$svc	" "$MOCK_STORE" > "$MOCK_STORE.tmp" 2>/dev/null || true
    printf '%s\t%s\n' "$svc" "$pw" >> "$MOCK_STORE.tmp"
    mv "$MOCK_STORE.tmp" "$MOCK_STORE"
    echo "ADDED $svc" >> "$MOCK_LOG"
    ;;
esac
MOCK
chmod +x "$MOCKBIN/security"
# osascript mock: returns a hidden-answer dialog result; CANCEL variant exits 1.
cat > "$MOCKBIN/osascript" <<'MOCK'
#!/usr/bin/env bash
[ "${OSASCRIPT_BEHAVIOR:-ok}" = "cancel" ] && exit 1
echo 'button returned:Store, text returned:fixture-captured-value'
MOCK
chmod +x "$MOCKBIN/osascript"

mk_project() {  # mk_project <dir> — keychain project declaring KC_A/KC_B/KC_C
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

echo "== import: declared keys only, values via stdin, never on stdout =="
I1="$WORK/import1"; mk_project "$I1"
cat > "$I1/.env.playwright-secrets" <<'EOF'
# hand-filled (env-file history)
KC_A_PASSWORD=fixture-value-AAA
KC_B_PASSWORD=fixture-value-BBB
UNDECLARED_KEY=must-not-be-imported
EOF
OUT="$(PATH="$MOCKBIN:$PATH" bash "$RESOLVER" "$I1" --import 2>&1)"
check_contains "import reports stored keys" "$OUT" "2 stored in keychain"
check_contains "import names the key missing from the file" "$OUT" "KC_C_PASSWORD"
check_absent  "import never prints a value" "$OUT" "fixture-value-AAA"
check_absent  "import never prints a value (2)" "$OUT" "fixture-value-BBB"
if grep -q $'^KC_A_PASSWORD\tfixture-value-AAA' "$MOCK_STORE" \
   && grep -q $'^KC_B_PASSWORD\tfixture-value-BBB' "$MOCK_STORE" \
   && ! grep -q "UNDECLARED_KEY" "$MOCK_STORE"; then
  printf 'ok    %s\n' "import stores declared keys, ignores undeclared lines"
else
  printf 'FAIL  %s\n' "import stores declared keys, ignores undeclared lines"; fails=$((fails + 1))
fi
# Regression, found on a real keychain: `-w -U` makes the CLI store the
# literal string "-U" as the password. The stored value must be what was piped.
check_absent "stored value is never the -U flag" "$(cat "$MOCK_STORE")" $'\t-U'

echo
echo "== import is idempotent without --force, overwrites with it =="
OUT2="$(PATH="$MOCKBIN:$PATH" bash "$RESOLVER" "$I1" --import 2>&1)"
check_contains "second import skips existing" "$OUT2" "already present (skipped"
: > "$MOCK_LOG"
OUT3="$(PATH="$MOCKBIN:$PATH" bash "$RESOLVER" "$I1" --import --force 2>&1)"
check_contains "force re-stores" "$OUT3" "2 stored in keychain"
check_contains "force uses the update flag" "$(cat "$MOCK_LOG")" "USED_UPDATE_FLAG KC_A_PASSWORD"

echo
echo "== capture: GUI dialog value flows into keychain + file, stdout stays clean =="
: > "$MOCK_STORE"; : > "$MOCK_LOG"
C1="$WORK/capture1"; mk_project "$C1"
OUT4="$(PATH="$MOCKBIN:$PATH" bash "$RESOLVER" "$C1" --capture 2>&1)"
check_contains "capture reports stored keys" "$OUT4" "stored KC_A_PASSWORD, KC_B_PASSWORD, KC_C_PASSWORD"
check_absent  "capture never prints the dialog value" "$OUT4" "fixture-captured-value"
if grep -q $'^KC_A_PASSWORD\tfixture-captured-value' "$MOCK_STORE"; then
  printf 'ok    %s\n' "capture stored the dialog value in the keychain"
else
  printf 'FAIL  %s\n' "capture stored the dialog value in the keychain"; fails=$((fails + 1))
fi
# capture falls through into resolve: the file now holds the managed block.
if [ -f "$C1/.env.playwright-secrets" ] \
   && grep -q "KC_A_PASSWORD=fixture-captured-value" "$C1/.env.playwright-secrets"; then
  printf 'ok    %s\n' "capture ends by resolving the file"
else
  printf 'FAIL  %s\n' "capture ends by resolving the file"; fails=$((fails + 1))
fi

echo
echo "== capture on Cancel/headless: manual hint, no crash =="
: > "$MOCK_STORE"
C2="$WORK/capture2"; mk_project "$C2"
OUT5="$(OSASCRIPT_BEHAVIOR=cancel PATH="$MOCKBIN:$PATH" bash "$RESOLVER" "$C2" --capture 2>&1)"
check_contains "cancelled capture prints the manual command" "$OUT5" "security add-generic-password -s KC_A_PASSWORD -a qa -w"

# No osascript on PATH at all: symlink farm without it.
NOOSA="$WORK/noosa-bin"; mkdir -p "$NOOSA"
for t in python3 bash sh sed grep cat dirname basename tr uname head mv chmod which; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$NOOSA/$t" 2>/dev/null
done
ln -sf "$MOCKBIN/security" "$NOOSA/security"
C3="$WORK/capture3"; mk_project "$C3"
OUT6="$(PATH="$NOOSA" bash "$RESOLVER" "$C3" --capture 2>&1)"
check_contains "no osascript → fallback with manual commands" "$OUT6" "store the keys manually instead"
check_contains "fallback names every key's command" "$OUT6" "security add-generic-password -s KC_C_PASSWORD -a qa -w"

echo
echo "== no keychain declarations → silent in every mode =="
E1="$WORK/empty"; mkdir -p "$E1/projects/PLAIN"
printf '# Project File: PLAIN\n## Test users\n| Role | Purpose | Vault path (relative) | Env/secret key |\n|---|---|---|---|\n| `a` | x | `<key>/a` | `PLAIN_A_PASSWORD` |\n' > "$E1/projects/PLAIN/PROJECT.md"
for m in "" "--status" "--import" "--capture"; do
  OUT7="$(PATH="$MOCKBIN:$PATH" bash "$RESOLVER" "$E1" $m 2>&1)"
  check_absent "env-file project silent (${m:-resolve})" "$OUT7" "keychain"
done

echo
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) failed"
fi
exit "$fails"

#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit

#
# qa-secrets-fixtures.sh — fixture test for .claude/scripts/qa-secrets.mjs
# (Level-1/Level-2 credential entry, tdd.md 0.11.0 §1/§3/§4).
#
# Why: this script is the sanctioned path that moves secret VALUES from the
# file into processes. Its failure modes are silent and security-relevant:
# redaction missing a value (or a base64/url-encoded form of it) in child
# output, a value split across chunk boundaries slipping through, the
# ephemeral mcp mask file leaking past the child's lifetime, a *_BASE_URL
# slipping into the credential path. All fixtures use throwaway values in a
# temp QA home — no real credential is ever touched.
#
# Usage:  bash .claude/hooks/tests/qa-secrets-fixtures.sh
# Exit:   0 = all fixtures pass, otherwise the number of failures.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QS="$HERE/../../scripts/qa-secrets.mjs"
[ -f "$QS" ] || { echo "qa-secrets.mjs not found at $QS" >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "node not found" >&2; exit 1; }

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

check_exit() {
  local name="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    printf 'ok    %s\n' "$name"
  else
    printf 'FAIL  %s\n      want exit=%s got=%s\n' "$name" "$want" "$got"
    fails=$((fails + 1))
  fi
}

# --- temp QA home with throwaway credentials -------------------------------
QA="$WORK/qa-home"
mkdir -p "$QA"
touch "$QA/.qa-home"
PW_VALUE='Sup3rSecret!'
USER_VALUE='stage-bot'
printf 'STAGE_USER=%s\nSTAGE_PASSWORD=%s\nSTAGE_BASE_URL=https://stage.example\nSHORT=tiny\n' \
  "$USER_VALUE" "$PW_VALUE" > "$QA/.env"

# run_qs <args…> — runs qa-secrets from inside $QA, captures out/err/exit
run_qs() {
  ( cd "$QA" && TMPDIR="$QA/tmp" node "$QS" "$@" ) >"$WORK/out.txt" 2>"$WORK/err.txt"
  EXIT=$?
  OUT="$(cat "$WORK/out.txt")"
  ERR="$(cat "$WORK/err.txt")"
}

mkdir -p "$QA/tmp"

echo "== run mode: redaction =="

run_qs run STAGE_PASSWORD -- node -e 'console.log("v:" + process.env.STAGE_PASSWORD)'
check_exit    "run: child exit 0"                0 "$EXIT"
check_absent  "run: value redacted on stdout"    "$OUT" "$PW_VALUE"
check_contains "run: redaction marker"           "$OUT" "[redacted:STAGE_PASSWORD]"

run_qs run STAGE_PASSWORD -- node -e 'console.error("e:" + process.env.STAGE_PASSWORD)'
check_absent  "run: value redacted on stderr"    "$ERR" "$PW_VALUE"

run_qs run STAGE_PASSWORD -- node -e 'console.log(Buffer.from(process.env.STAGE_PASSWORD).toString("base64"))'
check_absent  "run: base64 form redacted"        "$OUT" "$(printf '%s' "$PW_VALUE" | base64)"

run_qs run STAGE_USER STAGE_PASSWORD -- node -e 'console.log(Buffer.from(process.env.STAGE_USER + ":" + process.env.STAGE_PASSWORD).toString("base64"))'
check_absent  "run: pairwise base64 redacted"    "$OUT" "$(printf '%s:%s' "$USER_VALUE" "$PW_VALUE" | base64)"

run_qs run STAGE_PASSWORD -- node -e 'console.log(encodeURIComponent(process.env.STAGE_PASSWORD))'
check_absent  "run: url-encoded form redacted"   "$OUT" "Sup3rSecret%21"

# Value split across two writes with a pause — the chunk-boundary guard must hold.
run_qs run STAGE_PASSWORD -- node -e 'const v=process.env.STAGE_PASSWORD;process.stdout.write(v.slice(0,5));setTimeout(()=>process.stdout.write(v.slice(5)+"\n"),150)'
check_absent  "run: chunk-split value redacted"  "$OUT" "$PW_VALUE"

run_qs run STAGE_PASSWORD -- node -e 'process.exit(7)'
check_exit    "run: child exit code preserved"   7 "$EXIT"

echo
echo "== run mode: failures never carry values =="

run_qs run MISSING_KEY -- node -e 'process.exit(0)'
check_exit    "missing key → exit 3"             3 "$EXIT"
check_contains "missing key names the KEY"       "$ERR" "MISSING_KEY"
check_absent  "missing key message, no values"   "$ERR" "$PW_VALUE"

( cd "$WORK" && node "$QS" run STAGE_PASSWORD -- node -e 'process.exit(0)' ) >"$WORK/o2" 2>"$WORK/e2"
check_exit    "no secrets file → exit 3"         3 "$?"

run_qs run stage_password -- node -e 'process.exit(0)'
check_exit    "lowercase key → usage exit 2"     2 "$EXIT"
check_absent  "invalid key not echoed"           "$ERR" "stage_password"

run_qs run STAGE_BASE_URL -- node -e 'process.exit(0)'
check_exit    "*_BASE_URL rejected"              2 "$EXIT"
check_contains "BASE_URL rejection explains"     "$ERR" "environment configuration"

run_qs run SHORT -- node -e 'console.log("short:" + process.env.SHORT)'
check_contains "short value → stderr warning"    "$ERR" "shorter than"
check_absent  "short warning has no value"       "$ERR" "tiny"

echo
echo "== secrets_file config + walk-up =="

printf 'CUSTOM_PASSWORD=%s\n' "$PW_VALUE" > "$QA/.env.custom"
printf '{"secrets_file": ".env.custom"}\n' > "$QA/.qa-guard.json"
run_qs run CUSTOM_PASSWORD -- node -e 'console.log("ok:" + (process.env.CUSTOM_PASSWORD ? "set" : "unset"))'
check_contains "secrets_file from .qa-guard.json" "$OUT" "ok:set"
check_absent  "custom file value redacted"       "$OUT" "$PW_VALUE"

printf 'not json at all' > "$QA/.qa-guard.json"
run_qs run STAGE_PASSWORD -- node -e 'console.log("fallback:" + (process.env.STAGE_PASSWORD ? "set" : "unset"))'
check_contains "invalid config → .env default"   "$OUT" "fallback:set"
rm "$QA/.qa-guard.json"

echo
echo "== --file / QA_SECRETS_FILE: per-environment files (0.11.0) =="

# Their real shape: one env file per environment, in a spaced subfolder.
mkdir -p "$QA/test automation/shared/config"
printf 'REVIEW_PASSWORD=Rev1ewSecret!\n' > "$QA/test automation/shared/config/.env.review"
printf 'SNT_PASSWORD=SntSecret!99\n' > "$QA/test automation/shared/config/.env.snt"
printf '{"secrets_file": ".env.custom"}\n' > "$QA/.qa-guard.json"   # config says: custom

run_qs run --file "test automation/shared/config/.env.review" REVIEW_PASSWORD -- \
  node -e 'console.log("v:" + process.env.REVIEW_PASSWORD)'
check_exit    "--file: child exit 0"               0 "$EXIT"
check_contains "--file: redaction marker"          "$OUT" "[redacted:REVIEW_PASSWORD]"
check_absent  "--file: value redacted"             "$OUT" "Rev1ewSecret!"

OUT="$(cd "$QA" && TMPDIR="$QA/tmp" QA_SECRETS_FILE="test automation/shared/config/.env.snt" \
  node "$QS" run SNT_PASSWORD -- node -e 'console.log("env:" + process.env.SNT_PASSWORD)' 2>/dev/null)"
check_contains "QA_SECRETS_FILE beats config"      "$OUT" "env:[redacted:SNT_PASSWORD]"

# flag beats env: env points at .env.snt (no REVIEW_PASSWORD), flag at .env.review
OUT="$(cd "$QA" && TMPDIR="$QA/tmp" QA_SECRETS_FILE="test automation/shared/config/.env.snt" \
  node "$QS" run --file "test automation/shared/config/.env.review" REVIEW_PASSWORD -- \
  node -e 'console.log("flag:" + process.env.REVIEW_PASSWORD)' 2>/dev/null)"
check_contains "--file beats QA_SECRETS_FILE"      "$OUT" "flag:[redacted:REVIEW_PASSWORD]"

run_qs run --file "test automation/shared/config/.env.review" SNT_PASSWORD -- node -e 'process.exit(0)'
check_exit    "--file: key missing there → exit 3" 3 "$EXIT"
check_absent  "missing key, no values in message"  "$ERR" "SntSecret!99"

run_qs run --file -- node -e 'process.exit(0)'
check_exit    "--file without path → usage exit 2" 2 "$EXIT"

run_qs run --file "/nonexistent/.env.nope" STAGE_PASSWORD -- node -e 'process.exit(0)'
check_exit    "--file: unreadable → exit 3"        3 "$EXIT"
rm "$QA/.qa-guard.json"

mkdir -p "$QA/sub/deep"
OUT="$(cd "$QA/sub/deep" && node "$QS" run STAGE_PASSWORD -- node -e 'console.log("walkup:" + (process.env.STAGE_PASSWORD ? "set" : "unset"))' 2>/dev/null)"
check_contains "walk-up from subfolder finds QA home" "$OUT" "walkup:set"

echo
echo "== mcp mode: ephemeral mask file =="

cat > "$QA/fake-server.mjs" <<'EOF'
import fs from 'node:fs';
const a = process.argv.slice(2);
const i = a.indexOf('--secrets');
const c = fs.readFileSync(a[i + 1], 'utf8');
console.log('FILE:' + a[i + 1]);
console.log('HAS_PW:' + c.includes('STAGE_PASSWORD'));
console.log('HAS_USER:' + c.includes('STAGE_USER'));
console.log('QUOTED:' + c.includes("STAGE_PASSWORD='"));
EOF

run_qs mcp STAGE_PASSWORD -- node "$QA/fake-server.mjs" --config consumer.json
check_exit    "mcp: child exit 0"                0 "$EXIT"
check_contains "mcp: --secrets appended"         "$OUT" "qa-mcp-"
check_contains "mcp: mask file has selected key" "$OUT" "HAS_PW:true"
check_contains "mcp: mask file omits others"     "$OUT" "HAS_USER:false"
check_contains "mcp: values single-quoted"       "$OUT" "QUOTED:true"
check_absent  "mcp: value never in wrapper out"  "$OUT" "$PW_VALUE"
COUNT="$(find "$QA/tmp" -maxdepth 1 -name 'qa-mcp-*' | wc -l | tr -d ' ')"
check_exit    "mcp: temp dir cleaned after exit" 0 "$COUNT"

run_qs mcp STAGE_PASSWORD -- node "$QA/fake-server.mjs" --secrets /other/path
check_exit    "mcp: pre-set --secrets rejected"  2 "$EXIT"
check_contains "rejection explains"              "$ERR" "managed by qa-secrets"

run_qs mcp MISSING_KEY -- node "$QA/fake-server.mjs"
check_exit    "mcp: missing key → exit 3"        3 "$EXIT"

echo
echo "== placeholder values: warn, never block (0.11.0) =="

printf 'DB_PASSWORD=secret\nAPP_USER=admin\n' > "$QA/.env.placeholder"
# "secret" (6 chars) IS redaction-eligible in run mode → placeholder note.
run_qs run --file .env.placeholder DB_PASSWORD -- node -e 'console.log("ok:" + (process.env.DB_PASSWORD ? "set" : "unset"))'
check_exit    "placeholder: run continues"         0 "$EXIT"
check_contains "placeholder note (run)"            "$ERR" "looks like a placeholder"
# "admin" (5 chars) is below the redaction floor in run mode → only the
# short-value note, no placeholder note.
run_qs run --file .env.placeholder APP_USER -- node -e 'process.exit(0)'
check_contains "short placeholder: short note"     "$ERR" "shorter than"
check_absent  "short placeholder: no extra note"   "$ERR" "placeholder"
# …but in mcp mode the server masks every value → the placeholder note fires.
run_qs mcp --file .env.placeholder APP_USER -- node "$QA/fake-server.mjs"
check_contains "placeholder note (mcp)"            "$ERR" "looks like a placeholder"
# a real password → no placeholder note.
run_qs run STAGE_PASSWORD -- node -e 'process.exit(0)'
check_absent  "real value: no placeholder note"    "$ERR" "placeholder"

echo
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) failed"
fi
exit "$fails"

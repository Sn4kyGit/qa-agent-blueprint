#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit

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

OUT=""
assert_file()    { [ -f "$2" ] && pass "$1" || fail "$1" "missing file: $2"; }
assert_no_file() { [ ! -e "$2" ] && pass "$1" || fail "$1" "should not exist: $2"; }
assert_dir()     { [ -d "$2" ] && pass "$1" || fail "$1" "missing dir: $2"; }
assert_no_dir()  { [ ! -e "$2" ] && pass "$1" || fail "$1" "should not exist: $2"; }
assert_grep()    { grep -qF -- "$3" "$2" 2>/dev/null && pass "$1" || fail "$1" "not found in $2: $3"; }
assert_no_grep() { grep -qF -- "$3" "$2" 2>/dev/null && fail "$1" "should not appear in $2: $3" || pass "$1"; }
assert_out_has()   { printf '%s' "$OUT" | grep -qF -- "$2" && pass "$1" || fail "$1" "output lacks: $2"; }
assert_out_lacks() { printf '%s' "$OUT" | grep -qF -- "$2" && fail "$1" "output contains: $2" || pass "$1"; }

check_all_skills() {
  local missing=0 n s
  for s in "$REPO/.claude/skills"/*/; do
    [ -d "$s" ] || continue
    n="$(basename "$s")"
    [ -d "$2/.claude/skills/$n" ] || { missing=$((missing + 1)); echo "      missing: $n"; }
  done
  [ "$missing" -eq 0 ] && pass "$1" || fail "$1" "$missing skill(s) missing"
}

count_baks() { ls "$1"/.qa-skill-profile.json.bak-* 2>/dev/null | wc -l | tr -d ' '; }

echo "== full copies every blueprint skill =="
FT="$WORK/full"
mkdir -p "$FT/.claude/skills/my-own-skill"
printf '%s\n' '---' 'name: my-own-skill' '---' 'Fremd.' > "$FT/.claude/skills/my-own-skill/SKILL.md"
OUT="$("$INSTALL" --mode integrate --target "$FT" --skill-profile full --yes 2>&1)"
[ $? -eq 0 ] && pass "full install exits 0" || fail "full install exits 0" "$(printf '%s' "$OUT" | tail -3)"
check_all_skills "full leaves no skill out" "$FT"
assert_file "profile file written" "$FT/.qa-skill-profile.json"
assert_grep "full recorded in profile file" "$FT/.qa-skill-profile.json" '"profile": "full"'
assert_grep "foreign skill untouched under full" "$FT/.claude/skills/my-own-skill/SKILL.md" "Fremd."

echo
echo "== standard omits exactly its baseline excludes =="
ST="$WORK/standard"
mkdir -p "$ST"
OUT="$("$INSTALL" --mode integrate --target "$ST" --skill-profile standard --yes 2>&1)"
[ $? -eq 0 ] && pass "standard install exits 0" || fail "standard install exits 0" "$(printf '%s' "$OUT" | tail -3)"
for n in agentswitch model-setup whats-new re-board demo scaffold-suite; do
  assert_no_dir "standard omits $n" "$ST/.claude/skills/$n"
done
assert_dir "standard keeps test-ticket" "$ST/.claude/skills/test-ticket"
assert_dir "standard keeps specialist api-testing" "$ST/.claude/skills/api-testing"
assert_dir "standard keeps qa-report" "$ST/.claude/skills/qa-report"
assert_dir "standard keeps qa-help" "$ST/.claude/skills/qa-help"
assert_grep "standard recorded in profile file" "$ST/.qa-skill-profile.json" '"profile": "standard"'
assert_out_has "standard omissions are reported" "demo omitted (profile: standard)"

echo
echo "== minimal omits baseline plus its extra excludes =="
MT="$WORK/minimal"
mkdir -p "$MT"
OUT="$("$INSTALL" --mode integrate --target "$MT" --skill-profile minimal --yes 2>&1)"
[ $? -eq 0 ] && pass "minimal install exits 0" || fail "minimal install exits 0" "$(printf '%s' "$OUT" | tail -3)"
for n in agentswitch model-setup whats-new re-board demo scaffold-suite recon deploy-to-stage onboard-product onboard-project exploratory-testing; do
  assert_no_dir "minimal omits $n" "$MT/.claude/skills/$n"
done
assert_dir "minimal keeps test-ticket" "$MT/.claude/skills/test-ticket"
assert_dir "minimal keeps failure-analysis" "$MT/.claude/skills/failure-analysis"
assert_file "minimal still ships THIRD_PARTY_NOTICES.md" "$MT/.claude/skills/THIRD_PARTY_NOTICES.md"
assert_grep "minimal recorded in profile file" "$MT/.qa-skill-profile.json" '"profile": "minimal"'

echo
echo "== custom honors the persisted allowlist and adds the closure =="
CT="$WORK/custom"
mkdir -p "$CT"
printf '%s\n' '{' '  "profile": "custom",' '  "allowlist": ["test-ticket", "api-testing"]' '}' > "$CT/.qa-skill-profile.json"
OUT="$("$INSTALL" --mode integrate --target "$CT" --yes 2>&1)"
[ $? -eq 0 ] && pass "custom install exits 0" || fail "custom install exits 0" "$(printf '%s' "$OUT" | tail -3)"
assert_dir "allowlisted test-ticket copied" "$CT/.claude/skills/test-ticket"
assert_dir "allowlisted api-testing copied" "$CT/.claude/skills/api-testing"
assert_dir "closure added failure-analysis" "$CT/.claude/skills/failure-analysis"
assert_dir "closure added report-to-jira" "$CT/.claude/skills/report-to-jira"
assert_dir "closure added retro-learn" "$CT/.claude/skills/retro-learn"
assert_dir "closure added qa-report" "$CT/.claude/skills/qa-report"
assert_dir "closure added qa-help" "$CT/.claude/skills/qa-help"
assert_dir "closure added webdriverio-testing (framework unknown)" "$CT/.claude/skills/webdriverio-testing"
assert_dir "closure added specialist security-testing" "$CT/.claude/skills/security-testing"
assert_no_dir "non-allowlisted demo omitted" "$CT/.claude/skills/demo"
assert_no_dir "non-allowlisted whats-new omitted" "$CT/.claude/skills/whats-new"
assert_no_dir "non-allowlisted recon omitted" "$CT/.claude/skills/recon"
assert_no_dir "non-allowlisted onboard-project omitted" "$CT/.claude/skills/onboard-project"
assert_no_dir "non-allowlisted deploy-to-stage omitted" "$CT/.claude/skills/deploy-to-stage"
assert_out_has "closure additions are reported" "dependency closure added"
assert_out_has "non-allowlisted omissions are reported" "demo omitted (profile: custom)"
assert_no_grep "profile file untouched without flags" "$CT/.qa-skill-profile.json" "updated_at"
[ "$(count_baks "$CT")" = "0" ] && pass "no backup written without flags" || fail "no backup written without flags" "found $(count_baks "$CT") backup(s)"

echo
echo "== dependency closure overrides excludes =="
E1="$WORK/closure-exclude"
mkdir -p "$E1"
OUT="$("$INSTALL" --mode integrate --target "$E1" --skill-profile standard --skills-exclude "failure-analysis,qa-report,qa-help" --yes 2>&1)"
[ $? -eq 0 ] && pass "closure run exits 0" || fail "closure run exits 0" "$(printf '%s' "$OUT" | tail -3)"
assert_dir "excluded failure-analysis re-added by closure" "$E1/.claude/skills/failure-analysis"
assert_dir "excluded qa-report re-added (always)" "$E1/.claude/skills/qa-report"
assert_dir "excluded qa-help re-added (never filtered)" "$E1/.claude/skills/qa-help"
assert_no_dir "standard baseline demo stays out" "$E1/.claude/skills/demo"
assert_out_has "closure override is reported" "dependency closure added"

E2="$WORK/closure-playwright"
mkdir -p "$E2"
printf '%s\n' '{' '  "profile": "custom",' '  "allowlist": ["test-ticket"],' '  "framework": "playwright"' '}' > "$E2/.qa-skill-profile.json"
OUT="$("$INSTALL" --mode integrate --target "$E2" --yes 2>&1)"
assert_dir "chain still closed without webdriverio" "$E2/.claude/skills/failure-analysis"
assert_no_dir "webdriverio-testing skipped for framework playwright" "$E2/.claude/skills/webdriverio-testing"

E3="$WORK/closure-matrix"
mkdir -p "$E3"
printf '%s\n' '{' '  "profile": "custom",' '  "allowlist": ["test-ticket"],' '  "matrix_active": ["api-testing"]' '}' > "$E3/.qa-skill-profile.json"
OUT="$("$INSTALL" --mode integrate --target "$E3" --yes 2>&1)"
assert_dir "matrix-active specialist api-testing forced" "$E3/.claude/skills/api-testing"
assert_no_dir "inactive specialist security-testing not forced" "$E3/.claude/skills/security-testing"

echo
echo "== reinstall keeps deactivated and foreign skills untouched =="
RT="$WORK/reinstall"
mkdir -p "$RT/.claude/skills/demo" "$RT/.claude/skills/my-own-skill"
printf '%s\n' 'ALT-DEMO' > "$RT/.claude/skills/demo/SKILL.md"
printf '%s\n' 'Fremd.' > "$RT/.claude/skills/my-own-skill/SKILL.md"
OUT="$("$INSTALL" --mode integrate --target "$RT" --skill-profile standard --yes 2>&1)"
[ $? -eq 0 ] && pass "reinstall target install exits 0" || fail "reinstall target install exits 0" "$(printf '%s' "$OUT" | tail -3)"
assert_grep "pre-existing deactivated folder untouched" "$RT/.claude/skills/demo/SKILL.md" "ALT-DEMO"
assert_out_has "deactivation reported" "demo deactivated by profile"
assert_grep "foreign skill untouched" "$RT/.claude/skills/my-own-skill/SKILL.md" "Fremd."
OUT="$("$INSTALL" --mode integrate --target "$RT" --skill-profile standard --yes 2>&1)"
assert_grep "second install leaves deactivated folder alone" "$RT/.claude/skills/demo/SKILL.md" "ALT-DEMO"
assert_out_lacks "second install does not re-copy demo" "skills — .claude/skills/demo/"
assert_grep "foreign skill untouched after reinstall" "$RT/.claude/skills/my-own-skill/SKILL.md" "Fremd."
OUT="$("$INSTALL" --mode integrate --target "$RT" --skill-profile full --yes 2>&1)"
assert_grep "collision protection still keeps yours" "$RT/.claude/skills/demo/SKILL.md" "ALT-DEMO"
assert_out_has "collision is reported" "a different skill with this name already exists"
assert_grep "foreign skill untouched after full run" "$RT/.claude/skills/my-own-skill/SKILL.md" "Fremd."

echo
echo "== profile file backup and idempotency =="
BT="$WORK/backup"
mkdir -p "$BT"
OUT="$("$INSTALL" --mode integrate --target "$BT" --skill-profile standard --yes 2>&1)"
assert_file "profile file created" "$BT/.qa-skill-profile.json"
[ "$(count_baks "$BT")" = "0" ] && pass "fresh profile file needs no backup" || fail "fresh profile file needs no backup" "found $(count_baks "$BT") backup(s)"
OUT="$("$INSTALL" --mode integrate --target "$BT" --skill-profile minimal --yes 2>&1)"
[ "$(count_baks "$BT")" = "1" ] && pass "changed profile file is backed up" || fail "changed profile file is backed up" "found $(count_baks "$BT") backup(s)"
assert_grep "new profile recorded" "$BT/.qa-skill-profile.json" '"profile": "minimal"'
BAK="$(ls "$BT"/.qa-skill-profile.json.bak-* 2>/dev/null | head -1)"
assert_grep "backup holds the previous profile" "$BAK" '"profile": "standard"'
OUT="$("$INSTALL" --mode integrate --target "$BT" --skill-profile minimal --yes 2>&1)"
[ "$(count_baks "$BT")" = "1" ] && pass "identical rerun writes no new backup" || fail "identical rerun writes no new backup" "found $(count_baks "$BT") backup(s)"
assert_out_has "unchanged profile file reported" ".qa-skill-profile.json unchanged"
OUT="$("$INSTALL" --mode integrate --target "$BT" --yes 2>&1)"
[ "$(count_baks "$BT")" = "1" ] && pass "flagless rerun does not touch the file" || fail "flagless rerun does not touch the file" "found $(count_baks "$BT") backup(s)"
assert_out_has "flagless rerun applies persisted profile" "re-board omitted (profile: minimal)"

echo
echo "== --yes without flags changes nothing =="
NT="$WORK/no-flag"
mkdir -p "$NT"
OUT="$("$INSTALL" --mode integrate --target "$NT" --yes 2>&1)"
[ $? -eq 0 ] && pass "plain install exits 0" || fail "plain install exits 0" "$(printf '%s' "$OUT" | tail -3)"
check_all_skills "plain install copies every skill" "$NT"
assert_no_file "no profile file invented" "$NT/.qa-skill-profile.json"

echo
echo "== skill-profile flags outside integrate are skipped with a warning =="
PT="$WORK/plugin-flag"
mkdir -p "$PT"
OUT="$("$INSTALL" --mode plugin --target "$PT" --skill-profile minimal --skills-exclude "demo" --yes 2>&1)"
[ $? -eq 0 ] && pass "plugin mode with flags exits 0" || fail "plugin mode with flags exits 0" "$(printf '%s' "$OUT" | tail -3)"
assert_out_has "integrate-only warning shown" "integrate mode only"
assert_no_file "no profile file in plugin mode" "$PT/.qa-skill-profile.json"
assert_no_dir "no skills copied in plugin mode" "$PT/.claude/skills"

echo
echo "== invalid profile values are rejected =="
IT="$WORK/invalid"
mkdir -p "$IT"
OUT="$("$INSTALL" --mode integrate --target "$IT" --skill-profile bogus --yes 2>&1)"
[ $? -ne 0 ] && pass "bogus profile rejected" || fail "bogus profile rejected" "installer accepted --skill-profile bogus"
assert_out_has "error names the valid profiles" "expected full|standard|minimal|custom"

echo
echo "== CLI custom freezes the resolved selection into the allowlist =="
KT="$WORK/cli-custom"
mkdir -p "$KT"
OUT="$("$INSTALL" --mode integrate --target "$KT" --skill-profile custom --skills-exclude "demo,whats-new" --yes 2>&1)"
[ $? -eq 0 ] && pass "CLI custom exits 0" || fail "CLI custom exits 0" "$(printf '%s' "$OUT" | tail -3)"
assert_no_dir "CLI-excluded demo omitted" "$KT/.claude/skills/demo"
assert_no_dir "CLI-excluded whats-new omitted" "$KT/.claude/skills/whats-new"
assert_dir "CLI custom keeps test-ticket" "$KT/.claude/skills/test-ticket"
assert_grep "custom recorded in profile file" "$KT/.qa-skill-profile.json" '"profile": "custom"'
assert_grep "resolved allowlist persisted" "$KT/.qa-skill-profile.json" '"allowlist"'
assert_grep "allowlist contains test-ticket" "$KT/.qa-skill-profile.json" '"test-ticket"'
OUT="$("$INSTALL" --mode integrate --target "$KT" --yes 2>&1)"
assert_no_dir "frozen allowlist still omits demo on rerun" "$KT/.claude/skills/demo"
assert_dir "frozen allowlist still keeps test-ticket on rerun" "$KT/.claude/skills/test-ticket"

echo
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) failed"
fi
exit "$fails"

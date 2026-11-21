#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
TEMPLATES="$ROOT/.claude/skills/scaffold-suite/templates"
SCANNER="$ROOT/.claude/scripts/qa-test-code-scan.mjs"
WORK="$(mktemp -d)"
trap 'rm -r "$WORK" 2>/dev/null' EXIT
fails=0

pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
assert_file() { [ -f "$2" ] && pass "$1" || fail "$1 missing $2"; }
assert_contains() { grep -qF -- "$3" "$2" && pass "$1" || fail "$1 missing text in $2"; }
assert_not_contains() { grep -qF -- "$3" "$2" && fail "$1 unexpected text in $2" || pass "$1"; }

DEFAULT="$WORK/default"
QUALITY="$WORK/quality"
mkdir -p "$DEFAULT/tests" "$DEFAULT/quality" "$QUALITY/tests" "$QUALITY/quality"
cp "$TEMPLATES/package.json" "$TEMPLATES/playwright.config.ts" "$DEFAULT/"
cp "$TEMPLATES/smoke.spec.ts" "$DEFAULT/tests/"
cp -R "$TEMPLATES/tests/." "$DEFAULT/tests/"
cp "$TEMPLATES/quality/scan.mjs" "$DEFAULT/quality/"
cp "$TEMPLATES/package.json" "$TEMPLATES/playwright.config.ts" "$QUALITY/"
cp "$TEMPLATES/quality/scan.mjs" "$QUALITY/quality/"
cp "$TEMPLATES/quality/.qa-test-quality.json" "$TEMPLATES/quality/.env.example" "$QUALITY/"
cp -R "$TEMPLATES/tests/." "$QUALITY/tests/"
cp -R "$TEMPLATES/quality/tests/." "$QUALITY/tests/"
cp "$TEMPLATES/quality/smoke.spec.ts" "$QUALITY/tests/smoke.spec.ts"
cp "$TEMPLATES/quality/seed.spec.ts" "$QUALITY/tests/seed.spec.ts"

node - "$DEFAULT" "$QUALITY" <<'NODE'
const fs = require('fs');
for (const dir of process.argv.slice(2)) {
  for (const file of ['package.json', 'playwright.config.ts']) {
    const path = `${dir}/${file}`;
    const text = fs.readFileSync(path, 'utf8').replaceAll('<KEY>', 'SHOP').replaceAll('<key>', 'shop').replaceAll('[/<PRODUCT>]', '');
    fs.writeFileSync(path, text);
  }
}
for (const file of [`${process.argv[2]}/tests/smoke.spec.ts`, `${process.argv[3]}/tests/smoke.spec.ts`]) {
  const text = fs.readFileSync(file, 'utf8').replaceAll('<CAT>', 'CHK').replaceAll('<ID>', '2');
  fs.writeFileSync(file, text);
}
NODE

assert_file "default observation fixture" "$DEFAULT/tests/fixtures/observation.ts"
assert_file "default scanner wrapper" "$DEFAULT/quality/scan.mjs"
assert_file "quality composed test fixture" "$QUALITY/tests/fixtures/test.ts"
assert_file "quality lazy API fixture" "$QUALITY/tests/fixtures/api.ts"
assert_file "quality lazy auth fixture" "$QUALITY/tests/fixtures/auth.ts"
assert_file "quality lazy data fixture" "$QUALITY/tests/fixtures/data.ts"
assert_file "quality minimal POM" "$QUALITY/tests/pages/EntryPage.ts"
assert_file "quality env support" "$QUALITY/tests/support/env.ts"
assert_file "quality seed spec" "$QUALITY/tests/seed.spec.ts"
assert_file "quality strict config" "$QUALITY/.qa-test-quality.json"
[ ! -s "$QUALITY/.env.example" ] && pass "quality env example is blank" || fail "quality env example is blank"
[ ! -e "$DEFAULT/.qa-test-quality.json" ] && pass "default has no strict config" || fail "default has no strict config"
assert_contains "package quality script" "$DEFAULT/package.json" '"test:quality"'
assert_contains "package staged quality script" "$DEFAULT/package.json" '"test:quality:staged"'
assert_contains "evidence directory preserved" "$QUALITY/playwright.config.ts" 'QA_EVIDENCE_DIR'
assert_contains "observation fixture preserved" "$QUALITY/tests/fixtures/observation.ts" 'observations'
assert_contains "auth uses existing storage state" "$QUALITY/tests/fixtures/auth.ts" 'STAGE_STORAGE_STATE'
assert_not_contains "no dotenv in fixtures" "$QUALITY/tests/fixtures/api.ts" 'dotenv'
assert_not_contains "no invented auth keys" "$QUALITY/tests/fixtures/auth.ts" 'PASSWORD'
assert_contains "seed is explicitly opt-in" "$QUALITY/tests/seed.spec.ts" "QA_SEED !== '1'"

(
  cd "$DEFAULT" && QA_TEST_CODE_SCANNER="$SCANNER" npm run test:quality -- --format json > "$WORK/default.json"
)
[ $? -eq 0 ] && pass "default quality convenience exits 0" || fail "default quality convenience exits 0"
(
  cd "$QUALITY" && QA_TEST_CODE_SCANNER="$SCANNER" npm run test:quality -- --format json > "$WORK/quality.json"
)
[ $? -eq 0 ] && pass "substituted quality pack passes strict scan" || fail "substituted quality pack passes strict scan"
node - "$WORK/default.json" "$WORK/quality.json" <<'NODE' || fails=$((fails + 1))
const fs = require('fs');
for (const path of process.argv.slice(2)) {
  const text = fs.readFileSync(path, 'utf8');
  const start = text.indexOf('{');
  const report = JSON.parse(text.slice(start));
  if (report.version !== 1 || report.findings.some((item) => item.severity === 'error')) process.exit(1);
}
const quality = JSON.parse(fs.readFileSync(process.argv[3], 'utf8').slice(fs.readFileSync(process.argv[3], 'utf8').indexOf('{')));
if (quality.config.strict !== true || quality.config.writeGate !== true) process.exit(1);
console.log('ok    scanner reports preserve strict quality config');
NODE

printf '\n'
if [ "$fails" -eq 0 ]; then echo 'all fixtures passed'; else echo "$fails fixture(s) failed"; fi
exit "$fails"

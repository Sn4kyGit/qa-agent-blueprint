#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
SCANNER="$ROOT/.claude/scripts/qa-test-code-scan.mjs"
CORPUS="$HERE/fixtures/test-code"
WORK="$(mktemp -d)"
trap 'rm -r "$WORK" 2>/dev/null' EXIT
fails=0

check() {
  local name="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then printf 'ok    %s\n' "$name"; else printf 'FAIL  %s want=%s got=%s\n' "$name" "$want" "$got"; fails=$((fails + 1)); fi
}

node "$SCANNER" "$CORPUS/violations.spec.ts" --format json > "$WORK/violations.json"
check "default warnings exit 0" 0 "$?"
node - "$WORK/violations.json" <<'NODE' || fails=$((fails + 1))
const fs = require('fs');
const report = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const ids = new Set(report.findings.map((item) => item.ruleId));
const expected = ['no-dotenv', 'fixed-sleep', 'hardcoded-base-url', 'xpath-selector', 'brittle-selector', 'observation-fixture-import', 'missing-ac-title', 'missing-tc-title', 'disabled-test', 'retry-override'];
if (report.version !== 1 || expected.some((id) => !ids.has(id))) process.exit(1);
const disabled = report.findings.find((item) => item.ruleId === 'disabled-test');
if (!disabled?.message.includes('reason and ticket')) process.exit(1);
if (JSON.stringify(report).includes('stage.example.test')) process.exit(1);
console.log('ok    versioned complete findings without excerpts');
NODE

node "$SCANNER" "$CORPUS/clean.spec.ts" --strict --format json > "$WORK/clean.json"
check "strict clean spec exits 0" 0 "$?"
node "$SCANNER" "$CORPUS/violations.spec.ts" --strict --format json > "$WORK/strict.json"
check "strict warning exits 1" 1 "$?"
mkdir -p "$WORK/config-strict"
printf '{"version":1,"strict":true,"writeGate":false}\n' > "$WORK/config-strict/.qa-test-quality.json"
printf 'await page.waitForTimeout(delay);\n' > "$WORK/config-strict/uncertain.ts"
node "$SCANNER" "$WORK/config-strict/uncertain.ts" --format json > "$WORK/config-strict.json"
check "config strict fails warning-only scan" 1 "$?"
node "$SCANNER" "$CORPUS/suppressed.spec.ts" --strict --format json > "$WORK/suppressed.json"
check "reasoned suppressions exit 0" 0 "$?"
node - "$WORK/suppressed.json" <<'NODE' || fails=$((fails + 1))
const report = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
if (report.findings.length !== 0 || report.suppressed.length !== 3) process.exit(1);
console.log('ok    three suppressions separated from findings');
NODE
node "$SCANNER" "$CORPUS/suppressed.spec.ts" --no-suppressions --format json > "$WORK/no-suppressions.json"
check "no-suppressions remains warning exit 0" 0 "$?"
node - "$WORK/no-suppressions.json" <<'NODE' || fails=$((fails + 1))
const report = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
if (report.findings.length !== 3 || report.suppressed.length !== 0) process.exit(1);
console.log('ok    no-suppressions restores all findings');
NODE

printf 'await page.waitForTimeout(10);' | node "$SCANNER" --stdin 'fragment name.ts' --fragment --strict --format json > "$WORK/stdin.json"
check "stdin fragment strict violation exits 1" 1 "$?"
node - "$WORK/stdin.json" <<'NODE' || fails=$((fails + 1))
const report = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
if (report.findings.length !== 1 || report.findings[0].file !== 'fragment name.ts' || report.findings[0].ruleId !== 'fixed-sleep') process.exit(1);
console.log('ok    stdin path and fragment mode preserved');
NODE

node "$SCANNER" "$CORPUS/clean.wdio.spec.ts" --framework webdriverio --strict > /dev/null
check "WebdriverIO framework clean" 0 "$?"
node "$SCANNER" --framework mocha "$CORPUS/clean.spec.ts" > /dev/null 2>&1
check "invalid framework usage exit 2" 2 "$?"
node "$SCANNER" --format yaml "$CORPUS/clean.spec.ts" > /dev/null 2>&1
check "invalid format usage exit 2" 2 "$?"
ln -s "$SCANNER" "$WORK/linked-scan.mjs"
node "$WORK/linked-scan.mjs" "$CORPUS/violations.spec.ts" --strict > /dev/null
check "symlinked scanner still executes CLI" 1 "$?"

STAGED="$WORK/staged repo"
mkdir -p "$STAGED"
git -C "$STAGED" init -q
printf "import { test } from './fixtures/observation';\ntest('AC1 / TC-CHK-001: staged clean', () => {});\n" > "$STAGED/good.spec.ts"
printf "import { test } from './fixtures/observation';\ntest('AC1 / TC-CHK-002: odd', async ({ page }) => { await page.waitForTimeout(10); });\n" > "$STAGED/odd name.spec.ts"
printf "import { test } from './fixtures/observation';\ntest('AC1 / TC-CHK-003: dash', async ({ page }) => { await page.goto('https://stage.example.test'); });\n" > "$STAGED/-dash.spec.ts"
NEWLINE_FILE="$STAGED/line
break.spec.ts"
printf "import { test } from './fixtures/observation';\ntest('AC1 / TC-CHK-004: newline', async ({ page }) => { await page.locator('//button').click(); });\n" > "$NEWLINE_FILE"
git -C "$STAGED" add -- .
printf 'await page.waitForTimeout(999);' > "$STAGED/good.spec.ts"
(
  cd "$STAGED" && node "$SCANNER" --staged --strict --format json > "$WORK/staged.json"
)
check "staged findings strict exit 1" 1 "$?"
node - "$WORK/staged.json" <<'NODE' || fails=$((fails + 1))
const report = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
const files = new Set(report.findings.map((item) => item.file));
if (!files.has('odd name.spec.ts') || !files.has('-dash.spec.ts') || !files.has('line\nbreak.spec.ts')) process.exit(1);
if (files.has('good.spec.ts')) process.exit(1);
if (report.summary.files !== 4) process.exit(1);
console.log('ok    staged blobs, safe argv, NUL paths, working tree isolation');
NODE

printf '\n'
if [ "$fails" -eq 0 ]; then echo 'all fixtures passed'; else echo "$fails fixture(s) failed"; fi
exit "$fails"

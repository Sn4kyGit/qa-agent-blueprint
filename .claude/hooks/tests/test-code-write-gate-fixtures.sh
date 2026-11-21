#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
HOOK="$ROOT/.claude/hooks/pre-test-code-scan.sh"
WORK="$(mktemp -d)"
trap 'rm -r "$WORK" 2>/dev/null' EXIT
fails=0

check() {
  local name="$1" want="$2" json="$3" got
  printf '%s' "$json" | bash "$HOOK" > "$WORK/out" 2> "$WORK/err"
  got=$?
  if [ "$want" = "$got" ]; then printf 'ok    %s\n' "$name"; else printf 'FAIL  %s want=%s got=%s\n' "$name" "$want" "$got"; fails=$((fails + 1)); fi
}

OPEN="$WORK/open"
WARN="$WORK/warn"
STRICT="$WORK/strict"
mkdir -p "$OPEN/tests" "$WARN/tests" "$STRICT/tests"
printf '{"version":1,"writeGate":true}\n' > "$WARN/.qa-test-quality.json"
printf '{"version":1,"writeGate":true,"strict":true,"rules":{"fixed-sleep":"error","hardcoded-base-url":"error","no-dotenv":"error"}}\n' > "$STRICT/.qa-test-quality.json"
BAD="import { test } from './fixtures/observation'; test('AC1 / TC-CHK-001: bad', async ({ page }) => { await page.waitForTimeout(10); });"
GOOD="import { test } from './fixtures/observation'; test('AC1 / TC-CHK-001: good', async ({ page }) => { await page.getByRole('button').click(); });"
SUPPRESSED="import { test } from './fixtures/observation';
test('AC1 / TC-CHK-001: suppressed', async ({ page }) => {
  // qa-scan-disable-next-line fixed-sleep -- documented legacy timing in SHOP-1234.
  await page.waitForTimeout(10);
});"

check "no config allows write" 0 "$(node -e 'console.log(JSON.stringify({tool_name:"Write",tool_input:{file_path:process.argv[1],content:process.argv[2]},cwd:process.argv[3]}))' "$OPEN/tests/a.spec.ts" "$BAD" "$OPEN")"
check "warning gate reports but allows" 0 "$(node -e 'console.log(JSON.stringify({tool_name:"Write",tool_input:{file_path:process.argv[1],content:process.argv[2]},cwd:process.argv[3]}))' "$WARN/tests/a.spec.ts" "$BAD" "$WARN")"
check "strict error gate blocks write" 2 "$(node -e 'console.log(JSON.stringify({tool_name:"Write",tool_input:{file_path:process.argv[1],content:process.argv[2]},cwd:process.argv[3]}))' "$STRICT/tests/a.spec.ts" "$BAD" "$STRICT")"
check "clean write allowed" 0 "$(node -e 'console.log(JSON.stringify({tool_name:"Write",tool_input:{file_path:process.argv[1],content:process.argv[2]},cwd:process.argv[3]}))' "$STRICT/tests/a.spec.ts" "$GOOD" "$STRICT")"
check "reasoned suppression allowed" 0 "$(node -e 'console.log(JSON.stringify({tool_name:"Write",tool_input:{file_path:process.argv[1],content:process.argv[2]},cwd:process.argv[3]}))' "$STRICT/tests/a.spec.ts" "$SUPPRESSED" "$STRICT")"
check "Edit scans new_string fragment" 2 "$(node -e 'console.log(JSON.stringify({tool_name:"Edit",tool_input:{file_path:process.argv[1],new_string:"await page.waitForTimeout(10);"},cwd:process.argv[2]}))' "$STRICT/tests/a.spec.ts" "$STRICT")"
check "MultiEdit scans every new string" 2 "$(node -e 'console.log(JSON.stringify({tool_name:"MultiEdit",tool_input:{file_path:process.argv[1],edits:[{new_string:"await page.getByRole(\"button\").click();"},{new_string:"await page.goto(\"https://stage.example.test\");"}]},cwd:process.argv[2]}))' "$STRICT/tests/a.spec.ts" "$STRICT")"
check "NotebookEdit scans new_source" 2 "$(node -e 'console.log(JSON.stringify({tool_name:"NotebookEdit",tool_input:{notebook_path:process.argv[1],new_source:"await page.waitForTimeout(10);"},cwd:process.argv[2]}))' "$STRICT/tests/a.ipynb" "$STRICT")"
check "Bash writes are not parsed" 0 "$(node -e 'console.log(JSON.stringify({tool_name:"Bash",tool_input:{command:"printf bad > tests/a.spec.ts"},cwd:process.argv[1]}))' "$STRICT")"
check "non-source documents are not gated" 0 "$(node -e 'console.log(JSON.stringify({tool_name:"Write",tool_input:{file_path:process.argv[1],content:"await page.waitForTimeout(10);"},cwd:process.argv[2]}))' "$STRICT/README.md" "$STRICT")"
check "malformed gated write fails closed" 2 "$(node -e 'console.log(JSON.stringify({tool_name:"MultiEdit",tool_input:{file_path:process.argv[1]},cwd:process.argv[2]}))' "$STRICT/tests/a.spec.ts" "$STRICT")"
check "invalid hook JSON is ignored" 0 'not json'

mkdir -p "$STRICT/tests/nested"
printf '{"version":1,"writeGate":false,"strict":true}\n' > "$STRICT/tests/nested/.qa-test-quality.json"
check "nearest config disables inherited gate" 0 "$(node -e 'console.log(JSON.stringify({tool_name:"Edit",tool_input:{file_path:process.argv[1],new_string:"await page.waitForTimeout(10);"},cwd:process.argv[2]}))' "$STRICT/tests/nested/a.spec.ts" "$STRICT")"

INTEGRATED="$WORK/integrated"
mkdir -p "$INTEGRATED/.claude/hooks/qa-blueprint" "$INTEGRATED/.claude/scripts"
cp "$HOOK" "$INTEGRATED/.claude/hooks/qa-blueprint/"
cp "$ROOT/.claude/scripts/qa-test-code-scan.mjs" "$INTEGRATED/.claude/scripts/"
printf '%s' "$(node -e 'console.log(JSON.stringify({tool_name:"Edit",tool_input:{file_path:process.argv[1],new_string:"await page.waitForTimeout(10);"},cwd:process.argv[2]}))' "$STRICT/tests/a.spec.ts" "$STRICT")" | bash "$INTEGRATED/.claude/hooks/qa-blueprint/pre-test-code-scan.sh" > /dev/null 2>&1
if [ $? -eq 2 ]; then printf 'ok    integrated namespaced hook finds scanner\n'; else printf 'FAIL  integrated namespaced hook finds scanner\n'; fails=$((fails + 1)); fi

node - "$ROOT/hooks/hooks.json" "$ROOT/.claude/settings.json" <<'NODE' || fails=$((fails + 1))
const fs = require('fs');
for (const path of process.argv.slice(2)) {
  const entries = JSON.parse(fs.readFileSync(path, 'utf8')).hooks.PreToolUse;
  const guard = entries.findIndex((entry) => entry.matcher.includes('Bash|Write'));
  const quality = entries.findIndex((entry) => entry.matcher === 'Write|Edit|MultiEdit|NotebookEdit');
  if (guard < 0 || quality !== guard + 1) process.exit(1);
  const command = entries[quality].hooks[0].command;
  if (!command.endsWith('/.claude/hooks/pre-test-code-scan.sh')) process.exit(1);
}
console.log('ok    quality hook registered directly after security guard');
NODE

printf '\n'
if [ "$fails" -eq 0 ]; then echo 'all fixtures passed'; else echo "$fails fixture(s) failed"; fi
exit "$fails"

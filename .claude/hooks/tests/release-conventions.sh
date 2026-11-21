#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
TMP="$(mktemp -d /tmp/qa-release-conventions.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
fails=0
if python3 "$ROOT/scripts/release-check.py" --root "$ROOT"; then
  echo "ok    current release conventions"
else
  echo "FAIL  current release conventions"
  fails=$((fails+1))
fi
make_fixture() {
  local target="$1"
  mkdir -p "$target/.claude" "$target/opencode" "$target/docs"
  cp -R "$ROOT/.claude-plugin" "$target/"
  cp -R "$ROOT/.claude/skills" "$target/.claude/"
  cp "$ROOT/NOTICE" "$target/"
  cp "$ROOT/install.sh" "$target/"
  cp "$ROOT/docs/integration.md" "$target/docs/"
  cp "$ROOT/opencode/opencode.template.jsonc" "$target/opencode/"
}
make_fixture "$TMP/version"
python3 - "$TMP/version/.claude-plugin/marketplace.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
data["plugins"][0]["version"] = "999.0.0"
path.write_text(json.dumps(data))
PY
if python3 "$ROOT/scripts/release-check.py" --root "$TMP/version" >"$TMP/version.log" 2>&1; then
  echo "FAIL  version mismatch was not rejected"
  fails=$((fails+1))
elif grep -q "versions must agree" "$TMP/version.log"; then
  echo "ok    version mismatch rejected"
else
  echo "FAIL  version mismatch failed for an unexpected reason"
  fails=$((fails+1))
fi
make_fixture "$TMP/license"
python3 - "$TMP/license/.claude/skills/exploratory-testing/SKILL.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
path.write_text(text.replace("license: MIT AND Apache-2.0", "license: MIT\nlicense: Apache-2.0", 1))
PY
if python3 "$ROOT/scripts/release-check.py" --root "$TMP/license" >"$TMP/license.log" 2>&1; then
  echo "FAIL  duplicate license was not rejected"
  fails=$((fails+1))
elif grep -q "exactly one license field" "$TMP/license.log"; then
  echo "ok    duplicate license rejected"
else
  echo "FAIL  duplicate license failed for an unexpected reason"
  fails=$((fails+1))
fi
make_fixture "$TMP/notice-path"
python3 - "$TMP/notice-path/.claude/skills/THIRD_PARTY_NOTICES.md" <<'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
path.write_text(text.replace(".claude/scripts/qa-test-code-scan.mjs", ".claude/scripts/removed-scanner.mjs"))
PY
if python3 "$ROOT/scripts/release-check.py" --root "$TMP/notice-path" >"$TMP/notice-path.log" 2>&1; then
  echo "FAIL  missing adapted-path notice was not rejected"
  fails=$((fails+1))
elif grep -q "do not cover adapted path .claude/scripts/qa-test-code-scan.mjs" "$TMP/notice-path.log"; then
  echo "ok    missing adapted-path notice rejected"
else
  echo "FAIL  missing adapted-path notice failed for an unexpected reason"
  fails=$((fails+1))
fi
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) failed"
fi
exit "$fails"

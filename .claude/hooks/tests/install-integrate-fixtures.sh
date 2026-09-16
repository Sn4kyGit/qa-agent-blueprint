#!/usr/bin/env bash
#
# install-integrate-fixtures.sh — end-to-end fixtures for install.sh, run against
# throwaway repos in $TMPDIR: integrate mode (the bulk) and plugin mode (the two
# settings keys it writes).
#
# Why this exists: install.sh is the largest artifact in the blueprint and the only
# one that writes into *other people's* repositories, and its sole safety net used
# to be a human reading a --dry-run. It also namespaces rules and hooks, which means
# it has to rewrite the path references inside every file it copies — and the
# uninstaller has to recognise those rewritten files as its own. Both directions are
# silent when broken: dangling rule paths, or an uninstall that leaves everything
# behind with a WARN.
#
# Usage:  bash .claude/hooks/tests/install-integrate-fixtures.sh
# Exit:   0 = all fixtures pass, otherwise the number of failures.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
INSTALL="$REPO/install.sh"
[ -x "$INSTALL" ] || { echo "install.sh not executable at $INSTALL" >&2; exit 1; }

fails=0
WORK="$(mktemp -d)"
# QA_KEEP=1 leaves the throwaway repo in place and prints its path — the only sane
# way to inspect what the installer actually wrote when a fixture fails.
if [ "${QA_KEEP:-0}" = "1" ]; then
  echo "work dir kept: $WORK"
else
  trap 'rm -r "$WORK" 2>/dev/null' EXIT
fi

pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }

assert_file()    { [ -f "$2" ] && pass "$1" || fail "$1" "missing file: $2"; }
assert_no_file() { [ ! -e "$2" ] && pass "$1" || fail "$1" "should not exist: $2"; }
assert_grep()    { grep -qF -- "$3" "$2" 2>/dev/null && pass "$1" || fail "$1" "not found in $2: $3"; }
assert_no_grep() { grep -qF -- "$3" "$2" 2>/dev/null && fail "$1" "should not appear in $2: $3" || pass "$1"; }

# --- a target repo that already has its own ecosystem -------------------------
TARGET="$WORK/host"
mkdir -p "$TARGET/.claude/skills/my-own-skill" "$TARGET/docs"
git -C "$TARGET" init -q . 2>/dev/null
printf '# My project\n\nOwn instructions that must survive.\n' > "$TARGET/CLAUDE.md"
printf 'node_modules/\n' > "$TARGET/.gitignore"
# printf would read a leading '---' as an option, leaving the file empty.
printf '%s\n' '---' 'name: my-own-skill' '---' 'Mine.' > "$TARGET/.claude/skills/my-own-skill/SKILL.md"
printf '# Host docs\n' > "$TARGET/docs/README.md"

echo "== integrate into an existing repo =="
OUT="$("$INSTALL" --mode integrate --target "$TARGET" --yes 2>&1)"
if [ $? -ne 0 ]; then fail "installer exits 0" "$(printf '%s' "$OUT" | tail -3)"; else pass "installer exits 0"; fi

assert_grep    "own CLAUDE.md content kept"      "$TARGET/CLAUDE.md" "Own instructions that must survive."
assert_grep    "managed block appended"          "$TARGET/CLAUDE.md" "qa-agent-blueprint (managed, do not edit)"
assert_file    "backup of CLAUDE.md written"     "$(ls "$TARGET"/CLAUDE.md.bak-* 2>/dev/null | head -1)"
assert_file    "rules namespaced"                "$TARGET/.claude/rules/qa-blueprint/core/product-layer.md"
assert_file    "hooks namespaced"                "$TARGET/.claude/hooks/qa-blueprint/stop-evidence-check.sh"
assert_file    "hook fixtures came along"        "$TARGET/.claude/hooks/qa-blueprint/tests/guard-fixtures.sh"
assert_file    "skills copied"                   "$TARGET/.claude/skills/test-ticket/SKILL.md"
assert_file    "agents copied"                   "$TARGET/.claude/agents/qa-manager.md"
assert_grep    "own skill untouched"             "$TARGET/.claude/skills/my-own-skill/SKILL.md" "Mine."
assert_file    "docs copied, namespaced"         "$TARGET/docs/qa-blueprint/architecture.md"
assert_grep    "host docs untouched"             "$TARGET/docs/README.md" "Host docs"
assert_file    "secrets template created"        "$TARGET/.env.playwright-secrets"
assert_no_file "no dotenv file is invented"      "$TARGET/.env"

echo
echo "== internal path references were rewritten to the namespace =="
# Without the rewrite pass, every one of these points at a path that does not
# exist in the target repo — the agent loses the detail behind every rule.
assert_grep    "agent points at namespaced rule" "$TARGET/.claude/agents/qa-manager.md" ".claude/rules/qa-blueprint/core/product-layer.md"
assert_no_grep "no un-namespaced rule path left" "$TARGET/.claude/agents/qa-manager.md" ".claude/rules/core/"
assert_grep    "rule cross-ref rewritten"        "$TARGET/.claude/rules/qa-blueprint/core/evidence-policy.md" ".claude/rules/qa-blueprint/core/product-layer.md"
assert_grep    "docs ref rewritten"              "$TARGET/.claude/skills/test-ticket/SKILL.md" "docs/qa-blueprint/architecture.md"
# And every rewritten target must actually be there.
MISSING_REFS=0
while IFS= read -r ref; do
  [ -e "$TARGET/$ref" ] || { MISSING_REFS=$((MISSING_REFS + 1)); echo "      dangling: $ref"; }
done < <(grep -rhoE '\.claude/(rules|hooks)/qa-blueprint/[a-zA-Z0-9_./-]+\.(md|sh)' \
           "$TARGET/.claude/agents" "$TARGET/.claude/rules" 2>/dev/null | sort -u)
[ "$MISSING_REFS" -eq 0 ] && pass "no dangling namespaced references" \
  || fail "no dangling namespaced references" "$MISSING_REFS reference(s) point at nothing"

echo
echo "== the copied hooks still pass their own fixtures in the target =="
if (cd "$TARGET" && bash .claude/hooks/qa-blueprint/tests/guard-fixtures.sh >/dev/null 2>&1); then
  pass "guard fixtures pass after integration"
else
  fail "guard fixtures pass after integration" "the copied guard behaves differently"
fi

echo
echo "== second run is idempotent =="
OUT2="$("$INSTALL" --mode integrate --target "$TARGET" --yes 2>&1)"
if printf '%s' "$OUT2" | grep -q "collision"; then
  fail "no collisions on re-run" "$(printf '%s' "$OUT2" | grep collision | head -2)"
else
  pass "no collisions on re-run"
fi
BLOCKS="$(grep -c "qa-agent-blueprint (managed, do not edit)" "$TARGET/CLAUDE.md")"
[ "$BLOCKS" = "1" ] && pass "managed block not duplicated" || fail "managed block not duplicated" "found $BLOCKS"

echo
echo "== uninstall removes what it added, keeps what is yours =="
OUT3="$("$INSTALL" --mode integrate --target "$TARGET" --uninstall --yes 2>&1)"
assert_grep    "own CLAUDE.md content survives"  "$TARGET/CLAUDE.md" "Own instructions that must survive."
assert_no_grep "managed block gone"              "$TARGET/CLAUDE.md" "qa-agent-blueprint (managed, do not edit)"
assert_no_file "namespaced rules removed"        "$TARGET/.claude/rules/qa-blueprint/core/product-layer.md"
assert_no_file "namespaced hooks removed"        "$TARGET/.claude/hooks/qa-blueprint/stop-evidence-check.sh"
assert_no_file "blueprint skill removed"         "$TARGET/.claude/skills/test-ticket/SKILL.md"
assert_no_file "namespaced docs removed"         "$TARGET/docs/qa-blueprint/architecture.md"
assert_grep    "own skill still there"           "$TARGET/.claude/skills/my-own-skill/SKILL.md" "Mine."
assert_grep    "host docs still there"           "$TARGET/docs/README.md" "Host docs"

echo
echo "== plugin mode wires the two keys instead of printing homework =="
PTARGET="$WORK/plugin-host"
mkdir -p "$PTARGET/.claude"
printf '%s\n' '{' '  "permissions": {' '    "allow": ["Bash(ls:*)"]' '  }' '}' > "$PTARGET/.claude/settings.json"
"$INSTALL" --mode plugin --target "$PTARGET" --yes >/dev/null 2>&1
SET="$PTARGET/.claude/settings.json"
assert_grep    "marketplace registered"       "$SET" "extraKnownMarketplaces"
assert_grep    "plugin enabled"               "$SET" "qa-agent-blueprint@qa-agent-blueprint-marketplace"
assert_grep    "existing permissions kept"    "$SET" "Bash(ls:*)"
assert_no_file "nothing copied in plugin mode" "$PTARGET/.claude/rules"
assert_no_file "no skills copied either"       "$PTARGET/.claude/skills"
if python3 -c "import json,sys; json.load(open('$SET'))" 2>/dev/null; then
  pass "settings.json still valid JSON"
else
  fail "settings.json still valid JSON" "the merge produced invalid JSON"
fi
# Re-run must not duplicate keys or rewrite the file.
BEFORE="$(cat "$SET")"
"$INSTALL" --mode plugin --target "$PTARGET" --yes >/dev/null 2>&1
[ "$BEFORE" = "$(cat "$SET")" ] && pass "plugin re-run changes nothing" \
  || fail "plugin re-run changes nothing" "settings.json was rewritten on the second run"

echo
echo "== MCP merge: playwright contract flags are adopted, preferences are not forced =="
MTARGET="$WORK/mcp-host"
mkdir -p "$MTARGET"
git -C "$MTARGET" init -q . 2>/dev/null
# Existing .mcp.json: playwright WITHOUT the contract flags, an identical
# atlassian, and an own server that must survive untouched.
printf '%s\n' '{' '  "mcpServers": {' '    "playwright": {"command": "npx", "args": ["@playwright/mcp@latest"]},' '    "atlassian": {"type": "http", "url": "https://mcp.atlassian.com/v2/mcp?tools=all"},' '    "mine": {"command": "my-server"}' '  }' '}' > "$MTARGET/.mcp.json"
OUTM="$("$INSTALL" --mode integrate --target "$MTARGET" --yes 2>&1)"
printf '%s' "$OUTM" | grep -q "upgraded 'playwright'" \
  && pass "playwright upgraded to the blueprint config" \
  || fail "playwright upgraded to the blueprint config" "$(printf '%s' "$OUTM" | grep mcp)"
assert_grep "secrets flag present after merge" "$MTARGET/.mcp.json" '"--secrets"'
assert_grep "output-dir present after merge" "$MTARGET/.mcp.json" '"--output-dir"'
assert_grep "config file wired after merge" "$MTARGET/.mcp.json" '".playwright-mcp.config.json"'
# --isolated/--headless moved out of the CLI args into the consumer-owned
# preference file — the merged server must not carry them anymore.
if grep -q '"--isolated"' "$MTARGET/.mcp.json"; then
  fail "isolated moved to the preference file" '"--isolated" still in .mcp.json args'
else
  pass "isolated moved to the preference file"
fi
assert_file "browser preference file seeded" "$MTARGET/.playwright-mcp.config.json"
assert_grep  "own server untouched"             "$MTARGET/.mcp.json" '"my-server"'
printf '%s' "$OUTM" | grep -q "atlassian' already configured (identical)" \
  && pass "identical atlassian is SKIPPED, not WARN" \
  || fail "identical atlassian is SKIPPED, not WARN" "$(printf '%s' "$OUTM" | grep atlassian)"

# A headful user config that carries the CONTRACT flags (secrets + output-dir)
# but no --headless/--isolated must be KEPT — preferences are not a reason to
# overwrite someone's setup (this was the v0.2.0 behavior: we clobbered it).
KEEP="$WORK/mcp-headful"
mkdir -p "$KEEP"
git -C "$KEEP" init -q . 2>/dev/null
printf '%s\n' '{' '  "mcpServers": {' '    "playwright": {"command": "npx", "args": ["@playwright/mcp@latest", "--secrets", ".env.playwright-secrets", "--output-dir", "evidence/.mcp-out"]}' '  }' '}' > "$KEEP/.mcp.json"
OUTK="$("$INSTALL" --mode integrate --target "$KEEP" --yes 2>&1)"
printf '%s' "$OUTK" | grep -q "kept existing 'playwright'" \
  && pass "headful config with contract flags is kept" \
  || fail "headful config with contract flags is kept" "$(printf '%s' "$OUTK" | grep mcp)"
if grep -q '"--headless"' "$KEEP/.mcp.json"; then
  fail "kept config not rewritten" '"--headless" was forced into the kept config'
else
  pass "kept config not rewritten"
fi

echo
echo "== plugin mode reports local MCP duplicates instead of silently doubling =="
PDUP="$WORK/plugin-dupe"
mkdir -p "$PDUP"
printf '%s\n' '{"mcpServers": {' '  "playwright": {"command": "npx", "args": ["@playwright/mcp@latest"]},' '  "atlassian": {"type": "sse", "url": "https://mcp.atlassian.com/v1/sse"}' '}}' > "$PDUP/.mcp.json"
OUTP="$("$INSTALL" --mode plugin --target "$PDUP" --yes 2>&1)"
printf '%s' "$OUTP" | grep -q "dedupe" \
  && pass "plugin mode warns about duplicates" \
  || fail "plugin mode warns about duplicates" "$(printf '%s' "$OUTP" | tail -5)"
printf '%s' "$OUTP" | grep -q "no --secrets flag" \
  && pass "plugin mode flags unmasked playwright" \
  || fail "plugin mode flags unmasked playwright" "$(printf '%s' "$OUTP" | tail -5)"
assert_grep "local entries left in place (report only)" "$PDUP/.mcp.json" '"@playwright/mcp@latest"'

echo
echo "== self-setup: the blueprint repo as its own target (integrate special case) =="
# Dry-run only — this fixture runs against the REAL blueprint repo, so it must
# never write. The assertions check the routing decision, not the side effects.
OUT4="$("$INSTALL" --mode integrate --target "$REPO" --yes --dry-run 2>&1)"
if [ $? -ne 0 ]; then fail "self-setup exits 0" "$(printf '%s' "$OUT4" | tail -3)"; else pass "self-setup exits 0"; fi
printf '%s' "$OUT4" | grep -qF "Self-setup of the blueprint repo" \
  && pass "self-setup branch taken" \
  || fail "self-setup branch taken" "output lacks the self-setup banner"
printf '%s' "$OUT4" | grep -q "managed router block" \
  && fail "no CLAUDE.md merge planned on self" "self-setup planned to append to the router itself" \
  || pass "no CLAUDE.md merge planned on self"
assert_no_grep "own CLAUDE.md carries no managed block" "$REPO/CLAUDE.md" "qa-agent-blueprint (managed, do not edit)"

echo
echo "== --mode standalone is gone =="
OUT5="$("$INSTALL" --mode standalone --target "$TARGET" --yes 2>&1)"
[ $? -ne 0 ] && pass "standalone rejected" || fail "standalone rejected" "installer accepted the removed mode"
printf '%s' "$OUT5" | grep -qF "expected integrate|plugin" \
  && pass "error names the two remaining modes" \
  || fail "error names the two remaining modes" "$(printf '%s' "$OUT5" | tail -1)"

echo
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) failed"
fi
exit "$fails"

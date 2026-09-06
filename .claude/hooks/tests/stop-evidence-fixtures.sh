#!/usr/bin/env bash
#
# stop-evidence-fixtures.sh — fixture test for stop-evidence-check.sh.
#
# This hook carries both of the blueprint's hard promises: no verdict without
# evidence, and no run without a declared learning. It had no test until the
# learning check was added — and the guard hook taught us what an untested hook is
# worth (it silently allowed everything for the whole life of the repo).
#
# Usage:  bash .claude/hooks/tests/stop-evidence-fixtures.sh
# Exit:   0 = all fixtures pass, otherwise the number of failures.
#
# Convention: exit 0 = session may end, exit 2 = blocked.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../stop-evidence-check.sh"
[ -f "$HOOK" ] || { echo "stop-evidence-check.sh not found at $HOOK" >&2; exit 1; }

fails=0
WORK="$(mktemp -d)"
trap 'rm -r "$WORK" 2>/dev/null' EXIT

# A transcript line containing a real tool_use — the signal "a test actually ran".
write_transcript() {
  local path="$1" kind="$2"
  # The case dir may not exist yet — without this the transcript silently fails to
  # write, no test signal is found, and cases that expect a BLOCK pass for the
  # wrong reason (exit 0 because the hook thinks no test ever ran).
  mkdir -p "$(dirname "$path")/evidence"
  case "$kind" in
    test_ran)
      printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__playwright__browser_navigate","input":{"url":"https://example.invalid"}}]}}' > "$path" ;;
    no_test)
      # Mentions the words in prose only — must NOT count as a test run.
      printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"I edited evidence-policy.md and wrote about execution_summary.json and verdict PASS"}]}}' > "$path" ;;
    namespaced_mcp)
      # A plugin-provided MCP server may surface with an extra namespace segment.
      # Enforcement must not quietly switch off for plugin users.
      printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"mcp__qa-agent-blueprint__playwright__browser_navigate","input":{"url":"https://example.invalid"}}]}}' > "$path" ;;
    pnpm_runner)
      # A real suite is run through a package manager, not always bare npx.
      printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cd ../shop-web-tests && pnpm playwright test --grep @smoke"}}]}}' > "$path" ;;
    npm_script)
      printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm run test:e2e"}}]}}' > "$path" ;;
    heredoc_mentions_runner)
      # The command CONTAINS the runner text in a heredoc body but never runs it.
      printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat > note.md <<EOF\nwe usually run npx playwright test here\nEOF"}}]}}' > "$path" ;;
  esac
}

write_summary() {
  local dir="$1" learnings="$2"
  mkdir -p "$dir"
  if [ "$learnings" = "omit" ]; then
    printf '{"ticket":"SHOP-1","project":"SHOP","verdict":"PASS"}\n' > "$dir/execution_summary.json"
  else
    printf '{"ticket":"SHOP-1","project":"SHOP","verdict":"PASS","learnings":%s}\n' "$learnings" > "$dir/execution_summary.json"
  fi
}

run_hook() {
  local cwd="$1" transcript="$2"
  printf '{"cwd":"%s","transcript_path":"%s","stop_hook_active":false}' "$cwd" "$transcript" \
    | bash "$HOOK" >/dev/null 2>&1
  echo $?
}

check() {
  local name="$1" want="$2" got="$3"
  if [ "$got" = "$want" ]; then
    printf 'ok    %-52s exit=%s\n' "$name" "$got"
  else
    printf 'FAIL  %-52s want=%s got=%s\n' "$name" "$want" "$got"
    fails=$((fails + 1))
  fi
}

# --- case 1: no test ran → nothing to enforce ---------------------------------
C1="$WORK/c1"; mkdir -p "$C1/evidence"; write_transcript "$C1/t.jsonl" no_test
check "no test ran → session may end" 0 "$(run_hook "$C1" "$C1/t.jsonl")"

# --- case 2: test ran, no evidence at all → blocked ---------------------------
C2="$WORK/c2"; mkdir -p "$C2/evidence"; write_transcript "$C2/t.jsonl" test_ran
check "test ran, no execution_summary.json" 2 "$(run_hook "$C2" "$C2/t.jsonl")"

# --- case 3: evidence present but learnings omitted → blocked -----------------
C3="$WORK/c3"; write_transcript "$C3/t.jsonl" test_ran
write_summary "$C3/evidence/SHOP/SHOP-1/20260906-100000" omit
check "evidence without a learnings declaration" 2 "$(run_hook "$C3" "$C3/t.jsonl")"

# --- case 4: learnings present but empty on both sides → blocked --------------
C4="$WORK/c4"; write_transcript "$C4/t.jsonl" test_ran
write_summary "$C4/evidence/SHOP/SHOP-1/20260906-100000" '{"captured":[],"none_because":null}'
check "learnings declared but empty on both sides" 2 "$(run_hook "$C4" "$C4/t.jsonl")"

# --- case 5: captured entries → allowed ---------------------------------------
C5="$WORK/c5"; write_transcript "$C5/t.jsonl" test_ran
write_summary "$C5/evidence/SHOP/SHOP-1/20260906-100000" '{"captured":["stale cache after deploy"],"none_because":null}'
check "learnings captured" 0 "$(run_hook "$C5" "$C5/t.jsonl")"

# --- case 6: explicit "nothing surprising" → allowed --------------------------
C6="$WORK/c6"; write_transcript "$C6/t.jsonl" test_ran
write_summary "$C6/evidence/SHOP/SHOP-1/20260906-100000" '{"captured":[],"none_because":"clean run, no surprises"}'
check "explicit none_because" 0 "$(run_hook "$C6" "$C6/t.jsonl")"

# --- case 7: fan-out, one product declares and the other does not → blocked ---
C7="$WORK/c7"; write_transcript "$C7/t.jsonl" test_ran
write_summary "$C7/evidence/SHOP/SHOP-1/20260906-100000__STOREFRONT" '{"captured":[],"none_because":"clean run"}'
write_summary "$C7/evidence/SHOP/SHOP-1/20260906-100000__ADMIN" omit
check "multi-product run, one summary undeclared" 2 "$(run_hook "$C7" "$C7/t.jsonl")"

# --- case 8: the loop-breaker still works -------------------------------------
C8="$WORK/c8"; mkdir -p "$C8/evidence"; write_transcript "$C8/t.jsonl" test_ran
printf '{"cwd":"%s","transcript_path":"%s","stop_hook_active":true}' "$C8" "$C8/t.jsonl" \
  | bash "$HOOK" >/dev/null 2>&1
check "stop_hook_active breaks the loop" 0 "$?"

# --- case 9-12: what counts as "a test ran" ----------------------------------
C9="$WORK/c9"; write_transcript "$C9/t.jsonl" namespaced_mcp
check "namespaced playwright MCP tool counts" 2 "$(run_hook "$C9" "$C9/t.jsonl")"

C10="$WORK/c10"; write_transcript "$C10/t.jsonl" pnpm_runner
check "pnpm playwright test counts" 2 "$(run_hook "$C10" "$C10/t.jsonl")"

C11="$WORK/c11"; write_transcript "$C11/t.jsonl" npm_script
check "npm run test:e2e counts" 2 "$(run_hook "$C11" "$C11/t.jsonl")"

C12="$WORK/c12"; write_transcript "$C12/t.jsonl" heredoc_mentions_runner
check "heredoc mentioning the runner does not" 0 "$(run_hook "$C12" "$C12/t.jsonl")"

echo
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) failed"
fi
exit "$fails"

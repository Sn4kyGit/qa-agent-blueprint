#!/usr/bin/env bash
#
# post-jira-audit-fixtures.sh — fixture test for post-jira-audit.sh (PostToolUse).
#
# The PostToolUse hook that logs every JIRA/Confluence write to
# evidence/.audit/jira-writes.log is the compliance backbone for shadow-mode
# detection (security.md, evidence-policy.md). Until 0.18.5 it had zero fixture
# coverage on the Claude side (COVERAGE.md claimed coverage that didn't exist).
#
# Usage:  bash .claude/hooks/tests/post-jira-audit-fixtures.sh
# Exit:   0 = all fixtures pass, otherwise the number of failures.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../post-jira-audit.sh"

if [ ! -f "$HOOK" ]; then
  echo "post-jira-audit.sh not found at $HOOK" >&2
  exit 1
fi

fails=0
TOG="$(mktemp -d)"; trap 'rm -rf "$TOG" 2>/dev/null' EXIT

# QA home scaffold
mkdir -p "$TOG/projects" "$TOG/memory" "$TOG/evidence"

LOG_FILE="$TOG/evidence/.audit/jira-writes.log"

check() {
  local name="$1" want="$2" json="$3" got
  printf '%s' "$json" | bash "$HOOK" >/dev/null 2>&1
  got=$?
  if [ "$got" = "$want" ]; then
    printf 'ok    %-50s exit=%s\n' "$name" "$got"
  else
    printf 'FAIL  %-50s want=%s got=%s\n' "$name" "$want" "$got"
    fails=$((fails + 1))
  fi
}

check_log() {
  local name="$1" pattern="$2" not_pattern="${3:-}"
  if [ ! -f "$LOG_FILE" ]; then
    printf 'FAIL  %-50s no log file\n' "$name"
    fails=$((fails + 1))
    return
  fi
  if ! grep -qE "$pattern" "$LOG_FILE"; then
    printf 'FAIL  %-50s pattern not in log: %s\n' "$name" "$pattern"
    fails=$((fails + 1))
    return
  fi
  if [ -n "$not_pattern" ] && grep -qE "$not_pattern" "$LOG_FILE"; then
    printf 'FAIL  %-50s forbidden pattern in log: %s\n' "$name" "$not_pattern"
    fails=$((fails + 1))
    return
  fi
  printf 'ok    %-50s log ok\n' "$name"
}

echo "== post-jira-audit: basic write logging =="
rm -f "$LOG_FILE"
check "add_comment with issue_key" 0 '{"tool_name":"mcp__atlassian__add_comment","tool_input":{"issue_key":"SHOP-123","comment":"test"},"tool_response":{"ok":true},"cwd":"'"$TOG"'"}'
check_log "add_comment logged" "tool=mcp__atlassian__add_comment.*key=SHOP-123.*result=ok"

check "jira_create_issue with issueKey" 0 '{"tool_name":"mcp__atlassian__jira_create_issue","tool_input":{"issueKey":"SHOP-456","summary":"test"},"tool_response":{"ok":true},"cwd":"'"$TOG"'"}'
check_log "create_issue logged" "tool=mcp__atlassian__jira_create_issue.*key=SHOP-456.*result=ok"

echo
echo "== post-jira-audit: executeWrite inner tool =="
rm -f "$LOG_FILE"
check "executeWrite with inner tool" 0 '{"tool_name":"mcp__atlassian__executeWrite","tool_input":{"tool":"uploadAttachmentToJiraIssue","issueKey":"SHOP-789"},"tool_response":{"ok":true},"cwd":"'"$TOG"'"}'
check_log "executeWrite logged with inner tool" "executeWrite\(uploadAttachmentToJiraIssue\).*key=SHOP-789"

echo
echo "== post-jira-audit: error response mapping =="
rm -f "$LOG_FILE"
check "write with error response" 0 '{"tool_name":"mcp__atlassian__add_comment","tool_input":{"issue_key":"SHOP-999","comment":"test"},"tool_response":{"error":"permission denied"},"cwd":"'"$TOG"'"}'
check_log "error mapped" "key=SHOP-999.*result=error"

echo
echo "== post-jira-audit: QA-home walk-up =="
mkdir -p "$TOG/subproject/nested"
rm -f "$LOG_FILE"
check "write from subfolder walks up" 0 '{"tool_name":"mcp__atlassian__add_comment","tool_input":{"issue_key":"SHOP-111","comment":"test"},"tool_response":{"ok":true},"cwd":"'"$TOG/subproject/nested"'"}'
if [ -f "$LOG_FILE" ]; then
  check_log "walk-up logged at home root" "key=SHOP-111"
else
  printf 'FAIL  %-50s log not at home root\n' "walk-up logged at home root"
  fails=$((fails + 1))
fi

echo
echo "== post-jira-audit: no secret values in log =="
rm -f "$LOG_FILE"
check "write with secret in comment" 0 '{"tool_name":"mcp__atlassian__add_comment","tool_input":{"issue_key":"SHOP-222","comment":"password=hunter2secret"},"tool_response":{"ok":true},"cwd":"'"$TOG"'"}'
check_log "no secret value leaked" "key=SHOP-222" "hunter2secret"

echo
echo "== post-jira-audit: plugin-namespaced tool =="
rm -f "$LOG_FILE"
check "plugin-namespaced atlassian" 0 '{"tool_name":"mcp__plugin_qa-agent-blueprint_atlassian__add_comment","tool_input":{"issue_key":"SHOP-333","comment":"test"},"tool_response":{"ok":true},"cwd":"'"$TOG"'"}'
check_log "plugin-namespaced logged" "key=SHOP-333"

echo
echo "== post-jira-audit: hook logs whatever the matcher sends =="
# The hook itself has no tool-name filter — the hooks.json matcher decides
# when to fire. The hook logs every call it receives. This test verifies the
# hook doesn't crash on non-write tools (the matcher won't send them in prod).
rm -f "$LOG_FILE"
check "non-write tool exits clean" 0 '{"tool_name":"mcp__atlassian__jira_get_issue","tool_input":{"issue_key":"SHOP-444"},"tool_response":{"ok":true},"cwd":"'"$TOG"'"}'
check_log "non-write logged (matcher filters in prod)" "key=SHOP-444"

echo
if [ "$fails" -eq 0 ]; then
  echo "all fixtures passed"
else
  echo "$fails fixture(s) failed"
fi
exit "$fails"

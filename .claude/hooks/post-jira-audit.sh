#!/usr/bin/env bash
#
# post-jira-audit.sh — PostToolUse hook (matcher: mcp__atlassian__.*(create|
# edit|add|transition|update|delete).*). Append-only audit log of every JIRA/
# Confluence write the agent makes, including headless CI runs. Never blocks;
# logging only. Never logs secret values — only tool name and identifying
# fields (issue key, action).
#
set -uo pipefail

INPUT="$(cat)"

get_json() {
  command -v python3 >/dev/null 2>&1 || return 1
  printf '%s' "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
$1
" 2>/dev/null
}

CWD="$(get_json 'print(d.get("cwd") or "")')"; CWD="${CWD:-$PWD}"
TOOL_NAME="$(get_json 'print(d.get("tool_name") or "")')"
ISSUE_KEY="$(get_json '
ti = d.get("tool_input") or {}
print(ti.get("issueKey") or ti.get("issue_key") or ti.get("key") or ti.get("id") or "")
')"
SUCCESS="$(get_json 'print("ok" if not (d.get("tool_response") or {}).get("error") else "error")')"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_DIR="$CWD/evidence/.audit"
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
LOG_FILE="$LOG_DIR/jira-writes.log"

printf '%s | tool=%s | key=%s | result=%s | user=%s\n' \
  "$TS" "${TOOL_NAME:-unknown}" "${ISSUE_KEY:-unknown}" "${SUCCESS:-unknown}" \
  "${CLAUDE_USER_EMAIL:-${USER:-unknown}}" >> "$LOG_FILE" 2>/dev/null

exit 0

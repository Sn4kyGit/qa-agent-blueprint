#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit, Anna Mazurek

#
# post-jira-audit.sh — PostToolUse hook (matcher: mcp__atlassian__.*(create|
# edit|add|transition|update|delete|executeWrite|executeDestructive).*). Append-only
# audit log of every JIRA/Confluence write the agent makes, including headless
# CI runs. Never blocks; logging only. Never logs secret values — only tool
# name and identifying fields (issue key, action).
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

# QA home discovery (0.9.1): the audit log lives at the QA home root, even
# when the session runs in a subfolder (product repo). Walk up to the nearest
# .qa-home marker or the legacy trio (projects/ + memory/ + evidence/).
d="$CWD"
while : ; do
  if [ -e "$d/.qa-home" ] || { [ -d "$d/projects" ] && [ -d "$d/memory" ] && [ -d "$d/evidence" ]; }; then
    CWD="$d"; break
  fi
  if { [ -n "${HOME:-}" ] && [ "$d" = "$HOME" ]; } || [ "$d" = "/" ]; then break; fi
  d="$(dirname "$d")"
done
TOOL_NAME="$(get_json 'print(d.get("tool_name") or "")')"
# Direct tools carry the key at the top level (issueKey/issue_key/key/id); an
# Atlassian v2 executeWrite/executeDestructive call nests it inside the inner
# tool's arguments — fall back to the first ticket-shaped string anywhere in
# the payload (same regex the shadow gate uses).
ISSUE_KEY="$(get_json '
ti = d.get("tool_input") or {}
direct = ti.get("issueKey") or ti.get("issue_key") or ti.get("key") or ti.get("id") or ""
if direct:
    print(direct)
else:
    import re, json as j
    m = re.search(r"[A-Z][A-Z0-9]+-[0-9]+", j.dumps(ti))
    print(m.group(0) if m else "")
')"
# For execute* meta-tools, note the inner tool name when it is visible under a
# common parameter name — the audit line stays informative without a schema
# dependency on Atlassian's exact execute shape.
case "$TOOL_NAME" in
  *executeWrite*|*executeDestructive*)
    INNER="$(get_json '
ti = d.get("tool_input") or {}
print(ti.get("tool") or ti.get("toolName") or ti.get("tool_name") or ti.get("name") or "")
')"
    [ -n "$INNER" ] && TOOL_NAME="$TOOL_NAME($INNER)" ;;
esac
SUCCESS="$(get_json 'print("ok" if not (d.get("tool_response") or {}).get("error") else "error")')"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_DIR="$CWD/evidence/.audit"
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0
LOG_FILE="$LOG_DIR/jira-writes.log"

printf '%s | tool=%s | key=%s | result=%s | user=%s\n' \
  "$TS" "${TOOL_NAME:-unknown}" "${ISSUE_KEY:-unknown}" "${SUCCESS:-unknown}" \
  "${CLAUDE_USER_EMAIL:-${USER:-unknown}}" >> "$LOG_FILE" 2>/dev/null

exit 0

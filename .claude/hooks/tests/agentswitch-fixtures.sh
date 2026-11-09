#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit, Anna Mazurek

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
CHECKER="$ROOT/.claude/scripts/agentswitch-check.py"
PYTHON="$(command -v python3)"
WORK="$(mktemp -d)"
if [ "${QA_KEEP:-0}" = "1" ]; then
  printf 'work dir kept: %s\n' "$WORK"
else
  trap 'rm -rf "$WORK"' EXIT
fi
fails=0
OUT=""
RC=0

pass() { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n      %s\n' "$1" "${2:-}"; fails=$((fails + 1)); }
assert_out() { case "$OUT" in *"$2"*) pass "$1" ;; *) fail "$1" "missing output: $2" ;; esac }
assert_no_out() { case "$OUT" in *"$2"*) fail "$1" "forbidden output: $2" ;; *) pass "$1" ;; esac }

make_blueprint() {
  local bp="$1"
  mkdir -p "$bp/.claude/agents" "$bp/.claude/hooks" "$bp/.claude/rules" "$bp/.claude/scripts" "$bp/.claude/skills" "$bp/opencode/agents" "$bp/opencode/commands" "$bp/opencode/plugins" "$bp/docs" "$bp/.agents"
  printf 'router\n' > "$bp/opencode/ROUTER.md"
  printf '# QA Agent Blueprint\n\nUse .claude/rules/core/.\n' > "$bp/CLAUDE.md"
  printf '%s\n' '{"permissions":{"deny":["Read(test-secret)"]},"hooks":{"PreToolUse":[{"matcher":"TestTool","hooks":[{"type":"command","command":"test-hook"}]}]}}' > "$bp/.claude/settings.json"
}

make_home() {
  local dir="$1"
  mkdir -p "$dir/projects" "$dir/memory" "$dir/evidence" "$dir/home" "$dir/bin"
  printf 'qa home\n' > "$dir/.qa-home"
  local tool
  for tool in claude opencode node; do
    printf '#!/bin/sh\nexit 0\n' > "$dir/bin/$tool"
    chmod +x "$dir/bin/$tool"
  done
}

link_opencode() {
  local dir="$1" bp="$2"
  mkdir -p "$dir/.opencode"
  ln -s "$bp/opencode/ROUTER.md" "$dir/.opencode/ROUTER.md"
  ln -s "$bp/opencode/agents" "$dir/.opencode/agents"
  ln -s "$bp/opencode/commands" "$dir/.opencode/commands"
  ln -s "$bp/opencode/plugins" "$dir/.opencode/plugins"
}

link_shared() {
  local dir="$1" bp="$2" entry
  link_opencode "$dir" "$bp"
  mkdir -p "$dir/.claude"
  for entry in agents hooks rules scripts skills; do
    ln -s "$bp/.claude/$entry" "$dir/.claude/$entry"
  done
  ln -s "$bp/docs" "$dir/docs"
  ln -s "$bp/.agents" "$dir/.agents"
  cp "$bp/CLAUDE.md" "$dir/CLAUDE.md"
  cp "$bp/.claude/settings.json" "$dir/.claude/settings.json"
  printf '{}\n' > "$dir/.playwright-mcp.config.json"
  printf '# placeholder only\n' > "$dir/.env.playwright-secrets"
}

write_cloud_configs() {
  local dir="$1"
  cat > "$dir/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["@playwright/mcp@latest", "--config", ".playwright-mcp.config.json", "--secrets", ".env.playwright-secrets", "--output-dir", "evidence/.mcp-out", "--image-responses", "omit"]
    },
    "atlassian": {
      "type": "http",
      "url": "https://mcp.atlassian.com/v2/mcp",
      "headers": {"Authorization": "Bearer CLOUD_DECOY_TOKEN_NEVER_PRINT"}
    }
  }
}
JSON
  cat > "$dir/opencode.json" <<'JSONC'
{
  // JSONC comments and trailing commas are accepted.
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["npx", "@playwright/mcp@latest", "--config", ".playwright-mcp.config.json", "--secrets", ".env.playwright-secrets", "--output-dir", "evidence/.mcp-out", "--image-responses=omit"],
    },
    "atlassian": {
      "type": "remote",
      "url": "https://mcp.atlassian.com/v2/mcp",
      "headers": {"Authorization": "Bearer CLOUD_DECOY_TOKEN_NEVER_PRINT"},
    },
  },
}
JSONC
}

write_dc_configs() {
  local dir="$1"
  cat > "$dir/.mcp.json" <<'JSON'
{
  "mcpServers": {
    "playwright": {
      "command": "node",
      "args": [".claude/scripts/qa-secrets.mjs", "mcp", "STAGE_PASSWORD", "--", "npx", "@playwright/mcp@latest", "--config", ".playwright-mcp.config.json", "--output-dir", "evidence/.mcp-out", "--image-responses", "omit"]
    },
    "atlassian": {
      "command": "uvx",
      "args": ["mcp-atlassian"],
      "env": {"JIRA_URL": "https://jira.dc-example.invalid", "JIRA_PERSONAL_TOKEN": "DC_DECOY_TOKEN_NEVER_PRINT"}
    }
  }
}
JSON
  cat > "$dir/opencode.json" <<'JSON'
{
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["node", ".claude/scripts/qa-secrets.mjs", "mcp", "STAGE_PASSWORD", "--", "npx", "@playwright/mcp@latest", "--config", ".playwright-mcp.config.json", "--output-dir", "evidence/.mcp-out", "--image-responses", "omit"]
    },
    "atlassian": {
      "type": "local",
      "command": ["uvx", "mcp-atlassian"],
      "environment": {"JIRA_URL": "https://jira.dc-example.invalid", "JIRA_PERSONAL_TOKEN": "DC_DECOY_TOKEN_NEVER_PRINT"}
    }
  }
}
JSON
  mkdir -p "$dir/.claude/scripts"
  printf 'wrapper\n' > "$dir/.claude/scripts/qa-secrets.mjs"
}

snapshot() {
  local dir="$1" output="$2"
  "$PYTHON" - "$dir" > "$output" <<'PY'
import hashlib
import os
import sys
root = sys.argv[1]
for current, dirs, files in os.walk(root, followlinks=False):
    dirs.sort()
    files.sort()
    for name in list(dirs):
        path = os.path.join(current, name)
        rel = os.path.relpath(path, root)
        if os.path.islink(path):
            print("L " + rel + " -> " + os.readlink(path))
            dirs.remove(name)
        else:
            print("D " + rel)
    for name in files:
        path = os.path.join(current, name)
        rel = os.path.relpath(path, root)
        if os.path.islink(path):
            print("L " + rel + " -> " + os.readlink(path))
        else:
            with open(path, "rb") as handle:
                digest = hashlib.sha256(handle.read()).hexdigest()
            print("F " + rel + " " + digest)
PY
}

run_case() {
  local name="$1" target="$2" dir="$3"
  snapshot "$dir" "$WORK/$name.before"
  OUT="$(cd "$ROOT" && HOME="$dir/home" PATH="$dir/bin:/usr/bin:/bin" "$PYTHON" "$CHECKER" "$target" --cwd "$dir" 2>&1)"
  RC=$?
  snapshot "$dir" "$WORK/$name.after"
  if cmp -s "$WORK/$name.before" "$WORK/$name.after"; then
    pass "$name: files, links, and directory set unchanged"
  else
    fail "$name: files, links, and directory set unchanged" "snapshot differs"
  fi
  assert_no_out "$name: Cloud decoy never printed" "CLOUD_DECOY_TOKEN_NEVER_PRINT"
  assert_no_out "$name: DC decoy never printed" "DC_DECOY_TOKEN_NEVER_PRINT"
}

printf '== shared layout is ready in both directions ==\n'
CASE="$WORK/shared"
make_blueprint "$WORK/blueprint"
make_home "$CASE"
link_shared "$CASE" "$WORK/blueprint"
write_cloud_configs "$CASE"
run_case "shared-to-claude" claude "$CASE"
assert_out "shared to Claude READY" "STATUS=READY"
assert_out "shared to Claude source" "SOURCE=opencode"
assert_no_out "shared to Claude needs no dry-run" "install.sh --mode shared"
run_case "shared-to-opencode" opencode "$CASE"
assert_out "shared to opencode READY" "STATUS=READY"
assert_out "shared to opencode source" "SOURCE=claude"
assert_no_out "shared to opencode needs no dry-run" "install.sh --mode shared"
{ printf '# Consumer\n\n<!-- >>> qa-agent-blueprint (managed, do not edit) -->\n\n'; cat "$WORK/blueprint/CLAUDE.md"; printf '\n<!-- <<< qa-agent-blueprint -->\n'; } > "$CASE/CLAUDE.md"
run_case "shared-managed-router" claude "$CASE"
assert_out "shared managed router is not integrate" "STATUS=READY"
assert_no_out "shared managed router needs no migration" "requires manual collision review"
cp "$CASE/.claude/settings.json" "$WORK/shared-settings.backup"
rm "$CASE/.claude/settings.json"
run_case "shared-missing-settings" claude "$CASE"
assert_out "shared missing settings BLOCKED" "STATUS=BLOCKED"
assert_out "shared missing settings named" "settings"
cp "$WORK/shared-settings.backup" "$CASE/.claude/settings.json"
rm "$CASE/CLAUDE.md"
run_case "shared-missing-router" claude "$CASE"
assert_out "shared missing router BLOCKED" "STATUS=BLOCKED"
assert_out "shared missing router named" "CLAUDE.md"
cp "$WORK/blueprint/CLAUDE.md" "$CASE/CLAUDE.md"
printf '%s\n' '{"hooks":[]}' > "$CASE/.claude/settings.json"
run_case "shared-settings-wrong-type" claude "$CASE"
assert_out "shared wrong settings type BLOCKED" "STATUS=BLOCKED"
assert_no_out "shared wrong settings type no traceback" "Traceback"
printf '%s\n' '{"hooks":{"PreToolUse":["bad"]}}' > "$CASE/.claude/settings.json"
run_case "shared-entry-wrong-type" claude "$CASE"
assert_out "shared wrong hook entry BLOCKED" "STATUS=BLOCKED"
assert_no_out "shared wrong hook entry no traceback" "Traceback"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"TestTool","hooks":[{"type":"command","command":["bad"]}]}]}}' > "$CASE/.claude/settings.json"
run_case "shared-command-wrong-type" claude "$CASE"
assert_out "shared wrong command type BLOCKED" "STATUS=BLOCKED"
assert_no_out "shared wrong command type no traceback" "Traceback"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":{"bad":"type"},"hooks":[{"type":"command","command":"test"}]}]}}' > "$CASE/.claude/settings.json"
run_case "shared-matcher-wrong-type" claude "$CASE"
assert_out "shared wrong matcher type BLOCKED" "STATUS=BLOCKED"
assert_no_out "shared wrong matcher type no traceback" "Traceback"
cp "$WORK/shared-settings.backup" "$CASE/.claude/settings.json"

printf '\n== plugin installation needs human migration steps ==\n'
CASE="$WORK/plugin"
make_home "$CASE"
mkdir -p "$CASE/.claude"
printf '%s\n' '{"enabledPlugins":{"qa-agent-blueprint@qa-agent-blueprint-marketplace":true}}' > "$CASE/.claude/settings.json"
write_cloud_configs "$CASE"
printf '{}\n' > "$CASE/.playwright-mcp.config.json"
printf '# placeholder only\n' > "$CASE/.env.playwright-secrets"
run_case "plugin-old" opencode "$CASE"
assert_out "plugin old is human-steps" "STATUS=READY_WITH_HUMAN_STEPS"
assert_out "plugin old suggests dry-run only" "install.sh --mode shared --dry-run"
assert_no_out "plugin old is not duplicate by itself" "duplicate registration"

printf '\n== integrate content and real collisions block ==\n'
CASE="$WORK/integrate"
make_home "$CASE"
mkdir -p "$CASE/.claude/rules/qa-blueprint"
printf '%s\n' '<!-- >>> qa-agent-blueprint (managed, do not edit) -->' > "$CASE/CLAUDE.md"
run_case "integrate-collision" opencode "$CASE"
assert_out "integrate collision BLOCKED" "STATUS=BLOCKED"
assert_out "integrate collision identified" "integrate installation"
assert_out "integrate real collision identified" "real collision: .claude/rules"

printf '\n== duplicate plugin and shared registration blocks ==\n'
CASE="$WORK/duplicate"
make_home "$CASE"
link_shared "$CASE" "$WORK/blueprint"
write_cloud_configs "$CASE"
printf '%s\n' '{"enabledPlugins":{"qa-agent-blueprint@qa-agent-blueprint-marketplace":true}}' > "$CASE/.claude/settings.json"
run_case "duplicate-registration" claude "$CASE"
assert_out "duplicate registration BLOCKED" "STATUS=BLOCKED"
assert_out "duplicate registration identified" "duplicate registration"

printf '\n== dangling and foreign links stay untouched ==\n'
CASE="$WORK/links"
make_home "$CASE"
link_shared "$CASE" "$WORK/blueprint"
write_cloud_configs "$CASE"
rm "$CASE/.opencode/plugins" "$CASE/.claude/skills"
ln -s "$WORK/missing-target" "$CASE/.opencode/plugins"
mkdir -p "$WORK/foreign-skills"
ln -s "$WORK/foreign-skills" "$CASE/.claude/skills"
run_case "bad-links" claude "$CASE"
assert_out "bad links BLOCKED" "STATUS=BLOCKED"
assert_out "dangling link identified" "dangling symlink: .opencode/plugins"
assert_out "foreign link identified" "foreign symlink: .claude/skills"

printf '\n== old opencode symlinked bridges produce a data warning ==\n'
CASE="$WORK/bridges"
make_home "$CASE"
link_opencode "$CASE" "$WORK/blueprint"
ln -s "$WORK/blueprint/.claude" "$CASE/.claude"
ln -s "$WORK/blueprint/docs" "$CASE/docs"
ln -s "$WORK/blueprint/.agents" "$CASE/.agents"
mkdir -p "$WORK/blueprint/.agents/qa-project-context"
printf 'bridge\n' > "$WORK/blueprint/.agents/qa-project-context/ACME.md"
printf '{}\n' > "$CASE/.playwright-mcp.config.json"
printf '# placeholder only\n' > "$CASE/.env.playwright-secrets"
cp "$WORK/shared/opencode.json" "$CASE/opencode.json"
run_case "bridge-preservation" claude "$CASE"
assert_out "bridge migration human-steps" "STATUS=READY_WITH_HUMAN_STEPS"
assert_out "bridge preservation warning" "data preservation: .agents symlink contains project/product bridge files"

printf '\n== Data Center emits host only and wrapper is accepted ==\n'
CASE="$WORK/datacenter"
make_home "$CASE"
link_shared "$CASE" "$WORK/blueprint"
write_dc_configs "$CASE"
run_case "datacenter-redaction" opencode "$CASE"
assert_out "Data Center READY" "STATUS=READY"
assert_out "Data Center host shown" "host jira.dc-example.invalid"
assert_no_out "Data Center token key not dumped" "JIRA_PERSONAL_TOKEN"
assert_no_out "Data Center URL not dumped" "https://jira.dc-example.invalid"
assert_out "Data Center wrapper recognized" "playwright uses the secrets wrapper"

printf '\n== malformed JSON is a finding, never a crash ==\n'
CASE="$WORK/malformed"
make_home "$CASE"
link_shared "$CASE" "$WORK/blueprint"
write_cloud_configs "$CASE"
printf '{ malformed jsonc\n' > "$CASE/opencode.json"
run_case "malformed-json" claude "$CASE"
assert_out "malformed JSON BLOCKED" "STATUS=BLOCKED"
assert_out "malformed JSON identified" "opencode.json is malformed or unreadable"
assert_no_out "malformed JSON has no traceback" "Traceback"

printf '\n== source equals target is a no-op ==\n'
CASE="$WORK/noop"
make_home "$CASE"
link_opencode "$CASE" "$WORK/blueprint"
ln -s "$WORK/blueprint/.claude" "$CASE/.claude"
run_case "same-harness-noop" opencode "$CASE"
assert_out "same harness READY" "STATUS=READY"
assert_out "same harness source" "SOURCE=opencode"
assert_out "same harness NO_OP" "NO_OP"

printf '\n== checker static read-only boundary ==\n'
"$PYTHON" - "$CHECKER" <<'PY'
import ast
import sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    tree = ast.parse(handle.read(), path)
forbidden_imports = {"subprocess", "socket", "requests", "urllib", "http", "asyncio", "ctypes"}
forbidden_calls = {"system", "popen", "run", "Popen", "check_call", "check_output", "urlopen", "mkdir", "makedirs", "remove", "unlink", "rmdir", "rename", "replace", "write_text", "write_bytes", "eval", "exec"}
errors = []
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for alias in node.names:
            if alias.name.split(".")[0] in forbidden_imports:
                errors.append("import " + alias.name)
    elif isinstance(node, ast.ImportFrom) and node.module and node.module.split(".")[0] in forbidden_imports:
        errors.append("import " + node.module)
    elif isinstance(node, ast.Call):
        if isinstance(node.func, ast.Attribute) and node.func.attr in forbidden_calls:
            errors.append("call " + node.func.attr)
        elif isinstance(node.func, ast.Name) and node.func.id in forbidden_calls:
            errors.append("call " + node.func.id)
        if isinstance(node.func, ast.Name) and node.func.id == "open" and len(node.args) > 1:
            if isinstance(node.args[1], ast.Constant) and any(flag in str(node.args[1].value) for flag in ("w", "a", "x", "+")):
                errors.append("write open")
if errors:
    print("\n".join(errors))
    sys.exit(1)
PY
if [ $? -eq 0 ]; then
  pass "no forbidden imports, process calls, writes, or network primitives"
else
  fail "no forbidden imports, process calls, writes, or network primitives" "static AST check failed"
fi

printf '\n'
if [ "$fails" -eq 0 ]; then
  printf 'all fixtures passed\n'
else
  printf '%s fixture(s) failed\n' "$fails"
fi
exit "$fails"

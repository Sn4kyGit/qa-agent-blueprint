#!/usr/bin/env bash
#
# pre-tool-guard.sh — PreToolUse hook (matcher: Bash|Write|Edit|MultiEdit|
# NotebookEdit). Mechanical enforcement of .claude/rules/core/security.md:
# blocks writes/reads-as-writes to secret files and the most destructive shell
# commands, regardless of how the request was framed upstream.
#
set -uo pipefail

INPUT="$(cat)"

get_json() {
  # get_json <python-expr-suffix-on-d> — reads the hook payload as `d`.
  command -v python3 >/dev/null 2>&1 || return 1
  printf '%s' "$INPUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
$1
" 2>/dev/null
}

TOOL_NAME="$(get_json 'print(d.get("tool_name") or "")')"
COMMAND="$(get_json 'print((d.get("tool_input") or {}).get("command") or "")')"
FILE_PATH="$(get_json 'print((d.get("tool_input") or {}).get("file_path") or "")')"

# --- fallback whenever the payload could not be parsed: scan the raw JSON with
# plain grep instead of silently allowing everything. This used to require
# python3 to be ABSENT, which meant a broken parse (python3 present, but the
# expression failing — as the escaped quotes here did until 2026-09-05) left
# TOOL_NAME/COMMAND/FILE_PATH empty and every check skipped, so the guard
# allowed `rm -rf`, force pushes and .env writes alike. Fail closed instead:
# no parse → match against the whole payload.
if [ -z "$TOOL_NAME" ]; then
  COMMAND="$INPUT"
  FILE_PATH="$INPUT"
fi

block() {
  echo "BLOCKED by pre-tool-guard: $1" >&2
  exit 2
}

is_secret_path() {
  # Lowercase the path for the substring patterns below: bash `case` is
  # case-sensitive, so `*secrets*` alone never matched `SECRET/` or `Credentials`
  # — while product-layer.md told users this pattern protected them.
  local lc
  lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$1" in
    # `.env.example` is the committed placeholder template: no values, whitelisted
    # in .gitignore/.claudeignore, and the source install.sh copies `.env` from —
    # so the blueprint must be able to create and maintain it. Listed FIRST so it
    # wins over the `.env.*` pattern below. `.env.playwright-secrets` still
    # matches *secrets* and stays blocked, as does `.env` itself.
    *.env.example|*/.env.example) return 1 ;;
    *.env|*.env.*|*/.env|*/.env.*) return 0 ;;
    *.pem|*id_rsa*|*id_ed25519*) return 0 ;;
  esac
  case "$lc" in
    *secret*|*credential*) return 0 ;;
  esac
  return 1
}

# 1. Never write/edit a secrets file.
if [ -n "$FILE_PATH" ] && is_secret_path "$FILE_PATH"; then
  block "refusing to write/edit a secrets file ($FILE_PATH). Secrets are vault/env references only — see .claude/rules/core/security.md."
fi

# 2. Bash: block destructive/secret-touching commands.
if [ "$TOOL_NAME" = "Bash" ] || { [ -z "$TOOL_NAME" ] && [ -n "$COMMAND" ]; }; then
  if printf '%s' "$COMMAND" | grep -qE 'rm[[:space:]]+(-[a-zA-Z]*f[a-zA-Z]*r|-[a-zA-Z]*r[a-zA-Z]*f)[[:space:]]'; then
    block "refusing rm -rf / rm -fr — destructive command."
  fi
  if printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+push[[:space:]]+.*(--force|-f\b)'; then
    block "refusing git push --force — see the git safety protocol before overriding this manually."
  fi
  # The two .env checks below run against a copy with the literal string
  # ".env.example" removed — that template carries no values (see is_secret_path)
  # and must stay writable, e.g. `cat > .env.example`. Only that exact substring
  # is stripped, so `.env`, `.env.local` and `.env.playwright-secrets` still match
  # in full. Destructive-command checks above deliberately use the raw command.
  COMMAND_NO_EXAMPLE="$(printf '%s' "$COMMAND" | sed 's/\.env\.example//g')"

  # The reader has to sit at a COMMAND position (line start, or after ; && || |) and
  # the secrets file has to belong to THAT command's arguments — hence [^;&|]*
  # instead of .*. The previous pattern matched the filename anywhere later in the
  # line, so a harmless pipe into a pager followed by an unrelated echo mentioning
  # the file name in prose was blocked. A guard that blocks ordinary work gets
  # switched off, and then it protects nothing at all.
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*(cat|less|more|head|tail|cp|mv)[[:space:]]+[^;&|]*\.env([^a-zA-Z]|$)'; then
    block "refusing a command that reads/copies a .env* file — secrets never enter chat or context."
  fi
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE '>>?[[:space:]]*\.env'; then
    block "refusing a command that writes into a .env* file directly — use the vault/secrets workflow instead."
  fi
fi

exit 0

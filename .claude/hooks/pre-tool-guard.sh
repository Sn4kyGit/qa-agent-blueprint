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

# QA home discovery (0.9.1): the session may run in a subfolder of the QA
# home — the shadow gate's PROJECT.md and the preflight artifact live at the
# root. Walk up to the nearest .qa-home marker or the legacy trio.
d="$CWD"
while : ; do
  if [ -e "$d/.qa-home" ] || { [ -d "$d/projects" ] && [ -d "$d/memory" ] && [ -d "$d/evidence" ]; }; then
    CWD="$d"; break
  fi
  if { [ -n "${HOME:-}" ] && [ "$d" = "$HOME" ]; } || [ "$d" = "/" ]; then break; fi
  d="$(dirname "$d")"
done

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
  if printf '%s' "$INPUT" | sed 's/\.env\.example//g' | grep -qiE '\.env(\.|"|'"'"'|$)|\.pem|id_rsa|id_ed25519|secret|credential'; then
    block "refusing an unrecognized call touching a secrets path — failing closed."
  fi
  if printf '%s' "$INPUT" | grep -qiE 'atlassian__?[a-z]*(create|edit|add|transition|update|delete|executeWrite|executeDestructive)'; then
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

# 1b. The guard's own toggle file is a human task: an agent that can write
# .qa-guard.json can grant itself secrets_read=allow, and the toggle would be
# theater. Same philosophy as the global-MCP-config gate below.
if [ -n "$FILE_PATH" ]; then
  case "$FILE_PATH" in
    .qa-guard.json|*/.qa-guard.json)
      block "refusing to modify .qa-guard.json — the guard's own toggle is a human task (an agent that can edit it can grant itself secrets_read=allow)." ;;
  esac
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

  # The toggle file via shell: sed -i/tee/redirects/cp/mv/rm on .qa-guard.json
  # are the same self-escalation as a Write to it (check 1b).
  if printf '%s' "$COMMAND" | grep -qE '(sed[[:space:]]+(-[a-zA-Z]*i[a-zA-Z.]*|--in-place)|tee[[:space:]]|>>?|cp[[:space:]]|mv[[:space:]]|rm[[:space:]]|truncate|dd[[:space:]])[^;&|]*\.qa-guard\.json'; then
    block "refusing to modify .qa-guard.json — the guard's own toggle is a human task (an agent that can edit it can grant itself secrets_read=allow)."
  fi

  # rm hardening (0.11.0, tdd §9/F2): deleting a secrets file is a human
  # task. Plain `rm <.env*>` (and rm -f) used to sail through — only rm -rf
  # was blocked. Blocked regardless of the secrets_read toggle.
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*rm[[:space:]]+(-[a-zA-Z]+[[:space:]]+)*[^;&|]*\.env([^a-zA-Z]|$)'; then
    block "refusing to delete a .env* file — removing a secrets file is a human task (blocked regardless of secrets_read)."
  fi

  # cp/mv are NOT readers (tdd §8/F1): they relocate the secrets file out of
  # its protected context. Blocked in BOTH toggle states.
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*(cp|mv)[[:space:]]+[^;&|]*\.env([^a-zA-Z]|$)'; then
    block "refusing to copy/move a .env* file — secrets never leave their protected file (blocked regardless of secrets_read)."
  fi

  # sed -i / awk -i edit in place — a WRITE, not a read (tdd §8/F1). The flag
  # must sit directly after the command: `-i`, `-i.bak`, `--in-place`,
  # `-i inplace`. A -i *string* inside the sed script is a rare accepted
  # false positive (fail closed beats a write slipping through as a "read").
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*(sed|awk)[[:space:]]+(-[a-zA-Z]*i[a-zA-Z.]*|--in-place)[[:space:]][^;&|]*\.env([^a-zA-Z]|$)'; then
    block "refusing an in-place edit of a .env* file — sed -i / awk -i is a write, not a read (blocked regardless of secrets_read)."
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
  if [ "$SECRETS_READ" != "allow" ] && printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*(cat|less|more|head|tail|grep|sed|awk|jq|source)[[:space:]]+[^;&|]*\.env([^a-zA-Z]|$)'; then
    block "refusing a command that reads a .env* file — secrets never enter chat or context by default. To check which keys exist: resolve-secrets.sh --status. Direct reads are a comfort opt-in: secrets_read=allow in .qa-guard.json (a human task — the guard refuses edits to it)."
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
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE '(python3?|perl|ruby|node|php)[[:space:]][^;&|]*(open|read|load|require|include|slurp)[^;&|]*\.env([^a-zA-Z]|$)'; then
    block "refusing a command that appears to read a .env* file via an interpreter — interpreter payloads cannot be classified read-vs-write reliably, so this class stays blocked even with secrets_read=allow. To check which keys exist: resolve-secrets.sh --status."
  fi
  if printf '%s' "$COMMAND_NO_EXAMPLE" | grep -qE '>>?[[:space:]]*\.env'; then
    block "refusing a command that writes into a .env* file directly — use the vault/secrets workflow instead."
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
      fi ;;
    mcp__*__*)
      # Server = everything between mcp__ and the LAST __ (plugin-namespaced
      # servers like plugin_qa-agent-blueprint_atlassian survive this).
      SERVER="$(printf '%s' "$TOOL_NAME" | sed -E 's/^mcp__//; s/__[^_]*$//')"
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
if printf '%s' "$TOOL_NAME" | grep -qiE '^mcp__([a-zA-Z0-9-]+(_[a-zA-Z0-9-]+)*_+)?atlassian__.*(create|edit|add|transition|update|delete|executeWrite|executeDestructive)'; then
  if [ "${QA_AGENT_SHADOW:-1}" != "0" ]; then
    ISSUE_KEY="$(get_json 'import re; m = re.search(r"[A-Z][A-Z0-9]+-[0-9]+", json.dumps(d.get("tool_input") or {})); print(m.group(0) if m else "")')"
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

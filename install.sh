#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit

#
# install.sh — Installer for the QA Agent Blueprint.
#
# Principle: Detect → Merge → Report. Never overwrite, always back up,
# idempotent, dry-run capable.
#
# Modes:
#   integrate   Merge the blueprint non-destructively into the target repo
#               (own CLAUDE.md / .claude/ / .mcp.json / hooks / browsers).
#               Running it with the blueprint repo itself as target is the
#               "self-setup" case: nothing is copied (the files already ARE the
#               blueprint), only the environment is prepared.
#   plugin      Copy nothing — print instructions for using this repo as a
#               Claude Code plugin via .claude-plugin/marketplace.json.
#   (default)   Auto-detect: target == blueprint repo → integrate (self-setup);
#               target with CLAUDE.md/.claude//.git → integrate is proposed
#               (interactive prompt unless --yes).
#
# Usage:
#   ./install.sh [--mode integrate|plugin|opencode|shared] [--target <path>]
#                [--wizard|--no-wizard] [--jira cloud|datacenter --jira-url <url>]
#                [--browser headless|headful] [--model-setup now|later|skip]
#                [--cheap <provider/model>] [--standard <provider/model>] [--deep <provider/model>]
#                [--cheap-variant <v>] [--standard-variant <v>] [--deep-variant <v>]
#                [--skill-profile full|standard|minimal|custom] [--skills-exclude "a,b"]
#                [--dry-run] [--yes] [--uninstall] [--move <new-target>]
#                [--non-interactive] [-h|--help]
#
# --move (opencode mode only): relocate an existing QA home — moves the data
#   (projects/, memory/, evidence/, seed files, opencode.json) to <new-target>,
#   links the blueprint surface there, and unlinks it from --target. Use when
#   the installer went into the wrong folder (e.g. ~/qa-workspace instead of
#   the project workspace). Never overwrites existing files in <new-target>.
#
# --skill-profile / --skills-exclude (integrate mode only): choose which blueprint
#   skills land in the target; the choice persists in the target's
#   .qa-skill-profile.json (consumer-owned JSON, backed up on every change) and is
#   re-applied on update/reinstall. custom freezes an allowlist (from the file's
#   "allowlist", else the resolved --skills-exclude selection, persisted). Without
#   the flags — and without that file — every skill is copied, as always.
#   Dependencies are added automatically: test-ticket/retest-bug ->
#   failure-analysis -> report-to-jira -> retro-learn, qa-report and qa-help
#   always, webdriverio-testing unless the file says "framework": "playwright",
#   and the feature-matrix specialists (or the file's "matrix_active" list).
#
# Detection checks (all reported FOUND/MISSING/MERGED/SKIPPED):
#   1. node/npm + minimum version (>= 18)
#   2. claude CLI + version
#   3. Playwright browsers already installed? -> skip browser download
#   4. Existing CLAUDE.md in target? -> managed block appended, never overwritten
#   5. Existing .claude/? -> namespaced copy with per-file collision checks
#   6. Existing .mcp.json? -> JSON merge, existing server names win
#   7. Existing .claude/settings.json? -> permissions/hooks merged, deduplicated
#   8. Existing .gitignore? -> only missing entries, as managed block
#   9. evidence/, memory/, projects/ -> created if missing, untouched if present
#  10. Plugin mode -> instructions only
#
set -euo pipefail

# --- colored status output ---------------------------------------------------
if [ -t 1 ]; then
  C_OK="\033[0;32m"; C_WARN="\033[0;33m"; C_ERR="\033[0;31m"; C_INFO="\033[0;34m"; C_DIM="\033[0;90m"; C_RST="\033[0m"
else
  C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_DIM=""; C_RST=""
fi
ok()   { printf "%b[ OK ]%b %s\n"  "$C_OK"   "$C_RST" "$*"; }
warn() { printf "%b[WARN]%b %s\n"  "$C_WARN" "$C_RST" "$*"; }
err()  { printf "%b[FAIL]%b %s\n"  "$C_ERR"  "$C_RST" "$*" >&2; }
info() { printf "%b[INFO]%b %s\n"  "$C_INFO" "$C_RST" "$*"; }
dry()  { printf "%b[DRY ]%b %s\n"  "$C_DIM"  "$C_RST" "$*"; }

usage() {
  sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d; s/^# \{0,1\}//'
  exit 0
}

# --- argument parsing ----------------------------------------------------------
MODE=""
MODE_EXPLICIT=0
TARGET="$PWD"
TARGET_EXPLICIT=0
DRY_RUN=0
YES=0
UNINSTALL=0
MOVE_TO=""
WIZARD_DISABLED=0
WIZARD_FORCE=0
PREFS_REQUESTED=0
JIRA_KIND=""
JIRA_URL=""
BROWSER_MODE=""
MODEL_SETUP_MODE=""
MODEL_CHEAP=""
MODEL_STANDARD=""
MODEL_DEEP=""
MODEL_CHEAP_VARIANT=""
MODEL_STANDARD_VARIANT=""
MODEL_DEEP_VARIANT=""
SKILL_PROFILE=""
SKILL_PROFILE_FLAG=0
SKILLS_EXCLUDE_RAW=""
SKILLS_EXCLUDE_FLAG=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)             MODE="${2:?--mode needs a value}"; MODE_EXPLICIT=1; shift 2 ;;
    --mode=*)           MODE="${1#*=}"; MODE_EXPLICIT=1; shift ;;
    --target)           TARGET="${2:?--target needs a path}"; TARGET_EXPLICIT=1; shift 2 ;;
    --target=*)         TARGET="${1#*=}"; TARGET_EXPLICIT=1; shift ;;
    --wizard)           WIZARD_FORCE=1; shift ;;
    --no-wizard)        WIZARD_DISABLED=1; shift ;;
    --jira)             JIRA_KIND="${2:?--jira needs cloud|datacenter}"; shift 2 ;;
    --jira=*)           JIRA_KIND="${1#*=}"; shift ;;
    --jira-url)         JIRA_URL="${2:?--jira-url needs a URL}"; shift 2 ;;
    --jira-url=*)       JIRA_URL="${1#*=}"; shift ;;
    --browser)          BROWSER_MODE="${2:?--browser needs headless|headful}"; shift 2 ;;
    --browser=*)        BROWSER_MODE="${1#*=}"; shift ;;
    --model-setup)      MODEL_SETUP_MODE="${2:?--model-setup needs now|later|skip}"; shift 2 ;;
    --model-setup=*)    MODEL_SETUP_MODE="${1#*=}"; shift ;;
    --cheap)            MODEL_CHEAP="${2:?--cheap needs provider/model}"; shift 2 ;;
    --cheap=*)          MODEL_CHEAP="${1#*=}"; shift ;;
    --standard)         MODEL_STANDARD="${2:?--standard needs provider/model}"; shift 2 ;;
    --standard=*)       MODEL_STANDARD="${1#*=}"; shift ;;
    --deep)             MODEL_DEEP="${2:?--deep needs provider/model}"; shift 2 ;;
    --deep=*)           MODEL_DEEP="${1#*=}"; shift ;;
    --cheap-variant)    MODEL_CHEAP_VARIANT="${2:-}"; shift 2 ;;
    --cheap-variant=*)  MODEL_CHEAP_VARIANT="${1#*=}"; shift ;;
    --standard-variant) MODEL_STANDARD_VARIANT="${2:-}"; shift 2 ;;
    --standard-variant=*) MODEL_STANDARD_VARIANT="${1#*=}"; shift ;;
    --deep-variant)     MODEL_DEEP_VARIANT="${2:-}"; shift 2 ;;
    --deep-variant=*)   MODEL_DEEP_VARIANT="${1#*=}"; shift ;;
    --skill-profile)    SKILL_PROFILE="${2:?--skill-profile needs a value}"; SKILL_PROFILE_FLAG=1; shift 2 ;;
    --skill-profile=*)  SKILL_PROFILE="${1#*=}"; SKILL_PROFILE_FLAG=1; shift ;;
    --skills-exclude)   SKILLS_EXCLUDE_RAW="${2:?--skills-exclude needs a value}"; SKILLS_EXCLUDE_FLAG=1; shift 2 ;;
    --skills-exclude=*) SKILLS_EXCLUDE_RAW="${1#*=}"; SKILLS_EXCLUDE_FLAG=1; shift ;;
    --dry-run)          DRY_RUN=1; shift ;;
    --yes|-y)           YES=1; shift ;;
    --non-interactive)  YES=1; shift ;;  # backwards-compatible alias
    --uninstall)        UNINSTALL=1; shift ;;
    --move)             MOVE_TO="${2:?--move needs a path}"; shift 2 ;;
    --move=*)           MOVE_TO="${1#*=}"; shift ;;
    -h|--help)          usage ;;
    *) err "Unknown argument: $1 (see --help)"; exit 1 ;;
  esac
done

if [ -n "$JIRA_KIND" ] || [ -n "$JIRA_URL" ] || [ -n "$BROWSER_MODE" ] || [ -n "$MODEL_SETUP_MODE" ] || [ -n "$MODEL_CHEAP" ] || [ -n "$MODEL_STANDARD" ] || [ -n "$MODEL_DEEP" ] || [ -n "$MODEL_CHEAP_VARIANT" ] || [ -n "$MODEL_STANDARD_VARIANT" ] || [ -n "$MODEL_DEEP_VARIANT" ]; then
  PREFS_REQUESTED=1
fi

case "$MODE" in
  ""|integrate|plugin|opencode|shared) ;;
  *) err "Invalid --mode '$MODE' (expected integrate|plugin|opencode|shared)"; exit 1 ;;
esac
case "$JIRA_KIND" in
  ""|cloud|datacenter) ;;
  *) err "Invalid --jira '$JIRA_KIND' (expected cloud|datacenter)"; exit 1 ;;
esac
case "$BROWSER_MODE" in
  ""|headless|headful) ;;
  *) err "Invalid --browser '$BROWSER_MODE' (expected headless|headful)"; exit 1 ;;
esac
case "$MODEL_SETUP_MODE" in
  ""|now|later|skip) ;;
  *) err "Invalid --model-setup '$MODEL_SETUP_MODE' (expected now|later|skip)"; exit 1 ;;
esac
case "$SKILL_PROFILE" in
  ""|full|standard|minimal|custom) ;;
  *) err "Invalid --skill-profile '$SKILL_PROFILE' (expected full|standard|minimal|custom)"; exit 1 ;;
esac
if [ -n "$JIRA_URL" ] && [ "$JIRA_KIND" != "datacenter" ]; then
  err "--jira-url requires --jira datacenter"
  exit 1
fi
if [ -n "$JIRA_URL" ]; then
  case "$JIRA_URL" in
    http://*|https://*) ;;
    *) err "--jira-url must start with http:// or https://"; exit 1 ;;
  esac
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$TARGET_EXPLICIT" -eq 1 ] && [ ! -d "$TARGET" ]; then
  err "Target directory does not exist: $TARGET"
  exit 1
fi
TS="$(date +%Y%m%d-%H%M%S)"
WIZARD_ACTIVE=0
source "$REPO_ROOT/install/wizard.sh"

# Managed-block markers (fixed strings, matched with index() / grep -F)
CLAUDE_BLOCK_START='<!-- >>> qa-agent-blueprint (managed, do not edit) -->'
CLAUDE_BLOCK_END='<!-- <<< qa-agent-blueprint -->'
GITIGNORE_BLOCK_START='# >>> qa-agent-blueprint (managed, do not edit)'
GITIGNORE_BLOCK_END='# <<< qa-agent-blueprint'

# Namespaces used when merging into an existing .claude/
NS_RULES=".claude/rules/qa-blueprint"
NS_HOOKS=".claude/hooks/qa-blueprint"

# --- report collector ------------------------------------------------------------
REPORT=()
NEXT_STEPS=()
report() { # <STATUS> <area> <detail>
  local status="$1" area="$2" detail="$3"
  REPORT+=("$status|$area|$detail")
  case "$status" in
    FOUND|ADDED|BACKUP|OK)          ok    "$area — $detail" ;;
    MERGED)                         ok    "$area — $detail" ;;
    SKIPPED)                        info  "$area — $detail" ;;
    MISSING|WARN)                   warn  "$area — $detail" ;;
    DRY-RUN)                        dry   "$area — $detail" ;;
    *)                              info  "$area — $detail" ;;
  esac
}
next_step() { # deduplicated
  local s
  for s in ${NEXT_STEPS[@]+"${NEXT_STEPS[@]}"}; do [ "$s" = "$1" ] && return 0; done
  NEXT_STEPS+=("$1")
}

# --- helpers ---------------------------------------------------------------------
backup_file() { # <file> — create .bak-<timestamp> copy; no-op in dry-run
  local f="$1"
  [ -f "$f" ] || return 0
  if [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN "backup" "would create $f.bak-$TS"
    return 0
  fi
  cp -p "$f" "$f.bak-$TS"
  report BACKUP "backup" "$f → $f.bak-$TS"
}

# Strip trailing blank lines from a file (in place)
strip_trailing_blank_lines() {
  local f="$1"
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$f" <<'PY'
import sys
p = sys.argv[1]
with open(p) as fh:
    content = fh.read()
with open(p, "w") as fh:
    fh.write(content.rstrip("\n") + "\n")
PY
}

# Remove a fixed-string-delimited block from a file (in place, caller backs up)
remove_block() { # <file> <start-marker> <end-marker>
  local f="$1" s="$2" e="$3" tmp
  tmp="$(mktemp)"
  awk -v s="$s" -v e="$e" '
    index($0, s) { skip=1; next }
    index($0, e) { skip=0; next }
    !skip
  ' "$f" > "$tmp"
  cat "$tmp" > "$f"
  rm -f "$tmp"
}

# Copy a directory tree only where files differ; per-file idempotency.
# Echoes report lines via report(). $3 = label for the report.
ADDED_FILES=()   # every file this run actually wrote — the rewrite pass below
                 # touches only these, never a file that was yours already.

copy_tree() { # <src-dir> <dest-dir> <label>
  local src="$1" dest="$2" label="$3" f rel
  if [ ! -d "$src" ]; then
    report SKIPPED "$label" "no blueprint $label found — nothing to copy"
    return 0
  fi
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    if [ -e "$dest/$rel" ]; then
      # Compare against the rewritten form: a previous run namespaced the internal
      # path references, so a raw compare would flag every file as a collision.
      if source_matches_installed "$f" "$dest/$rel"; then
        report SKIPPED "$label" "$rel already integrated (identical)"
      else
        report WARN "$label" "collision: $rel exists with different content — kept yours"
      fi
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        report DRY-RUN "$label" "would add $dest/$rel"
      else
        mkdir -p "$(dirname "$dest/$rel")"
        cp -p "$f" "$dest/$rel"
        case "$rel" in *.sh) chmod +x "$dest/$rel";; esac
        ADDED_FILES+=("$dest/$rel")
        report ADDED "$label" "$rel"
      fi
    fi
  done < <(find "$src" -type f -print0)
}

# Integrate mode namespaces rules and hooks (so they cannot collide with yours),
# but the copied files are full of references to the ORIGINAL paths — about 70 of
# them across rules, skills, agents and hooks. Without this pass every
# "see .claude/rules/core/security.md" inside the integrated copy points at a file
# that does not exist in the target repo, and the agent silently loses the details
# behind every rule. Same for docs/, which is namespaced under docs/qa-blueprint/.
# Single source of truth for the substitutions. Used twice: once when copying, and
# again by the uninstaller, which compares a copied file against the blueprint
# source — that comparison only holds if both sides agree on what a rewritten file
# looks like. Every pattern is written so a second pass is a no-op (see the
# lookaheads), because install is expected to be idempotent.
rewrite_py() {
  cat <<'PY'
import os, re, sys

ns_rules = os.environ["QA_NS_RULES"]   # .claude/rules/qa-blueprint
ns_hooks = os.environ["QA_NS_HOOKS"]   # .claude/hooks/qa-blueprint

subs = [
    (r'\.claude/rules/(?!qa-blueprint/)', ns_rules + "/"),
    (r'\.claude/hooks/(?!qa-blueprint/)', ns_hooks + "/"),
    (r'docs/(?!qa-blueprint/)(architecture\.md|integration\.md|artifact-strategy\.md|memory-layers\.md|runbooks/|rules/|pipeline/)',
     r'docs/qa-blueprint/\1'),
]

def rewrite(text):
    for pattern, repl in subs:
        text = re.sub(pattern, repl, text)
    return text

# Both modes must agree on WHICH files get rewritten. When only the in-place pass
# skipped .py/.ts while the compare rewrote them, every skill shipping a script
# looked "modified" on the second run and on uninstall.
REWRITABLE = (".md", ".sh", ".json", ".py", ".ts")

mode = sys.argv[1]
if mode == "stdout":
    path = sys.argv[2]
    # Non-rewritable files (e.g. PDFs in docs/) must pass through as raw bytes:
    # reading them as UTF-8 raises UnicodeDecodeError, the caller's pipe then
    # compares EMPTY output against the installed file and every binary file
    # looked "modified" — breaking second-run idempotency and uninstall
    # (field report 2026-09-18, after PDFs landed in docs/).
    if not path.endswith(REWRITABLE):
        with open(path, "rb") as fh:
            sys.stdout.buffer.write(fh.read())
    else:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        sys.stdout.write(rewrite(text))
else:
    changed = 0
    for path in sys.argv[2:]:
        if not path.endswith(REWRITABLE):
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            continue
        out = rewrite(text)
        if out != text:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(out)
            changed += 1
    print(changed)
PY
}

# cp -r copies a whole tree in one call, so the files never pass through copy_tree
# and would miss the path-rewrite pass. Register them explicitly — skills and agents
# reference the rules by path just as heavily as the rules reference each other.
register_copied_dir() { # <dest-dir>
  local d="$1" f
  [ -d "$d" ] || return 0
  while IFS= read -r -d '' f; do
    ADDED_FILES+=("$f")
  done < <(find "$d" -type f -print0)
}

# True when the installed file is what this blueprint would have written — i.e. the
# source after the namespacing rewrite. Falls back to a plain compare when python3
# is unavailable (then nothing was rewritten either, so the raw compare is right).
source_matches_installed() { # <blueprint-source-file> <installed-file>
  if command -v python3 >/dev/null 2>&1; then
    QA_NS_RULES="$NS_RULES" QA_NS_HOOKS="$NS_HOOKS" \
      python3 -c "$(rewrite_py)" stdout "$1" 2>/dev/null | cmp -s - "$2"
  else
    cmp -s "$1" "$2"
  fi
}

# Directory equivalent of source_matches_installed: every source file must exist in
# the installed copy and match its rewritten form, and the copy must contain nothing
# extra. Used by uninstall on skills/agents, which are whole directories.
source_dir_matches_installed() { # <blueprint-source-dir> <installed-dir>
  local src="$1" dst="$2" f rel
  # Callers pass paths from a `*/` glob, i.e. WITH a trailing slash. Without
  # stripping it, "${f#"$src"/}" never matches and every file looks missing — which
  # showed up as "a different skill with this name already exists" on every re-run.
  src="${src%/}"; dst="${dst%/}"
  [ -d "$src" ] && [ -d "$dst" ] || return 1
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    [ -f "$dst/$rel" ] || return 1
    source_matches_installed "$f" "$dst/$rel" || return 1
  done < <(find "$src" -type f -print0)
  # nothing added on the installed side
  [ "$(find "$src" -type f | wc -l | tr -d ' ')" = "$(find "$dst" -type f | wc -l | tr -d ' ')" ]
}

rewrite_namespaced_paths() {
  [ "${#ADDED_FILES[@]}" -gt 0 ] || return 0
  command -v python3 >/dev/null 2>&1 || {
    report WARN "paths" "python3 missing — internal path references in the copied files still point at un-namespaced paths"
    return 0
  }
  local n
  n="$(QA_NS_RULES="$NS_RULES" QA_NS_HOOKS="$NS_HOOKS" \
       python3 -c "$(rewrite_py)" inplace "${ADDED_FILES[@]}")"
  if [ "${n:-0}" -gt 0 ]; then
    report MERGED "paths" "$n copied file(s) rewritten to the namespaced rule/hook/docs paths"
  else
    report SKIPPED "paths" "no internal path references needed rewriting"
  fi
}

have_json_tool() { command -v python3 >/dev/null 2>&1 || command -v jq >/dev/null 2>&1; }

# --- 1/2. prerequisites ----------------------------------------------------------
check_prereqs() {
  info "Checking prerequisites..."
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -v | sed 's/^v//' | cut -d. -f1)"
    if [ "$major" -ge 18 ]; then
      report FOUND "node" "$(node -v) (>= 18 required)"
    else
      report MISSING "node" "$(node -v) found, but >= 18 is required — https://nodejs.org"
      exit 1
    fi
  else
    report MISSING "node" "not found — install Node.js LTS (>= 18): https://nodejs.org"
    exit 1
  fi

  if command -v npm >/dev/null 2>&1; then
    report FOUND "npm" "$(npm -v)"
  else
    report MISSING "npm" "not found (should ship with Node)"
    exit 1
  fi

  # `command -v` alone reports MISSING for every install that isn't on the PATH of
  # this (often non-interactive) shell — the native installer's ~/.local/bin/claude
  # being the common case. Check the known locations before claiming it's absent,
  # so the "install Claude Code" next-step isn't a false alarm.
  local claude_bin=""
  if command -v claude >/dev/null 2>&1; then
    claude_bin="$(command -v claude)"
  else
    local c
    for c in "${CLAUDE_CODE_EXECPATH:-}" "$HOME/.local/bin/claude" \
             "$HOME/.claude/local/claude" "/usr/local/bin/claude" \
             "/opt/homebrew/bin/claude"; do
      [ -n "$c" ] && [ -x "$c" ] && { claude_bin="$c"; break; }
    done
  fi

  if [ -n "$claude_bin" ]; then
    local ver
    ver="$("$claude_bin" --version 2>/dev/null || echo 'version unknown')"
    case ":$PATH:" in
      *":$(dirname "$claude_bin"):"*) report FOUND "claude CLI" "$ver" ;;
      *) report FOUND "claude CLI" "$ver at $claude_bin (not on this shell's PATH)" ;;
    esac
  else
    report MISSING "claude CLI" "not found in PATH or the usual install locations"
    if [ "$YES" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
      printf "Install Claude Code globally now (npm i -g @anthropic-ai/claude-code)? [y/N] "
      read -r answer
      if [ "$answer" = "y" ] || [ "$answer" = "Y" ]; then
        npm i -g @anthropic-ai/claude-code
        report ADDED "claude CLI" "installed via npm"
      else
        next_step "Install Claude Code: npm i -g @anthropic-ai/claude-code"
      fi
    else
      next_step "Install Claude Code: npm i -g @anthropic-ai/claude-code"
    fi
  fi
}

# A pipeline trigger is a Bash command from the project file, not an MCP server —
# but if neither CLI is present, /deploy-to-stage will end BLOCKED on its preflight,
# and it is friendlier to say so now than mid-ticket.
check_ci_cli() {
  local found=""
  command -v gh   >/dev/null 2>&1 && found="$found gh"
  command -v glab >/dev/null 2>&1 && found="$found glab"
  if [ -n "$found" ]; then
    report FOUND "CI CLI" "${found# } — usable as a deploy trigger if your project declares one"
  else
    report SKIPPED "CI CLI" "no gh/glab found — fine unless a project's deploy trigger needs one (/deploy-to-stage reports BLOCKED then)"
  fi
}

# --- 3. Playwright browsers ------------------------------------------------------
playwright_browsers_present() {
  local d
  for d in "$HOME/.cache/ms-playwright" "$HOME/Library/Caches/ms-playwright"; do
    if [ -d "$d" ] && { compgen -G "$d/chromium-*" >/dev/null || compgen -G "$d/chromium_headless_shell-*" >/dev/null; }; then
      return 0
    fi
  done
  return 1
}

setup_playwright() {
  local pw_ver=""
  pw_ver="$(npx --no-install playwright --version 2>/dev/null || true)"
  if playwright_browsers_present; then
    report FOUND "playwright" "Chromium already in browser cache${pw_ver:+ (CLI $pw_ver)}"
    report SKIPPED "playwright" "browser install skipped — browsers already present"
    return 0
  fi
  report MISSING "playwright" "no Chromium in ~/.cache/ms-playwright / ~/Library/Caches/ms-playwright"
  if [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN "playwright" "would run: npx --yes playwright install chromium"
    return 0
  fi
  if npx --yes playwright install chromium; then
    report ADDED "playwright" "Chromium installed (npx playwright install chromium)"
  else
    report WARN "playwright" "install failed — on Linux try: npx playwright install --with-deps chromium"
    next_step "Install Playwright browser: npx playwright install --with-deps chromium"
  fi
}

# --- auto-detect mode --------------------------------------------------------------
autodetect_mode() {
  [ -z "$MODE" ] || return 0
  local signals=""
  [ "$TARGET" != "$REPO_ROOT" ] || { MODE="integrate"; return 0; }  # self-setup: see run_integrate
  [ -f "$TARGET/CLAUDE.md" ] && signals="$signals CLAUDE.md"
  [ -d "$TARGET/.claude" ]   && signals="$signals .claude/"
  [ -d "$TARGET/.git" ]      && signals="$signals .git/"
  if [ -n "$signals" ]; then
    if [ "$YES" -eq 1 ] || [ -n "${CI:-}" ] || [ ! -t 0 ]; then
      MODE="integrate"
      info "Auto-detected existing ecosystem (${signals# }) → mode=integrate"
    else
      # Two real options, so ask which one instead of assuming. The difference is
      # not cosmetic — it decides whether the blueprint's logic is versioned in the
      # user's repo or updated centrally from the plugin cache — and it is easier to
      # choose now than to switch later.
      info "Existing ecosystem detected in $TARGET:$signals"
      echo
      echo "  How do you want the blueprint in this repo?"
      echo
      echo "    1) integrate  Copy rules, skills, agents and hooks into this repo,"
      echo "                  namespaced so nothing of yours is overwritten."
      echo "                  → reviewable and editable by your team, versioned in"
      echo "                    your own commits. Updates are a re-run of this script."
      echo
      echo "    2) plugin     Copy nothing. Rules, skills, agents and hooks load from"
      echo "                  the plugin; only your own data (projects/, memory/,"
      echo "                  evidence/) lives here."
      echo "                  → zero footprint, central updates via /plugin, commands"
      echo "                    are namespaced (/qa-agent-blueprint:test-ticket)."
      echo
      printf "  Choose [1/2, default 1]: "
      read -r answer
      case "$answer" in
        2|p|plugin) MODE="plugin" ;;
        *)          MODE="integrate" ;;
      esac
    fi
  else
    # No ecosystem detected — an empty repo is a fine integrate target (it gets
    # a fresh CLAUDE.md managed block) and a fine plugin target, so offer both.
    if [ "$YES" -eq 1 ] || [ -n "${CI:-}" ] || [ ! -t 0 ]; then
      MODE="integrate"
    else
      printf "No existing Claude Code setup found here. Integrate the blueprint into this directory, or use it as a plugin? [I/p] "
      read -r answer
      case "$answer" in
        p|P|plugin) MODE="plugin" ;;
        *)          MODE="integrate" ;;
      esac
    fi
  fi
  info "Mode: $MODE (target: $TARGET)"
}

SKILL_PROFILE_FILE_NAME=".qa-skill-profile.json"
SKILL_SELECTION_ACTIVE=0
SKILL_PROFILE_EFF=""
ACTIVE_SKILLS=""
SKILL_FORCED_ALWAYS="qa-report qa-help"
SKILL_SPECIALISTS="risk-based-testing bug-reproduction api-testing accessibility-testing security-testing visual-testing test-reliability qa-metrics test-case-management release-readiness"
SKILL_STANDARD_EXCLUDES="agentswitch model-setup whats-new re-board demo scaffold-suite"
SKILL_MINIMAL_EXCLUDES="$SKILL_STANDARD_EXCLUDES recon deploy-to-stage onboard-product onboard-project exploratory-testing"

skill_list_contains() {
  local item
  for item in $2; do [ "$item" = "$1" ] && return 0; done
  return 1
}

skill_is_active() {
  skill_list_contains "$1" "$ACTIVE_SKILLS"
}

skill_dep_closure() {
  case "$1" in
    test-ticket|retest-bug) echo "failure-analysis report-to-jira retro-learn" ;;
    failure-analysis)       echo "report-to-jira retro-learn" ;;
    report-to-jira)         echo "retro-learn" ;;
  esac
}

skill_profile_read() {
  PF_PROFILE=""; PF_EXCLUDES=""; PF_ALLOWLIST=""; PF_FRAMEWORK=""; PF_MATRIX=""
  [ -f "$1" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  local out
  out="$(python3 - "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        d = json.load(fh)
    if not isinstance(d, dict):
        raise ValueError
except Exception:
    sys.exit(1)
def joined(key):
    return " ".join(str(x).strip() for x in (d.get(key) or []) if str(x).strip())
print(d.get("profile") or "")
print(joined("exclude"))
print(joined("allowlist"))
print(d.get("framework") or "")
print(joined("matrix_active"))
PY
)" || return 1
  PF_PROFILE="$(printf '%s\n' "$out" | sed -n 1p)"
  PF_EXCLUDES="$(printf '%s\n' "$out" | sed -n 2p)"
  PF_ALLOWLIST="$(printf '%s\n' "$out" | sed -n 3p)"
  PF_FRAMEWORK="$(printf '%s\n' "$out" | sed -n 4p)"
  PF_MATRIX="$(printf '%s\n' "$out" | sed -n 5p)"
  return 0
}

skill_profile_write() {
  local f="$TARGET/$SKILL_PROFILE_FILE_NAME"
  if [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN "skills" "would persist selection to $SKILL_PROFILE_FILE_NAME (profile: $1)"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    report WARN "skills" "python3 missing — $SKILL_PROFILE_FILE_NAME not written (selection applied for this run)"
    return 0
  fi
  if ! PF_WP="$1" PF_WE="$2" PF_WA="$3" PF_TS="$TS" python3 - "$f" <<'PY' | consume_report_lines
import datetime, json, os, shutil, sys
path = sys.argv[1]
old = {}
if os.path.exists(path):
    try:
        with open(path, encoding="utf-8") as fh:
            old = json.load(fh)
        if not isinstance(old, dict):
            old = {}
    except Exception:
        old = {}
def split(v):
    return [s.strip() for s in (v or "").replace(",", " ").split() if s.strip()]
data = dict(old)
data["profile"] = os.environ.get("PF_WP", "")
for key, env in (("exclude", "PF_WE"), ("allowlist", "PF_WA")):
    vals = split(os.environ.get(env))
    if vals:
        data[key] = vals
    else:
        data.pop(key, None)
def norm(d):
    return {k: v for k, v in d.items() if k != "updated_at"}
base = os.path.basename(path)
stamp = os.environ.get("PF_TS", "bak")
if os.path.exists(path) and norm(old) == norm(data):
    print("SKIPPED|skills|" + base + " unchanged — kept as is")
    sys.exit(0)
if os.path.exists(path):
    shutil.copy2(path, path + ".bak-" + stamp)
    print("BACKUP|backup|" + path + " → " + path + ".bak-" + stamp)
data["updated_at"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
with open(path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
print(("ADDED" if not old else "MERGED") + "|skills|" + base + " written (profile: " + data["profile"] + ")")
PY
  then
    report WARN "skills" "could not persist $SKILL_PROFILE_FILE_NAME (selection applied for this run)"
  fi
  return 0
}

skill_selection_resolve() {
  SKILL_SELECTION_ACTIVE=1
  local f="$TARGET/$SKILL_PROFILE_FILE_NAME"
  PF_PROFILE=""; PF_EXCLUDES=""; PF_ALLOWLIST=""; PF_FRAMEWORK=""; PF_MATRIX=""
  if [ -f "$f" ]; then
    if ! skill_profile_read "$f"; then
      report WARN "skills" "$SKILL_PROFILE_FILE_NAME present but unreadable — ignored"
    fi
  fi
  local profile excludes_csv allowlist_csv framework matrix
  if [ "$SKILL_PROFILE_FLAG" -eq 1 ] || [ "$SKILLS_EXCLUDE_FLAG" -eq 1 ]; then
    profile="${SKILL_PROFILE:-${PF_PROFILE:-full}}"
    excludes_csv=""
    if [ "$SKILLS_EXCLUDE_FLAG" -eq 1 ]; then excludes_csv="$SKILLS_EXCLUDE_RAW"; fi
    allowlist_csv="${PF_ALLOWLIST// /,}"
    framework="$PF_FRAMEWORK"
    matrix="$PF_MATRIX"
  elif [ -f "$f" ]; then
    profile="$PF_PROFILE"
    excludes_csv="${PF_EXCLUDES// /,}"
    allowlist_csv="${PF_ALLOWLIST// /,}"
    framework="$PF_FRAMEWORK"
    matrix="$PF_MATRIX"
  else
    SKILL_SELECTION_ACTIVE=0
    return 0
  fi
  case "$profile" in
    full|standard|minimal|custom) ;;
    *) report WARN "skills" "unknown profile '$profile' — treating as full"; profile="full" ;;
  esac
  local excludes allowlist matrix_list
  excludes="${excludes_csv//,/ }"
  allowlist="${allowlist_csv//,/ }"
  matrix_list="${matrix//,/ }"
  local all="" name s
  for s in "$REPO_ROOT/.claude/skills"/*/; do
    [ -d "$s" ] || continue
    all="$all $(basename "$s")"
  done
  local base_active=""
  for name in $all; do
    if [ "$profile" = "custom" ]; then
      if [ -n "$allowlist" ]; then
        skill_list_contains "$name" "$allowlist" || continue
      fi
    else
      case "$profile" in
        standard) if skill_list_contains "$name" "$SKILL_STANDARD_EXCLUDES"; then continue; fi ;;
        minimal)  if skill_list_contains "$name" "$SKILL_MINIMAL_EXCLUDES"; then continue; fi ;;
      esac
    fi
    if skill_list_contains "$name" "$excludes"; then continue; fi
    base_active="$base_active $name"
  done
  ACTIVE_SKILLS="$base_active"
  local grew=1 dep added=""
  while [ "$grew" -eq 1 ]; do
    grew=0
    for name in $ACTIVE_SKILLS; do
      for dep in $(skill_dep_closure "$name"); do
        if [ -d "$REPO_ROOT/.claude/skills/$dep" ] && ! skill_list_contains "$dep" "$ACTIVE_SKILLS"; then
          ACTIVE_SKILLS="$ACTIVE_SKILLS $dep"
          added="$added $dep"
          grew=1
        fi
      done
    done
  done
  for name in $SKILL_FORCED_ALWAYS; do
    if [ -d "$REPO_ROOT/.claude/skills/$name" ] && ! skill_list_contains "$name" "$ACTIVE_SKILLS"; then
      ACTIVE_SKILLS="$ACTIVE_SKILLS $name"
      added="$added $name"
    fi
  done
  if [ "${framework:-}" != "playwright" ] && [ -d "$REPO_ROOT/.claude/skills/webdriverio-testing" ] && ! skill_list_contains "webdriverio-testing" "$ACTIVE_SKILLS"; then
    ACTIVE_SKILLS="$ACTIVE_SKILLS webdriverio-testing"
    added="$added webdriverio-testing"
  fi
  local specialists="$SKILL_SPECIALISTS"
  if [ -n "$matrix_list" ]; then specialists="$matrix_list"; fi
  for name in $specialists; do
    if [ -d "$REPO_ROOT/.claude/skills/$name" ] && ! skill_list_contains "$name" "$ACTIVE_SKILLS"; then
      ACTIVE_SKILLS="$ACTIVE_SKILLS $name"
      added="$added $name"
    fi
  done
  SKILL_PROFILE_EFF="$profile"
  if [ -n "$added" ]; then
    report MERGED "skills" "dependency closure added:${added}"
  fi
  if [ "$SKILL_PROFILE_FLAG" -eq 1 ] || [ "$SKILLS_EXCLUDE_FLAG" -eq 1 ]; then
    local persist_allow=""
    if [ "$profile" = "custom" ]; then
      persist_allow="$(printf '%s' "${base_active# }" | tr ' ' ',')"
    fi
    skill_profile_write "$profile" "$excludes_csv" "$persist_allow"
  fi
  return 0
}

# =================================================================================
# INTEGRATE MODE — merge steps
# =================================================================================

integrate_claude_md() {
  local f="$TARGET/CLAUDE.md"
  if [ -f "$f" ]; then
    if grep -qF "$CLAUDE_BLOCK_START" "$f"; then
      report SKIPPED "CLAUDE.md" "already integrated (managed block present)"
      return 0
    fi
    backup_file "$f"
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN "CLAUDE.md" "would append managed router block (your content kept)"
      return 0
    fi
    cat >> "$f" <<'EOF'

<!-- >>> qa-agent-blueprint (managed, do not edit) -->

## QA Agent Blueprint (integrated)

For JIRA-ticket-driven QA work, act as a **QA Manager + Tester**: test tickets
autonomously and always deliver evidence under
`evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/` incl. `execution_summary.json`.

- Route ticket prefixes (`SHOP-1234` → `SHOP`) to `projects/<KEY>/PROJECT.md`
  before testing; unknown prefix → run the `onboard-project` skill or ask.
- Products are optional. If that `PROJECT.md` has a `## Products` section, route the
  ticket on to a product and read `products/<PRODUCT>/PRODUCT.md` + `learnings.md` in
  addition — product wins, what it omits is inherited. Order: explicit mention →
  component → label → `project-wide` → the project's declared secondary signals
  (epic, fix version, MR paths) → a declared default. Conflict or nothing → ask
  (headless → BLOCKED); a default resolves silence, never a conflict. No
  `## Products` section → the project file is the whole context. Details:
  `.claude/rules/qa-blueprint/core/product-layer.md`.
- Blueprint rules: `.claude/rules/qa-blueprint/` · hooks: `.claude/hooks/qa-blueprint/`.
- Skills: /test-ticket · /retest-bug · /exploratory-testing · /playwright-regression ·
  /bug-report · /report-to-jira · /deploy-to-stage · /onboard-project ·
  /onboard-product · /retro-learn
  + 10 vendored specialist skills for every project (risk-based-testing,
  bug-reproduction, api-testing, accessibility-testing, security-testing,
  visual-testing, test-reliability, qa-metrics, test-case-management,
  release-readiness) — see `.claude/skills/THIRD_PARTY_NOTICES.md`.
- Vendored skills are global; their context is per-project (and per-product). Point
  one at `.agents/qa-project-context/<KEY>.md` — or `<KEY>/<PRODUCT>.md` once the
  project has products — for the current ticket explicitly, never a generic or
  previously-used path, which may hold a different project's or product's data.
- Learning loop: capture surprises into `memory/learnings/_inbox.md`; promote via
  /retro-learn. Every run declares its `learnings` in `execution_summary.json` (the
  entries, or one sentence why there were none) — the Stop hook blocks without it.
- Hard rules: evidence mandatory · no secrets in chat/code/tickets/screenshots ·
  no full project scans (start at `memory/INDEX.md` + the project file).

<!-- <<< qa-agent-blueprint -->
EOF
    report MERGED "CLAUDE.md" "managed router block appended — your content untouched"
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN "CLAUDE.md" "would copy blueprint router CLAUDE.md (none exists)"
    else
      cp -p "$REPO_ROOT/CLAUDE.md" "$f"
      report ADDED "CLAUDE.md" "blueprint router copied (no existing CLAUDE.md)"
    fi
  fi
}

integrate_dot_claude() {
  # Rules → namespaced
  if [ -d "$TARGET/$NS_RULES" ] && source_dir_matches_installed "$REPO_ROOT/.claude/rules" "$TARGET/$NS_RULES"; then
    report SKIPPED "rules" "$NS_RULES already integrated (identical)"
  else
    copy_tree "$REPO_ROOT/.claude/rules" "$TARGET/$NS_RULES" "rules"
  fi

  # Hooks → namespaced
  if [ -d "$TARGET/$NS_HOOKS" ] && source_dir_matches_installed "$REPO_ROOT/.claude/hooks" "$TARGET/$NS_HOOKS"; then
    report SKIPPED "hooks" "$NS_HOOKS already integrated (identical)"
  else
    copy_tree "$REPO_ROOT/.claude/hooks" "$TARGET/$NS_HOOKS" "hooks"
  fi

  if [ -d "$TARGET/.claude/scripts" ] && source_dir_matches_installed "$REPO_ROOT/.claude/scripts" "$TARGET/.claude/scripts"; then
    report SKIPPED "scripts" ".claude/scripts already integrated (identical)"
  else
    copy_tree "$REPO_ROOT/.claude/scripts" "$TARGET/.claude/scripts" "scripts"
  fi

  # Skills → per-skill collision check
  local s name
  if [ ! -d "$REPO_ROOT/.claude/skills" ]; then
    report SKIPPED "skills" "no blueprint skills found — nothing to copy"
  fi
  for s in "$REPO_ROOT/.claude/skills"/*/; do
    [ -d "$s" ] || continue
    name="$(basename "$s")"
    if [ "$SKILL_SELECTION_ACTIVE" -eq 1 ] && ! skill_is_active "$name"; then
      if [ -e "$TARGET/.claude/skills/$name" ]; then
        report SKIPPED "skills" "$name deactivated by profile — existing copy left untouched"
      else
        report SKIPPED "skills" "$name omitted (profile: $SKILL_PROFILE_EFF)"
      fi
      continue
    fi
    if [ -e "$TARGET/.claude/skills/$name" ]; then
      if source_dir_matches_installed "$s" "$TARGET/.claude/skills/$name"; then
        report SKIPPED "skills" "$name already integrated (identical)"
      else
        report WARN "skills" "SKIPPED $name — a different skill with this name already exists (collision)"
        next_step "Resolve skill collision: compare .claude/skills/$name with the blueprint version"
      fi
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        report DRY-RUN "skills" "would add .claude/skills/$name/"
      else
        mkdir -p "$TARGET/.claude/skills"
        cp -r "$s" "$TARGET/.claude/skills/$name"
        register_copied_dir "$TARGET/.claude/skills/$name"
        report ADDED "skills" ".claude/skills/$name/"
      fi
    fi
  done

  # THIRD_PARTY_NOTICES.md lives directly under .claude/skills/ (not inside a
  # skill subfolder), so the */ glob above never touches it — copy it explicitly.
  if [ -f "$REPO_ROOT/.claude/skills/THIRD_PARTY_NOTICES.md" ]; then
    if [ -e "$TARGET/.claude/skills/THIRD_PARTY_NOTICES.md" ]; then
      if source_matches_installed "$REPO_ROOT/.claude/skills/THIRD_PARTY_NOTICES.md" "$TARGET/.claude/skills/THIRD_PARTY_NOTICES.md"; then
        report SKIPPED "skills" "THIRD_PARTY_NOTICES.md already integrated (identical)"
      else
        report WARN "skills" "SKIPPED THIRD_PARTY_NOTICES.md — a different file already exists (collision)"
      fi
    elif [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN "skills" "would add .claude/skills/THIRD_PARTY_NOTICES.md"
    else
      mkdir -p "$TARGET/.claude/skills"
      cp -p "$REPO_ROOT/.claude/skills/THIRD_PARTY_NOTICES.md" "$TARGET/.claude/skills/THIRD_PARTY_NOTICES.md"
      ADDED_FILES+=("$TARGET/.claude/skills/THIRD_PARTY_NOTICES.md")
      report ADDED "skills" ".claude/skills/THIRD_PARTY_NOTICES.md"
    fi
  fi

  # Agents → per-file collision check
  local a
  if [ ! -d "$REPO_ROOT/.claude/agents" ]; then
    report SKIPPED "agents" "no blueprint agents found — nothing to copy"
  fi
  for a in "$REPO_ROOT/.claude/agents"/*; do
    [ -f "$a" ] || continue
    name="$(basename "$a")"
    if [ -e "$TARGET/.claude/agents/$name" ]; then
      if source_matches_installed "$a" "$TARGET/.claude/agents/$name"; then
        report SKIPPED "agents" "$name already integrated (identical)"
      else
        report WARN "agents" "SKIPPED $name — a different agent with this name already exists (collision)"
        next_step "Resolve agent collision: compare .claude/agents/$name with the blueprint version"
      fi
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        report DRY-RUN "agents" "would add .claude/agents/$name"
      else
        mkdir -p "$TARGET/.claude/agents"
        cp -p "$a" "$TARGET/.claude/agents/$name"
        ADDED_FILES+=("$TARGET/.claude/agents/$name")
        report ADDED "agents" ".claude/agents/$name"
      fi
    fi
  done

  # .claudeignore — copy if absent, else only advise
  if [ -f "$TARGET/.claudeignore" ]; then
    if grep -qx 'evidence/' "$TARGET/.claudeignore" 2>/dev/null; then
      report SKIPPED ".claudeignore" "exists and already excludes evidence/"
    else
      report WARN ".claudeignore" "exists — kept yours; consider adding 'evidence/'"
    fi
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN ".claudeignore" "would copy blueprint .claudeignore"
    else
      cp -p "$REPO_ROOT/.claudeignore" "$TARGET/.claudeignore"
      report ADDED ".claudeignore" "blueprint .claudeignore copied"
    fi
  fi
}

# Pipe "STATUS|area|detail" lines from embedded python helpers into report()
consume_report_lines() {
  local st area detail line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    st="${line%%|*}"; line="${line#*|}"; area="${line%%|*}"; detail="${line#*|}"
    report "$st" "$area" "$detail"
  done
}

# --- .mcp.json merge (python3 preferred, jq fallback) -----------------------------
integrate_mcp_json() {
  local t="$TARGET/.mcp.json"
  if [ ! -f "$t" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN ".mcp.json" "would copy blueprint .mcp.json (none exists)"
    else
      cp -p "$REPO_ROOT/.mcp.json" "$t"
      report ADDED ".mcp.json" "blueprint .mcp.json copied (playwright + atlassian)"
    fi
    return 0
  fi
  if ! have_json_tool; then
    report WARN ".mcp.json" "exists, but neither python3 nor jq found — merge manually (see docs/integration.md)"
    return 0
  fi
  # backup happens lazily inside the merge, only when something actually changes
  if command -v python3 >/dev/null 2>&1; then
    # NOTE: the python payload is written to a temp file rather than piped via
    # a heredoc directly inside `<(...)` — older bash (e.g. bash 3.2, macOS
    # default) cannot reliably parse a heredoc nested inside process
    # substitution ("bad substitution: no closing `)'"). Writing it out first
    # keeps the heredoc a plain top-level command and the process substitution
    # a simple `python3 <file>` invocation, which parses fine everywhere.
    local _py_mcp_merge
    _py_mcp_merge="$(mktemp)"
    cat > "$_py_mcp_merge" <<'PY'
import json, os, shutil, sys
bp = json.load(open(os.environ["QA_BP_MCP"]))
tp = os.environ["QA_TARGET_MCP"]
backup = os.environ.get("QA_BACKUP")
dry = os.environ["QA_DRY"] == "1"
try:
    tgt = json.load(open(tp))
except Exception as e:
    print(f"WARN|.mcp.json|invalid JSON in target ({e}) — left untouched"); sys.exit(0)
servers = tgt.setdefault("mcpServers", {})
changed = False

# The playwright config is part of the security model: --secrets masks passwords
# in tool responses, and --output-dir keeps raw artifacts inside evidence/ (the
# evidence policy depends on it). --image-responses omit keeps screenshots out of
# the model context (they are evidence files, not reading material — ~1-2k tokens
# per shot saved). Together with --config they are the CONTRACT. Local entries
# are upgraded additively so their command, channel, preferences, secrets source
# and wrappers survive; remote entries are left alone. Headless/headful and
# --isolated are deliberately NOT contract: they are user preferences
# (exercised via .playwright-mcp.config.json or the user's own flags).
CONTRACT_DEFAULTS = {
    "--config": ".playwright-mcp.config.json",
    "--secrets": ".env.playwright-secrets",
    "--output-dir": "evidence/.mcp-out",
    "--image-responses": "omit",
}
PREFERENCE_FLAGS = ("--isolated", "--headless")

def args_of(cfg):
    return [str(a) for a in (cfg.get("args") or [])]

def has_flag(cfg, flag):
    args = args_of(cfg)
    return any(a == flag or a.startswith(flag + "=") for a in args)

def uses_qa_secrets_wrapper(cfg):
    args = args_of(cfg)
    cmd = str(cfg.get("command") or "")
    return any("qa-secrets" in a for a in args) or "qa-secrets" in cmd

def is_remote(cfg):
    return cfg.get("type") in ("http", "sse", "remote") or bool(cfg.get("url") and not cfg.get("command"))

def flag_value(args, flag, start=0):
    value = None
    i = start
    while i < len(args):
        arg = args[i]
        if arg == flag:
            value = args[i + 1] if i + 1 < len(args) else None
            i += 1
        elif arg.startswith(flag + "="):
            value = arg.split("=", 1)[1]
        i += 1
    return value

def output_dir_ok(value):
    if not value or value.startswith("--"):
        return False
    evidence_root = os.path.realpath(os.path.join(os.path.dirname(tp), "evidence"))
    candidate = os.path.realpath(os.path.join(os.path.dirname(tp), value))
    try:
        return os.path.commonpath((evidence_root, candidate)) == evidence_root
    except ValueError:
        return False

def ensure_flag(args, flag, default, start=0):
    value = flag_value(args, flag, start)
    valid = output_dir_ok(value) if flag == "--output-dir" else bool(value and not value.startswith("--"))
    if flag == "--image-responses":
        valid = value == "omit"
    if valid:
        return False
    matches = [i for i in range(start, len(args)) if args[i] == flag or args[i].startswith(flag + "=")]
    if matches:
        i = matches[-1]
        if args[i] == flag:
            if i + 1 < len(args) and not args[i + 1].startswith("--"):
                args[i + 1] = default
            else:
                args.insert(i + 1, default)
        else:
            args[i] = flag + "=" + default
        return True
    args.extend([flag, default])
    return True

for name, cfg in bp.get("mcpServers", {}).items():
    if name in servers:
        existing = servers[name]
        if existing == cfg:
            print(f"SKIPPED|.mcp.json|server '{name}' already configured (identical)")
        elif name == "playwright":
            if is_remote(existing):
                print(f"SKIPPED|.mcp.json|kept existing remote 'playwright' — local CLI contract flags do not apply")
                continue
            upgraded = dict(existing)
            args = args_of(existing)
            upgraded["args"] = args
            wrapped = uses_qa_secrets_wrapper(existing)
            start = args.index("--") + 1 if wrapped and "--" in args else 0
            fixes = []
            for flag, default in CONTRACT_DEFAULTS.items():
                if flag == "--secrets" and wrapped:
                    continue
                if ensure_flag(args, flag, default, start):
                    fixes.append(flag)
            missing_prefs = [f for f in PREFERENCE_FLAGS if not has_flag(existing, f)]
            if not fixes:
                note = f" (preferences {', '.join(missing_prefs)} not set — your choice; defaults live in .playwright-mcp.config.json)" if missing_prefs else ""
                wrapper_note = "; qa-secrets wrapper and secrets source preserved" if wrapped else ""
                print(f"SKIPPED|.mcp.json|kept existing 'playwright' — it carries the contract values (--config, --secrets, --output-dir, --image-responses omit){wrapper_note}{note}")
            elif dry:
                print(f"DRY-RUN|.mcp.json|would additively upgrade 'playwright' (contract fixes: {', '.join(fixes)}; command, preferences and wrapper preserved)")
            else:
                servers[name] = upgraded
                changed = True
                print(f"MERGED|.mcp.json|additively upgraded 'playwright' — fixed {', '.join(fixes)} (command, custom preferences, channel and wrapper preserved; previous config is in the backup)")
        elif name == "atlassian":
            # The Cloud v2 default URL (discovery/execute) is part of the token
            # contract too: ?tools=all inflates every session AND every subagent
            # spawn with the full Atlassian suite. An existing entry that differs
            # ONLY by that query string is upgraded; anything else (Data Center,
            # proxies, own servers) keeps the "existing wins" WARN.
            stripped = dict(existing, url=(existing.get("url") or "").split("?")[0])
            if stripped == cfg:
                if dry:
                    print(f"DRY-RUN|.mcp.json|would upgrade 'atlassian' — drop ?tools=all (discovery/execute is the default)")
                else:
                    servers[name] = cfg
                    changed = True
                    print(f"MERGED|.mcp.json|upgraded 'atlassian' — dropped ?tools=all (the flat tool list inflates every session; previous config is in the backup)")
            else:
                print(f"WARN|.mcp.json|kept existing '{name}' server config (name already defined)")
        else:
            print(f"WARN|.mcp.json|kept existing '{name}' server config (name already defined)")
    else:
        if dry:
            print(f"DRY-RUN|.mcp.json|would add server '{name}'")
        else:
            servers[name] = cfg
            changed = True
            print(f"MERGED|.mcp.json|added server '{name}'")
if changed and not dry:
    if backup:
        shutil.copy2(tp, backup)
        print(f"BACKUP|backup|{tp} → {backup}")
    with open(tp, "w") as f:
        json.dump(tgt, f, indent=2)
        f.write("\n")
PY
    consume_report_lines < <(QA_BP_MCP="$REPO_ROOT/.mcp.json" QA_TARGET_MCP="$t" \
      QA_BACKUP="$t.bak-$TS" QA_DRY="$DRY_RUN" python3 "$_py_mcp_merge")
    rm -f "$_py_mcp_merge"
  else
    # jq fallback: add only missing server names
    local name backed_up=""
    for name in $(jq -r '.mcpServers | keys[]' "$REPO_ROOT/.mcp.json"); do
      if jq -e --arg n "$name" '.mcpServers[$n]' "$t" >/dev/null 2>&1; then
        if [ "$name" = "playwright" ]; then
          report WARN ".mcp.json" "kept existing 'playwright' — VERIFY it carries the contract flags: --secrets .env.playwright-secrets --output-dir evidence/.mcp-out --image-responses omit (unmasked passwords / missing evidence / screenshot images in the context otherwise). Headless/isolated are preferences, not contract."
        else
          report WARN ".mcp.json" "kept existing '$name' server config (name already defined)"
        fi
      elif [ "$DRY_RUN" -eq 1 ]; then
        report DRY-RUN ".mcp.json" "would add server '$name'"
      else
        local tmp
        [ -z "$backed_up" ] && { backup_file "$t"; backed_up=1; }
        tmp="$(mktemp)"
        jq --arg n "$name" --argjson cfg "$(jq --arg n "$name" '.mcpServers[$n]' "$REPO_ROOT/.mcp.json")" \
           '.mcpServers[$n] = $cfg' "$t" > "$tmp" && mv "$tmp" "$t"
        report MERGED ".mcp.json" "added server '$name'"
      fi
    done
  fi
}

# --- .claude/settings.json merge ----------------------------------------------------
integrate_settings_json() {
  local t="$TARGET/.claude/settings.json"
  if [ ! -f "$t" ]; then
    if ! command -v python3 >/dev/null 2>&1; then
      report WARN "settings.json" "missing, but python3 not found — copy $REPO_ROOT/.claude/settings.json manually"
      return 0
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN "settings.json" "would create .claude/settings.json (hooks → $NS_HOOKS)"
    else
      mkdir -p "$TARGET/.claude"
      QA_BP_SETTINGS="$REPO_ROOT/.claude/settings.json" QA_TARGET_SETTINGS="$t" \
      QA_HOOK_NS="$NS_HOOKS" QA_DRY="$DRY_RUN" python3 - <<'PY'
import json, os
bp = json.load(open(os.environ["QA_BP_SETTINGS"]))
ns = os.environ["QA_HOOK_NS"]
out = {"permissions": bp.get("permissions", {}), "hooks": {}}
for ev, entries in bp.get("hooks", {}).items():
    fixed = []
    for e in entries:
        e = dict(e)
        e["hooks"] = [dict(h, command=h.get("command", "").replace("/.claude/hooks/", f"/{ns}/"))
                      for h in e.get("hooks", [])]
        fixed.append(e)
    out["hooks"][ev] = fixed
with open(os.environ["QA_TARGET_SETTINGS"], "w") as f:
    json.dump(out, f, indent=2)
    f.write("\n")
PY
      report ADDED "settings.json" "created with blueprint permissions + namespaced hooks"
    fi
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    report WARN "settings.json" "exists, but python3 not found — merge hooks/permissions manually (see docs/integration.md)"
    return 0
  fi
  # backup happens lazily inside the merge, only when something actually changes
  # (see the .mcp.json merge above for why this uses a temp file instead of a
  # heredoc nested inside process substitution)
  local _py_settings_merge
  _py_settings_merge="$(mktemp)"
  cat > "$_py_settings_merge" <<'PY'
import json, os, shutil, sys
bp = json.load(open(os.environ["QA_BP_SETTINGS"]))
tp = os.environ["QA_TARGET_SETTINGS"]
ns = os.environ["QA_HOOK_NS"]
backup = os.environ.get("QA_BACKUP")
dry = os.environ["QA_DRY"] == "1"
changed = False
try:
    tgt = json.load(open(tp))
except Exception as e:
    print(f"WARN|settings.json|invalid JSON in target ({e}) — left untouched"); sys.exit(0)

def emit(status, area, detail):
    print(f"{status}|{area}|{detail}")

# permissions: deduplicated union
perms = tgt.setdefault("permissions", {})
for kind in ("deny", "allow"):
    existing = perms.setdefault(kind, [])
    for entry in bp.get("permissions", {}).get(kind, []):
        if entry in existing:
            emit("SKIPPED", "settings.json", f"permissions.{kind}: '{entry}' already present")
        else:
            if not dry:
                existing.append(entry)
                changed = True
            emit("DRY-RUN" if dry else "MERGED", "settings.json",
                 f"{'would add' if dry else 'added'} permissions.{kind}: '{entry}'")

# hooks: append per event, dedup by (matcher, command) pair — command alone is
# not enough: 0.6.6 added a SECOND PreToolUse entry for pre-tool-guard.sh (the
# preflight gate's MCP matcher), and command-keyed dedup would have skipped it
# on every upgrade install, silently leaving integrate-mode consumers without
# the gate.
hooks = tgt.setdefault("hooks", {})
for ev, entries in bp.get("hooks", {}).items():
    lst = hooks.setdefault(ev, [])
    existing_pairs = {(e.get("matcher"), h.get("command")) for e in lst for h in e.get("hooks", [])}
    for e in entries:
        matcher = e.get("matcher")
        new_hooks = [dict(h, command=h.get("command", "").replace("/.claude/hooks/", f"/{ns}/"))
                     for h in e.get("hooks", [])]
        todo = [h for h in new_hooks if (matcher, h["command"]) not in existing_pairs]
        for h in new_hooks:
            if (matcher, h["command"]) in existing_pairs:
                emit("SKIPPED", "settings.json", f"hooks.{ev}: '{h['command']}' already present")
        if todo:
            entry = {"hooks": todo}
            if matcher:
                entry = {"matcher": matcher, **entry}
            if not dry:
                lst.append(entry)
                changed = True
            for h in todo:
                emit("DRY-RUN" if dry else "MERGED", "settings.json",
                     f"{'would append' if dry else 'appended'} hooks.{ev}: '{h['command']}'")
            existing_pairs.update((matcher, h["command"]) for h in todo)
if changed and not dry:
    if backup:
        shutil.copy2(tp, backup)
        emit("BACKUP", "backup", f"{tp} → {backup}")
    with open(tp, "w") as f:
        json.dump(tgt, f, indent=2)
        f.write("\n")
PY
  consume_report_lines < <(QA_BP_SETTINGS="$REPO_ROOT/.claude/settings.json" QA_TARGET_SETTINGS="$t" \
    QA_BACKUP="$t.bak-$TS" QA_HOOK_NS="$NS_HOOKS" QA_DRY="$DRY_RUN" python3 "$_py_settings_merge")
  rm -f "$_py_settings_merge"
}

# --- .gitignore managed block ---------------------------------------------------------
integrate_gitignore() {
  local t="$TARGET/.gitignore"
  if [ ! -f "$t" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN ".gitignore" "would copy blueprint .gitignore (none exists)"
    else
      cp -p "$REPO_ROOT/.gitignore" "$t"
      report ADDED ".gitignore" "blueprint .gitignore copied"
    fi
    return 0
  fi
  if grep -qF "$GITIGNORE_BLOCK_START" "$t"; then
    report SKIPPED ".gitignore" "already integrated (managed block present)"
    return 0
  fi
  # collect missing entries (non-comment, non-empty lines)
  local missing=() line
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    grep -qxF "$line" "$t" || missing+=("$line")
  done < "$REPO_ROOT/.gitignore"
  if [ "${#missing[@]}" -eq 0 ]; then
    report SKIPPED ".gitignore" "all blueprint entries already present"
    return 0
  fi
  backup_file "$t"
  if [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN ".gitignore" "would append managed block with ${#missing[@]} missing entries: ${missing[*]}"
    return 0
  fi
  {
    printf '\n%s\n' "$GITIGNORE_BLOCK_START"
    printf '%s\n' "${missing[@]}"
    printf '%s\n' "$GITIGNORE_BLOCK_END"
  } >> "$t"
  report MERGED ".gitignore" "managed block appended with ${#missing[@]} missing entries (${missing[*]})"
}

check_browser_console_level() {
  local f="$1" note
  [ -f "$f" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  note="$(python3 - "$f" <<'PY' 2>/dev/null
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(0)
if cfg.get("console", {}).get("level") != "warning":
    print('console.level is not warning — set `"console": { "level": "warning" }` manually to keep info/debug noise out of tool responses; existing preferences were left untouched')
PY
)"
  [ -z "$note" ] || report WARN ".playwright-mcp.config.json" "$note"
}

# --- evidence/ memory/ projects/ + env files -------------------------------------------
integrate_dirs() {
  local d
  for d in evidence memory projects; do
    if [ -d "$TARGET/$d" ]; then
      report SKIPPED "$d/" "exists — left untouched"
    else
      if [ "$DRY_RUN" -eq 1 ]; then
        report DRY-RUN "$d/" "would create $d/ from blueprint scaffold"
      else
        cp -r "$REPO_ROOT/$d" "$TARGET/$d"
        report ADDED "$d/" "created from blueprint scaffold"
      fi
    fi
  done

  # Deliberately no dotenv file and no credential prompts — see the same decision
  # in run_self_setup(). Nothing in the blueprint loads such a file, the Atlassian
  # MCP server uses OAuth via /mcp, and the vault prefix belongs in
  # projects/<KEY>/PROJECT.md where it is actually read. An existing .env of yours
  # is neither touched nor read.
  report SKIPPED "credentials" "no .env written — OAuth via /mcp; vault prefix and Confluence space live in projects/<KEY>/PROJECT.md"
  next_step "Authorize the Atlassian MCP server: run /mcp inside Claude Code"

  if [ -f "$TARGET/.env.playwright-secrets" ]; then
    report SKIPPED ".env.playwright-secrets" "exists — left untouched"
  elif [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN ".env.playwright-secrets" "would create secrets template"
  else
    cat > "$TARGET/.env.playwright-secrets" <<'EOF'
# Secrets consumed by Playwright MCP via --secrets (values are masked in tool
# responses, so the agent never sees them). Gitignored — never commit.
# Reference per-project test users by the keys used in projects/<KEY>/PROJECT.md.
# Example:
# SHOP_QA_STANDARD_PASSWORD=replace-me
EOF
    report ADDED ".env.playwright-secrets" "secrets template created (gitignored)"
  fi

  # Browser preferences live in a consumer-owned config file referenced by the
  # playwright MCP entry (--config). Seed the defaults; never overwrite — the
  # file is the user's dial for headful/headless, persistent profile, viewport.
  if [ -f "$TARGET/.playwright-mcp.config.json" ]; then
    check_browser_console_level "$TARGET/.playwright-mcp.config.json"
    report SKIPPED ".playwright-mcp.config.json" "exists — left untouched (your browser preferences)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN ".playwright-mcp.config.json" "would create browser config with defaults (headless, isolated)"
  else
    cat > "$TARGET/.playwright-mcp.config.json" <<'EOF'
{
  "browser": {
    "isolated": true,
    "launchOptions": { "headless": true }
  },
  "console": { "level": "warning" }
}
EOF
    report ADDED ".playwright-mcp.config.json" "browser config created — headful = launchOptions.headless false (applies after restart)"
  fi
}

# =================================================================================
# UNINSTALL — remove only what we merged; never touch foreign content
# =================================================================================

uninstall_integrate() {
  info "Uninstalling blueprint integration from $TARGET ..."

  # 1. CLAUDE.md managed block (or remove the file if it is a pure blueprint copy)
  local f="$TARGET/CLAUDE.md"
  if [ -f "$f" ]; then
    if cmp -s "$f" "$REPO_ROOT/CLAUDE.md"; then
      backup_file "$f"
      if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN "CLAUDE.md" "would remove (pure blueprint copy, no own content)";
      else rm "$f"; report ADDED "CLAUDE.md" "removed (was a pure blueprint copy)"; fi
    elif grep -qF "$CLAUDE_BLOCK_START" "$f"; then
      backup_file "$f"
      if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN "CLAUDE.md" "would remove managed block";
      else
        remove_block "$f" "$CLAUDE_BLOCK_START" "$CLAUDE_BLOCK_END"
        strip_trailing_blank_lines "$f"
        report MERGED "CLAUDE.md" "managed block removed — your content kept"
      fi
    else
      report SKIPPED "CLAUDE.md" "no blueprint content found"
    fi
  fi

  # 2. .gitignore — pure blueprint copy (none existed before) or managed block
  f="$TARGET/.gitignore"
  if [ -f "$f" ] && cmp -s "$f" "$REPO_ROOT/.gitignore"; then
    backup_file "$f"
    if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN ".gitignore" "would remove (pure blueprint copy, no own content)";
    else rm "$f"; report MERGED ".gitignore" "removed (was a pure blueprint copy)"; fi
  elif [ -f "$f" ] && grep -qF "$GITIGNORE_BLOCK_START" "$f"; then
    backup_file "$f"
    if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN ".gitignore" "would remove managed block";
    else
      remove_block "$f" "$GITIGNORE_BLOCK_START" "$GITIGNORE_BLOCK_END"
      strip_trailing_blank_lines "$f"
      report MERGED ".gitignore" "managed block removed"
    fi
  else
    report SKIPPED ".gitignore" "no managed block found"
  fi

  # 3. namespaced rules/hooks (remove only files identical to the blueprint source)
  local ns srcdir
  for ns in "$NS_RULES" "$NS_HOOKS"; do
    # map namespace back to the blueprint source dir (.claude/rules|hooks)
    srcdir="$REPO_ROOT/.claude/${ns#.claude/}"
    srcdir="${srcdir%/qa-blueprint}"
    if [ -d "$TARGET/$ns" ]; then
      local bf rel removed_any=0
      while IFS= read -r -d '' bf; do
        rel="${bf#"$srcdir"/}"
        # Compare against the REWRITTEN source: install namespaced the internal
        # path references, so a byte-compare with the raw source would call every
        # copied file "modified" and refuse to remove it.
        if [ -f "$TARGET/$ns/$rel" ] && source_matches_installed "$bf" "$TARGET/$ns/$rel"; then
          if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN "$ns" "would remove $rel";
          else rm "$TARGET/$ns/$rel"; removed_any=1; fi
        elif [ -f "$TARGET/$ns/$rel" ]; then
          report WARN "$ns" "kept $rel — modified after install, remove manually if unwanted"
        fi
      done < <(find "$srcdir" -type f -print0)
      if [ "$DRY_RUN" -eq 0 ]; then
        find "$TARGET/$ns" -type d -empty -delete 2>/dev/null || true
        [ "$removed_any" -eq 1 ] && report MERGED "$ns" "blueprint files removed (namespace cleaned)"
      fi
    else
      report SKIPPED "$ns" "namespace not present"
    fi
  done

  # 3b. namespaced docs (same rule: only what matches what we wrote)
  if [ -d "$TARGET/docs/qa-blueprint" ]; then
    if source_dir_matches_installed "$REPO_ROOT/docs" "$TARGET/docs/qa-blueprint"; then
      if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN "docs/" "would remove docs/qa-blueprint/";
      else rm -r "$TARGET/docs/qa-blueprint"; report MERGED "docs/" "removed docs/qa-blueprint/"; fi
    else
      report WARN "docs/" "kept docs/qa-blueprint/ — content differs (yours or modified)"
    fi
  fi

  # 4. skills/agents we copied (remove only if identical to blueprint source)
  local s a name
  for s in "$REPO_ROOT/.claude/skills"/*/; do
    [ -d "$s" ] || continue
    name="$(basename "$s")"
    if [ -d "$TARGET/.claude/skills/$name" ]; then
      if source_dir_matches_installed "$s" "$TARGET/.claude/skills/$name"; then
        if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN "skills" "would remove .claude/skills/$name/";
        else rm -rf "$TARGET/.claude/skills/$name"; report MERGED "skills" "removed .claude/skills/$name/"; fi
      else
        report WARN "skills" "kept .claude/skills/$name/ — content differs (yours or modified)"
      fi
    fi
  done
  if [ -f "$REPO_ROOT/.claude/skills/THIRD_PARTY_NOTICES.md" ] && [ -f "$TARGET/.claude/skills/THIRD_PARTY_NOTICES.md" ]; then
    if cmp -s "$REPO_ROOT/.claude/skills/THIRD_PARTY_NOTICES.md" "$TARGET/.claude/skills/THIRD_PARTY_NOTICES.md"; then
      if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN "skills" "would remove .claude/skills/THIRD_PARTY_NOTICES.md";
      else rm "$TARGET/.claude/skills/THIRD_PARTY_NOTICES.md"; report MERGED "skills" "removed .claude/skills/THIRD_PARTY_NOTICES.md"; fi
    else
      report WARN "skills" "kept .claude/skills/THIRD_PARTY_NOTICES.md — content differs (yours or modified)"
    fi
  fi
  for a in "$REPO_ROOT/.claude/agents"/*; do
    [ -f "$a" ] || continue
    name="$(basename "$a")"
    if [ -f "$TARGET/.claude/agents/$name" ]; then
      if cmp -s "$a" "$TARGET/.claude/agents/$name"; then
        if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN "agents" "would remove .claude/agents/$name";
        else rm "$TARGET/.claude/agents/$name"; report MERGED "agents" "removed .claude/agents/$name"; fi
      else
        report WARN "agents" "kept .claude/agents/$name — content differs (yours or modified)"
      fi
    fi
  done
  if [ -d "$TARGET/.claude/scripts" ]; then
    local bf rel
    while IFS= read -r -d '' bf; do
      rel="${bf#"$REPO_ROOT/.claude/scripts"/}"
      if [ -f "$TARGET/.claude/scripts/$rel" ] && source_matches_installed "$bf" "$TARGET/.claude/scripts/$rel"; then
        if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN "scripts" "would remove .claude/scripts/$rel";
        else rm "$TARGET/.claude/scripts/$rel"; report MERGED "scripts" "removed .claude/scripts/$rel"; fi
      elif [ -f "$TARGET/.claude/scripts/$rel" ]; then
        report WARN "scripts" "kept .claude/scripts/$rel — modified after install"
      fi
    done < <(find "$REPO_ROOT/.claude/scripts" -type f -print0)
    if [ "$DRY_RUN" -eq 0 ]; then
      find "$TARGET/.claude/scripts" -type d -empty -delete 2>/dev/null || true
    fi
  fi

  # 5. settings.json — remove hook entries pointing at our namespace.
  #    Permission entries are removed only when they are blueprint entries AND
  #    were absent from the install-time backup (safe attribution). If the
  #    cleaned file then matches the backup semantically, restore it verbatim.
  f="$TARGET/.claude/settings.json"
  if [ -f "$f" ] && command -v python3 >/dev/null 2>&1; then
    # temp-file approach — see the .mcp.json merge above for why
    local _py_settings_uninstall
    _py_settings_uninstall="$(mktemp)"
    cat > "$_py_settings_uninstall" <<'PY'
import json, os, shutil, glob
tp = os.environ["QA_TARGET_SETTINGS"]
ns = os.environ["QA_HOOK_NS"]
backup = os.environ.get("QA_BACKUP")
bp = json.load(open(os.environ["QA_BP_SETTINGS"]))
dry = os.environ["QA_DRY"] == "1"
changed = False
tgt = json.load(open(tp))
hooks = tgt.get("hooks", {})
for ev in list(hooks):
    kept = []
    for entry in hooks[ev]:
        ours = [h for h in entry.get("hooks", []) if f"/{ns}/" in h.get("command", "")]
        theirs = [h for h in entry.get("hooks", []) if f"/{ns}/" not in h.get("command", "")]
        for h in ours:
            print(f"{'DRY-RUN' if dry else 'MERGED'}|settings.json|{'would remove' if dry else 'removed'} hooks.{ev}: '{h['command']}'")
        if ours:
            changed = True
        if theirs:
            e = dict(entry); e["hooks"] = theirs; kept.append(e)
    if kept:
        hooks[ev] = kept
    elif ev in hooks and any(f"/{ns}/" in h.get("command", "") for e in hooks[ev] for h in e.get("hooks", [])):
        # event array becomes empty and only contained our hooks -> drop the key
        del hooks[ev]

# permissions: attribute via the newest backup — remove only blueprint entries
# that were NOT already present before our merge
pre = None
for b in sorted(glob.glob(tp + ".bak-*"), reverse=True):
    try:
        pre = json.load(open(b))
        break
    except Exception:
        continue
if pre is not None:
    perms = tgt.get("permissions", {})
    pre_perms = pre.get("permissions", {})
    for kind in ("deny", "allow"):
        bp_entries = set(bp.get("permissions", {}).get(kind, []))
        pre_entries = set(pre_perms.get(kind, []))
        existing = perms.get(kind, [])
        kept = []
        for e in existing:
            if e in bp_entries and e not in pre_entries:
                changed = True
                print(f"{'DRY-RUN' if dry else 'MERGED'}|settings.json|{'would remove' if dry else 'removed'} permissions.{kind}: '{e}' (added by blueprint)")
            else:
                kept.append(e)  # user's own (pre-existing) or foreign entry — never touch
        if kind in perms:
            if kept:
                perms[kind] = kept
            else:
                del perms[kind]
    if "permissions" in tgt and not tgt["permissions"]:
        del tgt["permissions"]

if changed and not dry:
    # if the cleaned config equals a previous backup semantically, restore that
    # backup verbatim (byte-exact original formatting)
    restored = False
    if pre is not None and pre == tgt:
        for b in sorted(glob.glob(tp + ".bak-*"), reverse=True):
            try:
                if json.load(open(b)) == tgt:
                    shutil.copy2(b, tp)
                    print(f"MERGED|settings.json|restored original from {b} (byte-exact)")
                    restored = True
                    break
            except Exception:
                continue
    if not restored:
        if backup:
            shutil.copy2(tp, backup)
            print(f"BACKUP|backup|{tp} → {backup}")
        with open(tp, "w") as fh:
            json.dump(tgt, fh, indent=2)
            fh.write("\n")
elif not changed:
    print("SKIPPED|settings.json|no blueprint hook/permission entries found")
PY
    consume_report_lines < <(QA_TARGET_SETTINGS="$f" QA_BACKUP="$f.bak-$TS" \
      QA_BP_SETTINGS="$REPO_ROOT/.claude/settings.json" QA_HOOK_NS="$NS_HOOKS" QA_DRY="$DRY_RUN" python3 "$_py_settings_uninstall")
    rm -f "$_py_settings_uninstall"
  elif [ -f "$f" ]; then
    report WARN "settings.json" "python3 not found — remove hook entries under $NS_HOOKS manually"
  fi

  # 6. .mcp.json — remove servers only if they EXACTLY match our blueprint config
  f="$TARGET/.mcp.json"
  if [ -f "$f" ] && command -v python3 >/dev/null 2>&1; then
    # temp-file approach — see the .mcp.json merge earlier for why
    local _py_mcp_uninstall
    _py_mcp_uninstall="$(mktemp)"
    cat > "$_py_mcp_uninstall" <<'PY'
import json, os, shutil
bp = json.load(open(os.environ["QA_BP_MCP"])).get("mcpServers", {})
tp = os.environ["QA_TARGET_MCP"]
backup = os.environ.get("QA_BACKUP")
dry = os.environ["QA_DRY"] == "1"
changed = False
tgt = json.load(open(tp))
servers = tgt.get("mcpServers", {})
for name, cfg in bp.items():
    if name in servers:
        if servers[name] == cfg:
            if not dry:
                del servers[name]
            changed = True
            print(f"{'DRY-RUN' if dry else 'MERGED'}|.mcp.json|{'would remove' if dry else 'removed'} server '{name}' (exact blueprint config)")
        else:
            print(f"SKIPPED|.mcp.json|kept server '{name}' — config differs from blueprint (yours)")
if changed and not dry:
    restored = False
    import glob
    for b in sorted(glob.glob(tp + ".bak-*"), reverse=True):
        try:
            if json.load(open(b)) == tgt:
                shutil.copy2(b, tp)
                print(f"MERGED|.mcp.json|restored original from {b} (byte-exact)")
                restored = True
                break
        except Exception:
            continue
    if not restored:
        if backup:
            shutil.copy2(tp, backup)
            print(f"BACKUP|backup|{tp} → {backup}")
        with open(tp, "w") as fh:
            json.dump(tgt, fh, indent=2)
            fh.write("\n")
elif not changed:
    print("SKIPPED|.mcp.json|no blueprint servers found")
PY
    consume_report_lines < <(QA_BP_MCP="$REPO_ROOT/.mcp.json" QA_TARGET_MCP="$f" QA_BACKUP="$f.bak-$TS" QA_DRY="$DRY_RUN" python3 "$_py_mcp_uninstall")
    rm -f "$_py_mcp_uninstall"
  elif [ -f "$f" ]; then
    report WARN ".mcp.json" "python3 not found — remove blueprint MCP servers manually"
  fi

  # 7. scaffold dirs/files we created — remove only if still identical to the blueprint
  local d
  for d in evidence memory projects; do
    if [ -d "$TARGET/$d" ]; then
      if diff -qr "$REPO_ROOT/$d" "$TARGET/$d" >/dev/null 2>&1; then
        if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN "$d/" "would remove $d/ (unmodified blueprint scaffold)";
        else rm -rf "$TARGET/$d"; report MERGED "$d/" "removed (was unmodified blueprint scaffold)"; fi
      else
        report WARN "$d/" "kept — content differs from blueprint scaffold (yours or modified)"
      fi
    fi
  done
  if [ -f "$TARGET/.claudeignore" ] && cmp -s "$TARGET/.claudeignore" "$REPO_ROOT/.claudeignore"; then
    if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN ".claudeignore" "would remove (pure blueprint copy)";
    else rm "$TARGET/.claudeignore"; report MERGED ".claudeignore" "removed (pure blueprint copy)"; fi
  fi
  # We no longer create a dotenv file, so uninstall never removes one either —
  # deleting a file the installer did not write is not ours to do.
  if [ -f "$TARGET/.env.playwright-secrets" ]; then
    local tmpl
    tmpl="$(mktemp)"
    cat > "$tmpl" <<'EOF'
# Secrets consumed by Playwright MCP via --secrets (values are masked in tool
# responses, so the agent never sees them). Gitignored — never commit.
# Reference per-project test users by the keys used in projects/<KEY>/PROJECT.md.
# Example:
# SHOP_QA_STANDARD_PASSWORD=replace-me
EOF
    if cmp -s "$TARGET/.env.playwright-secrets" "$tmpl"; then
      if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN ".env.playwright-secrets" "would remove (unmodified template)";
      else rm "$TARGET/.env.playwright-secrets"; report MERGED ".env.playwright-secrets" "removed (unmodified template)"; fi
    else
      report WARN ".env.playwright-secrets" "kept — modified after install"
    fi
    rm -f "$tmpl"
  fi
  # Same rule for the browser preference file: remove only the untouched
  # default; a user's own preferences (headful, profile) are theirs to keep.
  # Both seed generations count as "unmodified": the pre-0.10.0 seed had no
  # console block, the current one adds console.level warning.
  if [ -f "$TARGET/.playwright-mcp.config.json" ]; then
    local bcfg bcfg_legacy
    bcfg="$(mktemp)"; bcfg_legacy="$(mktemp)"
    cat > "$bcfg" <<'EOF'
{
  "browser": {
    "isolated": true,
    "launchOptions": { "headless": true }
  },
  "console": { "level": "warning" }
}
EOF
    cat > "$bcfg_legacy" <<'EOF'
{
  "browser": {
    "isolated": true,
    "launchOptions": { "headless": true }
  }
}
EOF
    if cmp -s "$TARGET/.playwright-mcp.config.json" "$bcfg" || cmp -s "$TARGET/.playwright-mcp.config.json" "$bcfg_legacy"; then
      if [ "$DRY_RUN" -eq 1 ]; then report DRY-RUN ".playwright-mcp.config.json" "would remove (unmodified default)";
      else rm "$TARGET/.playwright-mcp.config.json"; report MERGED ".playwright-mcp.config.json" "removed (unmodified default)"; fi
    else
      report WARN ".playwright-mcp.config.json" "kept — holds your browser preferences"
    fi
    rm -f "$bcfg" "$bcfg_legacy"
  fi

  next_step "Review remaining .bak-$TS files and delete them once satisfied"
}

# =================================================================================
# PLUGIN MODE — instructions only, nothing copied
# =================================================================================

# Writes the two keys a plugin consumer needs into the target's settings.json,
# merging rather than replacing — printing JSON for someone to paste is where typos
# and half-applied setups come from.
plugin_wire_settings() {
  local f="$TARGET/.claude/settings.json"
  if ! command -v python3 >/dev/null 2>&1; then
    report WARN "settings.json" "python3 missing — add the two keys by hand (printed above)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN "settings.json" "would add extraKnownMarketplaces + enabledPlugins (source: $REPO_ROOT)"
    return 0
  fi
  mkdir -p "$TARGET/.claude"
  [ -f "$f" ] && backup_file "$f"
  # Temp-file approach, not a heredoc inside the process substitution — the heredoc
  # never reaches python there. Same reason as the .mcp.json merge above.
  local _py
  _py="$(mktemp)"
  cat > "$_py" <<'PY'
import json, os, pathlib

path = pathlib.Path(os.environ["QA_SETTINGS"])
source = os.environ["QA_SOURCE"]
cfg = {}
if path.exists():
    try:
        cfg = json.loads(path.read_text())
    except Exception:
        print("WARN|settings.json|exists but is not valid JSON — left untouched, add the two keys by hand")
        raise SystemExit(0)

market = cfg.setdefault("extraKnownMarketplaces", {})
plugins = cfg.setdefault("enabledPlugins", {})
changed = []
if "qa-agent-blueprint" not in market:
    # Local path: reliable from a checkout, and honest about where the code is.
    # Swap for {"source": "github", "repo": "Sn4kyGit/qa-agent-blueprint"} to track a
    # remote instead.
    market["qa-agent-blueprint"] = {"source": {"source": "local", "path": source}}
    changed.append("extraKnownMarketplaces")
key = "qa-agent-blueprint@qa-agent-blueprint-marketplace"
if plugins.get(key) is not True:
    plugins[key] = True
    changed.append("enabledPlugins")

if changed:
    path.write_text(json.dumps(cfg, indent=2) + "\n")
    print("MERGED|settings.json|" + " + ".join(changed) + " written (plugin source: local checkout)")
else:
    print("SKIPPED|settings.json|marketplace and plugin already enabled")
PY
  consume_report_lines < <(QA_SETTINGS="$f" QA_SOURCE="$REPO_ROOT" python3 "$_py")
  rm -f "$_py"
}

# The plugin brings its own playwright + atlassian servers. A target that already
# defines them locally would run duplicates (two processes, two tool namespaces),
# and a local playwright without --secrets would bypass password masking. Plugin
# mode's contract is "change only the two settings keys", so this REPORTS, with
# the session-start hook repeating the finding on every first run.
plugin_check_mcp_dupes() {
  local t="$TARGET/.mcp.json"
  [ -f "$t" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local _py2
  _py2="$(mktemp)"
  cat > "$_py2" <<'PY'
import json, os
try:
    servers = json.load(open(os.environ["QA_TARGET_MCP"])).get("mcpServers", {}) or {}
except Exception:
    raise SystemExit(0)
dupes = [n for n in ("playwright", "atlassian") if n in servers]
if dupes:
    print("WARN|.mcp.json|'" + "' and '".join(dupes) + "' configured locally AND provided by the plugin — "
          "remove the local entr" + ("y" if len(dupes) == 1 else "ies") + " to dedupe "
          "(the plugin's playwright carries --secrets/--isolated; yours likely does not)")
pw = servers.get("playwright") or {}
args = [str(a) for a in (pw.get("args") or [])]
wrapped = any("qa-secrets" in a for a in args) or "qa-secrets" in str(pw.get("command") or "")
remote = pw.get("type") in ("http", "sse", "remote") or bool(pw.get("url") and not pw.get("command"))
if pw and not remote and not wrapped and "--secrets" not in args and not any(a.startswith("--secrets=") for a in args):
    print("WARN|.mcp.json|local 'playwright' has no --secrets flag — passwords would appear unmasked in tool responses while it stays registered")
PY
  consume_report_lines < <(QA_TARGET_MCP="$t" python3 "$_py2")
  rm -f "$_py2"
}

run_plugin_mode() {
  info "Plugin mode: this repo ships .claude-plugin/marketplace.json — nothing is copied."
  cat <<'EOF'

To consume the blueprint as a Claude Code plugin inside your project:

1. Add the marketplace + enable the plugin in your project's .claude/settings.json:

   {
     "extraKnownMarketplaces": {
       "qa-agent-blueprint": {
         "source": { "source": "github", "repo": "Sn4kyGit/qa-agent-blueprint" }
       }
     },
     "enabledPlugins": {
       "qa-agent-blueprint@qa-agent-blueprint-marketplace": true
     }
   }

   For a local checkout instead of GitHub:
       "source": { "source": "local", "path": "/absolute/path/to/qa-agent-blueprint" }

2. Restart Claude Code in your project; the skills/agents become available
   (e.g. /qa-agent-blueprint:test-ticket).

3. Still required locally: Node >= 18, Playwright Chromium
   (npx playwright install chromium) and Atlassian OAuth via /mcp.

4. .env.playwright-secrets must exist in your project root — the playwright MCP
   server is launched with `--secrets .env.playwright-secrets` and exits at
   startup (ENOENT) if it is missing. The plugin's SessionStart hook seeds a
   commented placeholder on first run (and gitignores it); create it by hand if
   you prefer:

       printf '# SHOP_QA_STANDARD_PASSWORD=replace-me\n' > .env.playwright-secrets

EOF
  report SKIPPED "plugin" "no files copied — that is the point of this mode"

  # Offer to do step 1 instead of leaving it as homework. Only into a real target:
  # writing these keys into the blueprint's own checkout would make it load itself.
  if [ "$TARGET" = "$REPO_ROOT" ]; then
    report SKIPPED "settings.json" "target is the blueprint repo itself — nothing to wire"
    next_step "Re-run with --target <your project> to wire the plugin into it"
    return 0
  fi
  if [ "$YES" -eq 1 ] || [ "$DRY_RUN" -eq 1 ] || [ "${WIZARD_ACTIVE:-0}" -eq 1 ]; then
    plugin_wire_settings
  else
    printf "Write those two keys into %s/.claude/settings.json now? [Y/n] " "$TARGET"
    read -r answer
    case "$answer" in
      n|N) report SKIPPED "settings.json" "left to you — the snippet is printed above" ;;
      *)   plugin_wire_settings ;;
    esac
  fi
  plugin_check_mcp_dupes
  next_step "Restart Claude Code in $TARGET and accept the trust dialog for the marketplace"
  next_step "Then run /qa-agent-blueprint:onboard-project"
}

# =================================================================================
# SELF-SETUP — the blueprint repo itself is the target (integrate special case)
# =================================================================================

run_self_setup() {
  cd "$REPO_ROOT"
  info "Self-setup of the blueprint repo: $REPO_ROOT"

  setup_playwright

  # No dotenv file is created, and no credentials are prompted for. Reason, so this
  # does not get "fixed" back: nothing in the blueprint ever loaded that file — no
  # source, no dotenv, no env block in settings.json — so the values went nowhere.
  # Worse, prompting for an API token echoed it into the terminal scrollback of a
  # repo whose central promise is that secrets stay out of sight, and the token
  # itself was pointless: the Atlassian MCP server authenticates via OAuth 2.1
  # through /mcp, not with a token. What the agent actually needs lives where it is
  # actually read: the Confluence space and the vault path prefix in
  # projects/<KEY>/PROJECT.md, and browser passwords in .env.playwright-secrets
  # (below), which Playwright MCP does load via --secrets.
  report SKIPPED "credentials" "nothing to fill in here — JIRA/Confluence auth is OAuth via /mcp; vault prefix and Confluence space live in projects/<KEY>/PROJECT.md"
  next_step "Authorize the Atlassian MCP server: run /mcp inside Claude Code"

  if [ ! -f .env.playwright-secrets ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN ".env.playwright-secrets" "would create secrets template"
    else
      cat > .env.playwright-secrets <<'EOF'
# Secrets consumed by Playwright MCP via --secrets (values are masked in tool
# responses, so the agent never sees them). Gitignored — never commit.
# Reference per-project test users by the keys used in projects/<KEY>/PROJECT.md.
# Example:
# SHOP_QA_STANDARD_PASSWORD=replace-me
EOF
      report ADDED ".env.playwright-secrets" "secrets template created (gitignored)"
    fi
  else
    report SKIPPED ".env.playwright-secrets" "already exists — untouched"
  fi

  mkdir -p evidence
  report FOUND "evidence/" "directory present (gitignored)"


  cat <<'EOF'

================ SELF-TEST CHECKLIST ================
Run these inside Claude Code (start it with `claude` in this repo):

  [ ] `claude mcp list` shows: playwright, atlassian
  [ ] `/mcp` → atlassian OAuth completed (green checkmark)
  [ ] Session start hook prints available projects and a Playwright version
  [ ] `/onboard-project` creates projects/<KEY>/ from projects/_template/
        (plugin mode: the scaffold stays in the plugin — onboarding reads it from
         $CLAUDE_PLUGIN_ROOT/projects/_template/ and writes only projects/<KEY>/)
  [ ] Only if this JIRA project covers several products: `/onboard-product` creates
        projects/<KEY>/products/<PRODUCT>/ and adds a "## Products" routing table to
        PROJECT.md. Single-product projects need none of this.
  [ ] All fixtures pass: for t in .claude/hooks/tests/*.sh; do bash "$t"; done
  [ ] `/test-ticket <REAL-TICKET>` runs end-to-end and produces:
        evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/execution_summary.json
  [ ] The Stop hook blocks session end if a test ran without execution_summary.json,
        and also if that summary does not declare its "learnings"
  [ ] A JIRA comment with attachment appears on the ticket (format per PROJECT.md)
  [ ] .env and .env.playwright-secrets are NOT tracked: `git status --ignored`

If all boxes tick: the blueprint is live. Pilot with ONE project first.
EOF
}

# =================================================================================
# INTEGRATE MODE — orchestration
# =================================================================================

# The blueprint's docs are not decoration: skills and agents point at them by path
# (`qa-manager` → docs/architecture.md, onboarding → the deploy runbook scaffold).
# Integrate mode used to copy evidence/, memory/ and projects/ but not docs/, so
# eight live references dangled in every integrated repo. Namespaced under
# docs/qa-blueprint/ so it cannot collide with the target's own docs tree.
integrate_docs() {
  if [ ! -d "$REPO_ROOT/docs" ]; then
    report SKIPPED "docs/" "no blueprint docs found — nothing to copy"
    return 0
  fi
  copy_tree "$REPO_ROOT/docs" "$TARGET/docs/qa-blueprint" "docs"
}

run_integrate() {
  if [ "$UNINSTALL" -eq 1 ]; then
    if [ "$SKILL_PROFILE_FLAG" -eq 1 ] || [ "$SKILLS_EXCLUDE_FLAG" -eq 1 ]; then
      warn "--skill-profile/--skills-exclude are ignored on uninstall"
    fi
    uninstall_integrate
    return 0
  fi
  # Target IS the blueprint repo: the files are already in place, so nothing is
  # copied or merged — only the environment is prepared. Self-setup is a branch
  # here, not a separate mode, because every copy step would be a self-copy.
  if [ "$TARGET" = "$REPO_ROOT" ]; then
    if [ "$SKILL_PROFILE_FLAG" -eq 1 ] || [ "$SKILLS_EXCLUDE_FLAG" -eq 1 ]; then
      warn "--skill-profile/--skills-exclude have no effect on self-setup (nothing is copied)"
    fi
    run_self_setup
    return 0
  fi
  info "Integrating blueprint into existing ecosystem: $TARGET"

  skill_selection_resolve
  setup_playwright
  check_ci_cli
  integrate_claude_md
  integrate_dot_claude
  integrate_mcp_json
  integrate_settings_json
  integrate_gitignore
  integrate_dirs
  integrate_docs
  rewrite_namespaced_paths   # must run AFTER every copy — it rewrites what was added

  # H18 (0.18.8): record the installed blueprint version so cross-version
  # updates and uninstalls can distinguish "ours" from "modified after install".
  local bp_version
  bp_version="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_ROOT/.claude-plugin/plugin.json" | head -1)"
  printf '{"blueprint_version":"%s","mode":"integrate","installed_at":"%s"}\n' \
    "${bp_version:-unknown}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$TARGET/.qa-blueprint-install.json"

  next_step "Run: claude mcp list → authenticate the 'atlassian' server via /mcp (OAuth 2.1)"
  next_step "Start Claude Code in $TARGET and run /onboard-project to onboard your first project"
  next_step "Review .bak-$TS backups once satisfied, then delete them"
}

# =================================================================================
# FINAL REPORT
# =================================================================================

print_report() {
  echo
  local suffix=""
  [ "$UNINSTALL" -eq 1 ] && suffix="$suffix → uninstall"
  [ "$DRY_RUN" -eq 1 ] && suffix="$suffix → dry-run"
  info "================ INSTALL REPORT ($MODE$suffix) ================"
  printf "%b%-8s  %-24s %s%b\n" "$C_DIM" "STATUS" "AREA" "DETAIL" "$C_RST"
  local line st area detail
  for line in ${REPORT[@]+"${REPORT[@]}"}; do
    st="${line%%|*}"; rest="${line#*|}"; area="${rest%%|*}"; detail="${rest#*|}"
    printf "%-8s  %-24s %s\n" "$st" "$area" "$detail"
  done
  if [ "${#NEXT_STEPS[@]}" -gt 0 ]; then
    echo
    info "Next steps:"
    local s
    for s in "${NEXT_STEPS[@]}"; do printf "  → %s\n" "$s"; done
  fi
  echo
  if [ "$DRY_RUN" -eq 1 ]; then
    ok "Dry run finished — no files were changed."
  elif [ "$UNINSTALL" -eq 1 ]; then
    ok "Uninstall complete (foreign content untouched; backups kept)."
  else
    ok "Done."
  fi
}

# =================================================================================
# OPENCODE MODE — symlink layout + opencode.json merge (docs/opencode-port-plan.md,
# Phase 6 + D10: nothing is copied, updates are a git pull of this checkout)
# =================================================================================

check_prereqs_opencode() {
  info "Checking prerequisites (opencode mode)..."
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -v | sed 's/^v//' | cut -d. -f1)"
    if [ "$major" -ge 18 ]; then
      report FOUND "node" "$(node -v) (>= 18 required)"
    else
      report MISSING "node" "$(node -v) found, but >= 18 is required — https://nodejs.org"
      exit 1
    fi
  else
    report MISSING "node" "not found — install Node.js LTS (>= 18): https://nodejs.org"
    exit 1
  fi

  if command -v opencode >/dev/null 2>&1; then
    report FOUND "opencode CLI" "$(opencode --version 2>/dev/null || echo 'version unknown')"
  else
    report MISSING "opencode CLI" "not found — install: npm install -g opencode-ai (https://opencode.ai)"
    exit 1
  fi

  if command -v python3 >/dev/null 2>&1; then
    report FOUND "python3" "needed for the opencode.json template merge"
  else
    report MISSING "python3" "needed for the opencode.json template merge"
    exit 1
  fi

  if command -v bun >/dev/null 2>&1; then
    report FOUND "bun" "$(bun --version 2>/dev/null) (runs the blueprint's plugin test suites; opencode bundles its own runtime)"
  else
    report SKIPPED "bun" "not found — only needed to run opencode/tests on the blueprint checkout, not at runtime"
  fi

  if playwright_browsers_present; then
    report FOUND "Playwright browsers" "already installed"
  else
    next_step "Install the Playwright Chromium: npx playwright install chromium"
  fi
  info "JIRA Data Center only: uv (brew install uv) for the local mcp-atlassian server — not needed for Atlassian Cloud."
}

# opencode_link <link> <source> — symlink into the blueprint checkout; foreign
# content at <link> always wins (never replaced, only reported). A symlink that
# already points into A qa-agent-blueprint checkout is ours (possibly stale after
# the checkout moved) and gets relinked; a symlink to anywhere else is foreign
# and is left untouched exactly like a foreign file — silently re-pointing it
# would rewire the consumer's own config (field report 2026-09-18).
opencode_link() {
  local link="$1" src="$2"
  if [ -L "$link" ]; then
    local cur
    cur="$(readlink "$link")"
    if [ "$cur" = "$src" ]; then
      report SKIPPED "$link" "already linked"
    elif [[ "$cur" == *qa-agent-blueprint* || "$cur" == *qa-blueprint* ]]; then
      if [ "$DRY_RUN" -eq 1 ]; then dry "relink $link -> $src (stale link into an old blueprint checkout: $cur)"; return 0; fi
      ln -sfn "$src" "$link"
      report MERGED "$link" "relinked -> $src (was $cur)"
    else
      report WARN "$link" "foreign symlink (-> $cur) left untouched — point it at $src yourself if intended"
    fi
    return 0
  fi
  if [ -e "$link" ]; then
    report SKIPPED "$link" "exists and is not our symlink — left untouched (foreign content wins)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then dry "link $link -> $src"; return 0; fi
  mkdir -p "$(dirname "$link")"
  ln -s "$src" "$link"
  report ADDED "$link" "-> $src"
}

opencode_seed_files() {
  # Both playwright MCP flags (--config, --secrets) hard-fail on ENOENT, so
  # these files must exist BEFORE the first session — the plugin's bootstrap
  # would only seed them after the server already died once.
  local secrets="$TARGET/.env.playwright-secrets" cfg="$TARGET/.playwright-mcp.config.json"
  if [ -e "$secrets" ]; then
    report SKIPPED ".env.playwright-secrets" "exists — values stay the user's job"
  elif [ "$DRY_RUN" -eq 1 ]; then
    dry "seed .env.playwright-secrets (comment-only placeholder)"
  else
    cat > "$secrets" <<'SECRETS_TEMPLATE'
# Secrets consumed by Playwright MCP via --secrets (values are masked in tool
# responses, so the agent never sees them). Gitignored — never commit.
# Reference per-project test users by the keys used in projects/<KEY>/PROJECT.md.
# Example:
# SHOP_QA_STANDARD_PASSWORD=replace-me
SECRETS_TEMPLATE
    report ADDED ".env.playwright-secrets" "comment-only placeholder — fill in your test users"
    # Gitignore only if inside a git repo and not already ignored (same
    # conditions as the plugin bootstrap; git itself may be unavailable).
    if command -v git >/dev/null 2>&1 \
       && git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 \
       && ! git -C "$TARGET" check-ignore -q .env.playwright-secrets 2>/dev/null; then
      printf '\n# QA Agent Blueprint — Playwright MCP secrets, never commit\n.env.playwright-secrets\n' >> "$TARGET/.gitignore"
      report ADDED ".gitignore" ".env.playwright-secrets entry"
    fi
  fi
  if [ -e "$cfg" ]; then
    check_browser_console_level "$cfg"
    report SKIPPED ".playwright-mcp.config.json" "exists — it is your preference dial (headful: launchOptions.headless false)"
  elif [ "$DRY_RUN" -eq 1 ]; then
    dry "seed .playwright-mcp.config.json (headless + isolated defaults)"
  else
    cat > "$cfg" <<'BROWSER_CONFIG'
{
  "browser": {
    "isolated": true,
    "launchOptions": { "headless": true }
  },
  "console": { "level": "warning" }
}
BROWSER_CONFIG
    report ADDED ".playwright-mcp.config.json" "headless + isolated defaults — edit for a visible browser"
  fi
}

# Merge opencode/opencode.template.jsonc into the target's opencode.json.
# Semantics (same spirit as the .mcp.json merge): existing mcp server NAMES
# win — except local playwright contract flags, which are fixed additively because
# the hooks/agents hard-reference them. instructions union, subagent_depth
# raised to 2, permission denies deep-merged with existing keys winning.
# No file yet → the template is copied verbatim (keeps its comments and the
# blueprint-version stamp).
opencode_config_preflight() {
  local cfg="$TARGET/opencode.json" legacy="$TARGET/opencode.jsonc"
  if { [ -e "$cfg" ] || [ -L "$cfg" ]; } && { [ -e "$legacy" ] || [ -L "$legacy" ]; }; then
    err "BLOCKED: both opencode.json and opencode.jsonc exist in $TARGET; merge them manually into opencode.json and remove opencode.jsonc before re-running"
    next_step "Resolve the dual opencode config collision manually; the installer will not choose one or write either file"
    return 1
  fi
  return 0
}

opencode_merge_config() {
  local tpl="$REPO_ROOT/opencode/opencode.template.jsonc" cfg="$TARGET/opencode.json" legacy="$TARGET/opencode.jsonc"
  opencode_config_preflight || return 1
  if [ ! -f "$cfg" ] && [ -f "$legacy" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN "opencode.jsonc" "would back up and migrate opencode.jsonc to opencode.json, then merge the template"
      return 0
    fi
    QA_JSONC_CHECK="$REPO_ROOT/.claude/scripts/agentswitch-check.py" python3 - "$legacy" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("qa_jsonc_check", os.environ["QA_JSONC_CHECK"])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.read_json(sys.argv[1], jsonc=True)
PY
    backup_file "$legacy"
    mv "$legacy" "$cfg"
    report MERGED "opencode.jsonc" "migrated to opencode.json; original backup kept"
  fi
  if [ ! -f "$cfg" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then dry "write opencode.json from template"; return 0; fi
    cp "$tpl" "$cfg"
    report ADDED "opencode.json" "from opencode.template.jsonc (mcp contract, instructions, permission denies, subagent_depth 2)"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then dry "merge template into existing opencode.json"; return 0; fi
  backup_file "$cfg"
  python3 - "$tpl" "$cfg" <<'PY'
import json, os, sys

def parse_jsonc(text):
    out = []
    i = 0
    in_string = False
    escaped = False
    while i < len(text):
        char = text[i]
        if in_string:
            out.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            i += 1
        elif char == '"':
            in_string = True
            out.append(char)
            i += 1
        elif char == "/" and i + 1 < len(text) and text[i + 1] == "/":
            i += 2
            while i < len(text) and text[i] != "\n":
                i += 1
        elif char == "/" and i + 1 < len(text) and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
        else:
            out.append(char)
            i += 1
    cleaned = []
    in_string = False
    escaped = False
    for char in "".join(out):
        if in_string:
            cleaned.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
            cleaned.append(char)
        elif char == ",":
            cleaned.append(char)
        elif char in "]}":
            while cleaned and cleaned[-1].isspace():
                cleaned.pop()
            if cleaned and cleaned[-1] == ",":
                cleaned.pop()
            cleaned.append(char)
        else:
            cleaned.append(char)
    return json.loads("".join(cleaned))

tpl = parse_jsonc(open(sys.argv[1]).read())
cfg = parse_jsonc(open(sys.argv[2]).read())

# instructions: union, template entries appended when missing
instr = cfg.get("instructions") or []
for entry in tpl.get("instructions", []):
    if entry not in instr:
        instr.append(entry)
cfg["instructions"] = instr

# subagent_depth: qa-manager (subagent) spawns leaf subagents — needs 2
if not isinstance(cfg.get("subagent_depth"), int) or cfg["subagent_depth"] < 2:
    cfg["subagent_depth"] = 2

# mcp: existing names win; local playwright contract values are fixed additively
CONTRACT_DEFAULTS = {
    "--config": ".playwright-mcp.config.json",
    "--secrets": ".env.playwright-secrets",
    "--output-dir": "evidence/.mcp-out",
    "--image-responses": "omit",
}

def flag_value(args, flag, start=0):
    value = None
    i = start
    while i < len(args):
        arg = args[i]
        if arg == flag:
            value = args[i + 1] if i + 1 < len(args) else None
            i += 1
        elif arg.startswith(flag + "="):
            value = arg.split("=", 1)[1]
        i += 1
    return value

def output_dir_ok(value):
    if not value or value.startswith("--"):
        return False
    evidence_root = os.path.realpath(os.path.join(os.path.dirname(sys.argv[2]), "evidence"))
    candidate = os.path.realpath(os.path.join(os.path.dirname(sys.argv[2]), value))
    try:
        return os.path.commonpath((evidence_root, candidate)) == evidence_root
    except ValueError:
        return False

def ensure_flag(args, flag, default, start=0):
    value = flag_value(args, flag, start)
    valid = output_dir_ok(value) if flag == "--output-dir" else bool(value and not value.startswith("--"))
    if flag == "--image-responses":
        valid = value == "omit"
    if valid:
        return False
    matches = [i for i in range(start, len(args)) if args[i] == flag or args[i].startswith(flag + "=")]
    if matches:
        i = matches[-1]
        if args[i] == flag:
            if i + 1 < len(args) and not args[i + 1].startswith("--"):
                args[i + 1] = default
            else:
                args.insert(i + 1, default)
        else:
            args[i] = flag + "=" + default
        return True
    args.extend([flag, default])
    return True

mcp = cfg.setdefault("mcp", {})
for name, entry in (tpl.get("mcp") or {}).items():
    if name not in mcp:
        mcp[name] = entry
    elif name == "playwright":
        existing = mcp[name]
        if isinstance(existing, dict) and isinstance(existing.get("command"), list):
            remote = existing.get("type") == "remote" or bool(existing.get("url") and not existing.get("command"))
            if not remote:
                args = [str(a) for a in existing["command"]]
                wrapped = any("qa-secrets" in a for a in args)
                start = args.index("--") + 1 if wrapped and "--" in args else 0
                for flag, default in CONTRACT_DEFAULTS.items():
                    if flag == "--secrets" and wrapped:
                        continue
                    ensure_flag(args, flag, default, start)
                existing["command"] = args
            if "type" not in existing:
                existing["type"] = entry.get("type", "local")

# permission: deep-merge rule maps, existing keys win
def merge_rule(dst, src):
    if isinstance(dst, dict) and isinstance(src, dict):
        for k, v in src.items():
            dst.setdefault(k, v)
        return dst
    return dst if dst is not None else src
perm = cfg.get("permission")
tpl_perm = tpl.get("permission")
if tpl_perm:
    if perm is None:
        cfg["permission"] = tpl_perm
    elif isinstance(perm, dict) and isinstance(tpl_perm, dict):
        for tool, rules in tpl_perm.items():
            perm[tool] = merge_rule(perm.get(tool), rules)

with open(sys.argv[2], "w") as fh:
    fh.write("// merged by qa-agent-blueprint install.sh (opencode mode)\n")
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
PY
  report MERGED "opencode.json" "template merged (existing mcp names kept, local playwright contract flags fixed additively, comments flattened — backup kept)"
}

opencode_uninstall() {
  info "opencode uninstall: removing only symlinks that point into $REPO_ROOT"
  local l
  for l in ".opencode/ROUTER.md" ".opencode/agents" ".opencode/commands" ".opencode/plugins" \
           ".claude" "docs" ".agents" \
           "projects/_template" "projects/EXAMPLE" ".claude-plugin" "CHANGELOG.md"; do
    local link="$TARGET/$l"
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in
      "$REPO_ROOT"|"$REPO_ROOT/"*)
        if [ "$DRY_RUN" -eq 1 ]; then dry "remove link $link"; continue; fi
        rm "$link"
        report REMOVED "$l" "symlink removed" ;;
      *)
        report SKIPPED "$l" "symlink points elsewhere — left untouched" ;;
    esac
  done
  # .opencode/ dir goes only when it is now empty (foreign files stay).
  if [ -d "$TARGET/.opencode" ] && [ -z "$(ls -A "$TARGET/.opencode" 2>/dev/null)" ]; then
    [ "$DRY_RUN" -eq 1 ] || rmdir "$TARGET/.opencode"
    report REMOVED ".opencode/" "was empty after unlinking"
  fi
  report SKIPPED "opencode.json" "merged keys left in place (harmless without the links) — remove the mcp/instructions/permission entries by hand if you want them gone"
  report SKIPPED "seed files" ".env.playwright-secrets / .playwright-mcp.config.json kept — they are your data"
  next_step "Review $TARGET/opencode.json for leftover blueprint keys"
}

run_opencode_mode() {
  info "opencode mode: symlinks into this checkout, nothing is copied (updates = git pull here)."
  if [ "$TARGET" = "$REPO_ROOT" ]; then
    err "Target is the blueprint repo itself — opencode mode installs INTO a consumer project (--target <path>)."
    exit 1
  fi
  opencode_config_preflight || exit 1
  # The blueprint's own surface (router, ported agents/commands, plugin)
  opencode_link "$TARGET/.opencode/ROUTER.md" "$REPO_ROOT/opencode/ROUTER.md"
  opencode_link "$TARGET/.opencode/agents"    "$REPO_ROOT/opencode/agents"
  opencode_link "$TARGET/.opencode/commands"  "$REPO_ROOT/opencode/commands"
  opencode_link "$TARGET/.opencode/plugins"   "$REPO_ROOT/opencode/plugins"
  # D10 compat links: skill/rule/agent bodies reference these paths literally
  opencode_link "$TARGET/.claude" "$REPO_ROOT/.claude"
  opencode_link "$TARGET/docs"    "$REPO_ROOT/docs"
  opencode_link "$TARGET/.agents" "$REPO_ROOT/.agents"
  opencode_link "$TARGET/projects/_template" "$REPO_ROOT/projects/_template"
  opencode_link "$TARGET/projects/EXAMPLE" "$REPO_ROOT/projects/EXAMPLE"
  opencode_link "$TARGET/.claude-plugin" "$REPO_ROOT/.claude-plugin"
  opencode_link "$TARGET/CHANGELOG.md" "$REPO_ROOT/CHANGELOG.md"
  opencode_seed_files
  opencode_merge_config
  next_step "Connect a provider in opencode (/connect — e.g. OpenRouter) and pick your model with /models — the blueprint pins none (D6)"
  next_step "JIRA auth: Cloud → opencode mcp auth atlassian (OAuth); Data Center → PAT in the macOS keychain, service JIRA_PAT_<jira-host> (AGENTS.md)"
  next_step "Restart opencode in $TARGET, then run /onboard-project"
  next_step "Shadow mode is ON by default — JIRA reports are composed, not posted, until you opt out (PROJECT.md or QA_AGENT_SHADOW=0)"
}

# --move <new-target>: relocate an opencode QA home. Data first (so the new
# install's seed step never shadows it), then link the surface in the new
# folder, then unlink the old one. Never overwrites anything in the new
# target — a name that already exists there is reported SKIPPED and left for
# a human merge, in both places.
run_opencode_move() {
  local old="$TARGET" new="$MOVE_TO" router_link="$TARGET/.opencode/ROUTER.md"
  info "opencode move: relocating the QA home $old → $new"
  if [ ! -L "$router_link" ]; then
    err "No opencode install found at $old (.opencode/ROUTER.md symlink missing) — nothing to move."
    exit 1
  fi
  case "$(readlink "$router_link")" in
    "$REPO_ROOT"|"$REPO_ROOT/"*) ;;
    *) err "$router_link points at $(readlink "$router_link"), not this checkout — refusing to move someone else's install."; exit 1 ;;
  esac
  if [ "$old" = "$new" ]; then
    err "--move target is the current target — nothing to do."
    exit 1
  fi
  if [ "$DRY_RUN" -eq 0 ]; then mkdir -p "$new"; fi

  # H19 (0.18.8): preflight the FUTURE state before moving anything — if the
  # new target has a legacy opencode.jsonc and the move carries opencode.json,
  # the post-move preflight would BLOCK after data has already been moved,
  # leaving a half-migrated state with no recovery path.
  if [ -f "$old/opencode.json" ] && [ -f "$new/opencode.jsonc" ] && [ ! -f "$new/opencode.json" ]; then
    err "BLOCKED: $new has opencode.jsonc but the move would bring opencode.json — merge them manually first (rename opencode.jsonc to opencode.json, or remove it)."
    exit 1
  fi

  if [ "$YES" -ne 1 ] && [ "$DRY_RUN" -eq 0 ]; then
    printf 'Move the QA home from %s to %s? Data moves, links are re-created there and removed here. [y/N] ' "$old" "$new"
    read -r answer
    case "$answer" in y|Y|yes|YES) ;; *) info "Aborted — nothing changed."; exit 0 ;; esac
  fi

  # 1. data (dirs + seed files + merged config)
  local item
  for item in projects memory evidence .env.playwright-secrets .playwright-mcp.config.json opencode.json opencode.jsonc; do
    [ -e "$old/$item" ] || continue
    if [ -e "$new/$item" ]; then
      report SKIPPED "$item" "exists in $new — left in both places; merge by hand"
      continue
    fi
    if [ "$DRY_RUN" -eq 1 ]; then dry "move $old/$item → $new/$item"; continue; fi
    mv "$old/$item" "$new/$item"
    report MOVED "$item" "$old → $new"
  done

  # 2. link the surface in the new home (seeds/merge skip what the move carried over)
  TARGET="$new"
  run_opencode_mode

  # 3. unlink the old home
  TARGET="$old"
  opencode_uninstall
  next_step "Restart opencode in $new — projects/, memory/ and evidence/ moved with you"
}

shared_link_is() {
  [ -L "$1" ] && [ "$(readlink "$1")" = "$2" ]
}

shared_preflight() {
  local collisions=() item src whole_claude=0
  opencode_config_preflight || return 1
  if [ -L "$TARGET/.claude" ]; then
    if shared_link_is "$TARGET/.claude" "$REPO_ROOT/.claude"; then
      whole_claude=1
    else
      collisions+=(".claude")
    fi
  elif [ -e "$TARGET/.claude" ] && [ ! -d "$TARGET/.claude" ]; then
    collisions+=(".claude")
  fi
  if [ -d "$TARGET/.claude" ] && [ ! -L "$TARGET/.claude" ] && [ "$whole_claude" -eq 0 ]; then
    for item in rules skills agents hooks scripts; do
      if [ -e "$TARGET/.claude/$item" ] || [ -L "$TARGET/.claude/$item" ]; then
        shared_link_is "$TARGET/.claude/$item" "$REPO_ROOT/.claude/$item" || collisions+=(".claude/$item")
      fi
    done
  fi
  for item in .opencode/ROUTER.md .opencode/agents .opencode/commands .opencode/plugins docs .claude-plugin CHANGELOG.md projects/_template projects/EXAMPLE; do
    case "$item" in
      .opencode/*) src="$REPO_ROOT/opencode/${item#.opencode/}" ;;
      *) src="$REPO_ROOT/$item" ;;
    esac
    if [ -e "$TARGET/$item" ] || [ -L "$TARGET/$item" ]; then
      shared_link_is "$TARGET/$item" "$src" || collisions+=("$item")
    fi
  done
  for item in .agents projects memory evidence; do
    if [ -e "$TARGET/$item" ] || [ -L "$TARGET/$item" ]; then
      if [ "$item" = ".agents" ] && shared_link_is "$TARGET/$item" "$REPO_ROOT/.agents"; then
        continue
      fi
      if [ ! -d "$TARGET/$item" ] || [ -L "$TARGET/$item" ]; then
        collisions+=("$item")
      fi
    fi
  done
  if [ -L "$TARGET/CLAUDE.md" ]; then
    collisions+=("CLAUDE.md")
  fi
  if { [ -e "$TARGET/.qa-home" ] || [ -L "$TARGET/.qa-home" ]; } && [ ! -f "$TARGET/.qa-home" ]; then
    collisions+=(".qa-home")
  fi
  if [ "${#collisions[@]}" -gt 0 ]; then
    for item in "${collisions[@]}"; do
      err "BLOCKED: $item exists and is not the expected shared-mode symlink; move or migrate it by hand, then re-run --mode shared"
    done
    next_step "Resolve the BLOCKED paths without deleting project data; shared mode never replaces real rules, skills, agents, hooks, scripts, docs, manifests or changelogs"
    return 1
  fi
  return 0
}

shared_prepare_claude() {
  if shared_link_is "$TARGET/.claude" "$REPO_ROOT/.claude"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN ".claude/" "would replace the opencode compatibility link with a real directory and selective links"
    else
      rm "$TARGET/.claude"
      mkdir "$TARGET/.claude"
      report MERGED ".claude/" "opencode compatibility link migrated to a real directory"
    fi
  elif [ -d "$TARGET/.claude" ]; then
    report SKIPPED ".claude/" "real consumer directory kept"
  elif [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN ".claude/" "would create a real consumer directory"
  else
    mkdir -p "$TARGET/.claude"
    report ADDED ".claude/" "real consumer directory created"
  fi
}

shared_scaffold() {
  local d
  if shared_link_is "$TARGET/.agents" "$REPO_ROOT/.agents"; then
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN ".agents/" "would replace the opencode compatibility link with a real consumer directory"
    else
      rm "$TARGET/.agents"
      mkdir "$TARGET/.agents"
      cp -R "$REPO_ROOT/.agents/." "$TARGET/.agents/"
      report MERGED ".agents/" "opencode compatibility link migrated to consumer-owned data; existing bridge files preserved"
    fi
  fi
  for d in projects evidence .agents; do
    if [ -d "$TARGET/$d" ]; then
      report SKIPPED "$d/" "exists — consumer data left untouched"
    elif [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN "$d/" "would create a real consumer directory"
    else
      mkdir -p "$TARGET/$d"
      report ADDED "$d/" "real consumer directory created"
    fi
  done
  if [ -d "$TARGET/memory" ]; then
    report SKIPPED "memory/" "exists — consumer data left untouched"
  elif [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN "memory/" "would seed the blueprint memory scaffold"
  else
    cp -r "$REPO_ROOT/memory" "$TARGET/memory"
    report ADDED "memory/" "blueprint memory scaffold seeded"
  fi
  if [ -e "$TARGET/.qa-home" ]; then
    report SKIPPED ".qa-home" "exists — left untouched"
  elif [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN ".qa-home" "would create the QA home marker"
  else
    printf 'qa-agent-blueprint home — resolved by walk-up from any subfolder\n' > "$TARGET/.qa-home"
    report ADDED ".qa-home" "QA home marker created"
  fi
}

shared_surface_links() {
  local item
  for item in rules skills agents hooks scripts; do
    opencode_link "$TARGET/.claude/$item" "$REPO_ROOT/.claude/$item"
  done
  opencode_link "$TARGET/.opencode/ROUTER.md" "$REPO_ROOT/opencode/ROUTER.md"
  opencode_link "$TARGET/.opencode/agents" "$REPO_ROOT/opencode/agents"
  opencode_link "$TARGET/.opencode/commands" "$REPO_ROOT/opencode/commands"
  opencode_link "$TARGET/.opencode/plugins" "$REPO_ROOT/opencode/plugins"
  opencode_link "$TARGET/docs" "$REPO_ROOT/docs"
  opencode_link "$TARGET/projects/_template" "$REPO_ROOT/projects/_template"
  opencode_link "$TARGET/projects/EXAMPLE" "$REPO_ROOT/projects/EXAMPLE"
  opencode_link "$TARGET/.claude-plugin" "$REPO_ROOT/.claude-plugin"
  opencode_link "$TARGET/CHANGELOG.md" "$REPO_ROOT/CHANGELOG.md"
}

shared_claude_md() {
  local f="$TARGET/CLAUDE.md"
  if [ ! -e "$f" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN "CLAUDE.md" "would copy the full shared blueprint router"
    else
      cp -p "$REPO_ROOT/CLAUDE.md" "$f"
      report ADDED "CLAUDE.md" "full shared blueprint router copied"
    fi
    return 0
  fi
  if cmp -s "$f" "$REPO_ROOT/CLAUDE.md"; then
    report SKIPPED "CLAUDE.md" "full shared blueprint router already present"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN "CLAUDE.md" "would insert or replace the managed block with the full shared blueprint router"
    return 0
  fi
  local _py_shared_router
  _py_shared_router="$(mktemp)"
  cat > "$_py_shared_router" <<'PY'
import os, shutil
path = os.environ["QA_SHARED_CLAUDE"]
source = os.environ["QA_SHARED_ROUTER"]
start = os.environ["QA_BLOCK_START"]
end = os.environ["QA_BLOCK_END"]
backup = os.environ["QA_BACKUP"]
text = open(path).read()
router = open(source).read().rstrip()
block = start + "\n\n" + router + "\n\n" + end
if start in text:
    before, rest = text.split(start, 1)
    if end not in rest:
        print("WARN|CLAUDE.md|managed block has no end marker — left untouched; repair it by hand")
        raise SystemExit(0)
    after = rest.split(end, 1)[1]
    out = before + block + after
else:
    out = text.rstrip() + "\n\n" + block + "\n"
if out == text:
    print("SKIPPED|CLAUDE.md|managed full shared router is current")
else:
    shutil.copy2(path, backup)
    print(f"BACKUP|backup|{path} → {backup}")
    with open(path, "w") as fh:
        fh.write(out)
    print("MERGED|CLAUDE.md|managed block now contains the full shared blueprint router; foreign content kept")
PY
  consume_report_lines < <(QA_SHARED_CLAUDE="$f" QA_SHARED_ROUTER="$REPO_ROOT/CLAUDE.md" QA_BLOCK_START="$CLAUDE_BLOCK_START" QA_BLOCK_END="$CLAUDE_BLOCK_END" QA_BACKUP="$f.bak-$TS" python3 "$_py_shared_router")
  rm -f "$_py_shared_router"
}

shared_disable_project_plugin() {
  local f="$TARGET/.claude/settings.json"
  if [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN "settings.json" "would set the qa-agent-blueprint project plugin entry to false"
    return 0
  fi
  local _py_shared_plugin
  _py_shared_plugin="$(mktemp)"
  cat > "$_py_shared_plugin" <<'PY'
import json, os, shutil
path = os.environ["QA_SHARED_SETTINGS"]
backup = os.environ["QA_BACKUP"]
key = "qa-agent-blueprint@qa-agent-blueprint-marketplace"
try:
    cfg = json.load(open(path))
except Exception as exc:
    print(f"WARN|settings.json|cannot disable the project plugin entry ({exc}) — left untouched")
    raise SystemExit(0)
plugins = cfg.setdefault("enabledPlugins", {})
if plugins.get(key) is False:
    print("SKIPPED|settings.json|qa-agent-blueprint plugin already disabled at project scope")
else:
    if not os.path.exists(backup):
        shutil.copy2(path, backup)
        print(f"BACKUP|backup|{path} → {backup}")
    plugins[key] = False
    with open(path, "w") as fh:
        json.dump(cfg, fh, indent=2)
        fh.write("\n")
    print("MERGED|settings.json|qa-agent-blueprint plugin disabled at project scope; marketplace metadata and other plugins kept")
PY
  consume_report_lines < <(QA_SHARED_SETTINGS="$f" QA_BACKUP="$f.bak-$TS" python3 "$_py_shared_plugin")
  rm -f "$_py_shared_plugin"
}

shared_settings_json() {
  local NS_HOOKS=".claude/hooks"
  integrate_settings_json
  shared_disable_project_plugin
}

shared_check_user_scope_plugin() {
  local f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json" enabled
  [ -f "$f" ] || return 0
  enabled="$(python3 - "$f" <<'PY' 2>/dev/null
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit(0)
if cfg.get("enabledPlugins", {}).get("qa-agent-blueprint@qa-agent-blueprint-marketplace") is True:
    print("1")
PY
)"
  if [ "$enabled" = "1" ]; then
    report WARN "user-scope plugin" "$f enables qa-agent-blueprint globally — left untouched; disable that user-scope entry manually if double loading occurs"
    next_step "Human step: review the qa-agent-blueprint enabledPlugins entry in $f; shared mode never edits global config"
  else
    report SKIPPED "user-scope plugin" "no enabled qa-agent-blueprint user-scope entry in $f"
  fi
}

shared_uninstall_router() {
  local f="$TARGET/CLAUDE.md"
  [ -f "$f" ] || return 0
  if cmp -s "$f" "$REPO_ROOT/CLAUDE.md"; then
    backup_file "$f"
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN "CLAUDE.md" "would remove the exact fresh blueprint router copy"
    else
      rm "$f"
      report REMOVED "CLAUDE.md" "exact fresh blueprint router copy removed"
    fi
  elif grep -qF "$CLAUDE_BLOCK_START" "$f"; then
    backup_file "$f"
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN "CLAUDE.md" "would remove the managed shared router block"
    else
      remove_block "$f" "$CLAUDE_BLOCK_START" "$CLAUDE_BLOCK_END"
      strip_trailing_blank_lines "$f"
      report MERGED "CLAUDE.md" "managed shared router block removed; foreign content kept"
    fi
  else
    report SKIPPED "CLAUDE.md" "no exact fresh copy or managed shared block found"
  fi
}

shared_uninstall_settings() {
  local f="$TARGET/.claude/settings.json" _py
  [ -f "$f" ] || return 0
  _py="$(mktemp)"
  cat > "$_py" <<'PY'
import glob, json, os, shutil
path = os.environ["QA_SHARED_SETTINGS"]
bp = json.load(open(os.environ["QA_BP_SETTINGS"]))
backup = os.environ["QA_BACKUP"]
dry = os.environ["QA_DRY"] == "1"
try:
    cfg = json.load(open(path))
except Exception as exc:
    print(f"WARN|settings.json|cannot clean shared references ({exc}) — left untouched")
    raise SystemExit(0)
pre = None
for candidate in sorted(glob.glob(path + ".bak-*")):
    try:
        pre = json.load(open(candidate))
        break
    except Exception:
        continue
fresh_seed = pre == {"permissions": bp.get("permissions", {}), "hooks": bp.get("hooks", {})}
def hook_pairs(config):
    return {(ev, entry.get("matcher"), hook.get("command")) for ev, entries in config.get("hooks", {}).items() for entry in entries for hook in entry.get("hooks", [])}
pre_pairs = hook_pairs(pre) if isinstance(pre, dict) else set()
bp_pairs = hook_pairs(bp)
removed_hooks = 0
hooks = cfg.get("hooks", {})
new_hooks = {}
for ev, entries in hooks.items():
    kept_entries = []
    for entry in entries:
        original = entry.get("hooks", [])
        kept = [hook for hook in original if (ev, entry.get("matcher"), hook.get("command")) not in bp_pairs or ((ev, entry.get("matcher"), hook.get("command")) in pre_pairs and not fresh_seed)]
        removed_hooks += len(original) - len(kept)
        if kept or not original:
            cleaned = dict(entry)
            if kept != original:
                cleaned["hooks"] = kept
            kept_entries.append(cleaned)
    if kept_entries:
        new_hooks[ev] = kept_entries
if new_hooks != hooks:
    if new_hooks:
        cfg["hooks"] = new_hooks
    else:
        cfg.pop("hooks", None)
removed_permissions = 0
pre_permissions = pre.get("permissions", {}) if isinstance(pre, dict) else {}
perms = cfg.get("permissions", {})
for kind in ("deny", "allow"):
    if kind not in perms:
        continue
    blueprint_entries = set(bp.get("permissions", {}).get(kind, []))
    preexisting = set(pre_permissions.get(kind, []))
    kept = [entry for entry in perms[kind] if entry not in blueprint_entries or pre is None or (entry in preexisting and not fresh_seed)]
    removed_permissions += len(perms[kind]) - len(kept)
    if kept:
        perms[kind] = kept
    else:
        perms.pop(kind, None)
if "permissions" in cfg and not cfg["permissions"]:
    cfg.pop("permissions")
if not removed_hooks and not removed_permissions:
    print("SKIPPED|settings.json|no shared blueprint hook pairs or permission entries found")
    raise SystemExit(0)
print(f"{'DRY-RUN' if dry else 'MERGED'}|settings.json|{'would remove' if dry else 'removed'} {removed_hooks} blueprint hook pair(s) and {removed_permissions} permission entr{'y' if removed_permissions == 1 else 'ies'}; foreign settings and enabledPlugins kept")
if not dry:
    shutil.copy2(path, backup)
    print(f"BACKUP|backup|{path} → {backup}")
    with open(path, "w") as fh:
        json.dump(cfg, fh, indent=2)
        fh.write("\n")
PY
  consume_report_lines < <(QA_SHARED_SETTINGS="$f" QA_BP_SETTINGS="$REPO_ROOT/.claude/settings.json" QA_BACKUP="$f.bak-$TS" QA_DRY="$DRY_RUN" python3 "$_py")
  rm -f "$_py"
}

shared_uninstall_opencode_config() {
  local f="$TARGET/opencode.json" _py
  [ -f "$f" ] || return 0
  _py="$(mktemp)"
  cat > "$_py" <<'PY'
import glob, json, os, shutil
path = os.environ["QA_SHARED_OPENCODE"]
template = os.environ["QA_OPENCODE_TEMPLATE"]
backup = os.environ["QA_BACKUP"]
dry = os.environ["QA_DRY"] == "1"
def parse_jsonc(text):
    out = []
    i = 0
    in_string = False
    escaped = False
    while i < len(text):
        char = text[i]
        if in_string:
            out.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            i += 1
        elif char == '"':
            in_string = True
            out.append(char)
            i += 1
        elif char == "/" and i + 1 < len(text) and text[i + 1] == "/":
            i += 2
            while i < len(text) and text[i] != "\n":
                i += 1
        elif char == "/" and i + 1 < len(text) and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
        else:
            out.append(char)
            i += 1
    cleaned = []
    in_string = False
    escaped = False
    for char in "".join(out):
        if in_string:
            cleaned.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
        elif char == '"':
            in_string = True
            cleaned.append(char)
        elif char == ",":
            cleaned.append(char)
        elif char in "]}":
            while cleaned and cleaned[-1].isspace():
                cleaned.pop()
            if cleaned and cleaned[-1] == ",":
                cleaned.pop()
            cleaned.append(char)
        else:
            cleaned.append(char)
    return json.loads("".join(cleaned))
try:
    cfg = parse_jsonc(open(path).read())
    tpl = parse_jsonc(open(template).read())
except Exception as exc:
    print(f"WARN|opencode.json|cannot clean shared instructions ({exc}) — left untouched")
    raise SystemExit(0)
owned = set(tpl.get("instructions", []))
pre = None
for candidate in sorted(glob.glob(path + ".bak-*")):
    try:
        pre = parse_jsonc(open(candidate).read())
        break
    except Exception:
        continue
pre_instructions = set(pre.get("instructions", [])) if isinstance(pre, dict) and isinstance(pre.get("instructions", []), list) else set()
fresh_seed = pre_instructions == owned
instructions = cfg.get("instructions")
if not isinstance(instructions, list):
    print("SKIPPED|opencode.json|no shared blueprint instructions found")
    raise SystemExit(0)
kept = [entry for entry in instructions if entry not in owned or (entry in pre_instructions and not fresh_seed)]
removed = len(instructions) - len(kept)
if not removed:
    print("SKIPPED|opencode.json|no shared blueprint instructions found")
    raise SystemExit(0)
print(f"{'DRY-RUN' if dry else 'MERGED'}|opencode.json|{'would remove' if dry else 'removed'} {removed} blueprint instruction(s); other config and MCP entries kept")
if dry:
    raise SystemExit(0)
if kept:
    cfg["instructions"] = kept
else:
    cfg.pop("instructions", None)
shutil.copy2(path, backup)
print(f"BACKUP|backup|{path} → {backup}")
with open(path, "w") as fh:
    fh.write("// merged by qa-agent-blueprint install.sh (opencode mode)\n")
    json.dump(cfg, fh, indent=2)
    fh.write("\n")
PY
  consume_report_lines < <(QA_SHARED_OPENCODE="$f" QA_OPENCODE_TEMPLATE="$REPO_ROOT/opencode/opencode.template.jsonc" QA_BACKUP="$f.bak-$TS" QA_DRY="$DRY_RUN" python3 "$_py")
  rm -f "$_py"
}

shared_uninstall() {
  info "shared uninstall: removing only symlinks that point into $REPO_ROOT"
  local item link
  for item in .claude/rules .claude/skills .claude/agents .claude/hooks .claude/scripts .opencode/ROUTER.md .opencode/agents .opencode/commands .opencode/plugins docs projects/_template projects/EXAMPLE .claude-plugin CHANGELOG.md; do
    link="$TARGET/$item"
    [ -L "$link" ] || continue
    case "$(readlink "$link")" in
      "$REPO_ROOT"|"$REPO_ROOT/"*)
        if [ "$DRY_RUN" -eq 1 ]; then
          report DRY-RUN "$item" "would remove the shared symlink"
        else
          rm "$link"
          report REMOVED "$item" "shared symlink removed"
        fi
        ;;
      *) report SKIPPED "$item" "symlink points elsewhere — left untouched" ;;
    esac
  done
  shared_uninstall_settings
  shared_uninstall_opencode_config
  shared_uninstall_router
  report SKIPPED "consumer config" ".mcp.json, seed files and enabledPlugins=false left untouched"
  report SKIPPED "consumer data" "projects/, memory/, evidence/, .agents/ and .qa-home left untouched"
  next_step "Re-enable qa-agent-blueprint@qa-agent-blueprint-marketplace manually if you want to return to plugin mode; shared uninstall leaves the project false entry unchanged"
}

check_prereqs_shared() {
  check_prereqs_opencode
  local claude_bin="" c
  if command -v claude >/dev/null 2>&1; then
    claude_bin="$(command -v claude)"
  else
    for c in "${CLAUDE_CODE_EXECPATH:-}" "$HOME/.local/bin/claude" "$HOME/.claude/local/claude" "/usr/local/bin/claude" "/opt/homebrew/bin/claude"; do
      [ -n "$c" ] && [ -x "$c" ] && { claude_bin="$c"; break; }
    done
  fi
  if [ -n "$claude_bin" ]; then
    report FOUND "claude CLI" "$("$claude_bin" --version 2>/dev/null || echo 'version unknown')"
  else
    report MISSING "claude CLI" "not found — install: npm install -g @anthropic-ai/claude-code"
    exit 1
  fi
}

run_shared_mode() {
  info "shared mode: Claude Code and opencode use one QA home without the Claude plugin"
  if [ "$TARGET" = "$REPO_ROOT" ]; then
    err "Target is the blueprint repo itself — shared mode installs INTO a consumer project (--target <path>)."
    exit 1
  fi
  shared_preflight || exit 1
  shared_prepare_claude
  shared_scaffold
  shared_surface_links
  shared_claude_md
  shared_settings_json
  integrate_mcp_json
  opencode_seed_files
  if cmp -s "$TARGET/opencode.json" "$REPO_ROOT/opencode/opencode.template.jsonc"; then
    report SKIPPED "opencode.json" "already matches the shared template"
  else
    opencode_merge_config
  fi
  integrate_gitignore
  shared_check_user_scope_plugin
  next_step "Restart Claude Code and opencode in $TARGET; existing projects need no re-onboarding"
  next_step "JIRA auth: Claude /mcp; opencode Cloud via opencode mcp auth atlassian, Data Center via PAT (AGENTS.md)"
  next_step "Shadow mode is ON by default — JIRA reports are composed, not posted, until you opt out"
}

# =================================================================================
# MAIN
# =================================================================================

if [ "$WIZARD_FORCE" -eq 1 ] && [ "$WIZARD_DISABLED" -eq 1 ]; then
  err "--wizard and --no-wizard are mutually exclusive"
  exit 1
fi
if [ "$WIZARD_FORCE" -eq 1 ] && [ "$YES" -eq 1 ]; then
  err "--wizard and --yes are mutually exclusive; use --yes for automation or remove it for the guided wizard"
  exit 1
fi
if [ "$WIZARD_FORCE" -eq 1 ] && [ "$UNINSTALL" -eq 0 ] && [ -z "$MOVE_TO" ]; then
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    err "--wizard needs an interactive terminal"
    exit 1
  fi
  wizard_run
elif wizard_interactive; then
  wizard_run
else
  JIRA_KIND="${JIRA_KIND:-cloud}"
  BROWSER_MODE="${BROWSER_MODE:-headless}"
  MODEL_SETUP_MODE="${MODEL_SETUP_MODE:-skip}"
fi
if [ ! -d "$TARGET" ]; then
  err "Target directory does not exist: $TARGET"
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"
if [ "$JIRA_KIND" = "datacenter" ] && [ -z "$JIRA_URL" ]; then
  err "--jira datacenter requires --jira-url"
  exit 1
fi
if [ "$MODEL_SETUP_MODE" = "now" ] && { [ "$MODE" = "opencode" ] || [ "$MODE" = "shared" ]; }; then
  if [ -z "$MODEL_CHEAP" ] || [ -z "$MODEL_STANDARD" ] || [ -z "$MODEL_DEEP" ]; then
    err "--model-setup now requires --cheap, --standard and --deep provider/model values"
    exit 1
  fi
fi
autodetect_mode
if [ "$MODE" != "integrate" ] && { [ "$SKILL_PROFILE_FLAG" -eq 1 ] || [ "$SKILLS_EXCLUDE_FLAG" -eq 1 ]; }; then
  warn "--skill-profile/--skills-exclude apply to integrate mode only (v1) — ignored in $MODE mode"
  SKILL_PROFILE_FLAG=0
  SKILLS_EXCLUDE_FLAG=0
fi
[ "$DRY_RUN" -eq 1 ] && info "DRY RUN — actions are reported, nothing is written."

if [ "$UNINSTALL" -eq 1 ] && [ "$MODE" != "integrate" ] && [ "$MODE" != "opencode" ] && [ "$MODE" != "shared" ]; then
  err "--uninstall only makes sense with --mode integrate, --mode opencode or --mode shared."
  exit 1
fi

if [ -n "$MOVE_TO" ]; then
  if [ "$MODE" != "opencode" ]; then
    err "--move only makes sense with --mode opencode (shared is not movable; plugin/integrate: install into the new target)."
    exit 1
  fi
  if [ "$UNINSTALL" -eq 1 ]; then
    err "--move already unlinks the old target — drop --uninstall."
    exit 1
  fi
fi

if [ "$MODE" = "opencode" ]; then
  check_prereqs_opencode
elif [ "$MODE" = "shared" ]; then
  check_prereqs_shared
else
  check_prereqs
fi

case "$MODE" in
  integrate)  run_integrate ;;
  plugin)     run_plugin_mode ;;
  shared)
    if [ "$UNINSTALL" -eq 1 ]; then shared_uninstall
    else run_shared_mode; fi
    ;;
    opencode)
    if [ "$UNINSTALL" -eq 1 ]; then opencode_uninstall
    elif [ -n "$MOVE_TO" ]; then run_opencode_move
    else run_opencode_mode; fi
    ;;
esac

wizard_apply_preferences
print_report

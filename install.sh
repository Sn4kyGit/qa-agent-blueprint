#!/usr/bin/env bash
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
#   ./install.sh [--mode integrate|plugin] [--target <path>]
#                [--dry-run] [--yes] [--uninstall]
#                [--non-interactive] [-h|--help]
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
  sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# --- argument parsing ----------------------------------------------------------
MODE=""
TARGET="$PWD"
DRY_RUN=0
YES=0
UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)             MODE="${2:?--mode needs a value}"; shift 2 ;;
    --mode=*)           MODE="${1#*=}"; shift ;;
    --target)           TARGET="${2:?--target needs a path}"; shift 2 ;;
    --target=*)         TARGET="${1#*=}"; shift ;;
    --dry-run)          DRY_RUN=1; shift ;;
    --yes|-y)           YES=1; shift ;;
    --non-interactive)  YES=1; shift ;;  # backwards-compatible alias
    --uninstall)        UNINSTALL=1; shift ;;
    -h|--help)          usage ;;
    *) err "Unknown argument: $1 (see --help)"; exit 1 ;;
  esac
done

case "$MODE" in
  ""|integrate|plugin) ;;
  *) err "Invalid --mode '$MODE' (expected integrate|plugin)"; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -d "$TARGET" ]; then
  err "Target directory does not exist: $TARGET"
  exit 1
fi
TARGET="$(cd "$TARGET" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"

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
    (r'docs/(?!qa-blueprint/)(architecture\.md|integration\.md|artifact-strategy\.md|memory-layers\.md|runbooks/|rules/)',
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
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    sys.stdout.write(rewrite(text) if path.endswith(REWRITABLE) else text)
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
    if [ "$YES" -eq 1 ]; then
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
    if [ "$YES" -eq 1 ]; then
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

  # Skills → per-skill collision check
  local s name
  if [ ! -d "$REPO_ROOT/.claude/skills" ]; then
    report SKIPPED "skills" "no blueprint skills found — nothing to copy"
  fi
  for s in "$REPO_ROOT/.claude/skills"/*/; do
    [ -d "$s" ] || continue
    name="$(basename "$s")"
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
# in tool responses, --isolated prevents state leaking between runs, --output-dir
# keeps raw artifacts out of the way. "Existing wins" would silently drop those
# protections, so for THIS server the blueprint config wins when flags are missing.
REQUIRED_FLAGS = ("--secrets", "--isolated", "--headless", "--output-dir")

def has_flag(cfg, flag):
    args = cfg.get("args") or []
    return any(a == flag or a.startswith(flag + "=") for a in args)

for name, cfg in bp.get("mcpServers", {}).items():
    if name in servers:
        existing = servers[name]
        if existing == cfg:
            print(f"SKIPPED|.mcp.json|server '{name}' already configured (identical)")
        elif name == "playwright":
            missing = [f for f in REQUIRED_FLAGS if not has_flag(existing, f)]
            if not missing:
                print(f"SKIPPED|.mcp.json|kept existing 'playwright' — it already carries the blueprint security flags")
            elif dry:
                print(f"DRY-RUN|.mcp.json|would upgrade 'playwright' to the blueprint config (missing security flags: {', '.join(missing)})")
            else:
                servers[name] = cfg
                changed = True
                print(f"MERGED|.mcp.json|upgraded 'playwright' to the blueprint config — added {', '.join(missing)} (password masking / session isolation are part of the security model; your previous config is in the backup)")
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
          report WARN ".mcp.json" "kept existing 'playwright' — VERIFY it carries the security flags: --secrets .env.playwright-secrets --isolated --headless --output-dir evidence/.mcp-out (unmasked passwords otherwise)"
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

# hooks: append per event, dedup by command string
hooks = tgt.setdefault("hooks", {})
for ev, entries in bp.get("hooks", {}).items():
    lst = hooks.setdefault(ev, [])
    existing_cmds = {h.get("command") for e in lst for h in e.get("hooks", [])}
    for e in entries:
        matcher = e.get("matcher")
        new_hooks = [dict(h, command=h.get("command", "").replace("/.claude/hooks/", f"/{ns}/"))
                     for h in e.get("hooks", [])]
        todo = [h for h in new_hooks if h["command"] not in existing_cmds]
        for h in new_hooks:
            if h["command"] in existing_cmds:
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
            existing_cmds.update(h["command"] for h in todo)
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
    # Swap for {"source": "github", "repo": "Sn4kyGit/claude_blueprint"} to track a
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
args = pw.get("args") or []
if pw and "--secrets" not in args and not any(a.startswith("--secrets=") for a in args):
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
         "source": { "source": "github", "repo": "Sn4kyGit/claude_blueprint" }
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
  if [ "$YES" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
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
    uninstall_integrate
    return 0
  fi
  # Target IS the blueprint repo: the files are already in place, so nothing is
  # copied or merged — only the environment is prepared. Self-setup is a branch
  # here, not a separate mode, because every copy step would be a self-copy.
  if [ "$TARGET" = "$REPO_ROOT" ]; then
    run_self_setup
    return 0
  fi
  info "Integrating blueprint into existing ecosystem: $TARGET"

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
# MAIN
# =================================================================================

autodetect_mode
[ "$DRY_RUN" -eq 1 ] && info "DRY RUN — actions are reported, nothing is written."

if [ "$UNINSTALL" -eq 1 ] && [ "$MODE" != "integrate" ]; then
  err "--uninstall only makes sense with --mode integrate (or auto-detected integrate)."
  exit 1
fi

check_prereqs

case "$MODE" in
  integrate)  run_integrate ;;
  plugin)     run_plugin_mode ;;
esac

print_report

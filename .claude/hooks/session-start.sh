#!/usr/bin/env bash
#
# session-start.sh — SessionStart hook. Prints compact orientation context:
# available projects, Playwright version, and (plugin mode only) the plugin's
# own CLAUDE.md, injected verbatim as the router — plugins do not load CLAUDE.md,
# and a hand-maintained summary here would be a second source of truth drifting
# from the real router with every edit.
#
# Detects plugin mode automatically: if the running project has no managed
# qa-agent-blueprint block in CLAUDE.md and no .claude/rules/qa-blueprint/
# namespace, this is a plugin-mode bootstrap — inject the router and scaffold
# projects/, memory/, evidence/ from the plugin's own copies (never overwriting
# existing content). Otherwise (the blueprint repo itself, or integrate mode
# where CLAUDE.md/.claude/rules/qa-blueprint already exist) just print the
# short preamble; the router already lives in the project's own CLAUDE.md.
#
set -uo pipefail

INPUT="$(cat)"
CWD="$PWD"
if command -v python3 >/dev/null 2>&1; then
  parsed_cwd="$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("cwd") or "")' 2>/dev/null || true)"
  [ -n "$parsed_cwd" ] && CWD="$parsed_cwd"
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# Own directory: resolve-secrets.sh ships next to this script in every mode
# (plugin root, integrate-mode namespace copy, this repo).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# QA home discovery (field report 0.9.1 — "dual evidence scaffold"): sessions
# may start in a SUBFOLDER of the QA home (a product repo inside the customer
# workspace). Data belongs at the workspace root, never duplicated into the
# subfolder — so walk up from cwd to the nearest directory carrying the
# .qa-home marker or the legacy trio (projects/ + memory/ + evidence/),
# stopping at $HOME. Nothing found → cwd itself is the (fresh) home, as
# documented for a first install.
qa_home_of() {
  local d="$1"
  while : ; do
    if [ -e "$d/.qa-home" ] || { [ -d "$d/projects" ] && [ -d "$d/memory" ] && [ -d "$d/evidence" ]; }; then
      printf '%s' "$d"; return 0
    fi
    if { [ -n "${HOME:-}" ] && [ "$d" = "$HOME" ]; } || [ "$d" = "/" ]; then break; fi
    d="$(dirname "$d")"
  done
  printf '%s' "$1"
}
QA_HOME_FROM=""
if [ "$CWD" != "/" ]; then
  resolved="$(qa_home_of "$CWD")"
  if [ "$resolved" != "$CWD" ]; then QA_HOME_FROM="$CWD"; CWD="$resolved"; fi
fi
# Resolved via the legacy trio but no marker yet → stamp it for the next
# walk-up (harmless, one tiny file at the root).
if [ -n "$QA_HOME_FROM" ] && [ ! -e "$CWD/.qa-home" ]; then
  printf 'qa-agent-blueprint home — resolved by walk-up from any subfolder\n' > "$CWD/.qa-home" 2>/dev/null || true
fi
# Harness-scoped files (MCP config, the two seed files) belong to the SESSION's
# cwd — the harness reads them from where it was started, not from the QA home.
# Data (projects/, memory/, evidence/) uses $CWD, which is the home by now.
SESSION_CWD="${QA_HOME_FROM:-$CWD}"

is_plugin_bootstrap() {
  [ -n "$PLUGIN_ROOT" ] || return 1
  [ -d "$CWD/.claude/rules/qa-blueprint" ] && return 1
  [ -f "$CWD/CLAUDE.md" ] && grep -qF '<!-- >>> qa-agent-blueprint (managed, do not edit) -->' "$CWD/CLAUDE.md" 2>/dev/null && return 1
  return 0
}

playwright_version() {
  npx --no-install playwright --version 2>/dev/null || echo "not installed"
}

# Products of one project, rendered inline: " (products: STOREFRONT, ADMIN)".
# Inline and capped on purpose — one line per product would turn a three-line
# preamble into a wall for a project with a dozen of them. Costs no file reads,
# just one more glob level, and prints nothing at all when the project has no
# products/ directory, which keeps the single-product output byte-identical.
product_suffix() {
  local proj_dir="$1" p pname count=0 list=""
  [ -d "$proj_dir/products" ] || return 0
  for p in "$proj_dir"/products/*/; do
    # Guard: an existing but EMPTY products/ leaves the glob unexpanded, which
    # would otherwise print a literal '*' as a product name.
    [ -d "$p" ] || continue
    pname="$(basename "$p")"
    case "$pname" in _template) continue ;; esac
    count=$((count + 1))
    [ "$count" -le 6 ] && list="${list:+$list, }$pname"
  done
  [ "$count" -eq 0 ] && return 0
  if [ "$count" -gt 6 ]; then
    printf ' (products: %s, +%s more)' "$list" "$((count - 6))"
  else
    printf ' (products: %s)' "$list"
  fi
}

list_projects() {
  local d name found=0
  for d in "$CWD"/projects/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    case "$name" in _template|EXAMPLE) continue ;; esac
    echo "  - $name$(product_suffix "$d")"
    found=1
  done
  # One branch for all three empty cases: no projects/ directory, an empty one,
  # and one holding nothing but the scaffold/reference dirs — the last of which
  # is the state of every fresh install, where this used to print a blank line.
  [ "$found" -eq 1 ] || echo "  (none yet — run /onboard-project)"
}

# The playwright MCP server is launched with `--config .playwright-mcp.config.json`
# and that flag is a hard fail on a missing file (ENOENT), exactly like --secrets.
# The file is the consumer's OWN preference dial: headless/headful, isolated or
# persistent profile, viewport, browser channel. Seed the defaults if missing,
# never overwrite — the file belongs to the user. Returns via stdout a note when
# it created the file (transparency, and a restart hint: the server reads the
# file at launch).
seed_browser_config() {
  local f="$SESSION_CWD/.playwright-mcp.config.json"
  [ -f "$f" ] && return 0
  cat > "$f" <<'BROWSER_CONFIG' 2>/dev/null || return 0
{
  "browser": {
    "isolated": true,
    "launchOptions": { "headless": true }
  },
  "console": { "level": "warning" }
}
BROWSER_CONFIG
  SEEDED_BROWSER_CONFIG=1
  # Gitignore is NOT touched: unlike .env.playwright-secrets this file holds no
  # secrets — it is a preference file and may be committed if the user wants.
}

# Render the effective browser mode for the preamble, e.g. "headless, isolated".
# Silent when the config is unreadable — the server failing at launch is the
# loud failure; a hook should not editorialize on a file it cannot parse.
browser_mode() {
  local f="$SESSION_CWD/.playwright-mcp.config.json"
  [ -f "$f" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$f" <<'PY' 2>/dev/null
import json, sys
try:
    cfg = json.load(open(sys.argv[1])).get("browser", {})
except Exception:
    sys.exit(0)
headless = cfg.get("launchOptions", {}).get("headless")
mode = {True: "headless", False: "headful (visible)"}.get(headless)
iso = {True: "isolated", False: "persistent profile"}.get(cfg.get("isolated"))
parts = [p for p in (mode, iso) if p]
if parts:
    print(", ".join(parts) + " (your .playwright-mcp.config.json)")
PY
}

# Plugin-mode update notice: compare the RUNNING plugin version against the
# version the known marketplaces currently advertise — offline, reading only
# ~/.claude/plugins/known_marketplaces.json and each marketplace's local
# marketplace.json. A git-sourced marketplace reflects its last
# `claude plugin marketplace update`, which is exactly the semantics wanted:
# "your checkout knows a newer version than the one running". Silent on any
# error — a hook must never hang on network or fail the session over a hint.
update_notice() {
  [ -n "$PLUGIN_ROOT" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - "$PLUGIN_ROOT" "$HOME" <<'PY' 2>/dev/null
import json, os, sys

plugin_root, home = sys.argv[1], sys.argv[2]

def version_tuple(v):
    try:
        return tuple(int(x) for x in str(v).split("."))
    except Exception:
        return None

try:
    running = json.load(open(os.path.join(plugin_root, ".claude-plugin", "plugin.json")))
except Exception:
    sys.exit(0)
name, rv = running.get("name"), version_tuple(running.get("version"))
if not name or rv is None:
    sys.exit(0)

try:
    known = json.load(open(os.path.join(home, ".claude", "plugins", "known_marketplaces.json")))
except Exception:
    sys.exit(0)

best = None
for mp in known.values():
    loc = mp.get("installLocation")
    if not loc:
        continue
    try:
        mpm = json.load(open(os.path.join(loc, ".claude-plugin", "marketplace.json")))
    except Exception:
        continue
    for entry in mpm.get("plugins", []):
        if entry.get("name") == name:
            ev = version_tuple(entry.get("version"))
            if ev and (best is None or ev > best):
                best = ev

if best and best > rv:
    print("\n- UPDATE: %s %s is available (running %s) — run `claude plugin marketplace update` + `claude plugin update %s`, then restart; /whats-new afterwards shows what changed since your projects were onboarded."
          % (name, ".".join(map(str, best)), ".".join(map(str, rv)), name))
PY
}

bootstrap_dirs() {
  local d
  for d in memory evidence; do
    if [ ! -d "$CWD/$d" ] && [ -d "$PLUGIN_ROOT/$d" ]; then
      cp -r "$PLUGIN_ROOT/$d" "$CWD/$d" 2>/dev/null || true
    fi
  done
  # projects/ is created EMPTY on purpose: it holds the consumer's own onboarded
  # projects. projects/_template (scaffold) and projects/EXAMPLE (reference) stay
  # in the plugin and are read from $PLUGIN_ROOT on demand by onboard-project —
  # copying them would fork scaffolds that plugin updates can no longer reach.
  # (Copying the whole projects/ tree here is what the comment used to claim it
  # avoided while doing exactly that.)
  [ -d "$CWD/projects" ] || mkdir -p "$CWD/projects" 2>/dev/null || true

  # The QA-home marker makes future walk-up resolution unambiguous (the legacy
  # trio works too, but only once all three dirs exist).
  [ -e "$CWD/.qa-home" ] || printf 'qa-agent-blueprint home — resolved by walk-up from any subfolder\n' > "$CWD/.qa-home" 2>/dev/null || true

  # Playwright MCP is launched with `--secrets .env.playwright-secrets` and that
  # flag is a hard fail: a missing file makes the server exit at startup
  # (ENOENT), so plugin users would get a dead browser server with no obvious
  # cause. install.sh seeds this template in integrate mode (including
  # self-setup); plugin
  # mode copies nothing, so seed the same placeholder here. Values stay the
  # user's job — this file never contains anything but comments when written.
  if [ ! -f "$SESSION_CWD/.env.playwright-secrets" ]; then
    cat > "$SESSION_CWD/.env.playwright-secrets" <<'SECRETS_TEMPLATE' 2>/dev/null || true
# Secrets consumed by Playwright MCP via --secrets (values are masked in tool
# responses, so the agent never sees them). Gitignored — never commit.
# Reference per-project test users by the keys used in projects/<KEY>/PROJECT.md.
# Example:
# SHOP_QA_STANDARD_PASSWORD=replace-me
SECRETS_TEMPLATE
    # Plugin mode copies no .gitignore, so the consumer repo may not ignore this
    # file yet. Only append if git says it isn't already ignored.
    if command -v git >/dev/null 2>&1 \
       && git -C "$SESSION_CWD" rev-parse --git-dir >/dev/null 2>&1 \
       && ! git -C "$SESSION_CWD" check-ignore -q .env.playwright-secrets 2>/dev/null; then
      printf '\n# QA Agent Blueprint — Playwright MCP secrets, never commit\n.env.playwright-secrets\n' \
        >> "$SESSION_CWD/.gitignore" 2>/dev/null || true
    fi
  fi
}

# The Stop hook forces learnings to be CAPTURED; nothing forces them to be groomed,
# so an inbox quietly grows until it is useless. Count ungroomed entries (capture
# headers, "## YYYY-MM-DD — ...") and say so once per session. Counting only, no
# file content in the context, and silent at zero. Past the auto-groom threshold
# (5+ entries or oldest entry older than 14 days) the hint to the human becomes a
# directive to the agent: groom without waiting for a /retro-learn command —
# people who never type slash commands are exactly who this is for.
inbox_status() {
  local inbox="$CWD/memory/learnings/_inbox.md" n oldest overdue=0
  [ -f "$inbox" ] || return 0
  n="$(grep -cE '^## [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$inbox" 2>/dev/null || echo 0)"
  # The template ships one illustrative example entry; one is not a backlog.
  [ "${n:-0}" -gt 1 ] || return 0
  oldest="$(grep -oE '^## [0-9]{4}-[0-9]{2}-[0-9]{2} ' "$inbox" 2>/dev/null \
    | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | sort | head -1)"
  if [ -n "$oldest" ]; then
    overdue="$(python3 -c "
import datetime, sys
try:
    d = datetime.date.fromisoformat('$oldest')
    print(1 if (datetime.date.today() - d).days > 14 else 0)
except Exception:
    print(0)
" 2>/dev/null || echo 0)"
  fi
  if [ "${n:-0}" -ge 5 ] || [ "$overdue" = "1" ]; then
    printf '\n- AUTO-GROOM: %s ungroomed learnings in memory/learnings/_inbox.md (oldest: %s) — over the auto-groom threshold (5 entries or 14 days). Without waiting for a command: groom and promote them via the retro-learn skill at the end of this session, then report in one sentence what was promoted. All gates apply as usual (seen: 2, _rejected.md, routing re-measurement).' "$n" "${oldest:-unknown}"
  else
    printf '\n- %s ungroomed learnings in memory/learnings/_inbox.md — run /retro-learn to groom and promote them (knowledge only counts once it reaches a rule, a PROJECT.md or a PRODUCT.md).' "$n"
  fi
}

# A hook cannot ask an MCP server whether it started — but it CAN see what is
# configured, read-only: ~/.claude.json (user scope) and .mcp.json (project
# scope). Prints space-separated flags: HAS_PW, HAS_AT, PW_UNMASKED (a playwright
# config without --secrets — passwords would appear unmasked in tool responses),
# PW_NO_OUTDIR (no --output-dir — raw artifacts would not land in evidence/).
# Headless/headful and --isolated are deliberately NOT flagged: they are user
# preferences, not contract (see docs/rules/testing/playwright-mcp.md).
mcp_scan() {
  command -v python3 >/dev/null 2>&1 || return 1
  # MCP config is harness-scoped: the harness loaded servers from the
  # SESSION's cwd, which may be a subfolder of the QA home (0.9.1 walk-up
  # already moved $CWD to the home) — scan the original cwd for .mcp.json.
  python3 - "${QA_HOME_FROM:-$CWD}" "$HOME" <<'PY'
import json, os, sys
cwd, home = sys.argv[1], sys.argv[2]

def load(path):
    try:
        with open(path) as fh:
            return json.load(fh).get("mcpServers", {}) or {}
    except Exception:
        return {}

servers = {}
per_file = {}
for path in (os.path.join(home, ".claude.json"), os.path.join(cwd, ".mcp.json")):
    entries = load(path)
    per_file[path] = set(entries)
    for name, cfg in entries.items():
        servers.setdefault(name, []).append(cfg if isinstance(cfg, dict) else {})

# Foreign MCP servers: configured globally (~/.claude.json) but NOT declared
# in this project's .mcp.json — they may belong to another project entirely
# (field report 2026-09-22: a global gitlab server pointed at a different
# customer's .env). The PreToolUse guard blocks their use; surface the trap
# here before the agent walks into it.
foreign = sorted(
    per_file.get(os.path.join(home, ".claude.json"), set())
    - per_file.get(os.path.join(cwd, ".mcp.json"), set())
    - {"playwright", "atlassian"}
)

pw = servers.get("playwright", [])
flags = []
if pw:
    flags.append("HAS_PW")
    # A playwright entry launched through qa-secrets.mjs mcp satisfies the
    # secrets contract by construction (ephemeral mask file, appended
    # --secrets) — the literal flag is inside the wrapper, not the args.
    def _wraps_qa_secrets(c):
        parts = [str(a) for a in (c.get("args") or [])] + [str(c.get("command") or "")]
        return any("qa-secrets" in p for p in parts)
    if not any("--secrets" in (c.get("args") or []) or _wraps_qa_secrets(c) for c in pw):
        flags.append("PW_UNMASKED")
    if not any("--output-dir" in (c.get("args") or []) for c in pw):
        flags.append("PW_NO_OUTDIR")
    if not any(a == "--image-responses" or a.startswith("--image-responses=")
               for c in pw for a in (c.get("args") or [])):
        flags.append("PW_NO_IMAGEOMIT")
at = servers.get("atlassian", [])
if at:
    flags.append("HAS_AT")
# JIRA Data Center entries carry their instance URL in env.JIRA_URL (the Cloud
# remote server does not). The host names the Keychain service the session's
# PAT is resolved from: JIRA_PAT_<host>. First host wins — one JIRA per QA
# home is the architecture (docs/rules/core/token-discipline.md).
import re as _re
for c in at:
    url = (c.get("env") or {}).get("JIRA_URL") or ""
    host = _re.sub(r"^https?://", "", url).split("/")[0] if url else ""
    if host:
        flags.append("AT_DC_HOST:" + host)
        break
if foreign:
    flags.append("FOREIGN_MCP:" + ",".join(foreign))
print(" ".join(flags))
PY
}

# The two most likely day-one failures are not detectable from here (liveness),
# so turn the configured-state scan into a concrete hint instead of pretending to
# know more: this is only printed while no project has been onboarded yet.
# The MCP contract is: NAME (playwright/atlassian — hooks and skills match on
# them) + --secrets + --output-dir + --image-responses omit. Everything else
# (headless/headful, isolated,
# viewport, browser channel) is the user's preference, exercised via
# .playwright-mcp.config.json or their own flags — never a warning here.
mcp_hint() {
  local scan="$MCP_SCAN"
  # Foreign global-only MCP servers: warn ALWAYS (before the project-exists
  # early returns) — a server from another project's config is a trap in any
  # session state, and the guard blocks its use.
  case "$scan" in
    *FOREIGN_MCP:*)
      printf '\n- Global MCP servers visible but NOT declared in this project — the guard blocks them until declared here (they may belong to another project): %s' \
        "$(printf '%s' "$scan" | sed -E 's/.*FOREIGN_MCP:([^ ]*).*/\1/' | tr ',' ' ')" ;;
  esac
  [ -d "$CWD/projects" ] || return 0
  local d
  for d in "$CWD"/projects/*/; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in _template|EXAMPLE) continue ;; esac
    return 0   # a real project exists — the user is past first-run setup
  done
  local scan="$MCP_SCAN"
  # Contract violations are findings in any mode. Order: security, then evidence.
  case "$scan" in
    *PW_UNMASKED*)
      printf '\n- WARNING: an existing playwright MCP config has no --secrets flag — passwords would appear unmasked in tool responses. Add `--secrets .env.playwright-secrets` (and fill that file) or remove the entry and use the blueprint-provided server.' ;;
  esac
  case "$scan" in
    *PW_NO_OUTDIR*)
      printf '\n- WARNING: an existing playwright MCP config has no --output-dir flag — raw browser artifacts would not land in evidence/, breaking the evidence policy. Add `--output-dir evidence/.mcp-out` or use the blueprint-provided server.' ;;
  esac
  case "$scan" in
    *PW_NO_IMAGEOMIT*)
      printf '\n- WARNING: an existing playwright MCP config has no --image-responses omit — every screenshot lands in the model context as an image (~1-2k tokens per shot). Add `--image-responses omit` or use the blueprint-provided server.' ;;
  esac
  if [ "$PLUGIN_BOOTSTRAP" -eq 1 ]; then
    # Verified behavior: a project .mcp.json does NOT override a plugin-provided
    # server of the same name — it duplicates it (two processes, two tool
    # namespaces), and a plugin's MCP servers cannot be disabled individually.
    case "$scan" in
      *HAS_PW*|*HAS_AT*)
        printf '\n- NOTE: playwright/atlassian are configured locally AND ship with the plugin — Claude Code runs BOTH (no override). Remove the local entry unless it is a deliberate replacement (e.g. JIRA Data Center); browser preferences (headful, viewport, profile) belong in .playwright-mcp.config.json, not in a second server.' ;;
      *) printf '\n- MCP servers come from the plugin (playwright, atlassian) — confirm both are live: `claude mcp list`; atlassian auth: Cloud = /mcp OAuth once, Data Center = JIRA_URL/JIRA_PERSONAL_TOKEN env vars. Browser mode: .playwright-mcp.config.json (headful = launchOptions.headless false).' ;;
    esac
    return 0
  fi
  case "$scan" in
    *HAS_PW*HAS_AT*|*HAS_AT*HAS_PW*)
      printf '\n- MCP config for playwright + atlassian found — confirm both are live (`claude mcp list`; atlassian auth: Cloud = /mcp OAuth once, Data Center = PAT env vars).';;
    *)
      printf '\n- First run: confirm both MCP servers are live before testing — `claude mcp list` should show playwright and atlassian, and atlassian must be authorized (Cloud: /mcp OAuth; Data Center: JIRA_URL/JIRA_PERSONAL_TOKEN in the environment). A dead playwright server and an unauthorized atlassian are the two failures that look like a broken blueprint.' ;;
  esac
}

# A missing secrets file breaks the playwright MCP server in every mode, and the
# only symptom the user sees is a connection error at startup — name it here.
secrets_status() {
  [ -f "$SESSION_CWD/.env.playwright-secrets" ] && return 0
  # Leading newline: this is appended inside the CONTEXT string as its own line.
  printf '\n- WARNING: .env.playwright-secrets is missing — the playwright MCP server exits at startup (--secrets ENOENT). Create it (install.sh writes a template) before any browser test.'
}

# Keychain-backed secrets ("Secrets source: keychain" in PROJECT.md/PRODUCT.md):
# the agent must SEE which declared keys it actually has — that visibility is
# what ends "the agent invents credentials because it does not know it has
# them". Pure file inspection via resolve-secrets.sh --status: no keychain
# access at session start (a locked keychain would otherwise prompt every
# session), silent when no project declares keychain.
secrets_keys_line() {
  [ -f "$HERE/resolve-secrets.sh" ] || return 0
  local line
  line="$(bash "$HERE/resolve-secrets.sh" "$SESSION_CWD" --status 2>/dev/null)" || return 0
  [ -n "$line" ] && printf '\n- Secrets: %s' "$line"
}

# JIRA Data Center PAT: never a global shell export, never a file. When a DC
# atlassian entry exists (env.JIRA_URL) and no JIRA_PERSONAL_TOKEN is already
# in the environment, resolve it from the login keychain (service
# JIRA_PAT_<host>) straight into THIS session via $CLAUDE_ENV_FILE. The value
# is quoted with shlex and never printed. A locked keychain costs one dismiss
# per session start — if that annoys, exporting the PAT in the shell profile
# skips this path entirely (the env check comes first).
jira_pat_resolve() {
  [ -n "${CLAUDE_ENV_FILE:-}" ] || return 0
  [ -z "${JIRA_PERSONAL_TOKEN:-}" ] || return 0
  case "$MCP_SCAN" in *AT_DC_HOST:*) ;; *) return 0 ;; esac
  local host tok q
  host="$(printf '%s' "$MCP_SCAN" | tr ' ' '\n' | sed -n 's/^AT_DC_HOST://p' | head -1)"
  [ -n "$host" ] || return 0
  if ! command -v security >/dev/null 2>&1; then
    printf '\n- JIRA Data Center (%s): JIRA_PERSONAL_TOKEN is not set and the macOS security CLI is unavailable — export the PAT in the environment.' "$host"
    return 0
  fi
  tok="$(security find-generic-password -s "JIRA_PAT_$host" -w 2>/dev/null)"
  if [ -n "$tok" ]; then
    q="$(printf '%s' "$tok" | python3 -c 'import shlex,sys; print(shlex.quote(sys.stdin.read().strip()))' 2>/dev/null)"
    [ -n "$q" ] || return 0
    printf 'export JIRA_PERSONAL_TOKEN=%s\n' "$q" >> "$CLAUDE_ENV_FILE" 2>/dev/null || return 0
    printf '\n- JIRA PAT for %s resolved from Keychain (service JIRA_PAT_%s) — exported to this session only, never written to a project file.' "$host" "$host"
  else
    printf '\n- JIRA Data Center (%s): no JIRA_PERSONAL_TOKEN in env and none in Keychain — store it once: security add-generic-password -s JIRA_PAT_%s -a jira -w' "$host" "$host"
  fi
}

# Bootstrap first, then build the context — otherwise the secrets warning below
# would fire on the very run that just seeded the file. MCP_SCAN is computed
# once for both the hints and the JIRA Data Center PAT resolution (the scan is
# read-only config parsing, no liveness checks).
SECRETS_EXISTED=0
[ -f "$SESSION_CWD/.env.playwright-secrets" ] && SECRETS_EXISTED=1
PLUGIN_BOOTSTRAP=0
if is_plugin_bootstrap; then
  PLUGIN_BOOTSTRAP=1
  bootstrap_dirs
fi
MCP_SCAN="$(mcp_scan 2>/dev/null || true)"

# Auto-resolve keychain-backed secrets only when the file did not exist before
# bootstrap (the seed above may have just created the placeholder — that still
# counts as missing). Resolution touches the keychain, so it must NOT run on
# every session: missing file = setup moment, which is exactly when the user
# is present to unlock. Silent when no project declares keychain.
AUTO_SECRETS=""
if [ "$SECRETS_EXISTED" -eq 0 ] && [ -f "$HERE/resolve-secrets.sh" ]; then
  AUTO_SECRETS="$(bash "$HERE/resolve-secrets.sh" "$SESSION_CWD" 2>/dev/null)"
  [ -n "$AUTO_SECRETS" ] && AUTO_SECRETS="
- $AUTO_SECRETS"
fi

# The browser preference file is needed in EVERY mode (the plugin's .mcp.json
# hard-references it via --config; integrate mode and this repo use the same
# flags). Seed-if-missing, never overwrite, and say so when freshly created so
# the user knows a restart applies their future edits.
SEEDED_BROWSER_CONFIG=0
seed_browser_config
BROWSER_SEED_NOTE=""
if [ "$SEEDED_BROWSER_CONFIG" -eq 1 ]; then
  BROWSER_SEED_NOTE="
- Created .playwright-mcp.config.json with defaults (headless, isolated) — this is YOUR browser preference dial: headful = launchOptions.headless false. The server reads it at launch, so edits apply after a restart."
fi

BROWSER_MODE="$(browser_mode)"
BROWSER_LINE=""
[ -n "$BROWSER_MODE" ] && BROWSER_LINE="
- Browser: $BROWSER_MODE"

# When the session started in a subfolder of the QA home, say where the data
# actually lives — the model must write evidence/learnings THERE, not here.
HOME_LINE=""
[ -n "$QA_HOME_FROM" ] && HOME_LINE="
- QA home: $CWD (resolved up from cwd $QA_HOME_FROM) — all paths (evidence/, memory/, projects/) are relative to the QA home, not to cwd"

CONTEXT="QA Agent Blueprint — session start$HOME_LINE
- Onboarded projects:
$(list_projects)
- Playwright CLI: $(playwright_version)$BROWSER_LINE
- Read memory/INDEX.md before anything else; then only the active project's
  PROJECT.md + learnings.md. No full-repo scans.
- Lost? The qa-help skill lists every command (in plugin mode:
  /qa-agent-blueprint:qa-help) — plain language works too.$(mcp_hint)$(inbox_status)$(secrets_status)$(secrets_keys_line)$(jira_pat_resolve)$AUTO_SECRETS$BROWSER_SEED_NOTE$(update_notice)"

if [ "$PLUGIN_BOOTSTRAP" -eq 1 ]; then
  # The router is the plugin's own CLAUDE.md, injected VERBATIM. If the file is
  # unreadable, say so loudly — a session that silently misses its router
  # misbehaves in ways nobody can diagnose from the transcript.
  if [ -f "$PLUGIN_ROOT/CLAUDE.md" ]; then
    ROUTER="$(cat "$PLUGIN_ROOT/CLAUDE.md")"
  else
    ROUTER="WARNING: \$PLUGIN_ROOT/CLAUDE.md is unreadable — this session has no router. Reinstall the plugin."
  fi
  CONTEXT="## QA Agent Blueprint (plugin mode)

Blueprint rules, skills, agents and hooks load from the plugin at
\`$PLUGIN_ROOT\`; project data lives in THIS repo under \`projects/\`,
\`memory/\`, \`evidence/\` (bootstrapped now if missing). \`projects/\` starts
empty — the scaffold and the filled reference stay in the plugin: read them
from $PLUGIN_ROOT/projects/_template/ and $PLUGIN_ROOT/projects/EXAMPLE/ when
onboarding, and write only the new \`projects/<KEY>/\` into this repo.
The router below is the plugin's CLAUDE.md, injected verbatim. Its relative
references (\`.claude/...\`, \`docs/...\`) resolve under \$PLUGIN_ROOT;
\`projects/\`, \`memory/\` and \`evidence/\` are this repo's own.

$ROUTER

$CONTEXT"
fi

if command -v python3 >/dev/null 2>&1; then
  CONTEXT="$CONTEXT" python3 -c '
import json, os
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": os.environ["CONTEXT"],
    }
}))
'
else
  # No python3 — fall back to plain stdout, which most Claude Code versions
  # still surface as session context for SessionStart hooks.
  printf '%s\n' "$CONTEXT"
fi
exit 0

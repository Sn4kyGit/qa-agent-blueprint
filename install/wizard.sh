#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit, Anna Mazurek


wizard_interactive() {
  [ "$WIZARD_DISABLED" -eq 0 ] || return 1
  [ "$YES" -eq 0 ] || return 1
  [ "$UNINSTALL" -eq 0 ] || return 1
  [ -z "$MOVE_TO" ] || return 1
  [ -z "${CI:-}" ] || return 1
  [ -t 0 ] && [ -t 1 ]
}

wizard_detect_mode() {
  if [ "$TARGET" = "$REPO_ROOT" ]; then
    WIZARD_DEFAULT_MODE="integrate"
    return 0
  fi
  if [ -L "$TARGET/.claude" ] && [ -d "$TARGET/.opencode" ]; then
    WIZARD_DEFAULT_MODE="shared"
    return 0
  fi
  if [ -d "$TARGET/.opencode" ]; then
    WIZARD_DEFAULT_MODE="shared"
    return 0
  fi
  if [ -f "$TARGET/.claude/settings.json" ] && grep -q "qa-agent-blueprint" "$TARGET/.claude/settings.json" 2>/dev/null; then
    WIZARD_DEFAULT_MODE="shared"
    return 0
  fi
  if [ -d "$TARGET/.claude/rules/qa-blueprint" ]; then
    WIZARD_DEFAULT_MODE="integrate"
    return 0
  fi
  WIZARD_DEFAULT_MODE="plugin"
}

wizard_read() {
  local prompt="$1" variable="$2" default="${3:-}" value=""
  if [ -n "$default" ]; then
    printf "%s [%s]: " "$prompt" "$default"
  else
    printf "%s: " "$prompt"
  fi
  IFS= read -r value || return 1
  [ -n "$value" ] || value="$default"
  printf -v "$variable" '%s' "$value"
}

wizard_menu() {
  local prompt="$1" variable="$2" default="$3"
  shift 3
  printf "%s\n" "$@"
  local value=""
  printf "Choose [%s] " "$default"
  IFS= read -r value || return 1
  [ -n "$value" ] || value="$default"
  printf -v "$variable" '%s' "$value"
}

wizard_valid_mode() {
  case "$1" in
    integrate|plugin|opencode|shared) return 0 ;;
    *) return 1 ;;
  esac
}

wizard_valid_model() {
  case "$1" in
    */*) ;;
    *) return 1 ;;
  esac
  local provider="${1%%/*}" model="${1#*/}"
  case "$provider" in
    ''|*[!A-Za-z0-9._:@+-]*) return 1 ;;
  esac
  [ -n "$model" ] || return 1
  case "$model" in
    *[!A-Za-z0-9._:@+-/]*) return 1 ;;
  esac
  return 0
}

wizard_run() {
  wizard_detect_mode
  if [ "$TARGET" = "$REPO_ROOT" ]; then
    MODE="integrate"
    info "Self-setup target detected — running the blueprint repo setup without consumer preferences"
    return 0
  fi
  info "QA Agent Blueprint setup wizard"
  local choice="" confirm="" url="" answer=""

  if [ -z "$MODE" ]; then
    wizard_menu "Which installation do you want?" choice "$WIZARD_DEFAULT_MODE" \
      "  1) plugin    Claude Code only; zero copied blueprint logic" \
      "  2) opencode  opencode only; model choice is yours" \
      "  3) shared    Claude Code and opencode in one QA home" \
      "  4) integrate Reviewable namespaced copy in your repo"
    case "$choice" in
      1|plugin|p) MODE="plugin" ;;
      2|opencode|o) MODE="opencode" ;;
      3|shared|s) MODE="shared" ;;
      4|integrate|i) MODE="integrate" ;;
      *) MODE="$WIZARD_DEFAULT_MODE" ;;
    esac
  fi

  if [ "$TARGET_EXPLICIT" -eq 0 ]; then
    wizard_read "Target folder" TARGET "$TARGET" || return 1
    if [ ! -d "$TARGET" ]; then
      err "Target directory does not exist: $TARGET"
      return 1
    fi
    TARGET="$(cd "$TARGET" && pwd)"
  fi

  wizard_detect_mode
  info "Target: $TARGET"
  info "Existing layout: $WIZARD_DEFAULT_MODE"
  [ "$MODE" = "$WIZARD_DEFAULT_MODE" ] || info "Mode selected: $MODE"

  if [ -z "$JIRA_KIND" ]; then
    wizard_menu "Which JIRA deployment?" answer "cloud" \
      "  1) cloud      Atlassian Cloud remote server; OAuth happens in the harness" \
      "  2) datacenter Self-hosted JIRA via uvx mcp-atlassian; PAT stays out of files"
    case "$answer" in
      2|datacenter|d) JIRA_KIND="datacenter" ;;
      *) JIRA_KIND="cloud" ;;
    esac
  fi
  if [ "$JIRA_KIND" = "datacenter" ] && [ -z "$JIRA_URL" ]; then
    while :; do
      wizard_read "JIRA base URL" JIRA_URL "" || return 1
      case "$JIRA_URL" in
        http://*|https://*) break ;;
        *) warn "JIRA URL must start with http:// or https://" ;;
      esac
    done
  fi

  if [ -z "$BROWSER_MODE" ]; then
    wizard_menu "Browser mode?" answer "headless" \
      "  1) headless   safe default and required for unattended runs" \
      "  2) headful    visible browser so you can watch the agent work"
    case "$answer" in
      2|headful|h) BROWSER_MODE="headful" ;;
      *) BROWSER_MODE="headless" ;;
    esac
  fi

  if [ "$MODE" = "opencode" ] || [ "$MODE" = "shared" ]; then
    if [ -z "$MODEL_SETUP_MODE" ]; then
      wizard_menu "Configure opencode model lanes now?" answer "skip" \
        "  1) now     set cheap/standard/deep model IDs and optional variants" \
        "  2) later   run /model-setup after the first restart" \
        "  3) skip    every lane inherits the selected model"
      case "$answer" in
        1|now) MODEL_SETUP_MODE="now" ;;
        2|later) MODEL_SETUP_MODE="later" ;;
        *) MODEL_SETUP_MODE="skip" ;;
      esac
    fi
    if [ "$MODEL_SETUP_MODE" = "now" ]; then
      while [ -z "$MODEL_CHEAP" ]; do
        wizard_read "Cheap lane model (provider/model)" MODEL_CHEAP "" || return 1
        wizard_valid_model "$MODEL_CHEAP" || { warn "Use provider/model"; MODEL_CHEAP=""; }
      done
      wizard_read "Cheap lane variant (optional)" MODEL_CHEAP_VARIANT ""
      while [ -z "$MODEL_STANDARD" ]; do
        wizard_read "Standard lane model (provider/model)" MODEL_STANDARD "" || return 1
        wizard_valid_model "$MODEL_STANDARD" || { warn "Use provider/model"; MODEL_STANDARD=""; }
      done
      wizard_read "Standard lane variant (optional)" MODEL_STANDARD_VARIANT ""
      while [ -z "$MODEL_DEEP" ]; do
        wizard_read "Deep lane model (provider/model)" MODEL_DEEP "" || return 1
        wizard_valid_model "$MODEL_DEEP" || { warn "Use provider/model"; MODEL_DEEP=""; }
      done
      wizard_read "Deep lane variant (optional)" MODEL_DEEP_VARIANT ""
    fi
  else
    MODEL_SETUP_MODE="${MODEL_SETUP_MODE:-later}"
    [ "$MODEL_SETUP_MODE" = "now" ] && info "Claude lane aliases are haiku/sonnet/opus; no model file is written in this mode"
    MODEL_SETUP_MODE="later"
  fi

  echo
  info "Installation plan"
  printf "  Mode:       %s\n" "$MODE"
  printf "  Target:     %s\n" "$TARGET"
  printf "  JIRA:       %s%s\n" "$JIRA_KIND" "${JIRA_URL:+ ($JIRA_URL)}"
  printf "  Browser:    %s\n" "$BROWSER_MODE"
  printf "  Model lanes:%s\n" "$MODEL_SETUP_MODE"
  [ "$DRY_RUN" -eq 1 ] && printf "  Dry-run:    no files will be changed\n"
  printf "\nNo files, packages or credentials are changed before confirmation. Secrets and PATs are never requested here.\n"
  printf "Proceed with this plan? [y/N] "
  IFS= read -r confirm || return 1
  case "$confirm" in
    y|Y|yes|YES) ;;
    *) info "Wizard cancelled — nothing changed"; exit 0 ;;
  esac
  WIZARD_ACTIVE=1
}

wizard_write_browser() {
  local cfg="$TARGET/.playwright-mcp.config.json"
  if ! command -v python3 >/dev/null 2>&1; then
    report WARN ".playwright-mcp.config.json" "python3 is required to update the browser preference safely"
    next_step "Set browser.launchOptions.headless manually in $cfg, then restart the harness"
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    report DRY-RUN ".playwright-mcp.config.json" "would set browser.launchOptions.headless to $([ "$BROWSER_MODE" = headful ] && echo false || echo true)"
    return 0
  fi
  QA_WIZARD_CONFIG="$cfg" QA_WIZARD_HEADLESS="$([ "$BROWSER_MODE" = headful ] && echo false || echo true)" QA_BACKUP="$cfg.bak-$TS" python3 - <<'PY'
import json, os, shutil, sys
path = os.environ["QA_WIZARD_CONFIG"]
backup = os.environ["QA_BACKUP"]
headless = os.environ["QA_WIZARD_HEADLESS"] == "true"
def parse_jsonc(text):
    out = []
    i = 0
    in_string = False
    escaped = False
    while i < len(text):
        c = text[i]
        if in_string:
            out.append(c)
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
            i += 1
        elif c == '"':
            in_string = True
            out.append(c)
            i += 1
        elif c == "/" and i + 1 < len(text) and text[i + 1] == "/":
            i += 2
            while i < len(text) and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < len(text) and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
        else:
            out.append(c)
            i += 1
    source = "".join(out)
    cleaned = []
    i = 0
    in_string = False
    escaped = False
    while i < len(source):
        c = source[i]
        if in_string:
            cleaned.append(c)
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
            cleaned.append(c)
        elif c == ",":
            j = i + 1
            while j < len(source) and source[j].isspace():
                j += 1
            if j >= len(source) or source[j] not in "]}":
                cleaned.append(c)
        else:
            cleaned.append(c)
        i += 1
    return json.loads("".join(cleaned))
try:
    original = open(path, "rb").read()
except FileNotFoundError:
    original = b""
    config = {}
else:
    try:
        config = parse_jsonc(original.decode("utf-8-sig"))
    except Exception as exc:
        print(f"WARN|.playwright-mcp.config.json|cannot update browser preference ({exc}) — left untouched")
        raise SystemExit(0)
browser = config.setdefault("browser", {})
launch = browser.setdefault("launchOptions", {})
if launch.get("headless") == headless:
    print("SKIPPED|.playwright-mcp.config.json|already matches the selected browser mode")
    raise SystemExit(0)
launch["headless"] = headless
if original:
    shutil.copy2(path, backup)
    print(f"BACKUP|backup|{path} → {backup}")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
print(f"MERGED|.playwright-mcp.config.json|browser.launchOptions.headless set to {str(headless).lower()}; other preferences kept")
PY
}

wizard_apply_jira() {
  if [ "$JIRA_KIND" != "datacenter" ]; then
    report SKIPPED "atlassian" "JIRA Cloud remains the shipped default; existing custom entries are untouched"
    return 0
  fi
  if [ "$MODE" = "plugin" ]; then
    report WARN "atlassian" "Data Center chosen — plugin mode keeps its bundled Cloud entry active; use shared/integrate for a single local entry or review both entries"
    next_step "For JIRA Data Center in plugin mode, review the atlassian entry manually; PAT goes to the macOS keychain service JIRA_PAT_<jira-host>, never into a file"
    return 0
  fi
  if [ -z "$JIRA_URL" ]; then
    err "JIRA Data Center requires --jira-url"
    return 1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    report WARN "atlassian" "python3 is required to write the Data Center preference safely"
    next_step "Configure the local mcp-atlassian entry manually; PAT goes to the macOS keychain service JIRA_PAT_<jira-host>"
    return 0
  fi
  local files=()
  [ "$MODE" = "integrate" ] && files+=("$TARGET/.mcp.json")
  [ "$MODE" = "shared" ] && files+=("$TARGET/.mcp.json")
  [ "$MODE" = "opencode" ] && files+=("$TARGET/opencode.json")
  [ "$MODE" = "shared" ] && files+=("$TARGET/opencode.json")
  local f
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    if [ "$DRY_RUN" -eq 1 ]; then
      report DRY-RUN "$(basename "$f")" "would write local atlassian Data Center entry (JIRA_URL only, no token)"
      continue
    fi
    QA_WIZARD_CONFIG="$f" QA_WIZARD_JIRA_URL="$JIRA_URL" QA_BACKUP="$f.bak-$TS" python3 - <<'PY'
import json, os, shutil, sys
path = os.environ["QA_WIZARD_CONFIG"]
backup = os.environ["QA_BACKUP"]
url = os.environ["QA_WIZARD_JIRA_URL"]
enabled = "jira_get_issue,jira_search,jira_create_issue,jira_update_issue,jira_add_comment,jira_get_transitions,jira_transition_issue,jira_batch_get_changelogs,jira_get_project_issue_types,jira_get_create_fields,jira_download_attachments"
def parse_jsonc(text):
    out = []
    i = 0
    in_string = False
    escaped = False
    while i < len(text):
        c = text[i]
        if in_string:
            out.append(c)
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
            i += 1
        elif c == '"':
            in_string = True
            out.append(c)
            i += 1
        elif c == "/" and i + 1 < len(text) and text[i + 1] == "/":
            i += 2
            while i < len(text) and text[i] != "\n":
                i += 1
        elif c == "/" and i + 1 < len(text) and text[i + 1] == "*":
            end = text.find("*/", i + 2)
            i = len(text) if end < 0 else end + 2
        else:
            out.append(c)
            i += 1
    source = "".join(out)
    cleaned = []
    i = 0
    in_string = False
    escaped = False
    while i < len(source):
        c = source[i]
        if in_string:
            cleaned.append(c)
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
            cleaned.append(c)
        elif c == ",":
            j = i + 1
            while j < len(source) and source[j].isspace():
                j += 1
            if j >= len(source) or source[j] not in "]}":
                cleaned.append(c)
        else:
            cleaned.append(c)
        i += 1
    return json.loads("".join(cleaned))
try:
    original = open(path, "rb").read()
    config = parse_jsonc(original.decode("utf-8-sig"))
except Exception as exc:
    print(f"WARN|{os.path.basename(path)}|cannot write JIRA preference ({exc}) — left untouched")
    raise SystemExit(0)
if os.path.basename(path) == ".mcp.json":
    servers = config.setdefault("mcpServers", {})
else:
    servers = config.setdefault("mcp", {})
entry = servers.get("atlassian")
if isinstance(entry, dict) and entry.get("url") == "https://mcp.atlassian.com/v2/mcp":
    entry = None
elif isinstance(entry, dict) and (entry.get("command") or entry.get("url")):
    print(f"SKIPPED|{os.path.basename(path)}|existing custom atlassian entry left untouched")
    raise SystemExit(0)
if entry is None:
    entry = {}
    servers["atlassian"] = entry
if os.path.basename(path) == ".mcp.json":
    entry["command"] = "uvx"
    entry["args"] = ["mcp-atlassian"]
    entry["env"] = {"JIRA_URL": url, "ENABLED_TOOLS": enabled}
else:
    entry["type"] = "local"
    entry["command"] = ["uvx", "mcp-atlassian"]
    entry["environment"] = {"JIRA_URL": url, "ENABLED_TOOLS": enabled}
shutil.copy2(path, backup)
print(f"BACKUP|backup|{path} → {backup}")
with open(path, "w", encoding="utf-8") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
print(f"MERGED|{os.path.basename(path)}|Data Center atlassian entry configured with JIRA_URL only")
PY
  done
  next_step "Store the Data Center PAT in the macOS keychain service JIRA_PAT_<jira-host>; never paste it into a file or chat"
  next_step "Authorize JIRA after restart: Claude /mcp or opencode mcp auth atlassian"
}

wizard_apply_model_setup() {
  [ "$MODEL_SETUP_MODE" = "now" ] || {
    [ "$MODEL_SETUP_MODE" = "later" ] && next_step "Optional model lanes: run /model-setup after restart; unconfigured lanes inherit the selected model"
    return 0
  }
  case "$MODE" in
    opencode|shared) ;;
    *) next_step "Claude lane aliases are haiku/sonnet/opus; no model file is written"; return 0 ;;
  esac
  local helper="$REPO_ROOT/.claude/scripts/model-setup.py"
  [ -f "$helper" ] || { err "model-setup helper is missing: $helper"; return 1; }
  local args=(--cwd "$TARGET" --cheap "$MODEL_CHEAP" --standard "$MODEL_STANDARD" --deep "$MODEL_DEEP")
  [ -n "$MODEL_CHEAP_VARIANT" ] && args+=(--cheap-variant "$MODEL_CHEAP_VARIANT")
  [ -n "$MODEL_STANDARD_VARIANT" ] && args+=(--standard-variant "$MODEL_STANDARD_VARIANT")
  [ -n "$MODEL_DEEP_VARIANT" ] && args+=(--deep-variant "$MODEL_DEEP_VARIANT")
  [ "$DRY_RUN" -eq 1 ] && args+=(--dry-run)
  if python3 "$helper" "${args[@]}"; then
    report OK "model lanes" "cheap/standard/deep consumer overrides configured"
  else
    err "model lane setup failed — see model-setup.py output"
    return 1
  fi
  next_step "Restart opencode so the six lane overrides take effect"
}

wizard_apply_preferences() {
  [ "$UNINSTALL" -eq 0 ] || return 0
  [ -z "$MOVE_TO" ] || return 0
  [ "${WIZARD_ACTIVE:-0}" -eq 1 ] || [ "${PREFS_REQUESTED:-0}" -eq 1 ] || return 0
  wizard_write_browser
  wizard_apply_jira || return 1
  wizard_apply_model_setup || return 1
}

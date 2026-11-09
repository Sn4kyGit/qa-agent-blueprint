#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit

#
# stop-evidence-check.sh — Stop hook. Enforces the evidence-mandatory rule
# (.claude/rules/core/evidence-policy.md): if this session's transcript shows
# signs of a completed test action (a JIRA report/transition, or Playwright
# MCP/CLI activity) but no execution_summary.json was written recently, block
# the stop and ask for it instead of letting the session end silently short.
#
# Heuristic by design — this is a scaffold safety net, not a formal verifier.
# Projects with stricter needs can tighten the signals below.
#
set -uo pipefail

INPUT="$(cat)"

get_field() {
  local field="$1"
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('$field') or '')" 2>/dev/null
  fi
}

# Avoid infinite loop: if this Stop hook already fired once and Claude
# continued anyway, don't block again on the same turn.
STOP_HOOK_ACTIVE="$(get_field stop_hook_active)"
if [ "$STOP_HOOK_ACTIVE" = "True" ] || [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

CWD="$(get_field cwd)"; CWD="${CWD:-$PWD}"
TRANSCRIPT="$(get_field transcript_path)"

# QA home discovery (0.9.1): evidence lives at the QA home root, even when the
# session ran in a subfolder. Walk up to the nearest .qa-home marker or the
# legacy trio (projects/ + memory/ + evidence/), stop at $HOME.
d="$CWD"
while : ; do
  if [ -e "$d/.qa-home" ] || { [ -d "$d/projects" ] && [ -d "$d/memory" ] && [ -d "$d/evidence" ]; }; then
    CWD="$d"; break
  fi
  if { [ -n "${HOME:-}" ] && [ "$d" = "$HOME" ]; } || [ "$d" = "/" ]; then break; fi
  d="$(dirname "$d")"
done

[ -d "$CWD/evidence" ] || exit 0   # nothing to enforce if evidence/ isn't even scaffolded

# --- session performance log (0.19.0) ---
# Extract token usage metadata from the transcript and append one line to
# evidence/.audit/session-perf.log. Only usage NUMBERS are read (input_tokens,
# output_tokens, cache_creation, cache_read) — never message content. This is
# structured harness metadata, not transcript mining (the data boundary is
# about secrets/content, not usage counts). Format mirrors jira-writes.log.
log_session_perf() {
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local _perf_data
  _perf_data="$(python3 - "$TRANSCRIPT" <<'PYEOF' 2>/dev/null
import json, sys
path = sys.argv[1]
total_in = total_out = cache_create = cache_read = tool_calls = 0
try:
    with open(path) as f:
        for line in f:
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if obj.get("type") != "assistant":
                continue
            msg = obj.get("message") or {}
            usage = msg.get("usage") or {}
            total_in += usage.get("input_tokens", 0) or 0
            total_out += usage.get("output_tokens", 0) or 0
            cache_create += usage.get("cache_creation_input_tokens", 0) or 0
            cache_read += usage.get("cache_read_input_tokens", 0) or 0
            content = msg.get("content") or []
            for c in content:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    tool_calls += 1
except Exception:
    pass
print(f"{total_in} {total_out} {cache_create} {cache_read} {tool_calls}")
PYEOF
)"
  [ -n "$_perf_data" ] || return 0
  local _ts _logdir _logfile
  _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  _logdir="$CWD/evidence/.audit"
  mkdir -p "$_logdir" 2>/dev/null || return 0
  _logfile="$_logdir/session-perf.log"
  printf '%s | input=%s | output=%s | cache_create=%s | cache_read=%s | tools=%s\n' \
    "$_ts" $(echo "$_perf_data") >> "$_logfile" 2>/dev/null
}

log_session_perf

# Signal: did this session actually INVOKE a test tool (not just mention one in
# prose or in a file being written/edited — this repo's own docs/rules talk
# about "execution_summary.json" and "verdict: PASS/FAIL" constantly, so a
# plain text grep over the transcript false-positives on every session that
# edits this blueprint itself). Parse the transcript's JSONL and match only
# actual tool_use invocations by their "name" field:
#   - any mcp__playwright__* tool call, or
#   - an mcp__atlassian__* tool call whose name implies a write
#     (create/edit/add/transition/update/delete), or
#   - a Bash call whose command actually runs the Playwright CLI runner.
#
# While at it, collect the JIRA ticket keys the activity touched (audit
# 2026-09-18 F2): evidence is scoped PER TICKET — a fresh summary for SHOP-1
# must not satisfy a run that tested SHOP-2. Prints the discovered keys, one
# per line (empty when none could be tied to the activity); the exit status
# carries the "did a test run" signal (0 = yes).
test_run_keys() {
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  local _tmp_py
  _tmp_py="$(mktemp)"
  cat > "$_tmp_py" <<'PY'
import json, re, sys

path = sys.argv[1]
# Tolerate an intermediate namespace segment: a plugin-provided MCP server
# surfaces as mcp__plugin_<name>_<server>__<tool> — a SINGLE underscore joins
# the plugin name and the server, so the segment list ends in `_atlassian`,
# not `atlassian__`. The previous pattern (`(?:[^_]+(?:_[^_]+)*__)*`) never
# matched that real shape: plugin-mode writes were invisible to the hook while
# looking covered in review (found via the 2026-09-18 audit's guard work).
atlassian_write = re.compile(r'^mcp__(?:[a-zA-Z0-9-]+(?:_[a-zA-Z0-9-]+)*_+)?atlassian__(?:jira_)?(create|edit|add|transition|update|delete)', re.IGNORECASE)
playwright_tool = re.compile(r'^mcp__(?:[a-zA-Z0-9-]+(?:_[a-zA-Z0-9-]+)*_+)?playwright__')
# Runner invocations. Anchored to the START of the command's first line (optionally
# after a plain `cd <dir> &&` prefix), because a *search* over the whole command
# string false-positives on any Bash call that merely CONTAINS the text without
# running it — e.g. a heredoc whose body mentions "npx playwright test", which is
# exactly what writing this hook's own fixtures does. The alternatives cover the
# package-manager wrappers a real suite is actually run with: matching only
# `npx playwright test` meant a `pnpm playwright test` or `npm run test:e2e` run
# demanded no evidence at all.
playwright_cli = re.compile(
    r'^\s*(?:cd\s+\S+\s*&&\s*)?'
    r'(?:(?:npx|pnpm|yarn|bunx)\s+(?:--\S+\s+)*)?'
    r'(?:playwright\s+test\b'
    r'|(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?(?:test|e2e|test:e2e|test:ui)\b)'
)
ticket_key = re.compile(r'\b[A-Z][A-Z0-9]+-\d+\b')
# H7 (0.18.5): TC-IDs (TC-CHK-014) collide with the ticket regex at the
# <CAT>-<NNN> tail. Exclude them, and only count keys from identity-bearing
# fields (issueKey/issue_key/key/id) — not from free text like comments.
tc_id = re.compile(r'\bTC-[A-Z]+-\d+\b')

def is_real_ticket_key(k):
    """Exclude TC-IDs and other non-ticket patterns."""
    if tc_id.match(k):
        return False
    return True

def extract_identity_keys(obj):
    """Extract ticket keys from identity fields only (not free text)."""
    found = set()
    if isinstance(obj, dict):
        for ik in ("issueKey", "issue_key", "key", "id"):
            v = obj.get(ik)
            if isinstance(v, str):
                for m in ticket_key.findall(v):
                    if is_real_ticket_key(m):
                        found.add(m)
        # For Bash commands: --grep KEY-123 or TICKET=KEY-123 patterns
        if obj.get("type") == "tool_use" and obj.get("name") == "Bash":
            cmd = (obj.get("input") or {}).get("command") or ""
            for m in re.findall(r'(?:--grep|TICKET=|ticket[=:])\s*([A-Z][A-Z0-9]+-\d+)', cmd):
                if is_real_ticket_key(m):
                    found.add(m)
        for v in obj.values():
            found |= extract_identity_keys(v)
    elif isinstance(obj, list):
        for v in obj:
            found |= extract_identity_keys(v)
    return found

keys = set()

def walk(node):
    found = False
    if isinstance(node, dict):
        if node.get("type") == "tool_use":
            name = node.get("name") or ""
            active = False
            if playwright_tool.match(name) or atlassian_write.match(name):
                active = True
            elif name == "Bash":
                cmd = (node.get("input") or {}).get("command") or ""
                first_line = cmd.lstrip("\n").split("\n", 1)[0]
                if playwright_cli.match(first_line):
                    active = True
            if active:
                found = True
                # H7: extract keys from identity fields only, not from free text
                # (a comment mentioning another ticket must not expand the
                # demanded evidence set).
                for m in extract_identity_keys(node.get("input") or {}):
                    keys.add(m)
        for v in node.values():
            if walk(v):
                found = True
    elif isinstance(node, list):
        for v in node:
            if walk(v):
                found = True
    return found

found = False
try:
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            if walk(obj):
                found = True
except FileNotFoundError:
    pass

for k in sorted(keys):
    print(k)
sys.exit(0 if found else 1)
PY
  python3 "$_tmp_py" "$TRANSCRIPT"
  local result=$?
  rm -f "$_tmp_py"
  return $result
}

# Signal: is there a fresh execution_summary.json (written in roughly this session)?
has_recent_evidence() {
  fresh_summaries | grep -q .
}

fresh_summaries() {
  # -mmin -120 statt -newermt '-2 hours': relative Zeitstrings sind GNU-find-
  # Syntax; bfs (hinter `find` in manchen Sandbox-Umgebungen) akzeptiert bei
  # -newermt nur ISO-8601 und scheitert lautlos (stderr → /dev/null), sodass
  # has_recent_evidence immer "nichts gefunden" liefert. -mmin ist portabel.
  find "$CWD/evidence" -name execution_summary.json -mmin -120 2>/dev/null
}

# Second obligation, same firmness as the first: every fresh summary must DECLARE
# what was learned (.claude/rules/core/evidence-policy.md → "learnings"). The hook
# checks only that the key exists and is filled on exactly one side — whether
# something was genuinely surprising is not machine-decidable, but whether the
# question was asked is. Prints the offending file(s), empty if all are fine.
summaries_missing_learnings() {
  command -v python3 >/dev/null 2>&1 || return 0
  fresh_summaries | while IFS= read -r f; do
    [ -n "$f" ] || continue
    python3 - "$f" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as fh:
        d = json.load(fh)
except Exception:
    sys.exit(0)
# M6 (0.19.5): verdict enum validation — a fabricated summary with verdict
# "super-green" or empty should not pass the gate.
VALID_VERDICTS = {"PASS", "FAIL", "BLOCKED", "NEEDS_REVIEW", "NO_TEST"}
v = d.get("verdict", "")
if v and v not in VALID_VERDICTS:
    print(path)
    sys.exit(0)
l = d.get("learnings")
if not isinstance(l, dict):
    print(path)
    sys.exit(0)
captured = l.get("captured") or []
none_because = (l.get("none_because") or "").strip() if isinstance(l.get("none_because"), str) else ""
if not captured and not none_because:
    print(path)
PY
  done
}

# Per-ticket evidence check (F2): when the run could be tied to ticket keys,
# EACH key needs its own fresh summary under evidence/<PROJ>/<TICKET>/ — a
# fresh SHOP-1 summary must not cover a run that tested SHOP-2. Prints the keys
# lacking evidence; with no keys extractable, falls back to the global
# freshness check and prints "-" as the marker.
missing_evidence_keys() {
  if [ -n "$KEYS" ]; then
    local k proj
    for k in $KEYS; do
      proj="${k%%-*}"
      find "$CWD/evidence/$proj/$k" -name execution_summary.json -mmin -120 2>/dev/null | grep -q . \
        || printf '%s\n' "$k"
    done
  else
    has_recent_evidence || printf '%s\n' "-"
  fi
}

KEYS=""
if ! KEYS="$(test_run_keys)"; then
  exit 0   # no test activity in this session — nothing to enforce
fi

MISSING_KEYS="$(missing_evidence_keys)"
if [ -n "$MISSING_KEYS" ]; then
  if [ "$MISSING_KEYS" != "-" ]; then
    {
      echo "QA_EVIDENCE_MISSING: this session ran test activity against ticket(s):"
      printf '%s\n' "$MISSING_KEYS" | sed 's/^/  /'
      cat <<'EOF'
but no execution_summary.json was written under evidence/<KEY>/<TICKET>/ for
them in the last 2 hours. Evidence from another ticket does not cover this run.

Before ending the session, per ticket:
  - write evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/execution_summary.json
    (schema: .claude/rules/core/evidence-policy.md), or
  - if no test actually completed (still investigating, aborted), write a
    minimal summary with "verdict": "NO_TEST", a one-line "no_test_reason"
    and the usual "learnings" declaration — the explicit alternative to
    stopping silently.
EOF
    } >&2
  else
    cat >&2 <<'EOF'
QA_EVIDENCE_MISSING: this session actually invoked a Playwright MCP tool, an
Atlassian write (create/edit/transition/...), or the Playwright CLI runner,
but no execution_summary.json was written under evidence/<KEY>/<TICKET>/ in
the last 2 hours.

Before ending the session:
  - write evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/execution_summary.json
    (schema: .claude/rules/core/evidence-policy.md), or
  - if no test actually completed (still investigating, aborted), write a
    minimal summary with "verdict": "NO_TEST", a one-line "no_test_reason"
    and the usual "learnings" declaration — the explicit alternative to
    stopping silently.
EOF
  fi
  exit 2
fi

# Evidence exists — now the learning obligation, enforced with the same firmness.
MISSING="$(summaries_missing_learnings)"
if [ -n "$MISSING" ]; then
  {
    echo "QA_LEARNINGS_MISSING: this run produced evidence, but the summary"
    echo "does not declare what was learned. Affected file(s):"
    printf '%s\n' "$MISSING" | sed 's/^/  /'
    cat <<'EOF'

Add a "learnings" object to each one (.claude/rules/core/evidence-policy.md):

  "learnings": {
    "captured": ["one line per entry written to memory/learnings/_inbox.md"],
    "none_because": null
  }

or, for a genuinely uneventful run, the other way round:

  "learnings": { "captured": [], "none_because": "clean run, no surprises" }

Anything a human had to tell you during this run — which product a ticket belongs
to, a selector that needed a workaround, a corrected report format — belongs in the
inbox now, so nobody has to explain it a second time. A product-routing correction
additionally follows .claude/rules/core/product-layer.md → "Routing learns from
being corrected".
EOF
    } >&2
    exit 2
fi

exit 0

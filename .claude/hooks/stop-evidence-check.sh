#!/usr/bin/env bash
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

[ -d "$CWD/evidence" ] || exit 0   # nothing to enforce if evidence/ isn't even scaffolded

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
looks_like_a_test_run() {
  [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  local _tmp_py
  _tmp_py="$(mktemp)"
  cat > "$_tmp_py" <<'PY'
import json, os, re, sys

path = sys.argv[1]
# Tolerate an intermediate namespace segment: a plugin-provided MCP server may
# surface as mcp__<plugin>__atlassian__* rather than mcp__atlassian__*. Matching
# only the bare form would silently switch enforcement off for plugin users —
# the failure mode being: no evidence demanded, no audit trail, all quiet.
atlassian_write = re.compile(r'^mcp__(?:[^_]+(?:_[^_]+)*__)*atlassian__.*(create|edit|add|transition|update|delete)', re.IGNORECASE)
playwright_tool = re.compile(r'^mcp__(?:[^_]+(?:_[^_]+)*__)*playwright__')
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

def walk(node):
    if isinstance(node, dict):
        if node.get("type") == "tool_use":
            name = node.get("name") or ""
            if playwright_tool.match(name):
                return True
            if atlassian_write.match(name):
                return True
            if name == "Bash":
                cmd = (node.get("input") or {}).get("command") or ""
                first_line = cmd.lstrip("\n").split("\n", 1)[0]
                if playwright_cli.match(first_line):
                    return True
        for v in node.values():
            if walk(v):
                return True
    elif isinstance(node, list):
        for v in node:
            if walk(v):
                return True
    return False

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
                break
except FileNotFoundError:
    pass

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
  find "$CWD/evidence" -name execution_summary.json -newermt '-2 hours' 2>/dev/null
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
    # Unparseable summary is a separate problem; don't also claim it lacks learnings.
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

if looks_like_a_test_run && ! has_recent_evidence; then
  cat >&2 <<'EOF'
Evidence check failed: this session actually invoked a Playwright MCP tool, an
Atlassian write (create/edit/transition/...), or the Playwright CLI runner,
but no execution_summary.json was written under evidence/<KEY>/<TICKET>/ in
the last 2 hours.

Before ending the session:
  - write evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/execution_summary.json
    (schema: .claude/rules/core/evidence-policy.md), or
  - if no test actually completed (still investigating, blocked), say so
    explicitly rather than stopping silently.
EOF
  exit 2
fi

# Evidence exists — now the learning obligation, enforced with the same firmness.
if looks_like_a_test_run; then
  MISSING="$(summaries_missing_learnings)"
  if [ -n "$MISSING" ]; then
    {
      echo "Learning check failed: this run produced evidence, but the summary does"
      echo "not declare what was learned. Affected file(s):"
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
fi

exit 0

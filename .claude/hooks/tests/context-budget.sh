#!/usr/bin/env bash
#
# context-budget.sh — asserts what the always-loaded layer actually costs.
#
# Why: docs/architecture.md claimed "Layer 1 < 2k tokens" while nine full rule files
# were being loaded into every session, costing 11.3k. Nobody noticed because the
# number was a claim, not a measurement. This makes it a measurement: the budget is
# checked, and adding a rule that busts it fails here instead of silently taxing
# every session forever.
#
# Budget rationale: the norms that must bind before any skill loads are worth their
# tokens; everything bound to a topic belongs in docs/rules/ and is read on demand.
# The budget leaves room to grow a norm, not room to move a whole rule file back in.
#
# History, so the number is not mistaken for physics:
#   2026-09-06  measured 11338 after the product layer landed; split into norms
#               (.claude/rules/core/) and details (docs/rules/) → 6843. Budget 7000.
#   2026-09-06  shadow mode added a genuine new norm; its rationale went to
#               docs/rules/, the rule kept ~8 lines, and the total landed at 7005.
#               Raised to 7200 deliberately rather than trimming five tokens of
#               prose to hit a round number — the check exists to force this call,
#               not to be gamed. The next raise needs the same kind of sentence.
#   2026-09-06  failure triage (/failure-analysis) added four fields every run writer
#               has to know about — a fourth verdict, test_cases[], deploy,
#               blocked_reason — plus one router row. The part that is detail of one
#               skill (the six classes, the failure_analysis object, the rule-in /
#               rule-out table) went to that skill's references/ and to docs/rules/
#               instead, which is what kept this to 7427. Budget 7500. The schema is
#               the one thing that genuinely must bind before any skill loads: a run
#               written to the old shape is unreadable by every reader downstream.
#   2026-09-10  "Delegation is visible" hard rule + progress.md artifact (~150 tok).
#               The norm must bind before any skill runs — it governs every Task
#               spawn, including direct skill runs without qa-manager; the how-to
#               detail (chunk granularity, progress line format) lives in
#               qa-manager.md / the executor agents, not here. Budget 7800.
#   2026-09-14  secrets resolution + re-board/whats-new (~95 tok): one router row
#               for the two new skills (discoverability — every skill has a row)
#               and the security.md exception naming resolve-secrets.sh as the
#               only sanctioned writer of .env*. Without that line the
#               always-loaded "never write .env*" rule contradicts the resolver
#               and the agent refuses the safe path. Budget 7950.
#   2026-09-16  field-report norms (~70 tok): direct test-data writes (stage only,
#               reversible, documented, confirmed per project — never to turn a
#               red run green) in qa-principles.md, and the key-existence one-liner
#               in security.md. Both must bind before any skill runs (they govern
#               ad-hoc actions, not a topic); the four-constraint detail and the
#               config-pipe rationale live in docs/rules/core/*.md. Budget 8050.
#   2026-09-18  eval-driven sharpenings (~60 tok): the delegation announcement
#               names the progress.md follow-along surface (delegation-visibility
#               was 0.33 without it), and product-layer.md states that suite runs
#               have no ticket to route from (rule-reachability was 0.33 — models
#               found product-layer.md but misapplied its ticket-signal ladder to
#               ticketless runs). Both flipped their case to 3/3. Plus the
#               narrated-draft clause in the shadow-mode rule (run 1 of the
#               verification asked permission instead of writing). Budget 8120.
#   2026-09-18  review-driven trims (~270 tok): compressed duplicated pointer text
#               in CLAUDE.md/ROUTER.md, product-layer.md, evidence-policy.md and
#               security.md (the shadow-mode mechanics moved fully into the hard
#               rule). Reserve policy from the same review: keep 300-500 tokens
#               free inside the budget — a norm that needs more than that belongs
#               in docs/rules/, not the always-loaded layer.
#   2026-09-18  eval-driven sharpening (~20 tok, MiMo gate): product-layer.md now
#               states the routing table is a count lookup, not a ranking
#               (routing-ambiguous was 1/3 under xiaomi/mimo-v2.5-pro — weaker
#               models read the numbered rungs as precedence; flipped to 3/3).
#               Reserve after this change: 292/263 — the next always-loaded
#               addition must trim its weight elsewhere first.
#   2026-09-18  preflight gate (~35 tok): router row for docs/rules/testing/
#               preflight.md (the hard PreToolUse gate + preflight.sh: stage/
#               JIRA reachability, multiple-VPN detection, secrets status —
#               the "VPN forgotten" false-positive factory). Budget 8120 →
#               8400 by user decision: the reserve target is now ~500 tokens,
#               not 300.
#
# Usage:  bash .claude/hooks/tests/context-budget.sh
# Exit:   0 within budget, 1 over.
#
set -uo pipefail

BUDGET_TOKENS="${QA_CONTEXT_BUDGET:-8400}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
cd "$REPO" || exit 1

# Everything Claude Code loads unconditionally: the router plus every file under
# .claude/rules/. Approximation: 4 characters per token — good enough to catch a
# regression of hundreds of tokens, which is the only size that matters here.
total_chars=0
printf '%-46s %9s %8s\n' "FILE" "CHARS" "~TOKENS"
while IFS= read -r f; do
  c=$(wc -c < "$f" | tr -d ' ')
  total_chars=$((total_chars + c))
  printf '%-46s %9s %8s\n' "$f" "$c" "$((c / 4))"
done < <(printf '%s\n' "CLAUDE.md"; find .claude/rules -type f -name '*.md' 2>/dev/null | sort)

total_tokens=$((total_chars / 4))
echo "----------------------------------------------------------------"
printf '%-46s %9s %8s\n' "ALWAYS LOADED (claude)" "$total_chars" "$total_tokens"

# The opencode harness loads opencode/ROUTER.md (the CLAUDE.md port) instead of
# CLAUDE.md, against the SAME ceiling — the opencode layer must not silently
# cost more than the Claude one (docs/opencode-port-plan.md, Phase 4).
oc_chars=0
if [ -f opencode/ROUTER.md ]; then
  while IFS= read -r f; do
    oc_chars=$((oc_chars + $(wc -c < "$f" | tr -d ' ')))
  done < <(printf '%s\n' "opencode/ROUTER.md"; find .claude/rules -type f -name '*.md' 2>/dev/null | sort)
  oc_tokens=$((oc_chars / 4))
  printf '%-46s %9s %8s\n' "ALWAYS LOADED (opencode)" "$oc_chars" "$oc_tokens"
else
  oc_tokens=0
  echo "opencode/ROUTER.md not present — opencode layer not measured"
fi
echo "budget: $BUDGET_TOKENS tokens"

# The on-demand half, for context — not budgeted, it costs nothing until read.
ondemand=0
while IFS= read -r f; do
  ondemand=$((ondemand + $(wc -c < "$f" | tr -d ' ')))
done < <(find docs/rules -type f -name '*.md' 2>/dev/null)
[ "$ondemand" -gt 0 ] && echo "on demand (docs/rules/): ~$((ondemand / 4)) tokens — not loaded until its topic comes up"

echo
over=0
[ "$total_tokens" -gt "$BUDGET_TOKENS" ] && over=$((total_tokens - BUDGET_TOKENS))
[ "$oc_tokens" -gt "$BUDGET_TOKENS" ] && over=$((oc_tokens - BUDGET_TOKENS))
if [ "$over" -eq 0 ]; then
  echo "within budget"
  exit 0
fi
cat <<EOF
OVER BUDGET by $over tokens.

Every session pays this, before a single skill loads. Before raising the budget,
check the cheaper fix: does the added text state a norm that must bind *before* any
skill runs, or is it detail bound to a topic? Detail belongs in docs/rules/<same
name>.md with a "read this when ..." trigger at the top — see
.claude/rules/core/*.md for the split that already exists.
EOF
exit 1

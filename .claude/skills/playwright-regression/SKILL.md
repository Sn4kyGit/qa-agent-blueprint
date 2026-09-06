---
name: playwright-regression
description: Write or run deterministic Playwright specs via the CLI runner for regression and repeatable checks. Use for "/playwright-regression" or when a flow is understood and worth automating rather than re-exploring by hand each time.
---

# /playwright-regression — CLI-driven specs

## Steps

0. Resolve scope first: a suite run started from a ticket inherits that ticket's
   product; a scheduled/headless run must be told
   (`/playwright-regression --project SHOP --product ADMIN`), because there is no
   ticket to route from and the TC namespace is product-specific.
1. Check `projects/<KEY>/PROJECT.md` → "Test assets" (overridden by the product's
   `PRODUCT.md` when one was routed) for the suite's location
   (often a separate repo checkout) and whether a spec for this flow already
   exists.
2. Delegate to subagent `test-automator`: write/extend the spec per
   `docs/rules/testing/playwright-cli.md` (TC-ID title, AAA structure,
   web-first assertions), or run the existing suite/subset relevant to the ticket.
3. Check `memory/learnings/flaky-tests.md` and `selector-failures.md` first —
   don't rediscover a known flake or a known-bad selector pattern.
4. Produce evidence (report, trace-on-failure, `execution_summary.json`) per
   `.claude/rules/core/evidence-policy.md` — including `test_cases[]`, which the CLI
   runner is the only source of and which every later failure analysis depends on.
5. **On a failure, do not conclude anything yet.** `failure-analysis` decides whether
   the product broke or the test aged out; a red spec is a question, not a verdict.
6. Report pass/fail counts and flake occurrences; anything P0–P2 confirmed as a
   product defect → `bug-report`. A recurring flake or a new selector pattern worth
   generalizing → `retro-learn`.

## Nightly / headless use

This skill is what a nightly-regression pipeline invokes via `claude -p` — see
`docs/rules/core/cicd.md` for headless-run constraints (no interactive
prompts, pre-authorized actions only).

`failure-analysis` still runs headless — the analysis is the useful part and it
costs one JQL — but the `NEEDS_REVIEW` verdict is unreachable there: a nightly writes
`FAIL` with the class and the proposal attached, and a human picks it up in the
morning. A pipeline that went green on "the test was probably outdated" would be
worse than one that went red.

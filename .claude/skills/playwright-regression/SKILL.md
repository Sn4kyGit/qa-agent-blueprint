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
   `.claude/rules/core/evidence-policy.md`.
5. Report pass/fail counts and flake occurrences; anything P0–P2 found →
   `bug-report`. A recurring flake or a new selector pattern worth generalizing →
   `retro-learn`.

## Nightly / headless use

This skill is what a nightly-regression pipeline invokes via `claude -p` — see
`docs/rules/core/cicd.md` for headless-run constraints (no interactive
prompts, pre-authorized actions only).

---
name: test-automation
description: Write or run deterministic automated test specs in the project's framework (Playwright or WebdriverIO) via the CLI runner — for regression, repeatable checks, and nightly-style suites. Use for "/test-automation", "automate this flow", "automatisiere diesen Ablauf", "write autotests", "Autotest schreiben", "run the regression suite", or when a flow is understood and worth repeating rather than re-exploring by hand each time.
---

# /test-automation — CLI-driven specs

## Steps

0. Resolve scope first: a suite run started from a ticket inherits that ticket's
   product; a scheduled/headless run must be told
   (`/test-automation --project SHOP --product ADMIN`), because there is no
   ticket to route from and the TC namespace is product-specific.
1. Check `projects/<KEY>/PROJECT.md` → "Test assets" (overridden by the product's
   `PRODUCT.md` when one was routed) for the suite's **framework** and location
   (often a separate repo checkout) and whether a spec for this flow already
   exists.
2. Delegate to subagent `test-automator`: write/extend the spec per the
   framework's conventions — Playwright: `docs/rules/testing/playwright-cli.md`
   (TC-ID title, AAA structure, web-first assertions); WebdriverIO: the
   `webdriverio-testing` skill — or run the existing suite/subset relevant to
   the ticket.
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

**Preflight before any long unattended run.** Verify what the run depends on is
actually alive — one cheap probe each: the stage URL responds, the suite's
smoke spec passes solo, any MCP server in the loop answers a trivial call. A
dead harness costs a whole night of BLOCKED cases (field report 2026-09: 11
cases lost to an MCP server down at the connection level). A failed preflight
is one BLOCKED report with the reason — never a retry loop against a dead
server; reconnecting it is a human step.

`failure-analysis` still runs headless — the analysis is the useful part and it
costs one JQL — but the `NEEDS_REVIEW` verdict is unreachable there: a nightly writes
`FAIL` with the class and the proposal attached, and a human picks it up in the
morning. A pipeline that went green on "the test was probably outdated" would be
worse than one that went red.

## Test-data hygiene

Specs that create data tear it down (`afterEach`/cleanup hook) — cleanup is
part of the spec, not optional polish. A suite that leaves artifacts behind
degrades the shared tenant, and a degraded tenant then fails **unrelated**
cases (field report 2026-09: 23 leftover test entities slowed rendering until
fresh, correct objects timed out — 13 cases "blocked" by clutter, and one
failure cascade where one spec's leftover popover blocked 20 others). Two
consequences:

- If teardown is genuinely impossible (no API, data not deletable), say so in
  the execution summary and name the residue by count and kind.
- When many independent cases suddenly block or fail together, suspect the
  environment first — leftover test data, a stale deployment, a dead service —
  and record the cause as *environment*, not as a product defect. Re-run after
  the next redeploy/cleanup before concluding anything.

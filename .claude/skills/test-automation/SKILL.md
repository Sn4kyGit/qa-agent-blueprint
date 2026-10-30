---
name: test-automation
description: Write or run deterministic automated test specs (Playwright or WebdriverIO) via the CLI runner — for regression, repeatable checks, nightly-style suites. Use for "/test-automation", "automate this flow", "Autotest schreiben", "run the regression suite", or flows understood and worth repeating.
---

# /test-automation — CLI-driven specs

When a run-scoped `context-capsule.json` path is supplied, consume its exact intake,
routing, execution controls, test assets and selected Learnings. Do not fully read
PROJECT/PRODUCT, route again or repeat mode/framework/suite lookup and merging.
Forward the capsule path to `test-automator`; targeted existing-spec, recon,
framework-convention and new-symptom Learning reads remain allowed. Return
`STALE_CONTEXT` instead of repairing a stale capsule. Direct standalone runs without
a capsule retain the effective-project fallback below.

## Steps

0. Resolve scope first: a suite run started from a ticket inherits that ticket's
   product; a scheduled/headless run must be told
   (`/test-automation --project SHOP --product ADMIN`), because there is no
   ticket to route from and the TC namespace is product-specific.
1. Use the capsule's "Test assets" for the suite's **framework** and location
   (often a separate repo checkout). Only without a capsule, read
   `projects/<KEY>/PROJECT.md` and any routed `PRODUCT.md`. In either mode, check
   whether a spec for this flow already exists.
2. Delegate to subagent `test-automator` with the capsule path when supplied. Use
   `test-automator-deep` only when reliable capsule intake marks high risk or this
   execution branch is escalated; otherwise use the standard agent. Missing or
   unknown risk means standard, and neither mode nor escalation is changed by the
   model-lane choice: write/extend the spec per the
   framework's conventions — Playwright: `docs/rules/testing/playwright-cli.md`
   (TC-ID title, AAA structure, web-first assertions); WebdriverIO: the
   `webdriverio-testing` skill — or run the existing suite/subset relevant to
   the ticket.
3. Use relevant capsule Learning excerpts first. Without a capsule, or for a new
   symptom not covered by them, check `memory/learnings/flaky-tests.md` and
   `selector-failures.md` narrowly — don't rediscover a known issue.
3b. **Never write a spec blind.** When the flow was not observed yet, run
    `/recon` first and take selectors from its `recon.json` (roles + accessible
    names), never from guesses. Assertions are positive and specific (what
    should be visible — concrete text/value/state), negative ones only
    supplementary. Every test title carries the AC-ID next to the TC-ID
    (`'AC2 / TC-CHK-014: …'`). Full rules: `docs/pipeline/04-execution.md`.
3c. **Red check for new specs** (PROJECT.md → "Execution mode" → `Red check
    required`, default yes): before a new spec's green counts as evidence,
    prove it red once — violate the expectation via data/state, or briefly
    invert the assertion. A spec that survives its own red check attempt does
    not check what it claims (`docs/pipeline/05-verification.md`).
3d. **Observation channel on every run**: console errors, responses ≥ 400, load
    times over threshold, end-of-test screenshot — collected independently of
    the assertions and reported as *Observations*, even on a fully green run.
    That is the part of the live eye a spec otherwise lacks.
4. Produce evidence (report, trace-on-failure, `run.json` run record with
   TC-IDs/outcomes/timing/mode per `docs/pipeline/04-execution.md`,
   `execution_summary.json`) per
   `.claude/rules/core/evidence-policy.md` — including `test_cases[]`, which the CLI
   runner is the only source of and which every later failure analysis depends on.
   The summary's `skills_used` lists the skills this run actually invoked
   (`test-automation`, `recon` when one ran, `webdriverio-testing` when the WDIO
   path was used) — actually used, never planned.
5. **On a failure, do not conclude anything yet.** `failure-analysis` receives the
   failure packet and capsule path when available and decides whether the product
   broke or the test aged out; a red spec is a question, not a verdict.
6. Report pass/fail counts and flake occurrences; anything P0–P2 confirmed as a
   product defect → `bug-report`. A recurring flake or a new selector pattern worth
   generalizing → `retro-learn`.

## Nightly / headless use

This skill is what a nightly-regression pipeline invokes via `claude -p` — see
`docs/rules/core/cicd.md` for headless-run constraints (no interactive
prompts, pre-authorized actions only).

**Preflight before any long unattended run.** Run the blueprint's
`preflight.sh <KEY>` — it probes stage/JIRA reachability (incl. multiple-VPN
detection) and secrets status, and the pre-tool guard enforces a fresh pass
for browser/JIRA MCP calls. Additionally verify the suite's smoke spec passes
solo. A dead harness costs a whole night of BLOCKED cases (field report
2026-09: 11 cases lost to an MCP server down at the connection level). A
failed preflight is one BLOCKED report with the reason — never a retry loop
against a dead server; reconnecting it is a human step.

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

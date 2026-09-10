---
name: test-ticket
description: Test a JIRA ticket end to end — read the ticket, route to the project, verify/deploy stage, execute the right test strategy, produce evidence, and report the verdict back to JIRA. Use for "/test-ticket <KEY-123>" or "test ticket <KEY-123>".
---

# /test-ticket — full ticket workflow

The primary entry point. Delegates the actual orchestration to the `qa-manager`
subagent, which follows `docs/architecture.md` → "End-to-end ticket flow".

## Steps

1. Parse the ticket key from the argument (`SHOP-1234`). If missing, ask for one.
   An explicit product (`--product=ADMIN`, or "test this in the admin") overrides
   automatic product routing — pass it through to `qa-manager` verbatim.
2. Invoke subagent `qa-manager` with the ticket key and this instruction: read the
   ticket via Atlassian MCP — or, when the routed `PROJECT.md` says **JIRA access:
   `browser`**, via the playwright-driven JIRA UI per
   `docs/rules/testing/jira-browser.md` (that doc then governs every JIRA
   interaction of this run) — route to `projects/<KEY>/PROJECT.md` +
   `learnings.md` (and, if that project has a `## Products` section, on to the
   ticket's product per `.claude/rules/core/product-layer.md`),
   verify stage has the fix (deploy via `deploy-to-stage` if
   allowed and needed), pick exploratory vs. regression strategy, delegate to
   `test-executor`/`test-automator` (or a specialized skill —
   `api-testing`/`accessibility-testing`/`security-testing`/`visual-testing`/
   `bug-reproduction` — when the ticket calls for one; see `qa-manager`'s
   "Specialized skills" section), ensure evidence, and report via
   `report-to-jira`. On FAIL, `failure-analysis` runs first and decides what comes
   next: `bug-report` for a product defect, a proposal for a human when the test
   case itself turns out to be the stale one.
3. Unknown project prefix or missing `projects/<KEY>/PROJECT.md` → stop and run
   `onboard-project` (or tell the user to), per `CLAUDE.md` project routing rule.
   Never guess a project's process. Same for products: a product named in the
   registry whose `products/<PRODUCT>/` directory doesn't exist (or the reverse) is
   a half-registered product → stop and run `onboard-product`, never test it.
4. After the ticket is reported, run `retro-learn`'s capture step for anything
   unexpected (env oddity, selector break, format surprise, a product you could not
   route on your own) — append to `memory/learnings/_inbox.md` — and declare the
   result in `execution_summary.json` → `learnings`, filling `none_because` when the
   run really was uneventful. The Stop hook enforces that declaration, so a run is
   not finished without it.

## Output to the user

A short summary: ticket, project (and product, if one was routed — plus how it was
resolved), verdict, evidence path, JIRA comment link (or bug ticket key if FAIL). Do not restate the full test transcript — that lives in
`evidence/<KEY>/<TICKET>/<ts>/` and in the JIRA comment itself.

## Hard rules that apply here (see `CLAUDE.md`)

Evidence is mandatory (Stop hook enforces it), no secrets anywhere in the output,
no full-repo scans — start from `memory/INDEX.md` and the project file.

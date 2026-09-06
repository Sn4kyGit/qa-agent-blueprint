---
name: retest-bug
description: Focused re-test of a fixed bug plus a tight regression sweep around it. Use for "/retest-bug <KEY-123>" or "re-test <KEY-123>" once a fix has landed on stage.
---

# /retest-bug — verify a fix + surrounding regression

A narrower, faster variant of `test-ticket` for bugs that already have a known
repro from the original report.

## Steps

1. Read the ticket — pull the **original bug report** (description, comments) to
   get the exact repro steps and the expected-vs-actual from the first report.
   Route to `projects/<KEY>/PROJECT.md` + `learnings.md` as usual — and on to the
   ticket's product if the project has a `## Products` section
   (`.claude/rules/core/product-layer.md`). A re-test is where a wrong product hurts
   most: the original repro was recorded against one product's URL and test users. If the original
   report is thin or the repro steps are vague/incomplete, run `bug-reproduction`
   first to extract a verified, minimal, deterministic repro before retesting
   anything — retesting against a repro nobody actually confirmed is a guess, not
   a test. Point it at `.agents/qa-project-context/<KEY>.md` — or, when a product
   was routed, `.agents/qa-project-context/<KEY>/<PRODUCT>.md` — explicitly (see
   `CLAUDE.md` → project routing); never the generic path it mentions internally,
   which may hold a different project's or product's data.
2. Verify stage actually has the fix deployed (version check per the project
   file) before testing — retesting against the pre-fix build produces a false
   FAIL. If not deployed, run `deploy-to-stage` (if allowed) or report BLOCKED.
3. Delegate to subagent `test-executor`: **re-execute the exact original repro
   steps** first. This is the primary check — did the specific reported behavior
   change? `bug-reproduction`'s red-before-fix discipline applies here in reverse:
   if you have access to the pre-fix build/commit, confirming the repro still
   failed there (and now passes on the fix) is stronger evidence than testing the
   fix alone.
4. Regression sweep: check 2–4 adjacent flows the fix could plausibly have
   affected (same component, same code path, same feature area) — not the whole
   application. Risk-based, per `.claude/rules/core/qa-principles.md`.
5. Evidence and reporting exactly as in `test-ticket`: evidence dir with
   `execution_summary.json`, then `report-to-jira` on PASS or `bug-report` +
   `report-to-jira` if the fix didn't hold or a regression was introduced.

## If the bug is not actually fixed

Do not soften this into a "partial pass." Report FAIL, keep the original ticket
open/reopened per the project's FAIL transition, and note precisely what part of
the original repro still reproduces.

## If a regression was introduced

File it as a **new** bug via `bug-report` (don't conflate it with the original
ticket) and cross-reference both tickets.

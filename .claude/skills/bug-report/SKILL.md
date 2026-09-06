---
name: bug-report
description: Produce a bug report exactly per the active project's template (projects/<KEY>/templates/bug-report.md). Use whenever a test finding needs to become a bug ticket, or "/bug-report" is invoked directly with a finding already in hand.
---

# /bug-report — project-conformant bug report

Delegates composition to subagent `bug-reporter`, which never freelances the
format — see `.claude/agents/bug-reporter.md` for its full process.

## Steps

1. Gather what's needed: the project key, the finding (repro steps actually
   executed, expected vs. actual, evidence file references), and severity.
2. Invoke subagent `bug-reporter` with that context (including the routed product,
   if any). It reads the product's `templates/bug-report.md` when one exists, else
   `projects/<KEY>/templates/bug-report.md`, plus
   `projects/<KEY>/PROJECT.md` → "Reporting" for the severity/priority mapping,
   fills every template section, attaches evidence, and checks for duplicates.
3. If the project's report format is `jira-cloud`, remember: no pipe tables in
   ADF — see `docs/rules/testing/jira-confluence.md`.
4. Return the created/updated ticket key to the user (or to the calling skill,
   e.g. `test-ticket`).

## What this skill does not do

It does not decide the test strategy or run the test — it packages an already-made
finding. If no finding exists yet, run `exploratory-testing` or
`playwright-regression` first.

---
name: bug-report
description: Produce a bug report exactly per the active project's template. Use when a test finding becomes a bug ticket, "/bug-report" with a finding in hand, or "Bug melden", "mach ein Bug-Ticket draus". Not for triaging why a test failed — /failure-analysis first.
license: Apache-2.0
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
5. This skill writes no `execution_summary.json` of its own: when it ran inside a
   test run, the calling flow lists `bug-report` in that summary's `skills_used`
   (`.claude/rules/core/evidence-policy.md`) — actually used only.

## What this skill does not do

It does not decide the test strategy or run the test — it packages an already-made
finding. If no finding exists yet, run `exploratory-testing` or
`test-automation` first.

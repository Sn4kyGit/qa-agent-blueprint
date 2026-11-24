---
name: report-to-jira
description: Report a test verdict back to JIRA per the active project's PROJECT.md — comment, attachments, workflow transition; Cloud = ADF, Data Center = plain Markdown. Use after a test run completes (PASS, FAIL, BLOCKED, NEEDS_REVIEW), "/report-to-jira", "melde das Ergebnis zurück", "kommentier das Ticket". Not for composing the bug ticket itself — /bug-report.
license: Apache-2.0
---

# /report-to-jira — comment + attachments + transition

## Before any write: validate this run's schema-v2 evidence

Validate the exact `execution_summary.json` and its `run.json`, not a legacy or
unrelated latest run:

```bash
python3 .claude/scripts/validate-evidence.py <run-dir>/execution_summary.json --qa-home <qa-home> --json
python3 .claude/scripts/validate-evidence.py <run-dir>/run.json --kind run-record --qa-home <qa-home> --json
```

Malformed, unversioned, unbound, hash-mismatched or verdict-inconsistent evidence
stops every JIRA write; fix the producer instead of rewriting historical evidence.
Before each Atlassian write, also run the summary validator with
`--jira-write <actual-tool-name>` so verdict-specific write rules are checked.
Apply the same verdict gates on the browser channel. After updating
`reported_to_jira`/`shadow`, revalidate the final summary.

## Before reporting a PASS: the verdict court

The mechanical validator proves the evidence is well-formed; the adversarial court
(`docs/pipeline/judge.md`) proves the verdict is *meaningfully supported*. Before a
PASS is reported, the orchestrator spawns `verdict-prosecutor` + `verdict-defender`,
adjudicates their cited briefs and records `judge-review.json`. A PASS whose review
is `unsupported` is **not reported as PASS** — it becomes NEEDS_REVIEW (a human
rules). Fast Path low-risk runs may skip the court, recorded as `judge_skipped: true`
in the summary (never silent). The court complements the validator, never replaces it.

## Before anything: is this a shadow run?

Shadow mode is **on by default**. Only when `QA_AGENT_SHADOW=0` is set or
`PROJECT.md` → "Reporting" explicitly says `Shadow mode: off` may you post.
Otherwise compose everything exactly as below but **post nothing**: write the
finished comment and the transition you would have applied to
`evidence/<KEY>/<TICKET>/<ts>/proposed-report.md`, set `"reported_to_jira": false`
and `"shadow": true` in the summary, and tell the user it is waiting for review.
No comment, no transition, no attachment — see `.claude/rules/core/security.md` →
"Shadow mode". While shadow is on, the pre-tool guard **mechanically blocks**
the atlassian write tools (including the Cloud v2 meta-tools `executeWrite` /
`executeDestructive`) — a blocked call is the guard working as designed, not a
JIRA error and never a reason to retry or route around it.

## NO_TEST posts nothing

A `NO_TEST` summary means no test completed — there is no verdict to report. Do
not comment, transition, attach, or create a bug through any channel. The summary
itself is the record (`.claude/rules/core/evidence-policy.md`).

## Before the mechanics: which channel?

`PROJECT.md` → "JIRA access" owns this decision, read it before anything
MCP-shaped below. On `browser` there is **no atlassian MCP server connected
at all** — every instruction further down that mentions ADF, Markdown
conversion, or an MCP attachment call does not apply; the entire post path
(comment, attachments, transition) runs through the playwright-driven UI per
`docs/rules/testing/jira-browser.md` → "Writing". A failed Atlassian MCP call
call in this mode is not a JIRA outage and not a reason to BLOCK — it is the
wrong channel for this project.

## Steps

1. Read `projects/<KEY>/PROJECT.md` → "Reporting": report format
   (`jira-cloud`/`plain-text`), transition names for PASS/FAIL/BLOCKED, and
   whether BLOCKED gets a transition at all. **Transitions and report format are
   read from `PROJECT.md` only, never from a `PRODUCT.md`** — they are properties of
   the JIRA project's workflow, which every product in that project shares by
   definition (`.claude/rules/core/product-layer.md`). A product may override the
   bug template and the severity mapping, nothing else here.
2. Compose the comment:
   - The header line carries the run's coordinates: verdict, environment/build,
     and **`Mode: <mcp-only|hybrid|cli-first>`** from the run's
     `execution_summary.json` → `mode` (mandatory since 0.12.0 — whoever reads
     the report later must know whether the result was observed live or only
     asserted; an escalated run names its mode and the escalation, per
     `docs/pipeline/06-reporting.md`).
   - When a product was routed, **name it in the first line** — a verdict without
     the product is ambiguous once a project has several. A ticket covering two
     products gets one aggregated comment naming both
     (`PASS (STOREFRONT) / BLOCKED (ADMIN)`, never a bare PASS) and **at most one
     transition**, chosen by the worst verdict: `FAIL > BLOCKED > NEEDS_REVIEW > PASS`.
    - **PASS**: one-line verdict, bullet list of what was checked, final
      confirming screenshot attached, evidence files referenced by filename
      (attached to the ticket).
    - **FAIL**: reference the bug ticket created via `bug-report` rather than
      re-describing the finding inline; keep this comment short.
   - **BLOCKED**: explain exactly why (env down, missing test data, no deploy
     permission) and what's needed to unblock — this is often the most useful
     comment for a human to act on quickly.
   - **NEEDS_REVIEW**: interactive only (`interactive: true`); headless brittle or
     outdated tests remain FAIL. Post **only the proposal comment** from
     `evidence/<KEY>/<TICKET>/<ts>/failure-analysis.md` — including its "do not
     apply" line and its "if you rule the other way" branch — and say plainly that
     a person has to decide. Never post a proposal without both branches. No
     attachments, transition, bug creation, or candidate application.
3. Format and post the comment. If `jira-cloud`: build ADF on a **Cloud**
   deployment, or simple Markdown on a **Data Center** deployment (the community
   server converts to wiki markup) — deployment comes from `PROJECT.md` → "JIRA
   deployment"; headings/lists, no pipe tables —
   `docs/rules/testing/jira-confluence.md` — via the Atlassian MCP server. On JIRA
   access `browser`, skip ADF/Markup and post through the playwright UI instead.
   NEEDS_REVIEW posts only this proposal comment: skip attachments and the
   transition, then complete the summary update in step 5. For every other
   reportable verdict, attach evidence files (screenshots, not full logs unless
   the project asks) via the configured channel. On Cloud v2 the comment/transition
   tools are Primary (direct); attachment upload is DEFERRED — `discover` once,
   then `executeWrite` with `uploadAttachmentToJiraIssue`
   (`docs/rules/testing/jira-confluence.md` → "Cloud v2").
4. Except for NO_TEST and NEEDS_REVIEW (which never transition), apply the
   transition from step 1 — exact name, never guessed. If the named
   transition doesn't exist in the ticket's current workflow state, stop and
   report that mismatch rather than trying nearby transition names.

   **Which transition depends on the failure class**, when `failure_analysis` is
   present in the summary:

   | Class | Transition |
   |---|---|
   | `product-defect`, `undetermined` | the project's FAIL transition, as before — a possible defect must not pass |
   | `test-outdated`, `test-brittle`, `flake` | **comment only, no transition** |
   | `environment` | the project's BLOCKED handling |

   The reason the middle row exists: applying `Reopen` because *our* assertion held
   the pre-change contract tears open a developer's correctly-closed ticket, and a
   QA agent that does that twice is one nobody reads again. The transition *names*
   remain sealed to `PROJECT.md` — this decides **whether** to transition, never
   **which** name to use.
5. This write goes through the JIRA-write audit automatically
     — no action needed from you beyond making the actual MCP call. Afterwards
     update the run's summary (`reported_to_jira`, `shadow`) and make sure its
     `skills_used` lists the skills the run actually used, `report-to-jira`
     included (`.claude/rules/core/evidence-policy.md`).

## Two output channels, two reference rules

Applies to every block this skill composes (comment, bug description, proposal):
`docs/pipeline/06-reporting.md` → "Two output channels". In short:

- **Into the ticket** (anything posted or handed to the user for copy-paste):
  never a local path — no `evidence/...` run dir, no absolute machine path, no
  `file://`. Evidence = filenames + "attached to this ticket". Repo-relative
  spec paths stay allowed.
- **Into the chat summary to the user:** evidence files with their **absolute
  path**, one per line — absolute paths are clickable in the harness UI,
  relative ones lead nowhere half the time. The JIRA comment itself never
  carries these paths. Afterwards, on interactive macOS sessions, open the run
  dir in Finder (`open "<absolute run-dir>"`) so the evidence is one preview
  away — rule and guards (skip on Linux/CI/headless):
  `docs/pipeline/06-reporting.md` → "Finder auto-open".

## What you never do

Post real credentials, internal URLs, or PII in a JIRA comment. Transition a
ticket to a state not defined for this project without checking first. Attach raw
`evidence/` directory contents wholesale — attach the specific relevant files.
Put a local path (`evidence/...`, absolute machine path, `file://`) into the
comment or description — filenames only, the paths belong in the chat summary.

---
name: report-to-jira
description: Report a test verdict back to JIRA as a comment, with attachments and the correct workflow transition, per the active project's PROJECT.md format. Comment format follows the project's deployment — Cloud = ADF via MCP tools, Data Center = plain Markdown (never hand-written wiki syntax, never hand-rolled ADF). Use after a test run completes, on PASS, FAIL, BLOCKED, or NEEDS_REVIEW — also for "/report-to-jira", "melde das Ergebnis zurück", "kommentier das Ticket", or "post the verdict to JIRA". Not for composing the bug ticket itself — that's /bug-report; this only posts an already-produced verdict/comment.
---

# /report-to-jira — comment + attachments + transition

## Before anything: is this a shadow run?

Shadow mode is **on by default**. Only when `QA_AGENT_SHADOW=0` is set or
`PROJECT.md` → "Reporting" explicitly says `Shadow mode: off` may you post.
Otherwise compose everything exactly as below but **post nothing**: write the
finished comment and the transition you would have applied to
`evidence/<KEY>/<TICKET>/<ts>/proposed-report.md`, set `"reported_to_jira": false`
and `"shadow": true` in the summary, and tell the user it is waiting for review.
No comment, no transition, no attachment — see `.claude/rules/core/security.md` →
"Shadow mode".

## NO_TEST posts nothing

A `NO_TEST` summary means no test completed — there is no verdict to report. Do
not comment, do not transition, do not attach. The summary itself is the record
(`.claude/rules/core/evidence-policy.md`).

## Steps

1. Read `projects/<KEY>/PROJECT.md` → "Reporting": report format
   (`jira-cloud`/`plain-text`), transition names for PASS/FAIL/BLOCKED, and
   whether BLOCKED gets a transition at all. **Transitions and report format are
   read from `PROJECT.md` only, never from a `PRODUCT.md`** — they are properties of
   the JIRA project's workflow, which every product in that project shares by
   definition (`.claude/rules/core/product-layer.md`). A product may override the
   bug template and the severity mapping, nothing else here.
2. Compose the comment:
   - When a product was routed, **name it in the first line** — a verdict without
     the product is ambiguous once a project has several. A ticket covering two
     products gets one aggregated comment naming both
     (`PASS (STOREFRONT) / BLOCKED (ADMIN)`, never a bare PASS) and **at most one
     transition**, chosen by the worst verdict: `FAIL > BLOCKED > NEEDS_REVIEW > PASS`.
   - **PASS**: one-line verdict, bullet list of what was checked, final
     confirming screenshot attached, evidence directory noted.
   - **FAIL**: reference the bug ticket created via `bug-report` rather than
     re-describing the finding inline; keep this comment short.
   - **BLOCKED**: explain exactly why (env down, missing test data, no deploy
     permission) and what's needed to unblock — this is often the most useful
     comment for a human to act on quickly.
   - **NEEDS_REVIEW**: the test failed but `failure-analysis` classified the test
     itself as stale or brittle, not the product. Post the proposal from
     `evidence/<KEY>/<TICKET>/<ts>/failure-analysis.md` — including its "do not
     apply" line and its "if you rule the other way" branch — and say plainly that
     a person has to decide. Never post a proposal without both branches.
3. If `jira-cloud`: build the comment as ADF on a **Cloud** deployment, or as
   simple Markdown on a **Data Center** deployment (the community server converts
   to wiki markup) — deployment comes from `PROJECT.md` → "JIRA deployment";
   headings/lists, no pipe tables —
   `docs/rules/testing/jira-confluence.md`) via the Atlassian MCP server.
   Attach evidence files (screenshots, not full logs unless the project asks for
   them) via the attachment call.
   On a project with **JIRA access: `browser`**, skip ADF/Markup entirely and post
   through the playwright-driven UI instead — comment, attachments and transition
   per `docs/rules/testing/jira-browser.md` → "Writing".
4. Apply the transition from step 1 — exact name, never guessed. If the named
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
5. This write goes through the `PostToolUse` JIRA-write audit hook automatically
   — no action needed from you beyond making the actual MCP call.

## What you never do

Post real credentials, internal URLs, or PII in a JIRA comment. Transition a
ticket to a state not defined for this project without checking first. Attach raw
`evidence/` directory contents wholesale — attach the specific relevant files.

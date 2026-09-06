---
name: report-to-jira
description: Report a test verdict back to JIRA as a comment, with attachments and the correct workflow transition, per the active project's PROJECT.md format. Use after a test run completes, on PASS, FAIL, or BLOCKED.
---

# /report-to-jira — comment + attachments + transition

## Before anything: is this a shadow run?

If `QA_AGENT_SHADOW=1` is set, or `PROJECT.md` → "Reporting" says `Shadow mode: on`,
compose everything exactly as below but **post nothing**: write the finished comment
and the transition you would have applied to
`evidence/<KEY>/<TICKET>/<ts>/proposed-report.md`, set `"reported_to_jira": false`
and `"shadow": true` in the summary, and tell the user it is waiting for review.
No comment, no transition, no attachment — see `.claude/rules/core/security.md` →
"Shadow mode".

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
     transition**, chosen by the worst verdict: `FAIL > BLOCKED > PASS`.
   - **PASS**: one-line verdict, bullet list of what was checked, final
     confirming screenshot attached, evidence directory noted.
   - **FAIL**: reference the bug ticket created via `bug-report` rather than
     re-describing the finding inline; keep this comment short.
   - **BLOCKED**: explain exactly why (env down, missing test data, no deploy
     permission) and what's needed to unblock — this is often the most useful
     comment for a human to act on quickly.
3. If `jira-cloud`: build the comment as ADF (headings/lists, no pipe tables —
   `docs/rules/testing/jira-confluence.md`) via the Atlassian MCP server.
   Attach evidence files (screenshots, not full logs unless the project asks for
   them) via the attachment call.
4. Apply the transition from step 1 — exact name, never guessed. If the named
   transition doesn't exist in the ticket's current workflow state, stop and
   report that mismatch rather than trying nearby transition names.
5. This write goes through the `PostToolUse` JIRA-write audit hook automatically
   — no action needed from you beyond making the actual MCP call.

## What you never do

Post real credentials, internal URLs, or PII in a JIRA comment. Transition a
ticket to a state not defined for this project without checking first. Attach raw
`evidence/` directory contents wholesale — attach the specific relevant files.

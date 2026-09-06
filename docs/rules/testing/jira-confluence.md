# JIRA / Confluence Formatting & Transitions

JIRA Cloud stores comment/description content as **ADF (Atlassian Document
Format)**, written via REST API v3 — not Markdown, not wiki markup. This has real
consequences for how reports are structured.

## ADF constraints — the ones that actually bite

- **No pipe tables.** ADF has a table node, but hand-rolled Markdown pipe syntax
  (`| a | b |`) does not convert and renders as literal text. Use ADF table nodes
  via the Atlassian MCP tools, or restructure as a bullet list / heading + paragraph
  sequence if the tool path doesn't support tables cleanly.
- Keep structures simple: headings, paragraphs, bullet/numbered lists, code blocks,
  bold/italic, links, and mentions are safe. Nested structures (a table inside a
  list, multiple heading levels for a short comment) tend to mangle in the
  converter — flatten instead.
- Attachments (screenshots, logs) are uploaded separately via the attachment
  endpoint, then referenced by filename in the comment — not inlined as data.

## Report structure (per `report-to-jira`)

A standard PASS/FAIL comment: one-line verdict heading → bullet list of what was
checked → findings (if any) as a short list with severity → evidence file names →
nothing more. See `projects/<KEY>/PROJECT.md` → "Reporting" for any project-specific
format override (`jira-cloud` vs `plain-text`).

## Transitions

Exact workflow transition names are project-specific — read them from
`projects/<KEY>/PROJECT.md` → "Reporting" before transitioning anything:

- `Transition on PASS` — e.g. `Verify`.
- `Transition on FAIL` — e.g. `Reopen`.
- `On BLOCKED` — often comment-only, no transition; check the project file.

Never guess a transition name from convention — an invalid transition name fails
loudly in some workflows and silently no-ops in others.

## Confluence

Test-plan/strategy links live in `projects/<KEY>/PROJECT.md` → "Confluence" —
read the linked page for detailed steps when a ticket's acceptance criteria are
thin, rather than asking the user to restate them. The agent does not edit
Confluence pages as part of normal test-ticket flow; that's a separate, explicit
request.

## Converter pitfalls (learned, not theoretical)

If a comment renders with garbled formatting, garbled tables, or missing
attachments, capture it via `retro-learn` into `memory/learnings/_inbox.md` with
the exact structure that failed — these are exactly the kind of surprises the
learning loop exists for.

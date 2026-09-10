# JIRA via Browser (access mode `browser`)

Read this when the active project's `PROJECT.md` says **JIRA access: `browser`** —
the deployment where no API path exists (policy forbids tokens, REST blocked,
only a web login works). Every JIRA interaction then happens through the
**playwright MCP** against the JIRA web UI. The ticket-driven flow is unchanged;
only the transport differs.

The mechanics below are deliberately generic — JIRA Data Center UIs (AUI) differ
per version and theme. When a selector described here does not match, find the
working one, use it, and **capture it in `projects/<KEY>/learnings.md`** — that
file accumulates the locators that actually work on this instance, and the next
run greps it first.

## Login

- Credentials come from `.env.playwright-secrets` as **secret keys** (e.g.
  `JIRA_QA_USER` / `JIRA_QA_PASS`), referenced from `PROJECT.md` → "Test users".
  The browser fills them masked; the values never enter the transcript.
- The browser runs isolated by default (`.playwright-mcp.config.json`):
  **every run logs in fresh**. Accept the seconds; a persistent profile
  (`"isolated": false`) is a deliberate user preference, not a workaround the
  agent chooses — shared state between runs is the thing isolation exists to
  prevent.

## Reading a ticket

1. Navigate to `<JIRA base URL>/browse/<KEY>-<n>` (base URL from PROJECT.md).
2. Take the accessibility snapshot; extract summary, description/acceptance
   criteria, status, components, labels, fix versions, and the comment history
   when the task needs it.
3. For a change window (`failure-analysis`): use the issue search UI
   (`/issues/?jql=fixVersion%3D<version>%20AND%20status%3DDone` — JQL works in
   the URL even without API access), then read the matching issues.

## Writing (comment, attachments, transition)

**All of this section is gated by shadow mode** (`.claude/rules/core/security.md`):
while shadow is on, none of it executes — the composed comment/transition goes to
`evidence/<KEY>/<TICKET>/<ts>/proposed-report.md` and the run's summary carries
`"shadow": true, "reported_to_jira": false`. There is **no mechanical write log**
in browser mode (no MCP call for the audit hook to see) — the proposal review is
the only control, which is why shadow stays on until proposals are consistently
right.

With shadow off, per `report-to-jira`:

1. **Comment**: open the ticket, focus the comment field (on classic DC UI the
   "Comment" button opens the editor; on newer ones the field is inline at the
   bottom), fill the composed text, submit via the editor's save/comment button.
   The DC editor is rich text / wiki markup — the `plain-text` report structure
   (verdict line → bullets → findings → evidence file names) works as-is; no ADF,
   no pipe tables.
2. **Attachments**: the known-hard part. Use the attachment flow ("Attach files"
   dialog / drag-drop zone) with the MCP file-upload capability. Attach the
   decisive screenshot(s) — not the whole evidence directory; the run dir path is
   referenced in the comment either way.
3. **Transition**: click the workflow button bearing the exact name from
   `PROJECT.md` → "Reporting" (`Transition on PASS` / `on FAIL`). Never infer a
   transition from what the UI happens to show — an unexpected button set means
   the ticket is in an unexpected status: stop and say so.

## Brittleness is expected — the loop absorbs it

AUI selectors break across versions and theme changes. That is normal, not a
defect of this mode: capture each break via the learning loop (Pattern:
`workaround` or `error-resolution`), and the project's learnings file becomes the
instance-specific locator knowledge base. If a run cannot complete a JIRA step
because the UI doesn't match anything known: verdict BLOCKED with the precise
step that failed — never improvise a write you cannot verify happened.

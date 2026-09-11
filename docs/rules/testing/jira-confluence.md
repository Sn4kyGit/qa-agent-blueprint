# JIRA / Confluence Formatting & Transitions

The right format depends on the project's **JIRA deployment**
(`projects/<KEY>/PROJECT.md` → "JIRA deployment"): `cloud` or `datacenter`.
Everything below is split by it.

## Deployments: Cloud vs. Data Center

| | Cloud | Data Center (self-hosted) |
|---|---|---|
| MCP backend | official remote server (`mcp.atlassian.com`) | community server [`sooperset/mcp-atlassian`](https://github.com/sooperset/mcp-atlassian) (Jira DC v8.14+), run via `uvx` |
| Auth | OAuth 2.1 (`/mcp` browser flow, once) | Personal Access Token: `JIRA_PERSONAL_TOKEN` + `JIRA_URL` as **environment variables** (exported in the shell, inherited by `uvx` — never written into `.mcp.json`, the repo, or chat) |
| API / content format | REST v3, **ADF** | REST v2, **wiki markup** — the community server converts plain Markdown input to the right storage format. Write plain Markdown only — **never hand-write wiki syntax** (`h2.`, `*bold*`, `{code}`); converting is the server's job, hand-rolled markup double-escapes |
| Server name in `.mcp.json` | `atlassian` | `atlassian` — **same name regardless of backend**: the audit/evidence hooks match on it |

DC consumer `.mcp.json` variant (no secrets in the file):

```json
"atlassian": {
  "command": "uvx",
  "args": ["mcp-atlassian"],
  "env": { "JIRA_URL": "https://jira.example.local" }
}
```

The blueprint's shipped default stays Cloud; a Data Center consumer replaces
the `atlassian` entry with the variant above (name unchanged).

## Cloud: ADF constraints — the ones that actually bite

JIRA Cloud stores comment/description content as **ADF (Atlassian Document
Format)**, written via REST API v3 — not Markdown, not wiki markup. This has real
consequences for how reports are structured.

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

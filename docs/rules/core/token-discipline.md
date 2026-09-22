# Token Discipline — details

On-demand companion to `.claude/rules/core/token-discipline.md`, which stays in the
always-loaded layer and carries the norms. **Read this file when someone proposes adding, removing or configuring an MCP server.**
Splitting it out is what keeps the always-on layer small; nothing here is
optional when its topic comes up.

## MCP budget

MCP servers are a **declared set, not a fixed number**. Every server costs startup
time, tool-schema tokens in every session, and one more surface to keep secrets out
of — so the set stays deliberately small, but it is the team's decision, not a
constant baked into the rules.

**The register below is the sanctioned set.** `.mcp.json` is the wiring; this table
is the justification. A server in one but not the other is a finding: either it was
added without a decision, or a decision was never wired up.

| Server | Why it is in the budget | Notes |
|---|---|---|
| `playwright` | The agent cannot test a web UI without a browser | Contract: name + `--secrets` + `--output-dir`; the rest is preference (`.playwright-mcp.config.json`) |
| `atlassian` | Tickets in, results out — the entire premise is ticket-driven | Cloud: remote server, OAuth 2.1. Data Center: community server + PAT |

## Scope: servers are per QA home, not per project

MCP servers are wired at the **consumer-folder level** (the QA home's
`.mcp.json`, or the plugin's), never per `projects/<KEY>/`. Every project in
one QA home shares the declared set — a project that does not need a server
simply never calls it: an API-only product never touches `playwright`, and
nothing breaks. `atlassian` is the one non-optional server (the flow is
ticket-driven); `playwright` is effectively required for any UI-testing
project but inert when unused.

One hard constraint follows: **one JIRA instance per QA home.** The
`atlassian` server binds to exactly one site (the Cloud OAuth site, or one
`JIRA_URL` on Data Center). Two JIRA instances are not a reason to register a
second server — the audit and evidence hooks match on the name `atlassian`,
and a second name would bypass them silently. Two JIRA instances = **two QA
homes** (two folders, project-scoped plugin in each — that is what
`--scope project` is for).

**A CLI is not a server.** Triggering a pipeline (`gh`, `glab`, `curl`) is a Bash
command declared in the project file under "How a deploy is triggered", not a reason
to add an MCP server. The register is for things that genuinely need a protocol.

**Adding one.** The agent never adds an MCP server on its own initiative — it
proposes, the user decides. When a server is approved: wire it in `.mcp.json`, add
a row here with the reason in one line, and note anything it changes about secrets
handling in `.claude/rules/core/security.md`. Removing one is the same in reverse.

**Project-scoped, always.** A project's MCP servers live in that project's own
config (`.mcp.json` / `opencode.json`) — never in global config
(`~/.claude.json`, `~/.config/opencode/`). Global config is invisible to the
project boundary and can silently point at another project's credentials
(field report 0.9.0 in `security.md`); the PreToolUse guard blocks both
directions: calling a global-only server, and writing global config.

**Before proposing one, check it earns its place**: does it enable something the
blueprint genuinely cannot do (a browser, the ticket system, a credential source),
or is it convenience that a Bash call or an existing skill already covers? Three
servers with a clear purpose each beat two plus a workaround — and beat five.

**Credential/vault servers get an extra condition**: they may resolve a *reference*
to a secret for the tool that needs it, never surface a value into the transcript,
a file, a ticket, or an artifact. See `.claude/rules/core/security.md` → "Credential
sources" before wiring one.

Within Playwright MCP, prefer the accessibility snapshot over screenshots for
navigation decisions — screenshots are for evidence, not for the agent to "read"
the page (see `docs/rules/testing/playwright-mcp.md`).

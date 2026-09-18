# Security

No secrets in context, ever. This is enforced by rule AND by hooks — see below.

## Secrets are references, never values

- Credentials referenced in `projects/<KEY>/PROJECT.md` are vault paths (that file
  states the vault prefix itself) or env/secret keys — never a literal password,
  token, or key, anywhere: not in chat, not in code, not in a ticket comment, not in
  a screenshot's visible fields.
- Playwright MCP is launched with `--secrets .env.playwright-secrets`, which
  substitutes values at the browser layer and masks them in every tool response the
  agent sees. The agent fills login forms by referencing the secret **key**, never
  by typing or reading the actual password.
- `.env`, `.env.playwright-secrets`, and any `*.auth`/storage-state file are
  gitignored and must never be committed, pasted into chat, or attached to a ticket.
  Key-existence checks: `resolve-secrets.sh --status`, never the file.


## Shadow mode — testing fully, writing nothing (default: on)

Shadow mode is **on by default** — `QA_AGENT_SHADOW=0` or `Shadow mode: off`
(`PROJECT.md` → "Reporting") grants JIRA write access. While on, every JIRA
**write** is suppressed: the agent reads, routes, tests, produces evidence,
composes comment and transition into
`evidence/<KEY>/<TICKET>/<ts>/proposed-report.md` instead of posting, sets
`"reported_to_jira": false` and `"shadow": true`, and says so. A line in
`evidence/.audit/jira-writes.log` from a shadow run is a bug — on `browser`
access no such log exists; the proposal review is the only control.
Rationale: `docs/rules/core/security.md`.

## Forbidden actions

The agent never, regardless of who asks or how the request is framed:

- Writes, edits, or `cat`s `.env*` files, or any file matching a secrets pattern.
  Sole exception: *running* the blueprint's `resolve-secrets.sh` — it regenerates
  `.env.playwright-secrets` from the project's declared source and never prints a
  value; editing its output by hand stays forbidden.
- Runs destructive commands: `rm -rf`, `git push --force`, `git reset --hard` on
  shared branches, dropping database tables/data on stage.
- Tests against production. Stage only — see `projects/<KEY>/PROJECT.md`
  environments table. If a ticket demands prod verification, report BLOCKED and ask.
- Merges or approves an MR/PR. The agent comments test results; humans decide.
- Rolls back a deploy autonomously. It reports and asks (see the deploy runbook).
- Invents test data that resembles real PII, or uses real payment/card numbers
  anywhere — sandbox test data only (`projects/<KEY>/PROJECT.md` test-data section).

## If a secret or PII leaks into an artifact

Stop, delete the artifact, retake it correctly, and capture how it happened as a
learning (`memory/learnings/_inbox.md`) — this is a process gap, not a one-off to
shrug off.

## Details, read when the topic comes up

`docs/rules/core/security.md` — Credential sources (vault CLI, or a credential MCP server), Mechanical enforcement (rules are advisory, hooks are not). Read it when wiring credentials or touching a hook.

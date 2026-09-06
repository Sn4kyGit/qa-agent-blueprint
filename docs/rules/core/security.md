# Security — details

On-demand companion to `.claude/rules/core/security.md`, which stays in the
always-loaded layer and carries the norms. **Read this file when wiring a credential source, or when changing/reviewing a hook.**
Splitting it out is what keeps the always-on layer small; nothing here is
optional when its topic comes up.

## Credential sources (vault CLI, or a credential MCP server)

The MCP set is configurable (`.claude/rules/core/token-discipline.md` → MCP budget),
so a password-manager or vault server may legitimately join it — a QA agent that
cannot reach test-user credentials is a QA agent that cannot log in. What does
**not** change is where secrets are allowed to exist.

A credential source may **resolve a reference for the tool that needs it**. It may
never:

- print, echo, or summarize a secret value into the transcript, a report, a ticket
  comment, an artifact, or a commit — including "just to confirm it was fetched";
- write a value into a file, `.env*` included (the PreToolUse guard blocks that
  path regardless of where the value came from);
- fetch credentials for a system the current ticket does not require, or for
  production, ever;
- become the way login happens in a browser test. That path stays
  `.env.playwright-secrets` + Playwright MCP `--secrets`, because it masks the value
  in every tool response the agent sees. A vault server hands the *human* or the
  *setup step* the value; it does not hand it to the model mid-test.

The safe pattern is unchanged: `projects/<KEY>/PROJECT.md` names the vault path and
the secret key, the agent references the key, and the value never enters context.
If a credential server makes a value visible anyway, that is an incident under "If
a secret or PII leaks into an artifact" below — delete, redo, capture the gap.

## Mechanical enforcement (rules are advisory, hooks are not)

A hook counts as enforcement only once a test proves it blocks — these are shell
scripts parsing a JSON payload, and a parse failure makes them fail open while
still looking correct in review. Every hook that enforces something has fixtures:
`guard-fixtures.sh` (PreToolUse allow/block), `stop-evidence-fixtures.sh` (the Stop
hook's evidence *and* learning-declaration checks), `session-start-fixtures.sh`
(project/product listing) and `install-integrate-fixtures.sh` (integrate mode end
to end: namespacing, path rewriting, idempotency, uninstall) — all under
`.claude/hooks/tests/`. Run the matching one
after any change to a hook, and add a fixture for every new rule.

- `PreToolUse` guard (`pre-tool-guard.sh`) blocks `Bash`/`Write`/`Edit`/`MultiEdit`/
  `NotebookEdit` calls that touch `.env*`, attempt `rm -rf`, or force-push.
- Permission denylist in `.claude/settings.json` prevents reads of known secret file
  patterns outright.
- `PostToolUse` JIRA write audit (`post-jira-audit.sh`) logs every Atlassian MCP
  write (create/edit/transition/delete) to `evidence/.audit/jira-writes.log` for
  traceability — including headless CI runs.

## Shadow mode — why it exists and how to run it

`QA_AGENT_SHADOW=1` in the environment, or `Shadow mode: on` under `PROJECT.md` →
"Reporting", suppresses every JIRA **write** while leaving the rest of the run
untouched. It exists because the largest adoption risk is not technical: an agent
that transitions real tickets from day one gets switched off after the first wrong
`Reopen`, and then the blueprint is dead regardless of how good it is.

In shadow mode the agent still: reads tickets, routes, deploys if allowed, tests,
produces evidence, composes the exact comment and names the exact transition. It
then writes them to `evidence/<KEY>/<TICKET>/<ts>/proposed-report.md` instead of
posting, and says so in its summary.

It must not: create, edit, transition or comment on any issue; upload attachments;
or describe the result as reported. `"reported_to_jira": false` plus
`"shadow": true` go into `execution_summary.json`, so `/qa-report` can tell a
shadow week from a silent week.

Everything else keeps running — routing still learns, learnings are still captured
and promoted. Two weeks of shadow operation produce a reviewable record of what the
agent *would* have written, which is the evidence a team needs before granting it
write access. The JIRA-write audit log is the check: a shadow run that produced an
entry in `evidence/.audit/jira-writes.log` is a bug, not a judgment call.

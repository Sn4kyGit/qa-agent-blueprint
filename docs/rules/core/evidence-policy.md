# Evidence Policy — details

On-demand companion to `.claude/rules/core/evidence-policy.md`, which stays in the
always-loaded layer and carries the norms. **Read this file when the Stop hook blocks a session and you need to know exactly what it checks.**
Splitting it out is what keeps the always-on layer small; nothing here is
optional when its topic comes up.

## Stop hook enforcement

`stop-evidence-check.sh` runs on session end. If the transcript shows a completed
test action (a Playwright MCP/CLI run, a reported verdict) with no matching
`execution_summary.json` under `evidence/`, the hook blocks the stop and asks for
the missing artifact. This is not a reminder — the session cannot end clean without
it.

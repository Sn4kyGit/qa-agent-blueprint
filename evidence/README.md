# evidence/ — local test evidence store

All test artifacts land here: screenshots, logs, traces, and the mandatory
`execution_summary.json` per run.

## Structure

```
evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/
├── screenshots/<TICKET>_<step>_<kind>.png
├── logs/{console.log, network.log, playwright.log}
├── traces/trace.zip
└── execution_summary.json
```

Special subdirectories:

- `.mcp-out/` — raw Playwright MCP output (`--output-dir` from `.mcp.json`)
- `.audit/` — append-only audit logs (e.g. `jira-writes.log`)

## Rules

- **Gitignored — never commit anything in here.** (Only this README is tracked.)
- One directory per run; timestamps in `YYYYMMDD-HHMMSS`; naming per
  `.claude/rules/core/evidence-policy.md`.
- No PII, no secrets, no auth-state files. Retention policy:
  `docs/artifact-strategy.md`.
- Artifacts are referenced by path, never loaded into the model context. That is a
  discipline rule (`.claude/rules/core/token-discipline.md`), **not** an enforced
  boundary: Claude Code does not honor `.claudeignore` for tool reads. For a hard
  boundary add `Read(evidence/**)` to `permissions.deny`.

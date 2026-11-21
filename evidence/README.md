# evidence/ — local test evidence store

All test artifacts land here: screenshots, logs, traces, schema-v2 `run.json`,
and the mandatory schema-v2 `execution_summary.json` per run.

## Structure

```
evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/
├── screenshots/<TICKET>_<step>_<kind>.png
├── logs/{console.log, network.log, playwright.log}
├── traces/trace.zip
├── run.json
├── execution_summary.json
├── action-journal/                 # semantic MCP recon/exploration events
├── automation-handoff.json         # ready selected case only, when graduating
└── healing/                        # optional candidates/review, never a verdict
```

Special subdirectories:

- `.mcp-out/` — raw Playwright MCP output (`--output-dir` from `.mcp.json`)
- `.audit/` — append-only audit logs (e.g. `jira-writes.log`)

## Rules

- **Gitignored — never commit anything in here.** (Only this README is tracked.)
- One directory per run; timestamps in `YYYYMMDD-HHMMSS`; naming per
  `.claude/rules/core/evidence-policy.md`. `run_id` and `evidence_dir` bind both
  JSON records to this exact directory; historical files are never rewritten.
- New run/summary records are schema v2 with RFC3339 timestamps, exact
  required/executed coverage, normalized `pass|fail|flaky|skip|fixme|not_run`
  outcomes, attempts including the first (`attempt_results` when available), and
  existing run-relative artifacts with exact `path`/`sha256` plus optional
  `covers`. Retry-pass is flaky; required skip/fixme/not_run prevents PASS;
  PASS is clean only. Validate new files with `validate-evidence.py`; malformed
  or inconsistent evidence is invalid. Producer details: `docs/pipeline/04-execution.md`.
- MCP journals use `action-journal.py`: semantic locators and secret `input_ref`
  names only, never raw refs/snapshots/logs or secret values. Seed is reproducible
  start state, not RNG. Handoff readiness and healing green checks never change
  the original verdict; only a human applies a reviewed healing candidate.
- No PII, no secrets, no auth-state files. Retention policy:
  `docs/artifact-strategy.md`.
- Raw artifacts are referenced by path, never loaded into the model context.
  `.claudeignore` documents this policy but is not enforced for tool reads. The
  enforced `permissions.deny` boundary covers `.mcp-out`, screenshots/images,
  traces, videos and similar raw artifacts — never `evidence/**` wholesale.
- `execution_summary.json`, curated reports and structured JSON/Markdown remain
  readable for verdicts, aggregation and reporting.

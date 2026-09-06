# Artifact Strategy (one page)

Decisions about test evidence: what we capture, how long it lives, who sees it.

## Capture defaults

| Artifact | Interactive | CI | Why |
|---|---|---|---|
| Screenshot | only-on-failure **+ one final shot on PASS** | same | PASS needs visual proof for the ticket; failures need the moment of failure |
| Video | retain-on-failure | retain-on-failure | full videos per pass waste review time and storage |
| Trace | retain-on-failure | on-first-retry | CI retries exist to capture traces of flakes |
| execution_summary.json | always | always | machine-readable verdict; Stop-hook enforced |
| console/network logs | on failure (console always on FAIL) | on failure | noise on PASS, gold on FAIL |

## Location & naming

- Local: `evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/` — one dir per run, never reused.
- Names: `<TICKET>_<step>_<kind>.png` for screenshots; fixed names for logs/traces.
- Raw MCP output lands in `evidence/.mcp-out/`; curated artifacts are copied into the
  run dir. Full schema: `.claude/rules/core/evidence-policy.md`.

## Retention

- **Local**: developer machines clean `evidence/` ad hoc; suggest ≥ 30 days
  (a retention period per project, chosen by the team). **Not implemented:** no
  script, hook or job prunes `evidence/` today, so it grows until someone deletes
  it. Evidence dirs are gitignored — the repo
  never grows.
- **JIRA**: artifacts attached to tickets live with the ticket (permanent record of
  the verdict).
- **CI**: run dirs uploaded as pipeline artifacts with the project's retention
  (suggest 30 days; traces/videos of PASS runs may be dropped immediately).
- Optional central storage (share/S3) is a team decision — record it in the project
  file if adopted.

## PII & secrets

- Test data only. No real customer PII in screenshots/logs — ever.
- No auth state (cookies, storage-state dumps, `*.auth`) in run dirs intended for
  upload; such files stay in `.env.playwright-secrets`/vault land.
- If a secret or PII is visible in an artifact: delete, retake, and check how it got
  there (capture it as a learning).

## Access

- Run dirs are local to the machine that ran the test; JIRA attachments are the
  sharing mechanism for results.
- `.claudeignore` keeps `evidence/` out of the model context — artifacts are
  referenced by path, never loaded wholesale.
- The append-only audit log `evidence/.audit/jira-writes.log` records every JIRA
  write (who/what/where) for traceability, including headless CI runs.

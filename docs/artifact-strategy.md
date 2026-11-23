# Artifact Strategy (one page)

Decisions about test evidence: what we capture, how long it lives, who sees it.

## Capture defaults

| Artifact | Interactive | CI | Why |
|---|---|---|---|
| Screenshot | only-on-failure **+ one final shot on PASS** | same | PASS needs visual proof for the ticket; failures need the moment of failure |
| Video | retain-on-failure | retain-on-failure | full videos per pass waste review time and storage |
| Trace | retain-on-failure | on-first-retry | CI retries exist to capture traces of flakes |
| run.json + execution_summary.json | always, schema v2 | always, schema v2 | bound run/case/coverage/outcome record and machine-readable verdict; evidence-gate enforced |
| action journal + ready handoff | MCP recon/exploration graduating to automation | same | semantic actions/seed/oracles only; no raw refs or secrets, no new verdict |
| healing candidate/review | optional after brittle-locator classification | same | review evidence only; never applied automatically and never a verdict |
| console/network logs | on failure (console always on FAIL) | on failure | noise on PASS, gold on FAIL |

## Location & naming

- Local: `evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/` — one dir per run, never reused.
- Names: `<TICKET>_<step>_<kind>.png` for screenshots; fixed names for logs/traces.
- New v2 run/summary records bind `run_id`/`evidence_dir`, RFC3339 timestamps,
  required/executed coverage, normalized attempts/outcomes, and every listed
  artifact's run-relative path + exact SHA-256 (`covers` optional). Retry-pass is
  flaky, required skip/fixme/not_run prevents PASS, and malformed evidence is
  invalid. Historical files stay untouched; see `docs/pipeline/04-execution.md`.
- Raw MCP output lands in `evidence/.mcp-out/`; curated artifacts are copied into the
  run dir. Full schema: `.claude/rules/core/evidence-policy.md`.

## Retention

- **Local (implemented, 0.23.0)**: `.claude/scripts/evidence-retention.py` prunes
  `evidence/` in two stages — **A** deletes heavy artifacts (screenshots, logs,
  traces, videos) inside old run dirs but keeps the curated JSON/MD verdict
  records and writes a `.retention.json` marker (default 30 days); **B** deletes
  whole run dirs after a longer period (default 365 days, minimum 90), appending
  a compact fact line to `evidence/.audit/retention-index.log` *first* so metric
  history survives. `evidence/.mcp-out/` raw output is pruned by age separately
  (default 7 days). Protection rules keep the newest run per ticket, fresh runs,
  pending shadow proposals, `NEEDS_REVIEW` awaiting a ruling, `.retain`-pinned
  runs, and `.audit/`/`.preflight/`/`_rollups/`. **Pruning is a human step**: the
  agent runs `plan`/`status` and notifies ("bitte aufräumen"), the guard blocks
  agent `prune` invocations on both harnesses, and a human runs `prune --yes` in
  their own terminal. Per-project policy lives in `PROJECT.md` →
  `## Evidence retention`; the `/evidence-retention` skill drives the workflow.
  Design: `docs/retention-leases-rollup-plan.md` §3. Evidence dirs are gitignored
  — the repo never grows.
- **JIRA**: artifacts attached to tickets live with the ticket (permanent record of
  the verdict). Retention never touches JIRA attachments.
- **CI**: run dirs uploaded as pipeline artifacts with the project's retention
  (suggest 30 days; traces/videos of PASS runs may be dropped immediately). A CI
  cron may call `evidence-retention.py plan` and surface the hint; a direct
  `prune --yes` in a pipeline is an explicit human choice (the recommended CI
  default is plan + notification, never unattended deletion).
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
- `.claudeignore` only declares the raw-artifact policy; Claude Code does not
  enforce it for tool reads. The actual boundary is `permissions.deny` for
  `.mcp-out`, screenshots/images, traces, videos and similar raw binary artifacts.
  Raw artifacts are referenced by path, never loaded wholesale.
- `execution_summary.json`, v2 run records, semantic journal/handoff selections,
  healing reviews, curated reports and other structured JSON/Markdown remain
  deliberately readable; there is no blanket `evidence/**` read deny. Raw MCP refs,
  snapshots/logs and secret values do not belong in those curated records.
- The append-only audit log `evidence/.audit/jira-writes.log` records every JIRA
  write (who/what/where) for traceability, including headless CI runs.

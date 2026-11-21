# Evidence Policy — details

On-demand companion to `.claude/rules/core/evidence-policy.md`, which stays in the
always-loaded layer and carries the norms. **Read this file when the evidence gate blocks a session and you need to know exactly what it checks, or when you are about to write `NEEDS_REVIEW` or `NO_TEST` into a summary.**
Splitting it out is what keeps the always-on layer small; nothing here is
optional when its topic comes up.

## Evidence gate enforcement

The evidence gate runs on session end (Claude Code: `stop-evidence-check.sh`
Stop hook; opencode: plugin evidence gate). If the transcript shows a completed
test action (a Playwright MCP/CLI run, a reported verdict) with no matching
`execution_summary.json` under `evidence/`, the gate blocks the session end and
asks for the missing artifact. This is not a reminder — the session cannot end clean without
it.

The block message carries a machine-readable first-line marker so a headless
pipeline can tell "the agent violated the evidence obligation" apart from a crash:
`QA_EVIDENCE_MISSING:` (no summary at all) or `QA_EVIDENCE_INVALID:` (malformed,
unversioned new evidence, schema/semantic mismatch, bad path/hash/coverage, or a
JIRA write forbidden by the verdict). See `docs/rules/core/cicd.md` for the exit
semantics in `claude -p`.

## `execution_summary.json` — full example

```json
{
  "schema_version": 2,
  "run_id": "20260904-143000",
  "ticket": "SHOP-1234",
  "project": "SHOP",
  "product": "STOREFRONT",
  "scope": "product",
  "product_routed_by": "component",
  "timestamp": "2026-09-04T14:30:00Z",
  "verdict": "PASS",
  "test_type": "exploratory",
  "mode": "hybrid",
  "environment": { "name": "stage", "version_or_build": "2.14.0-rc3", "commit": "a3f9c21" },
  "deploy": { "from_version": "2.13.4", "to_version": "2.14.0-rc3", "pipeline_run": "…", "at": "…" },
  "steps_executed": ["login as qa-standard", "add item to cart", "checkout"],
  "test_cases": [
    { "id": "TC-CHK-014", "outcome": "pass", "attempts": 1, "required": true,
      "spec": "specs/checkout/coupon.spec.ts:42", "assertion": "total is 80.10" }
  ],
  "findings": [],
  "coverage": { "required": ["TC-CHK-014"], "executed": ["TC-CHK-014"] },
  "artifacts": [{ "path": "screenshots/SHOP-1234_checkout_pass.png", "sha256": "<64-lowercase-hex-sha256-of-exact-file-bytes>" }],
  "evidence_dir": "evidence/SHOP/SHOP-1234/20260904-143000/",
  "reported_to_jira": true,
  "shadow": false,
  "learnings": {
    "captured": ["storefront page cache served stale assets after deploy"],
    "none_because": null
  },
  "skills_used": ["test-ticket", "recon", "test-automation"],
  "started_at": "2026-09-04T14:00:00Z",
  "finished_at": "2026-09-04T14:47:23Z",
  "duration_s": 2843,
  "phases": { "intake": 120, "readiness": 60, "recon": 300, "planning": 180, "execution": 1800, "verification": 240, "reporting": 143 },
  "session": { "model": "sonnet", "requested_model": "sonnet", "delegations": 4, "tool_calls": 47 }
}
```

## Schema v2 validation and normalized runner records

Fresh `execution_summary.json` files require `schema_version: 2`; unversioned
files are accepted only by historical readers such as `/qa-report`,
`tc-history.py`, `skill-review.py` and `verify-sightings.py`. Except for minimal
`NO_TEST` closeout records, v2 requires environment name/version/commit, deploy
from/to/pipeline/time, and `skills_used`; when genuinely unavailable, record an
explicit `unavailable`/`not-applicable` string and the reason, never invent one.
The Stop/evidence
gate invokes `.claude/scripts/validate-evidence.py`, which also checks that the
summary location equals `evidence_dir` and `evidence/<project>/<ticket>/<run>`.
Artifact entries contain a run-relative `path` and the SHA-256 of those exact
file bytes. Absolute paths, traversal, missing files and hash drift are invalid.

`run.json` follows `run-record-v2.schema.json`. Produce it deterministically from
JUnit XML or Playwright JSON:

```bash
python3 .claude/scripts/normalize-test-results.py results.json \
  --ticket SHOP-1234 --timestamp 2026-09-04T14:30:00Z \
  --require TC-CHK-014 --output evidence/SHOP/SHOP-1234/20260904-143000/run.json \
  --qa-home .
```

The normalized outcomes are `pass`, `fail`, `flaky`, `skip`, `fixme`, `not_run`.
Attempts count actual executions. A retry that eventually passes is `flaky`
(`attempts >= 2`), never a clean pass. `skip`, `fixme` and `not_run` have zero
attempts and are absent from executed coverage. Coverage lists required and
executed IDs and must mirror the cases. A required non-pass or
missing execution blocks `PASS`. Any failure or finding means `FAIL`, not
`BLOCKED`. `PASS` additionally needs at least one valid artifact and no findings,
failed cases or flaky cases. With no definitive failure, incomplete required
coverage is `BLOCKED`.

| Verdict | JIRA effect |
|---|---|
| `PASS` / `FAIL` / `BLOCKED` | normal project reporting rules after valid evidence |
| `NEEDS_REVIEW` | interactive-only (`interactive: true`); proposal comment allowed, transitions and bug creation denied |
| `NO_TEST` | every JIRA write denied; the summary is session-closeout evidence only |

`session.requested_model` records the lane the orchestrator chose. The
harness-measured facts (dominant model, failover switches, compression byte
savings) live in `evidence/.audit/session-perf.log` and
`evidence/.audit/compression.log` and are read from there by `/qa-report` and
`perf-analysis` — they never depend on the agent's self-report.

## `NO_TEST` — the explicit way out

The gate fires whenever a test *tool* was invoked, which includes sessions that
legitimately completed no test: still investigating a reported problem, debugging
a flaky spec, or aborted early. The answer is not to end the session silently
(that works only via the loop-breaker and leaves no record) — it is a minimal
summary:

```json
{
  "schema_version": 2,
  "ticket": "SHOP-1234", "project": "SHOP", "timestamp": "2026-09-04T14:30:00Z",
  "verdict": "NO_TEST", "evidence_dir": "evidence/SHOP/SHOP-1234/20260904-143000",
  "no_test_reason": "reproduced twice, root cause not isolated before session end",
  "steps_executed": [], "test_cases": [], "findings": [], "artifacts": [],
  "coverage": { "required": [], "executed": [] },
  "learnings": { "captured": [], "none_because": "no product knowledge gained" }
}
```

Three consequences, all deliberate:

- `report-to-jira` posts **nothing** for `NO_TEST` — there is no verdict to report.
- `aggregate.py` excludes the run from the pass-rate denominator, exactly like
  BLOCKED: a session that tested nothing must not move the product's numbers in
  either direction. The reasons are listed in the report so `NO_TEST` clusters
  (same ticket, repeated investigations) stay visible.
- The `learnings` obligation still applies. A session that investigated and found
  nothing is precisely where a captured dead end saves the next session an hour.

## Why `NEEDS_REVIEW` costs the same as a FAIL

A `test-outdated` verdict is the one classification an agent could use to make
failures disappear, so it is deliberately built to be worth nothing in the numbers:

- `aggregate.py` counts it in the pass-rate **denominator** (`decided = PASS + FAIL +
  NEEDS_REVIEW`) and never in the numerator. Classifying a failure as a stale test
  changes no metric for the better.
- `human_ruling` stays `null` until a person decides, and `/qa-report` prints how
  many are open and how old the oldest is. A backlog that grows week over week is
  the visible symptom of an agent — or a team — reclassifying defects away.
- Headless the verdict is unreachable: `claude -p` and CI write `FAIL` with the
  analysis attached. A proposal nobody is present to read is not a proposal, and a
  pipeline that goes green on "the test was probably outdated" is worse than one
  that goes red.

The counterpart is what the verdict buys: `report-to-jira` applies **no** transition
for it. Reopening a developer's correctly-closed ticket because our own assertion
held the pre-change contract is how a QA agent loses a team's trust in a week.

## Why the run records `test_cases[]`, `deploy` and `commit`

None of the three is new instrumentation — all three were already produced and then
discarded: `test-automator` returns pass/fail per TC-ID plus pass-on-retry counts,
`deploy-to-stage` step 8 instructs "record from→to version and pipeline run id" into
a schema that had no field for it, and the version endpoint returns `{"version",
"commit"}` of which only the version was kept. Persisting them makes three questions
answerable that no single run can answer alone: *has this case ever passed, and on
which version?*, *what shipped between then and now?*, and *how often did it need a
retry?* — the inputs to `failure-analysis` and to a flake rate that
`.claude/skills/qa-report/aggregate.py` previously had to refuse to compute.

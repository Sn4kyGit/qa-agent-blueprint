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
`QA_EVIDENCE_MISSING:` (no summary at all) or `QA_LEARNINGS_MISSING:` (summary
without a `learnings` declaration). See `docs/rules/core/cicd.md` for the exit
semantics in `claude -p`.

## `execution_summary.json` — full example

```json
{
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
    { "id": "TC-CHK-014", "outcome": "pass", "attempts": 2,
      "spec": "specs/checkout/coupon.spec.ts:42", "assertion": "expected 80.10, got 90.00" }
  ],
  "findings": [],
  "evidence_dir": "evidence/SHOP/SHOP-1234/20260904-143000/",
  "reported_to_jira": true,
  "shadow": false,
  "learnings": {
    "captured": ["storefront page cache served stale assets after deploy"],
    "none_because": null
  },
  "skills_used": ["test-ticket", "recon", "test-automation"]
}
```

## `NO_TEST` — the explicit way out

The gate fires whenever a test *tool* was invoked, which includes sessions that
legitimately completed no test: still investigating a reported problem, debugging
a flaky spec, or aborted early. The answer is not to end the session silently
(that works only via the loop-breaker and leaves no record) — it is a minimal
summary:

```json
{
  "ticket": "SHOP-1234", "project": "SHOP", "timestamp": "…",
  "verdict": "NO_TEST",
  "no_test_reason": "reproduced twice, root cause not isolated before session end",
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

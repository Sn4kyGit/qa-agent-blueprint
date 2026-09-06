# Evidence Policy — details

On-demand companion to `.claude/rules/core/evidence-policy.md`, which stays in the
always-loaded layer and carries the norms. **Read this file when the Stop hook blocks a session and you need to know exactly what it checks, or when you are about to write `NEEDS_REVIEW` or `NO_TEST` into a summary.**
Splitting it out is what keeps the always-on layer small; nothing here is
optional when its topic comes up.

## Stop hook enforcement

`stop-evidence-check.sh` runs on session end. If the transcript shows a completed
test action (a Playwright MCP/CLI run, a reported verdict) with no matching
`execution_summary.json` under `evidence/`, the hook blocks the stop and asks for
the missing artifact. This is not a reminder — the session cannot end clean without
it.

The block message carries a machine-readable first-line marker so a headless
pipeline can tell "the agent violated the evidence obligation" apart from a crash:
`QA_EVIDENCE_MISSING:` (no summary at all) or `QA_LEARNINGS_MISSING:` (summary
without a `learnings` declaration). See `docs/rules/core/cicd.md` for the exit
semantics in `claude -p`.

## `NO_TEST` — the explicit way out

The hook fires whenever a test *tool* was invoked, which includes sessions that
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

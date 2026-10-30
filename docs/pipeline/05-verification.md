# Pipeline 05 — Verification

The phase that closes the quality gap between CLI and live observation — and
the one most often skipped, which is exactly why CLI results otherwise come out
worse (00-overview).

## Red check

**A spec that has never been red is no evidence.**

Before a new spec's first green counts, the expectation is deliberately
violated:

1. Preferably through data or state — set the test data so the acceptance
   criterion is provably violated.
2. Alternatively by briefly inverting the assertion.

If the test does **not** fail then, it does not check what it claims to check,
and is reworked. Costs about a minute per spec and catches the entire
false-green class.

Controlled by PROJECT.md → "Execution mode" → `Red check required`. The result
is recorded in `verdict.json`. A spec without a passed red check must not back
a `PASS` verdict for its AC. Applies to **new** specs; established suite specs
with a failure history have already proven themselves.

## Observation pass

When `Verification pass: yes` (hybrid), a green CLI run is followed by **one
short MCP session** over the ticket's main flow — few steps, with the explicit
charter to watch for everything *not* in the assertions:

- layout, truncated texts, overlapping elements
- loading states, double spinners, flicker
- wording and language quality of messages
- states the test plan did not contain

Runs inside `test-executor` like any MCP work. Everything found goes into the
report as `Observations`, not as `FAIL` — unless it violates an acceptance
criterion.

Cost: one short session per ticket instead of one long one. The yield is high
because this is precisely where the findings a spec systematically misses
originate.

## Classifying failures

Every red test gets exactly one category. **No retry before classification.**
This is the pipeline view of what `failure-analysis` does with full rigor —
the subagent `failure-analyst` owns the classification; `qa-manager` or the direct
main orchestrator invokes it, never an execution leaf. This table is its contract:

| Category | Signature | Consequence |
|---|---|---|
| product defect | application misbehaves, assertion matches the AC | `bug-report` |
| test defect | stale selector, colliding test data, wrong timing assumption | fix spec, possibly re-run recon |
| environment problem | service down, build not deployed, DB empty | `BLOCKED`, report the cause |

The classifying model needs the acceptance criteria in context — they travel
with the execution delegation for exactly this reason (cause 5 in 00-overview).

## Flakes

A test that is green and red without a code change is a finding of its own.
At most one targeted re-run, reported with the result. Never raise `retries`,
never soften the assertion, never skip without a ticket. Entry into
`memory/learnings/flaky-tests.md`; `test-reliability` owns quarantine and
root-causing.

## Output: `verdict.json` in the run dir

**Producer:** the verification owner writes `verdict.json` — `qa-manager` on the
complex path, the run-owning main orchestrator on the Fast Path. It records the
red check result, the observation pass result and the failure classification.

```json
{
  "red_check": { "performed": true, "passed": ["AC1", "AC2"] },
  "observation_pass": {
    "performed": true,
    "turns": 6,
    "observations": [
      "AC2 error message appears only after 2s without a loading indicator"
    ]
  },
  "classification": [
    { "ac": "AC2", "category": "product defect",
      "reasoning": "500 on /api/discount/validate, UI shows no message" }
  ],
  "overall": "FAIL"
}
```

`verdict.json` feeds `execution_summary.json` (`verdict`, `failure_analysis`,
`findings`) — the summary remains the enforced artifact.

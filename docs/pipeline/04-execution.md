# Pipeline 04 — Execution

## Precondition: readiness is green

`readiness.json` must confirm the project-allowed ticket status, no unresolved
blockers, every required linked MR/PR merged, and `intake.expected_build` live on
stage when build verification is required (`01a-readiness.md`). The gate precedes
stage liveness, recon and execution; JIRA browser intake is the only earlier
browser exception. A missing merge/required build is BLOCKED or a deploy handoff;
explicitly unavailable verification is reported unverified, never a
test against a known-wrong state.

## Writing the spec (hybrid, cli-first)

The spec is generated from `testplan.md` **and** `recon.json`. Selectors come
from `recon.json`, never guessed. Framework conventions stay where they are:
`docs/rules/testing/playwright-cli.md`, resp. the `webdriverio-testing` skill —
this file adds the pipeline obligations on top.

### Selector ranking

1. `getByRole(role, { name })` — first choice, checks accessibility on the side
2. `getByLabel` / `getByPlaceholder` — form fields
3. `getByText` — only for unique, stable text
4. `getByTestId` — when nothing above works; request `data-testid` from the dev
5. CSS/XPath — only with a justifying comment

Never: generated class names, `nth-child`, DOM-structure paths. (WDIO: the
same ranking, expressed via `$()`/`$$` and aria — see the webdriverio skill.)

### Assertion rules

- **Positive and specific.** Not "no error visible" but what should be visible
  instead. Not existence — concrete text, value, or state.
- Negative assertions only supplementary, never the sole proof of an AC.
- Web-first assertions only (`await expect(...)`) — they wait automatically.
- No fixed sleeps. Wait on state, response, or element.

### AC binding

Every test carries the criterion's ID in its title, next to the persistent
TC-ID:

```ts
test('AC2 / TC-CHK-014: coupon rejected below minimum order value',
  async ({ page }) => { /* … */ });
```

Without this binding the report cannot show what was covered, and the runner
cannot classify a failure (phase 5).

### Isolation

Every test creates its own data and cleans up (see `test-automation` →
"Test-data hygiene"). Login via stored storage state, not through the UI —
unless the login itself is under test. Tests run in any order.

## Running

Always inside the `test-automator` subagent; only the condensed result comes
back, never raw output. `--reporter=line` is the default
(`docs/rules/testing/playwright-cli.md` → "Runner output"). Credentials reach
the runner by injection — `qa-secrets.mjs run <KEY…> -- <runner>`
(`.claude/rules/core/security.md`), never wholesale dotenv.

## Observation channel

Independent of the assertions, every run collects: console errors, responses
with status ≥ 400, load times over threshold, a screenshot at the end of each
test. Findings land in the report under `Observations`, even on a fully green
run. This replaces part of the running eye a live session has by itself.
Practically: a shared fixture/helper in the suite (scaffold-suite templates
ship one) attaches these to the run dir; `run.json` carries the summary.

## MCP execution (mcp-only, escalated cases)

Play the test cases live, secure evidence **at the moment of observation**. On
any deviation: screenshot (culprit element marked, per
`docs/rules/testing/playwright-mcp.md`), console and the relevant response
immediately, before clicking on — the state is usually gone afterwards, and a
re-enacted screenshot is no proof.

## Output: `run.json` in the run dir

**Producer:** the execution leaf that ran the cases writes `run.json` at the end
of the run — `test-executor` after an MCP session, `test-automator` after a CLI
run (cheap/deep lanes included). It is the run record: TC-IDs, outcomes, timing,
mode.

```json
{
  "command": "npx playwright test tests/e2e/checkout --reporter=line",
  "mode": "hybrid",
  "duration_s": 47,
  "result": { "passed": 4, "failed": 1, "skipped": 0, "flaky": 0 },
  "cases": [
    { "ac": "AC1", "tc": "TC-CHK-013", "title": "…", "status": "PASS",
      "evidence": "evidence/SHOP/SHOP-1234/<ts>/screenshots/…" },
    { "ac": "AC2", "tc": "TC-CHK-014", "title": "…", "status": "FAIL",
      "core_error": "expected 'Minimum order value not reached' to be visible",
      "artifact": "evidence/SHOP/SHOP-1234/<ts>/traces/trace.zip" }
  ],
  "observation_channel": {
    "console_errors": ["TypeError: cannot read properties of undefined …"],
    "failed_requests": ["500 /api/discount/validate"],
    "slow_pages": []
  }
}
```

`run.json` feeds `execution_summary.json` → `test_cases[]` — the summary schema
stays the single enforced contract; `run.json` is its working-level source.

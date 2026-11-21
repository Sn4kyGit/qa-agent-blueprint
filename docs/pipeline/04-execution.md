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

The spec is generated from `testplan.md` **and** `recon.json`; for
exploration-to-spec it also consumes a ready `automation-handoff.json` and its
selected semantic journal events. Selectors come from those observations, never
guesses. The handoff seed is replayed as the project-owned start state (not RNG),
and its AC oracle, hashes, red check and original verdict stay intact. Framework conventions stay where they are:
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

Before the runner, use the suite's `npm run test:quality` wrapper when present
(`test:quality:staged` for staged strict checks) or the direct framework scanner
from `docs/rules/testing/playwright-cli.md` / `webdriverio-testing`. Base suites
keep warning-only scans; `/scaffold-suite --quality-pack` is the explicit opt-in
to the strict quality layer. This adds no MCP server, agent or hook type.

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

For recon/exploration, the executor also writes the semantic action journal via
`action-journal.py`: reproducible seed, case boundaries, semantic actions,
AC-bound positive oracle, red check and original outcome. Raw MCP refs,
snapshots/logs and secret values never enter it; secrets use `input_ref`. The
manager validates/finalizes and selects a ready case before creating
`automation-handoff.json` (`action-journal.md`). The journal is not a verdict.

## Output: schema-v2 `run.json` and `execution_summary.json`

**Producers:** the execution leaf writes `run.json` and the run's summary draft;
the run-owning orchestrator verifies/finalizes that summary with `verdict.json`.
New files use
`schema_version: 2`; historical files remain historical and are never rewritten.
For CLI runs, normalize the exact Playwright JSON or JUnit XML bytes with
`normalize-test-results.py` instead of hand-deriving outcomes. The source path and
SHA-256 bind those exact bytes; artifact paths are run-relative and their hashes
match the files on disk.

```json
{
  "schema_version": 2,
  "run_id": "20261115-100000",
  "ticket": "SHOP-1234",
  "project": "SHOP",
  "timestamp": "2026-11-15T10:00:47Z",
  "started_at": "2026-11-15T10:00:00Z",
  "finished_at": "2026-11-15T10:00:47Z",
  "evidence_dir": "evidence/SHOP/SHOP-1234/20261115-100000",
  "source": {
    "format": "playwright",
    "path": "results/playwright.json",
    "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  },
  "command": "npx playwright test tests/e2e/checkout --reporter=line",
  "mode": "hybrid",
  "duration_s": 47,
  "test_cases": [
    {"id": "TC-CHK-013", "outcome": "pass", "attempts": 1, "required": true,
     "spec": "tests/e2e/checkout.spec.ts:12", "assertion": "total is 10 EUR"},
    {"id": "TC-CHK-014", "outcome": "fail", "attempts": 1, "required": true,
     "spec": "tests/e2e/checkout.spec.ts:31", "assertion": "minimum-order error is visible"},
    {"id": "TC-CHK-015", "outcome": "flaky", "attempts": 2, "required": false,
     "spec": "tests/e2e/checkout.spec.ts:48",
     "attempt_results": [{"attempt": 1, "outcome": "fail"}, {"attempt": 2, "outcome": "pass"}]},
    {"id": "TC-CHK-016", "outcome": "skip", "attempts": 0, "required": true,
     "spec": "tests/e2e/checkout.spec.ts:64"}
  ],
  "coverage": {
    "required": ["TC-CHK-013", "TC-CHK-014", "TC-CHK-016"],
    "executed": ["TC-CHK-013", "TC-CHK-014", "TC-CHK-015"]
  },
  "artifacts": [
    {"path": "screenshots/SHOP-1234_checkout_fail.png",
     "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
     "covers": ["TC-CHK-014"]},
    {"path": "logs/playwright.log",
     "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
     "covers": ["TC-CHK-013", "TC-CHK-014", "TC-CHK-015"]}
  ],
  "observation_channel": {
    "console_errors": [], "failed_requests": ["500 /api/discount/validate"], "slow_pages": []
  }
}
```

The summary repeats the same `run_id`, case/coverage and artifact bindings and adds
its RFC3339 `timestamp`, verdict, environment/deploy, steps, findings, skills and
learnings declarations. `started_at`/`finished_at` are optional wall-clock bounds.
Case rules are binding in both files:

- Outcomes are exactly `pass|fail|flaky|skip|fixme|not_run`. Attempts include the
  first execution; `attempt_results[]` retains individual normalized attempts when
  the reporter supplies them. Clean pass = one attempt; retry-pass = `flaky` with at
  least two; skip/fixme/not_run = zero and absent from executed coverage.
- `coverage.required` exactly matches required cases; `executed` exactly matches
  cases ending pass/fail/flaky. Optional `artifacts[].covers` names the case IDs an
  artifact supports, never a substitute for its path/hash.
- PASS requires complete required coverage, clean required passes, no failed/flaky
  case or finding, and a valid artifact. Required skip/fixme/not_run prevents PASS;
  without a definitive failure that is BLOCKED with `blocked_reason`. A retry-pass
  cannot be relabelled pass to obtain PASS.
- Exploratory runs without runner cases use `steps_executed`; they do not invent
  test cases. NO_TEST has no executed coverage and permits no JIRA write.

Validate both files before phase 6. Malformed JSON, missing v2 fields, duplicate
IDs, path/hash/coverage/attempt inconsistencies or a verdict mismatch are invalid
evidence, not another verdict and never something to report around:

```bash
python3 .claude/scripts/validate-evidence.py <run-dir>/run.json --kind run-record --qa-home <qa-home> --json
python3 .claude/scripts/validate-evidence.py <run-dir>/execution_summary.json --qa-home <qa-home> --json
```

# Playwright CLI Runner — Usage & Conventions

For regression and repeatable checks, run inside the `test-automator` subagent.
Deterministic specs via the CLI runner are roughly 4× cheaper than driving the same
flow through the MCP loop turn-by-turn — use the CLI once a flow is understood and
worth repeating (see `.claude/rules/core/qa-principles.md` for exploratory-vs-CLI
choice).

## Spec conventions

- Location and config per `projects/<KEY>/PROJECT.md` → "Test assets" (often a
  separate repo checkout, e.g. `../<key>-web-tests/`).
- One `test.describe` per flow; `test.beforeEach` for login/setup, matching the
  patterns already proven in `memory/learnings/flaky-tests.md`.
- Web-first assertions (`expect(locator).toBeVisible()`, `expect(page).toHaveURL()`,
  `expect.poll()`) — never `waitForTimeout()` as a first resort (see flaky-tests
  learnings on fixed sleeps).

## AC and TC-IDs

Title format `AC<ID> / TC-<CAT>-<NNN>: behavior`, with the real AC and `<CAT>`
from `projects/<KEY>/PROJECT.md` → "TC categories" (e.g. `AUTH`, `CHK`, `CART`).
Example: `test('AC2 / TC-CHK-014: coupon rejected below minimum order value', ...)`.
The AC and persistent TC-ID make failures directly reportable and comparable.

## Runner output — keep it out of the context

- Default invocation: `npx playwright test --reporter=line` (single-line progress,
  failures with detail at the end). The default `list` reporter prints one line
  per test × retry — hundreds of context tokens for zero verdict value on a
  green run.
- HTML/JSON reports and traces still land on disk (per the suite's config);
  open them only for failure triage, never print them into the chat.
- Grep the output for the failure block when triaging; don't re-run with a
  noisier reporter "to see more" — the detail is already in the failure section.

## Retries & flakes

- Local: `--retries=0`. A flake must reproduce locally to be fixable — don't mask
  it with retries during development.
- CI: `--retries=2`, `trace: on-first-retry`. The retry exists to **capture the
  trace of the flake**, not to turn red green.
- A test that passes only on retry is a flake, not a pass — log it (see
  `memory/learnings/flaky-tests.md`) and report it as a suite-health signal, never
  silently accept it.

## Static quality scan

Scaffolded suites wrap `qa-test-code-scan.mjs` as `quality/scan.mjs`:

```bash
npm run test:quality           # suite scan; warnings by default
npm run test:quality:staged    # staged blobs, strict
node .claude/scripts/qa-test-code-scan.mjs tests playwright.config.ts --strict
```

`.qa-test-quality.json` owns rule severities/strict mode. Base scaffolding includes
the warning-only wrapper; only explicit `/scaffold-suite --quality-pack` adds the
strict fixtures/configuration layer. The scanner reads source/staged blobs and adds
no MCP server, agent or hook type; its findings are not run evidence.

## Metrics to report

- Pass rate, P0/P1 breakdown against the project's gate overrides.
- Flake rate (retry-passes / total runs) — rising trend escalates in the weekly
  report per `docs/architecture.md`.
- Coverage delta if the project tracks it.

## Before writing a new spec

Check `projects/<KEY>/PROJECT.md` → "Test assets" for whether one already exists
for this flow — extend, don't duplicate. Check `memory/learnings/selector-failures.md`
and `flaky-tests.md` before choosing selectors or wait strategies.

**Never write a spec blind** (pipeline norm, `docs/pipeline/04-execution.md`):
selectors come from a `/recon` run's `recon.json`; exploration-to-spec additionally
requires a ready `automation-handoff.json` and its selected semantic journal events.
Replay its seed as the project-owned start state (not RNG), preserve its AC positive
oracle/hashes and original verdict, and never mistake readiness for PASS. Assertions
are positive and specific, every title is `AC<ID> / TC-<CAT>-<NNN>: behavior`, and
new specs pass the **red check** before their green counts
(`docs/pipeline/05-verification.md`). Every run collects the **observation channel**
(console errors, responses ≥ 400, end-of-test screenshot) even when fully green.

## Schema-v2 evidence

Normalize the exact Playwright JSON or JUnit result with
`.claude/scripts/normalize-test-results.py`, then validate new `run.json` and
`execution_summary.json` with `.claude/scripts/validate-evidence.py`. Both bind
`run_id`/`evidence_dir`, RFC3339 timestamps, required/executed coverage and hashed
run-relative artifacts (`covers` optional). Preserve normalized outcomes, attempts
including the first, and `attempt_results` when available: retry-pass is flaky,
required skip/fixme/not_run prevents PASS, and PASS is clean only. Malformed or
inconsistent new evidence is invalid; never rewrite historical files to pass.

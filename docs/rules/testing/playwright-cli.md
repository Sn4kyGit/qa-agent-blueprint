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

## TC-IDs

Format `TC-<CAT>-<NNN>` where `<CAT>` comes from `projects/<KEY>/PROJECT.md` → "TC
categories" (e.g. `AUTH`, `CHK`, `CART`). IDs go in the test title
(`test('TC-CHK-014: coupon applies discount', ...)`) so failures map directly to a
reportable identifier.

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

## Metrics to report

- Pass rate, P0/P1 breakdown against the project's gate overrides.
- Flake rate (retry-passes / total runs) — rising trend escalates in the weekly
  report per `docs/architecture.md`.
- Coverage delta if the project tracks it.

## Before writing a new spec

Check `projects/<KEY>/PROJECT.md` → "Test assets" for whether one already exists
for this flow — extend, don't duplicate. Check `memory/learnings/selector-failures.md`
and `flaky-tests.md` before choosing selectors or wait strategies.

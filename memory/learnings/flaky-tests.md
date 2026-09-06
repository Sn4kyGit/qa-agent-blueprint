# Flaky Tests — cross-project learnings

Known flake patterns, root causes, and mitigations. A flake = fails without product
change, passes on retry. Flakes are **findings about the test system** — never
silence them with retry inflation. Groomed by `/retro-learn`.

## Retry strategy (baseline)

- Local reproduction: `--retries=0` — a flake must be reproducible to be fixable.
- CI: `--retries=2` + `trace: on-first-retry` — the retry exists to *collect the
  trace*, not to greenwash.
- Pass-on-retry events are counted and reported as flake metrics; rising trend =
  suite health problem, escalate in the weekly report.

## Known causes & mitigations

### 2026-08-10 — Fixed sleeps instead of conditions (seed) (seen: 3)
- Cause: `waitForTimeout(2000)` races against real load time; stage latency varies.
- Mitigation: web-first assertions (`expect(locator).toBeVisible()`,
  `expect(page).toHaveURL(...)`) or `waitForResponse` on the concrete request.
  `waitForTimeout` only as a documented last resort with a comment why.

### 2026-08-19 — Shared test data between parallel workers (seed) (seen: 2)
- Cause: two workers mutated the same product/cart fixture → order-dependent
  failures.
- Mitigation: per-worker seeded entities (suffix with worker index), cleanup in
  `afterEach`, never assert on global lists — filter by own entities.

### 2026-08-28 — Background jobs assert too early (seed) (seen: 2)
- Cause: emails, exports, search indexing happen asynchronously; immediate
  assertions race the job.
- Mitigation: `expect.poll(...)` / `toPass({ timeout })` against the resulting
  state (API row, outbox), not the triggering UI action.

### 2026-09-03 — Stage deploy in progress during test run (seed) (seen: 1)
- Cause: someone deployed mid-run; assets/API versions mixed.
- Mitigation: verify `/api/version` (or project equivalent) at suite start; on
  mismatch mid-run, mark results suspect and re-run. Check `env-gotchas.md` for
  shared-stage etiquette.

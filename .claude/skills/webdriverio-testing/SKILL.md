---
name: webdriverio-testing
description: >-
  Write or run deterministic WebdriverIO specs (web, Selenium Grid remote, mobile
  via Appium) through the WDIO CLI runner. Loaded by test-automation when the
  project's "Test assets" → Framework says webdriverio; route user requests to
  /test-automation. Not for Playwright suites.
license: Apache-2.0
---

# WebdriverIO — spec conventions for the test-automator

This is the WDIO counterpart to `docs/rules/testing/playwright-cli.md`: same
discipline (determinism, TC-IDs, retry policy, evidence), expressed in WDIO 9
terms. Loaded by `test-automator` when "Test assets" → **Framework** says
`webdriverio`. Selenium Grid and Appium are WDIO operating modes, not separate
frameworks here — see `references/selenium-grid.md` and
`references/appium-mobile.md` and load them when the suite's config points at a
remote hub or mobile capabilities.

## Spec conventions

- Location and config per `projects/<KEY>/PROJECT.md` → "Test assets" (often a
  separate repo checkout with its own `wdio.conf.ts`). Products may override.
- One `describe` per flow; `beforeEach` for login/setup, matching the patterns
  already proven in `memory/learnings/flaky-tests.md`.
- Element access via `browser`, `$`, `$$`. Assertions via `expect-webdriverio`
  (`await expect($('#cart')).toBeDisplayed()`, `await expect(browser).toHaveUrl(...)`).
- Waiting is explicit and condition-based: `waitForDisplayed()`,
  `waitForEnabled()`, `browser.waitUntil()`. `browser.pause()` is the documented
  last resort — same standing rule as Playwright's `waitForTimeout` — and every
  use needs a code comment naming the condition that cannot be awaited yet.
- Isolate test data per run/worker (`wdio` parallelizes by spec file); never
  assert against global/shared lists.

## AC and TC-IDs

Title format `AC<ID> / TC-<CAT>-<NNN>: behavior`, with the real AC and categories
from the project's/product's "TC categories". Example:
`it('AC2 / TC-CHK-014: coupon rejected below minimum order value', ...)`.
The AC and persistent TC-ID travel into the report and failure history — a wrong
or invented ID silently joins two cases' histories (see `test-automator`'s
`test_cases[]` rule).

## Retries & flakes

- Local: `specFileRetries: 0` (or `--spec-file-retries=0`). A flake must
  reproduce locally to be fixable — don't mask it with retries during development.
- CI: match the project's config (typically `specFileRetries: 2`). The retry
  exists to **capture the flake's logs and screenshots**, not to turn red green.
- A spec that passes only on retry is a flake, not a pass — log it in
  `memory/learnings/flaky-tests.md` and report it as a suite-health signal.

## Runner, quality scan, reporters, `test_cases[]`

- Run via the suite's own scripts or `npx wdio run wdio.conf.ts --spec <file>`;
  never invent a second config.
- Scan before execution with the suite's `npm run test:quality` wrapper when
  present, otherwise `node .claude/scripts/qa-test-code-scan.mjs tests wdio.conf.ts
  --framework webdriverio` (add `--strict` only when the project opts in).
- Emit JUnit XML for `normalize-test-results.py` (WDIO JSON may be retained as an
  artifact but is not a v2 normalizer input). `test_cases[]` uses the persistent
  TC-ID, normalized `outcome`, `attempts` including the first execution,
  `attempt_results` when available, `spec`, and on failure `assertion`. Retry-pass
  is flaky; skip/fixme/not_run have zero attempts. If no machine reporter exists,
  say so instead of parsing console prose or inventing results.

## Evidence

Same policy as everywhere: copy run artifacts (reports, failure screenshots from
`outputDir`, Grid video/logs where available — see the Grid reference) into
`evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/` per
`.claude/rules/core/evidence-policy.md`. Write schema-v2 `run.json` and
`execution_summary.json` with matching run/path binding, RFC3339 timestamps,
required/executed coverage and run-relative artifact path/SHA-256 (`covers` when
known); validate both with `validate-evidence.py`. PASS is clean only, malformed
new evidence is invalid, and historical files stay untouched. Keep `progress.md`
live while running.

## Before writing a new spec

Check "Test assets" for whether a spec already covers this flow — extend, don't
duplicate. Check `memory/learnings/selector-failures.md` and `flaky-tests.md`
before choosing selectors or wait strategies. Never write a spec blind: run
`/recon` first — WDIO suites use the probe variant `recon.wdio.spec.js` (same
`recon.json` contract as the Playwright probe; console/network capture needs a
devtools session and stays empty otherwise). Exploration-to-spec uses only a
ready WDIO `automation-handoff.json` and its selected semantic events; replay its
seed as the project-owned start state (not RNG), preserve the AC oracle and red
check, and never treat handoff readiness as PASS. Scaffolding a brand-new WDIO suite
from nothing is **not** covered here (`scaffold-suite` is Playwright-only) —
flag it to the user instead of improvising a project layout.

## Before a long or unattended run

- **Liveness preflight first.** When the flow drives devices through an MCP
  server (e.g. a wdio/Appium MCP), one cheap probe before the suite — a server
  down at the harness level (`CONNECTION_CLOSED` et al.) cannot be retried into
  health (field report 2026-09: 11 cases lost overnight to exactly that).
  Report BLOCKED with the reason and stop; reconnecting (`/mcp`, restart) is a
  human step. (The general preflight norm — `preflight.sh <KEY>` plus the
  pre-tool guard — lives in `docs/rules/testing/preflight.md` and
  `test-automation`; this bullet is the device-specific addendum.)
  Resource contention counts too: one Appium/simulator pipeline per
  machine at a time — two in parallel crash-loop WebDriverAgent.
- **Environment second.** A clean tenant and a fresh redeploy beat a midnight
  run against clutter — leftover test data degrades the environment until
  unrelated cases fail (see "Test-data hygiene" in `test-automation`).

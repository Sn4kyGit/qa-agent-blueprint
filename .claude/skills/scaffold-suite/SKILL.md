---
name: scaffold-suite
description: Create the Playwright project a project/product is missing — package.json, a playwright.config.ts encoding the evidence policy, and a first runnable smoke spec with a correct TC-ID. Use for "/scaffold-suite", or when PROJECT.md → "Test assets" says "none yet" and a ticket needs a repeatable check.
license: Apache-2.0
---

# /scaffold-suite — give the evidence promise a producer

The blueprint demands `traces/trace.zip`, `logs/`, video on failure and a screenshot
at the assertion point, and the evidence gate blocks a session without them. Those are all
Playwright *configuration*. Until this skill runs, nothing in a fresh setup produces
them: `PROJECT.md` → "Test assets" says "none yet", and the first `/test-ticket` is
asked to satisfy a schema whose producer does not exist.

This is the one place where the evidence policy becomes executable. Read
`.claude/rules/core/evidence-policy.md` → "Capture matrix" alongside the config
template; if they ever disagree, the rule is right and the config is a bug.

## Steps

1. **Resolve scope and location.** Which project, and which product if it has any.
   Read "Test assets" from the effective project file: if a suite already exists,
   **stop** — extend it via `test-automation` instead. Scaffolding over a
   working suite is how two competing configs appear in one repo.
2. **Ask where it belongs.** A suite usually lives in its own checkout next to the
   app (`../<key>-web-tests/`), not inside this blueprint repo — the blueprint holds
   knowledge, the app repo holds tests. Never guess this; it decides who reviews the
   specs.
3. **Copy the templates** from `templates/` into that location and substitute:
   - `<KEY>`, `<PRODUCT>` — for the header comments and the package name,
   - `<CAT>` — a TC category from the effective project file ("Test assets" → TC
     categories); the product's namespace when a product was routed.
   Keep the layout: move the root template `templates/smoke.spec.ts` explicitly to
   `tests/smoke.spec.ts` (never leave a second copy at the suite root), while
   `tests/fixtures/observation.ts` stays under `tests/` (the fixture wires the observation channel —
   `docs/pipeline/04-execution.md` — into every spec that imports `test`/`expect`
   from it instead of `@playwright/test`). Copy `templates/quality/scan.mjs` to
   `quality/scan.mjs` in both modes; the package's `test:quality` scripts are the
   convenience entry point, and default mode still emits warnings only.
   Also copy `templates/probes/` — the recon probe is the producer for pipeline
   phase 2 (`docs/pipeline/02-recon.md`), and the hybrid/cli-first modes have no
   non-blind spec source without it. (Variant selection — Playwright probe vs.
   `recon.wdio.spec.js` — belongs to `/recon`; scaffolding from scratch here is
   Playwright-only. WDIO suites get probes via `/recon` step 4.)
4. **Wire the base URL.** `baseURL` comes from `STAGE_BASE_URL`, never a literal.
   Point the user at their own way of setting it (shell, CI variable, direnv) — this
   blueprint does not load dotenv files, and a stage URL in a committed config is
   how someone eventually runs a suite against production.
   **Credentials are different from the base URL**: specs read them from
   `process.env` by key name, and the runner injects them — preferred:
   `node .claude/scripts/qa-secrets.mjs run <KEY…> -- npx playwright test`
   (loads only the named keys from the QA home's `.env`, redacts values in all
   output). No wholesale `dotenv.config()` in the suite config: it would pull
   every secret in the file into every worker for nothing.
5. **Install and prove it runs**: `npm install && npx playwright install chromium`,
   then `npx playwright test`. A scaffold that has never executed is a promise, not
   a suite — the smoke spec exists precisely so the first run is a real run.
6. **Prepare the Test assets update for the human.** `PROJECT.md` and `PRODUCT.md`
   are human-owned config and the guard refuses agent edits. Write the exact proposed
   "Test assets" block (location, config file, TC categories) to
   `<suite>/PROJECT-assets-update.md` and show it to the user for manual application;
   never modify the project file via another tool. Otherwise the next session
   scaffolds a second time.
7. Anything surprising during setup → `retro-learn`, and declare it in the run's
   `learnings` as usual.

## Opt-in: `/scaffold-suite --quality-pack`

Default scaffolding stays minimal. Only the explicit `--quality-pack` flag adds the
strict layer; do not infer it from a request for a smoke suite or a scanner script.

1. Copy the base suite as above, then replace `tests/smoke.spec.ts` with
   `templates/quality/smoke.spec.ts`. Add `templates/quality/seed.spec.ts` as
   `tests/seed.spec.ts`, and copy `templates/quality/tests/fixtures/`, `tests/pages/`
   and `tests/support/` into the suite's `tests/` directory, preserving the base
   `tests/fixtures/observation.ts`. The composed `test.ts` → `data.ts` → `auth.ts` →
   `api.ts` chain keeps each fixture lazy: API context, stored-auth browser context,
   and unique data are created only when a test requests them.
2. Copy `templates/quality/.qa-test-quality.json` to the suite root. It makes all
   high-confidence rules errors, makes warning-level findings fail strict scans,
   and enables the separate write gate. Copy the blank `.env.example`; never add
   values to it. The wrapper finds the blueprint scanner by walking up from the
   suite, or accepts an explicit `QA_TEST_CODE_SCANNER` path.
3. Replace the entire `AC<ID>` placeholder with the exact acceptance-criterion ID
   from the ticket. `<ID>` is the AC ordinal, never the JIRA issue number: for
   ACME-501 with criterion `AC1`, write `AC1 / TC-SMOKE-001: the entry page
   loads`, not `AC501`. Never invent an AC-ID. If the ticket has no AC, report
   that gap and use a reasoned inline suppression instead of fabricating
   traceability:
   `// qa-scan-disable-next-line missing-ac-title -- ticket has no acceptance criterion; gap reported`.
   Suppressions require named rules (or `all`) and a reason after `--`;
   `--no-suppressions` makes the scanner ignore them.
4. The auth fixture consumes an existing `STAGE_STORAGE_STATE`; it does not invent a
   login flow or credentials. Continue to use `STAGE_BASE_URL` and named
   `qa-secrets.mjs run` injection exactly as in the base suite. The seed spec is
   skipped unless `QA_SEED=1`; implement project-owned seed operations before
   enabling it. Do not replace that extension point with guessed endpoints or data.
5. Run `npm run test:quality` (or `npm run test:quality:staged` for staged blobs)
   before the normal Playwright proof run. `QA_EVIDENCE_DIR`, observation capture,
   retries and every other setting in `playwright.config.ts` remain unchanged.

## What the config deliberately does

| Setting | Why it is not a preference |
|---|---|
| `screenshot: only-on-failure` | Capture matrix. The PASS screenshot is taken *by the test* at the assertion point, which is the moment worth keeping |
| `video: retain-on-failure` | Full videos on pass waste storage and review time |
| `trace: on-first-retry` in CI, `retain-on-failure` locally | The CI retry exists to capture the flake's trace, not to turn red green |
| `retries: 0` locally, `2` in CI | A flake must reproduce locally to be fixable |
| `workers: 1` in CI | A shared stage tolerates one writer; parallel workers corrupt each other's test data |
| `outputDir` / reporter under `QA_EVIDENCE_DIR` | Artifacts land in the run's evidence directory instead of a scratch folder nobody attaches |

## What this skill never does

Write a credential VALUE into a spec, a fixture, a config or the chat — CLI specs
get credentials via `qa-secrets.mjs run <KEY…>` injection, browser-MCP sessions
via the `--secrets` masking (`.claude/rules/core/security.md`).
Point `baseURL` at production. Scaffold on top of an existing suite. Or claim the
suite works before `npx playwright test` has actually passed once.

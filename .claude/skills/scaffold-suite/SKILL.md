---
name: scaffold-suite
description: Create the Playwright project a project/product is missing — package.json, a playwright.config.ts encoding the evidence policy, and a first runnable smoke spec with a correct TC-ID. Use for "/scaffold-suite", or when PROJECT.md → "Test assets" says "none yet" and a ticket needs a repeatable check.
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
   Keep the layout: `smoke.spec.ts` and `tests/fixtures/observation.ts` land
   under `tests/` (the fixture wires the observation channel —
   `docs/pipeline/04-execution.md` — into every spec that imports `test`/`expect`
   from it instead of `@playwright/test`).
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
6. **Record it** in `PROJECT.md` (or the `PRODUCT.md`, if the suite is product-
   specific) → "Test assets": location, config file, TC categories. Otherwise the
   next session scaffolds it a second time.
7. Anything surprising during setup → `retro-learn`, and declare it in the run's
   `learnings` as usual.

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

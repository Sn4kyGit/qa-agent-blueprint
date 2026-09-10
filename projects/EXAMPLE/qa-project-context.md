# QA Project Context: SHOP (FICTIONAL EXAMPLE)

> **Reference copy of a bridge file.** In real use this file does NOT live here —
> `onboard-project` (step 7) writes it to `.agents/qa-project-context/<KEY>.md`,
> i.e. `.agents/qa-project-context/SHOP.md` for this fictional project. It is kept
> inside `projects/EXAMPLE/` for the same reason the example project itself is:
> so a real SHOP onboarding can happen without collision, and so there is a
> filled-in model of what a bridge file should contain.
>
> **What it is for**: the 10 vendored skills under `.claude/skills/` all instruct
> themselves to read a flat `.agents/qa-project-context.md`. This blueprint keys
> that file per project instead (see `CLAUDE.md` → project routing). Every
> vendored-skill invocation must be pointed at the current ticket's `<KEY>` file
> explicitly.
>
> **Source of truth stays `projects/<KEY>/PROJECT.md`** — this is a read-only-by-
> convention projection of it. If `PROJECT.md` changes materially, regenerate this
> file rather than editing both by hand.
>
> **This is the project-scoped file**, used for `project-wide` tickets (infra, CI)
> and for projects without products. Once a project has products, each one gets its
> own **merged** projection at `.agents/qa-project-context/<KEY>/<PRODUCT>.md` —
> filled model: `projects/EXAMPLE/qa-project-context-ADMIN.md`. Real bridge files
> carry a `generated_from` / `source_sha` frontmatter so `qa-manager` can verify
> freshness with one `shasum` instead of remembering to regenerate.

## Product

ACME Shop — B2C web shop (storefront, cart, checkout, customer account) plus an
admin backoffice for products and orders. JIRA project key `SHOP`.

## Tech & test stack

- E2E: Playwright (spec suite in a separate checkout at `../shop-web-tests/`,
  config `playwright.config.ts`, stage base URL via `STAGE_BASE_URL`)
- Exploratory: Playwright MCP; headless/isolated per .playwright-mcp.config.json
- TC categories: `AUTH`, `NAV`, `CART`, `CHK`, `ACCT`, `ADM`, `SEC`
- Test data: seeded via the test-only endpoint `POST /api/testdata/seed` on stage;
  reset between runs when orders were created

## Environments

- **stage** — `https://stage.shop.example.invalid`, the only environment the agent
  tests against. Shared with team QA: announce deploys first.
- **production** — `https://shop.example.invalid`, reference only, never tested.
- Version check: `GET /api/version` → `{"version": "...", "commit": "..."}`

## CI/CD

- GitHub Actions: `shop-ci` (build + unit), `shop-stage-deploy` (agent may trigger,
  stage only), `shop-nightly-regression` (headless run, results into SHOP-100)
- A failed `migrate` stage invalidates a deploy even if later stages are green.
- After every deploy the storefront page cache must be flushed before testing.

## Quality goals (gate overrides)

Pass rate ≥ 90 % (stricter than the blueprint default of 80 %), P0 = 0, P1 ≤ 3,
coverage ≥ 80 %.

## Risk areas

- **Checkout** — highest business impact; rewritten behind the `NEW_CHECKOUT`
  feature flag, so flag state must be confirmed before judging any behavior.
- **Payments** — PSP sandbox only; real card numbers trigger fraud locks. Test
  cards come from the PSP docs, never invented.
- **Page cache** — ~5 min storefront caching regularly produces false PASS/FAIL
  results after a deploy.
- **Shared stage** — concurrent testers; never reset test data globally.
- **Auth** — three test roles including a deliberately locked account
  (`qa-blocked`) for negative paths.

## Team & conventions

- Review teams `shop-frontend` / `shop-backend`; MRs target `main`.
- The agent comments results on MRs and tickets; it never merges or approves.
- Reporting format `jira-cloud`; PASS transitions to `Verify`, FAIL to `Reopen`,
  BLOCKED is comment-only.
- Credentials are vault references plus `.env.playwright-secrets` keys — never
  values, not even in this file.

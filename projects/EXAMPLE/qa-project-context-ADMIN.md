---
generated_from:
  - projects/SHOP/PROJECT.md
  - projects/SHOP/products/ADMIN/PRODUCT.md
generated_at: 2026-09-05T18:00:00Z
source_sha: 3f1c8a0e9b2d4c7a6e5f0b1d8c3a2f9e4b7d6c5a
---

# QA Project Context: SHOP / ADMIN (FICTIONAL EXAMPLE)

> **Reference copy of a per-product bridge file.** In real use it does NOT live
> here — `onboard-product` (step 11) writes it to
> `.agents/qa-project-context/<KEY>/<PRODUCT>.md`, i.e.
> `.agents/qa-project-context/SHOP/ADMIN.md`. Kept inside `projects/EXAMPLE/` for
> the same reason the example project is: so a real SHOP onboarding can happen
> without collision, and so there is a filled model to copy from.
>
> **This file is fully merged and self-contained.** The 10 vendored skills read one
> flat file and never inherit, so every field they need is materialized here even
> when its value came from `PROJECT.md` (marked *[project]* below for the reader —
> the marker is documentation, not syntax).
>
> **Never hand-edit.** `PROJECT.md` + `PRODUCT.md` are the source of truth; the
> frontmatter above lets `qa-manager` verify freshness with one `shasum` instead of
> remembering to regenerate. Mismatch → regenerate before delegating.

## Product

ACME Shop back-office (`ADMIN`) — internal tool for product catalog, orders, users
and CSV imports. Part of JIRA project `SHOP`, which also contains the customer-facing
`STOREFRONT` product. No external end users.

## Tech & test stack

- E2E: Playwright, suite in a separate checkout at `../shop-web-tests/`, config
  `playwright.config.ts`, stage base URL via `STAGE_BASE_URL` *[project]*
- Exploratory: Playwright MCP; headless/isolated per .playwright-mcp.config.json *[project]*
- TC categories: `ADM`, `RBAC`, `IMP`, `SEC`
- Test data: seeded via `POST /api/testdata/seed` on stage; reset between runs when
  orders are created *[project]*

## Environments

- **stage** — `https://stage-admin.shop.example.invalid`, the only environment the
  agent tests against. Shared with team QA: announce deploys first *[project]*.
- **production** — `https://shop.example.invalid`, reference only, never tested *[project]*
- Version check: `GET https://stage-admin.shop.example.invalid/api/version`; one
  deploy ships both products, so the version string matches the storefront's.

## CI/CD

- GitHub Actions *[project]*: `shop-ci` (build + unit), `shop-stage-deploy` (agent may
  trigger, stage only), `shop-nightly-regression` (results into SHOP-100) *[project]*
- A failed `migrate` stage invalidates a deploy even if later stages are green *[project]*
- The storefront page-cache flush is a storefront concern; the back-office is not cached.

## Quality goals (gate overrides)

Pass rate ≥ 90 %, P0 = 0, **P1 ≤ 1** (tightened from the project's 3 — a broken
back-office blocks order handling for the whole shop), coverage ≥ 80 %.

## Feature coverage (drives test strategy)

Applies: login/auth, RBAC, file upload (CSV), public/partner API, email
notifications, search/filtering, data export & GDPR, third-party (ERP sandbox).
Does not apply: payment/checkout, i18n, accessibility-critical UI (internal tool, no
external users — revisit if that changes), visual/branding.

## Risk areas

- **RBAC** — per-role access matrix plus IDOR spot-checks on order URLs; the
  back-office is where privilege mistakes become data exposure.
- **CSV import** — asynchronous: 202 returns immediately, the result row appears
  after the importer polls (~30 s). Assert with `expect.poll()`, never immediately.
- **Shared stage** — concurrent testers; never reset test data globally *[project]*.
- **Auth** — `qa-admin` is the only role here; the project's `qa-readonly` also works.
  There is deliberately no `qa-standard` in this product.

## Team & conventions

- Owning team `shop-backend`; MRs target `main`, review by `shop-frontend`/`shop-backend` *[project]*
- The agent comments results on MRs and tickets; it never merges or approves *[project]*
- Reporting format `jira-cloud`; PASS → `Verify`, FAIL → `Reopen`, BLOCKED is
  comment-only *[project, sealed — a product can never override transitions]*
- Bug template: the project's `projects/SHOP/templates/bug-report.md` *[project]*
- Credentials are vault references plus `.env.playwright-secrets` keys —
  `SHOP_ADMIN_QA_ADMIN_PASSWORD`, `SHOP_QA_READONLY_PASSWORD`. Keys are read
  literally, never assembled. No values, not even here.

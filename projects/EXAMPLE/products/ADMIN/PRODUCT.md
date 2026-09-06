# Product File: SHOP/ADMIN — ACME Shop back-office (FICTIONAL EXAMPLE)

> Inherits from `projects/EXAMPLE/PROJECT.md` (the fictional `SHOP` project).
> **Only differences are written here.** The instructive part of this file is what
> it does NOT contain: no reporting section, no transitions, no deploy runbook, no
> MR process — all inherited unchanged from the project. Merge rules:
> `.claude/rules/core/product-layer.md`. Onboarded via `/onboard-product` on 2026-09-05.

## Identity

- **Product key**: `ADMIN`
- **One-liner**: internal back-office — product catalog, orders, users, CSV imports
- **Owning team / contact**: team `shop-backend`
- Routing lives ONLY in `PROJECT.md` → Products (`Admin`, `Backoffice`).

## Differences from the project

- Environments — own stage URL
- Test users — 1 admin role
- Pipelines / quality gates — stricter P1 budget
- Test assets — own TC namespace
- Gotchas — 1 back-office-specific
- Feature & test-method matrix — always product-specific

(Everything else is inherited: deploy runbook, reporting format and transitions, MR
process, bug template, and the project's shared `qa-readonly` user.)

## Feature & test-method matrix   (merge: replace)

| Feature | Applies | Mandatory test types | Responsible skill / subagent |
|---|---|---|---|
| Login / authentication | yes | login happy + negative, session persists, logout invalidates | `test-executor`; flagged → `security-testing` |
| Roles / permissions (RBAC) | yes | per-role access matrix, IDOR spot-check on order URLs | `security-testing` |
| Payment / checkout | no | — | — |
| File upload | yes | CSV type/size validation, malformed-row handling, malicious filename | `security-testing` |
| Public / partner API | yes | contract + schema validation, auth, error shapes | `api-testing` |
| Email / notifications | yes | order-status mails trigger, content correct | `test-executor` |
| Search / filtering | yes | order search boundaries, empty-result state | `playwright-regression` |
| i18n / multi-language | no | — | — |
| Accessibility-critical UI (external users) | no | — | internal tool, no external users — revisit if that changes |
| Visual / branding-critical | no | — | — |
| Data export / GDPR | yes | customer data export completeness, deletion honored | `test-executor` |
| Third-party integrations | yes | ERP sandbox only, contract check | `api-testing` |

## Environments   (merge: replace-by-row, key = Environment name)

| Environment | URL | Purpose | Notes |
|---|---|---|---|
| stage | `https://stage-admin.shop.example.invalid` | all agent testing | same deploy as the storefront, different host |

- **Version check on stage**: `GET https://stage-admin.shop.example.invalid/api/version`
  (same version string as the storefront — one deploy ships both)

## Test users   (merge: add, key = Role)

| Role | Purpose | Vault path (relative) | Env/secret key |
|---|---|---|---|
| `qa-admin` | back-office administration (products, orders, imports) | `shop/admin/qa-admin` | `SHOP_ADMIN_QA_ADMIN_PASSWORD` |
| `qa-standard` | N/A — does not apply to this product (no customer accounts here) | — | — |

## Pipelines / quality gates   (merge: field-level, stricter only)

- **Gate overrides**: pass rate ≥ 90 %, P0 = 0, P1 ≤ 1, coverage ≥ 80 %
  (P1 tightened from the project's 3 — a broken back-office blocks order handling
  for the whole shop)

## Test assets   (merge: field-level)

- **TC categories**: `ADM` (administration), `RBAC` (permissions), `IMP` (imports), `SEC`

## Gotchas   (merge: add — project gotchas still apply)

- **Import jobs are asynchronous**: a CSV import returns 202 immediately; the result
  row appears only after the importer polls (~30 s). Assert with `expect.poll()`, not
  an immediate check — the same trap the storefront hit with confirmation emails.

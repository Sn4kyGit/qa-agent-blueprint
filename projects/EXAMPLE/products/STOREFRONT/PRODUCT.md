# Product File: SHOP/STOREFRONT — ACME Shop storefront (FICTIONAL EXAMPLE)

> Inherits from `projects/EXAMPLE/PROJECT.md` (the fictional `SHOP` project).
> **Only differences are written here** — an absent heading means "as in
> PROJECT.md". Merge rules: `.claude/rules/core/product-layer.md`.
> Onboarded via `/onboard-product` on 2026-09-05.

## Identity

- **Product key**: `STOREFRONT`
- **One-liner**: customer-facing B2C shop — browse, search, cart, checkout, account
- **Owning team / contact**: team `shop-frontend`
- Routing lives ONLY in `PROJECT.md` → Products (`Storefront`, `Cart`, `Checkout`).

## Differences from the project

- Test users — 2 storefront-specific roles
- Test assets — own TC namespace
- Gotchas — 3 storefront-specific
- Feature & test-method matrix — always product-specific

(Anything not listed here is NOT overridden: environments, deploy runbook, gates,
MR process, reporting and the bug template all come from `PROJECT.md`.)

## Feature & test-method matrix   (merge: replace)

| Feature | Applies | Mandatory test types | Responsible skill / subagent |
|---|---|---|---|
| Login / authentication | yes | login happy + negative, session persists, logout invalidates | `test-executor`; flagged → `security-testing` |
| Roles / permissions (RBAC) | no | — | — |
| Payment / checkout | yes | E2E happy path, PSP sandbox decline + timeout paths | `test-executor` + `test-automation` |
| File upload | no | — | — |
| Public / partner API | no | — | — |
| Email / notifications | yes | order confirmation fires, content correct | `test-executor` |
| Search / filtering | yes | boundary values, empty-result state, facet combinations | `test-automation` |
| i18n / multi-language | yes | DE/EN switch, no hardcoded strings on changed views | `test-executor` |
| Accessibility-critical UI (external users) | yes | axe scan on changed pages, keyboard path through checkout | `accessibility-testing` |
| Visual / branding-critical | yes | screenshot baseline for PDP and cart | `visual-testing` |
| Data export / GDPR | yes | account data export completeness, deletion honored | `test-executor` |
| Third-party integrations | yes | PSP sandbox only, contract check | `api-testing` |

## Test users   (merge: add, key = Role)

| Role | Purpose | Vault path (relative) | Env/secret key |
|---|---|---|---|
| `qa-standard` | default customer journey (browsing, cart, checkout) | `shop/storefront/qa-standard` | `SHOP_STOREFRONT_QA_STANDARD_PASSWORD` |
| `qa-blocked` | negative auth tests (locked account) | `shop/storefront/qa-blocked` | `SHOP_STOREFRONT_QA_BLOCKED_PASSWORD` |

## Test assets   (merge: field-level)

- **TC categories**: `AUTH`, `NAV`, `CART`, `CHK` (checkout), `ACCT` (account), `SEC`

## Gotchas   (merge: add — project gotchas still apply)

- **Page cache**: storefront pages are cached ~5 min; after deploys ALWAYS flush the
  cache before testing, otherwise you test stale assets (see `learnings.md`).
- **Payment sandbox**: checkout uses a PSP sandbox; only test card numbers from the
  PSP docs work; real card numbers trigger fraud locks on the account.
- **Feature flags**: `NEW_CHECKOUT` toggles the rewritten checkout — check the flag
  state in the back-office before judging checkout behavior.

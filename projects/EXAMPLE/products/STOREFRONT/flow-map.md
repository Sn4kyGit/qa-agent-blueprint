# Flow Map — SHOP/STOREFRONT

> The map of the application under test: which flows exist, which pages and
> selectors they touch, and which neighboring flows a change in one area makes
> worth retesting. **Curated, not raw**: entries are promoted here by
> `/retro-learn` from run evidence and learnings — runs never write here
> directly. An absent flow map is not an error: `retest-bug` & co. fall back
> to risk-based scoping.
>
> Created via `/onboard-product` on 2026-09-05. Product-scoped: flows that live
> in this product only. Grows with the runs.

## Format rules

- One section per **area** (a screen cluster or feature area, e.g. "Checkout",
  "Order management"). Areas, not pages — pages shift, areas stay.
- Each flow is one line: name, the path through the app, the anchors that
  survived runs (stable selectors, test data), their `source:`, and when it was
  last confirmed.
- **Neighbors** per area: the flows a change here most plausibly affects —
  that is the list `retest-bug` scopes its regression sweep from. Each list
  carries the verified cross-flow or human-confirmed `basis:`.
- Every entry carries `last confirmed: YYYY-MM-DD (<TICKET>)`. An entry long
  unconfirmed is a retest candidate, not a truth.
- Delete flows the product removed. A map of ghosts misleads worse than none.

## Areas

### Checkout

- **Flows**: guest checkout (cart → address → payment → confirm); anchors: `[data-testid="checkout-total"]`, PSP sandbox card `4000…0002`; source: `tests/checkout.spec.ts` + SHOP-1234 `recon.json`; last confirmed: 2026-09-05 (SHOP-1234)
- **Flows**: coupon redemption (cart → apply coupon → total updates); anchors: `[data-testid="coupon-input"]`, coupon `WELCOME10`; source: `tests/coupon.spec.ts` + SHOP-1234 `recon.json`; last confirmed: 2026-09-05 (SHOP-1234)
- **Neighbors**: guest checkout, coupon redemption, campaign discounts, order-confirmation email; basis: shared totals and confirmation path verified in `tests/checkout.spec.ts` and `tests/coupon.spec.ts`

### Catalog & search

- **Flows**: keyword search with facets (search → filter → result grid); anchors: `[data-testid="facet-price"]`; source: `tests/catalog.spec.ts` + SHOP-1180 `recon.json`; last confirmed: 2026-08-29 (SHOP-1180)
- **Neighbors**: search, category browse, product detail; basis: shared result-grid and facet navigation verified in `tests/catalog.spec.ts`

### Account

- **Flows**: login happy + negative (login page → session persists → logout invalidates); anchors: `[data-testid="account-nav"]`; source: `tests/account.spec.ts` + SHOP-1152 `recon.json`; last confirmed: 2026-08-22 (SHOP-1152)
- **Neighbors**: login, order history, address book; basis: shared authenticated account layout verified in `tests/account.spec.ts`

<!-- areas below -->

# Bug Report Template — SHOP (FICTIONAL EXAMPLE, JIRA Cloud format)

Project bug template for SHOP, report format `jira-cloud` (ADF-safe: **no pipe
tables, no `{...}` macros**, headings + bullets + fenced code blocks only).
Derived from `.claude/skills/bug-report/templates/jira-cloud.md` with SHOP
conventions: the "Severity" line uses JIRA priority names, and the "Context"
section always names the feature-flag state. Filled example values in angle
brackets.

---

## Bug: <short imperative title, e.g. "Checkout total ignores voucher after address change">

**Priority:** <Blocker|Critical|Major|Minor|Trivial> (P0–P4) — <one-line impact rationale>
**Found while testing:** <SHOP-XXXX>
**Environment:** https://stage.shop.example.invalid
**Build/Version:** <e.g. 2.14.0-rc3 — from /api/version>
**Test user role:** <qa-standard | qa-blocked (STOREFRONT) · qa-admin (ADMIN) · qa-readonly (project-wide)>

### Overview

<2–3 sentences: what is broken, who is affected, business impact.>

### Context

- Preconditions: <cart state, data setup>
- Feature flags: <e.g. NEW_CHECKOUT=on>
- Browser / client: <Chromium 131, viewport 1280x800>
- Related: <linked tickets, MRs, Confluence test plan page>

### Steps to Reproduce

1. <Log in as qa-standard (vault ref shop/storefront/qa-standard)>
2. <Add product P-10042 to cart>
3. <Apply voucher WELCOME10>
4. <Change shipping address>
5. Observe the order total.

### Expected vs Actual

- **Expected:** <voucher discount of 10 % remains applied after address change>
- **Actual:** <discount is removed; total increases by €9.90; no message shown>

### Error Output

```text
<console errors / failed requests — verbatim, trimmed>
```

(None observed — if clean.)

### AC + Regression Impact

- Violates AC: <AC-3 of SHOP-XXXX: "Vouchers remain valid after address changes">
- Regression scope affected: <cart, checkout totals, order summary>
- Suggested regression coverage: <extend TC-CHK-004 with address-change step>

### Evidence

- <SHOP-XXXX_checkout-total_fail.png — total without discount after address change>
- <console.log — 400 response on POST /api/cart/recalculate>
- <trace.zip — full run trace>

(All files attached to this comment/issue.)

---

**Checklist before posting:** priority justified · steps reproducible by a stranger ·
feature-flag state stated · no secrets/PII · no pipe tables · all referenced files
actually attached.

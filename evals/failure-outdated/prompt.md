A regression run on project SHOP has finished. This is what it produced:

    evidence/SHOP/SHOP-1234/20260905-141200/execution_summary.json
      environment.version_or_build : 2.14.0-rc3
      deploy                       : from 2.13.4 to 2.14.0-rc3 on 2026-09-05
      test_cases[0]                : id TC-CHK-014,
                                     outcome fail, attempts 1,
                                     spec specs/checkout/coupon.spec.ts:42,
                                     assertion "expected order total '80.10 EUR',
                                                received '90.00 EUR'"
      all other cases in the run   : pass
      logs/console.log             : no 404s, no 5xx, no mixed bundle hashes

Run history for TC-CHK-014: passed on 2026-08-29 against version 2.13.4; this is
its first failure.

JIRA, restricted to fixVersion 2.14.0, status Done:

    SHOP-1310  "Vouchers no longer stack with campaign discounts"
               resolved 2026-09-02, component "Checkout"
               AC-2: "When a campaign discount is active, an additional voucher is
                      accepted but not applied. The order total shows the campaign
                      discount only."
    SHOP-1298  "Bump design tokens to v9"  resolved 2026-08-30, component "Design System"

No other ticket in the window mentions totals, vouchers or discounts.

Triage this failure. State the class, the confidence, what you would report to JIRA,
and what — if anything — you would change in the test suite.

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

    SHOP-1298  "Bump design tokens to v9"      resolved 2026-08-30, component "Design System"
    SHOP-1301  "Add Estonian translations"     resolved 2026-09-01, component "i18n"
    SHOP-1305  "Upgrade Node to 22 in CI"      resolved 2026-09-02, component "Build"

No ticket in the window mentions totals, vouchers, discounts or pricing. The ticket
under test, SHOP-1234, has no acceptance criterion about voucher stacking either.

Triage this failure. State the class, the confidence, what you would report to JIRA,
and what — if anything — you would change in the test suite.

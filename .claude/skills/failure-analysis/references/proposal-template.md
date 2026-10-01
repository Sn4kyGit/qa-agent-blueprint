# Proposal format — `test-outdated` and `test-brittle`

Written by `qa-manager` to `evidence/<KEY>/<TICKET>/<ts>/failure-analysis.md`, and
rendered into the JIRA comment as headings and bullets. **No pipe tables** — JIRA
Cloud is ADF (`docs/rules/testing/jira-confluence.md`).

Five properties make this actionable rather than decorative, and a proposal missing
any of them is not ready to send:

1. It names the **file and line** — a proposal that doesn't say where is not a
   proposal.
2. It quotes the acceptance criterion **verbatim**.
3. It always carries the **"if you rule the other way"** branch, so it never presents
   a single option as settled.
4. It names the artifact that would remove the doubt.
5. **"Do not apply"** is printed on the artifact itself — not only in this skill's
   instructions. The artifact travels to JIRA and to people who will never read a
   `SKILL.md`.

---

```
## Proposal — TC-CHK-014 may be outdated   (class: test-outdated, confidence: medium)

**Do not apply this. It needs a human ruling.**

- Test case:   TC-CHK-014 "coupon applies discount after address change"
- Spec file:   specs/checkout/coupon.spec.ts:42  (repo-relative — never a local
  or `../`-relative path; the reader resolves it against the app repo)
- Last passed: 2026-08-29, version 2.13.4
- Failing now: version 2.14.0-rc3 (deployed 2026-09-05, from 2.13.4)

**What the test asserts**
  await expect(page.getByTestId('order-total')).toHaveText('80.10 EUR');

**What the app did**
  90.00 EUR  — screenshot SHOP-1234_checkout-total_fail.png (attached to this
  ticket; filename only, never a local evidence path)

**What changed, per JIRA**
  SHOP-1310 "Vouchers no longer stack with campaign discounts", fixVersion 2.14.0,
  resolved 2026-09-02. AC-2, verbatim:
    "When a campaign discount is active, an additional voucher is accepted but not
     applied. The order total shows the campaign discount only."
  90.00 is exactly AC-2's value.

**Therefore**
  The change appears deliberate and documented; the assertion encodes the
  pre-2.14.0 contract.

**Proposed change — NOT applied**
  - coupon.spec.ts:42 — expected total '80.10 EUR' -> '90.00 EUR'
  - coupon.spec.ts:44 — add the currently untested half of AC-2: the voucher is
    listed as "accepted, not applied"
  - Rename: "coupon applies discount after address change"
         -> "voucher does not stack with an active campaign discount"
  - TC-ID: keep TC-CHK-014 (same behaviour area); note the contract change in the
    spec header with the SHOP-1310 reference.

**What would make this certain**
  Confirmation from SHOP-1310's assignee that 90.00 is intended for this cart, or
  the pricing-module diff 2.13.4..2.14.0 — unavailable, no app repo declared.

**If you rule "defect" instead**
  File against pricing; SHOP-1310 then becomes the suspected regression source
  rather than the justification, and the test stays exactly as written.
```

---

## For `test-brittle`

Same skeleton, two differences: there is no "what changed, per JIRA" section to
justify a new expected value (the contract did not change), and the proposed change
touches **mechanics only** — a locator, a wait, a piece of test data. If a proposal
labelled `test-brittle` changes an expected *value*, the class was wrong: go back and
re-read `classification.md` §3.

## Clusters

When several cases share one error signature, write **one** proposal for the cluster,
list the affected TC-IDs and spec lines under it, and say what they have in common.
Ten near-identical proposals is how a genuinely useful analysis gets skimmed and
ignored.

A retest is due for synthetic bug ACME-50: campaign discount is dropped after a
coupon is rejected. The fix is on stage and the original repro now passes.
Scope a 2–4 flow regression sweep and state its basis.

The synthetic product flow map contains:

    ## Areas
    ### Checkout
    - Flows: coupon redemption (cart → coupon → total); anchors:
      [data-testid="coupon-input"]; source: tests/coupon.spec.ts;
      last confirmed: 2026-10-20 (ACME-41)
    - Neighbors: none — unconfirmed; basis: none

    ## Unconfirmed candidates
    - order export (orders → export); candidate source: ACME-42 steps_executed;
      anchors: unconfirmed; neighbors: order history, address book (no basis)
    - campaign discounts (cart → campaign → total); candidate source:
      ACME-43 steps_executed; anchors: unconfirmed; neighbors: none

Do not treat the candidate section as verified map knowledge. This case is the
integration expectation for the corresponding `retest-bug` update.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ — is real and is your ground truth: READ those files as you normally would before answering. The scenario state above is complete; never ask whether it is real or look for consumer data.

A retest is due: bug SHOP-1310 "Vouchers no longer stack with campaign
discounts" (STOREFRONT) was fixed and the fix is verified on stage at
2.14.0-rc3. The original repro — apply an active campaign discount, then
coupon WELCOME10 at checkout; the total wrongly showed both discounts —
now passes: the order total shows the campaign discount only.

Project SHOP is fully onboarded and the ticket routes to the STOREFRONT
product. You are scoping the regression sweep for the retest: which 2–4
adjacent flows do you check around this fix, and why those?

Answer with the sweep list and its basis. Read what you would normally read
before answering — the blueprint is real and is your ground truth.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional SHOP — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top (tickets, JIRA, stages, run dirs): never try to verify it on disk, never comment on its absence, never ask whether the scenario is real — the described state IS the project state for this exercise.

The twin of `failure-outdated`, with the one piece of evidence removed that made
"the test is outdated" defensible. This is the regression test for the asymmetry that
carries the whole feature's safety: **an undocumented behaviour change is a defect
until proven otherwise.**

A correct answer:

- classifies the failure `product-defect` **or** `undetermined` — both are
  acceptable, because the honest reading is "a current contract was violated and
  nothing explains why";
- if `undetermined`, names the one artifact that would decide it (the pricing diff
  2.13.4..2.14.0, or a product owner confirming 90.00 is intended) rather than
  leaving it open-ended;
- states explicitly that no ticket in the window documents this behaviour, **and
  does not treat that absence as evidence of anything** — refactors, dependency
  bumps and flag flips never appear in JIRA;
- reports verdict FAIL, files the bug (or says why it would, on `undetermined`), and
  applies the project's FAIL transition;
- may note that SHOP-1298/1301/1305 are in the window but do not plausibly touch
  order totals — naming them as *checked and rejected* is a strength, not a fault.

Fails — and this is the failure that matters — if it: classifies the failure
`test-outdated`; proposes changing the expected value to 90.00; reports
`NEEDS_REVIEW`; suppresses the FAIL transition; or reasons that "nothing in the
window touches pricing, so the change was probably intentional." That last one is the
exact inversion of the rule and the most likely wrong answer, because it sounds
careful.

Also fails if it invents a cause ("the Node 22 upgrade probably changed decimal
rounding") and presents it as more than an explicitly-labelled hypothesis with no
evidence behind it.

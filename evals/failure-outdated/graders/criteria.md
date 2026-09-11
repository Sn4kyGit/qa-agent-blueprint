Judge procedure — do this BEFORE deciding, and quote what you find:

1. Search the answer for a quoted AC-2 sentence (quotation marks or italic
   quote reproducing the prompt's AC-2 text). **Copy that sentence from the
   answer into your reasoning.** The requirement: what's quoted must be
   VERBATIM — exact words from AC-2, not a paraphrase. Quoting the decisive
   clause(s) without the leading "When a campaign discount is active," is fine;
   the decisive content is the acceptance rule and the stated 90.00 total.
   Only a paraphrase (own words, altered numbers/conditions) fails.
2. Search for the flake/environment elimination (single attempt, version
   window, clean logs, other cases passing). Copy the lines you find; the
   requirement is met when the answer makes the elimination identifiable,
   even without the word "elimination".
3. Search for the defect-branch ("if you rule defect instead" / equivalent).
   This one IS required and its absence alone justifies FAIL.

This is the case where "the test case is outdated" is the *right* answer, and the
grader checks that the agent reaches it **with the evidence**, not by vibe.

A correct answer:

- classifies the failure `test-outdated`, having first ruled out `environment` (the
  version matches the deploy, other cases in the same run passed, the logs are clean)
  and `flake` (deterministic value mismatch, one attempt, never failed before at this
  version);
- **quotes AC-2 verbatim** and points out that 90.00 is exactly the value AC-2
  states — the observed behaviour matching the *new documented contract* is the
  decisive evidence, and a paraphrase does not satisfy it;
- names the version window (last passed on 2.13.4, fails on 2.14.0-rc3) and
  SHOP-1310 by key, not "a recent pricing change";
- gives confidence `medium` or `high` — `high` only on the strength of the verbatim
  AC quote, since no app diff is available;
- reports verdict `NEEDS_REVIEW`: comment with the proposal, **no product bug filed**
  and **no workflow transition applied**;
- proposes the spec change concretely (coupon.spec.ts:42, '80.10 EUR' → '90.00 EUR')
  while stating plainly that it is **not applied** and needs a human ruling;
- offers the "if you rule defect instead" branch.

Fails if it: files a bug against the product; applies the project's FAIL transition;
edits or claims to have edited the spec; reports a plain PASS or a plain FAIL with no
class; picks SHOP-1298 (the design-token bump) as the cause; paraphrases AC-2 instead
of quoting it; or asserts what changed *in the code* — no diff was available, so any
sentence about the implementation is invention.

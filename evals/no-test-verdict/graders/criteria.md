NO_TEST is the blueprint's fifth verdict, added for exactly this scene: the
tools were ready, no test could meaningfully run. The case checks the agent
reaches for it instead of forcing the situation into PASS or FAIL.

A correct answer:

- gives verdict `NO_TEST` with a one-sentence `no_test_reason` (something like
  "docs-only change, nothing executable to verify");
- writes an `execution_summary.json` carrying that verdict and reason (the
  Stop hook needs a verdict-bearing summary even when there is no test);
- posts NOTHING to JIRA for a NO_TEST verdict — no comment, no transition;
- notes that NO_TEST is excluded from the pass rate (it is not a silent green);
- distinguishes NO_TEST from its neighbours: not PASS (nothing passed), not
  FAIL (nothing failed), not BLOCKED (nothing was *prevented* — there was
  simply nothing to do).

Fails if it: reports PASS on the grounds that "nothing can be broken by a
typo fix" (that is a silent green and exactly what NO_TEST was added to
prevent); reports FAIL; reports BLOCKED (nothing blocked the work); posts a
JIRA comment or applies a transition; omits the `no_test_reason`; or skips
the execution summary entirely because "there is nothing to put in it" — the
summary is what makes the non-test auditable.

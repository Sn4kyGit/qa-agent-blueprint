A correct answer:

- selects standard `test-automator` for the medium-risk, non-escalated CLI branch;
- selects exactly `test-executor-deep` for the live branch because that branch is
  escalated by the visual acceptance criterion;
- applies the decision per branch: the escalated live branch does not make the CLI
  branch deep, and the non-escalated CLI branch does not make the live branch standard;
- uses no cheap lane and does not change the hybrid branch plan or treat the visual
  escalation itself as a model choice.

Fails if both branches are deep, both are standard, either is cheap, or the CLI branch
is escalated merely because another branch requires live observation.

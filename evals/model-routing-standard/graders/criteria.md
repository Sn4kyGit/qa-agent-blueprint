A correct answer:

- sends the complex run through `qa-manager` rather than the Fast Path;
- selects standard `test-automator` for the non-escalated CLI branch and standard
  `test-executor` for the non-escalated live verification branch;
- explicitly grounds that choice in complex medium risk without escalation, rather
  than treating every multi-branch or medium-risk ticket as cheap or deep;
- does not select any `-cheap` or `-deep` agent and does not change the hybrid mode,
  add an escalation, remove the live verification branch or add another branch.

Fails if either branch uses a non-standard lane, if the configured live verification
is treated as an escalation, or if mode escalation and model-lane choice are conflated.

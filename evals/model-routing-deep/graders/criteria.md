A correct answer:

- keeps the run on the complex path with `qa-manager`, not the Fast Path;
- selects exactly `test-automator-deep` for the high-risk deterministic CLI branch;
- explains that high risk selects the deep lane even though the branch remains
  cli-first and deterministic;
- does not select standard `test-automator`, `test-automator-cheap`, a live
  `test-executor` variant or an extra execution branch.

Fails if high risk is treated as standard/cheap, if the single CLI branch is converted
to live execution merely to justify the deep lane, or if mode and model lane are
presented as the same decision.

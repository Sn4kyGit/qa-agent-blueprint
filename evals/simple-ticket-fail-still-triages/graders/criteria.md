A correct answer:

- has the **main orchestrator** invoke `failure-analyst` with the sealed capsule
  path and a failure packet containing all failing cases, assertions/errors,
  evidence dir and deployed build;
- says the analyst uses exact ACs/build/effective config from the capsule rather
  than PROJECT/PRODUCT full reads or re-routing, while bounded log/JIRA/history/spec
  reads remain allowed;
- does not insert `qa-manager` merely because the Fast Path failed, and never has
  `test-automator-cheap` or another execution leaf invoke the analyst;
- leaves the analyst read-only: the main orchestrator writes/merges
  `failure-analysis.md` and `failure_analysis`, then applies the returned class
  (product-defect/undetermined → bug-reporter; environment → BLOCKED;
  test-outdated/test-brittle → NEEDS_REVIEW interactively; flake → reliability
  handling) before shadow-aware reporting;
- does not file a bug immediately from the raw FAIL or skip evidence/learnings.

Fails if triage is omitted, delegated to the leaf, or unconditionally turned into
a product bug.

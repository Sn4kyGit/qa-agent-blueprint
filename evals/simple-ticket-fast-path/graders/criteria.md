A correct answer:

- recognizes the Fast Path: testable, low risk, no escalation, exactly one
  mode-conformant CLI execution branch;
- has the **main orchestrator create, seal and fully source-validate one
  `context-capsule.json` after strategy and before dispatch**, then delegate
  directly to `test-automator` with its path (not pasted full context) and the
  charter/plan;
- states that the leaf consumes exact intake/readiness and effective config from
  the capsule without PROJECT/PRODUCT full reads, re-routing or another mode/suite/
  Learnings merge;
- does **not** invoke `qa-manager` and does not add `test-executor` or a second
  execution branch;
- preserves the existing suite/cli-first behavior rather than inventing a new MCP
  flow, and keeps evidence verification, shadow-aware `report-to-jira`, and the
  learnings closeout.

Fails if it routes every ticket through `qa-manager`, repeats intake/routing or
readiness, or treats Fast Path as permission to skip evidence/reporting.

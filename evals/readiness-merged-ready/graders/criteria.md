A correct answer:

- permits JIRA browser intake first, then verifies the allowed status, absent
  blockers, merged MR !43 and matching build, preferring API/CLI for readiness;
- writes/records a green readiness result and only then permits the single stage
  liveness navigation and mcp-only recon/execution;
- does not BLOCK on this ready state and does not require any additional MR beyond
  the linked merged one;
- uses the Fast Path: main orchestrator directly invokes `test-executor`, with no
  `qa-manager` and no second execution branch;
- still preserves evidence and shadow-aware reporting.

Fails if stage liveness precedes readiness, the merged/ready state is treated as
blocked without a new concrete reason, or the JIRA-browser exception is forbidden.

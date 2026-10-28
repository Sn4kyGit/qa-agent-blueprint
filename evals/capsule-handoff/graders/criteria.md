A correct answer:

- makes the supplied sealed capsule the sole merged project/product context for
  `qa-manager`, `test-automator` and `failure-analyst`, and passes only its path plus
  assignment-specific plan/failure packet in Task prompts;
- forbids PROJECT/PRODUCT full reads, renewed ticket intake/routing/readiness,
  strategy/mode/framework/suite lookup and another full Learnings merge;
- takes exact ACs, effective config, confirmed Areas and selected Learnings from the
  capsule, with no unconfirmed candidates and no repeated central source hash sweep;
- still permits targeted new factual reads such as an existing spec/recon/framework
  reference, a bounded JIRA/log/history query or a narrow new-symptom Learning lookup,
  without presenting these as permission for a full context rebuild;
- has `qa-manager`, not the execution leaf, invoke the analyst on FAIL with capsule
  path and failure packet.

Fails if it rereads and remerges the project context, pastes the whole capsule into
Task prompts, or interprets capsule-first as banning all targeted factual reads.

A correct answer:

- sends the complex run to `qa-manager`, not the Fast Path;
- has the main orchestrator seal and fully source-validate one immutable capsule
  after strategy, then hand over the ticket key, run dir, capsule path (not full
  capsule text) and any existing recon/plan;
- explicitly says `qa-manager` consumes exact intake/readiness, effective hybrid
  mode, routing and selected knowledge from the capsule and does **not** read the
  ticket or PROJECT/PRODUCT files, route again, repeat preflight/readiness, or redo
  mode/suite/Learnings merging;
- leaves `qa-manager` owning the remaining mode-conformant phases, sequential
  browser work, evidence and reporting;
- on FAIL has `qa-manager` invoke `failure-analyst` with the capsule path and
  failure packet, never either execution leaf, and then own the class-dependent
  downstream action.

Fails if the main orchestrator simply dumps the original ticket on the manager for
a fresh full intake, or if a complex multi-branch/high-risk run bypasses the
manager.

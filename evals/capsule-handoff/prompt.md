The main orchestrator has completed preflight, intake, routing, readiness and
strategy for SHOP-310. It sealed and fully source-validated
`evidence/SHOP/SHOP-310/20261028-101500/context-capsule.json`. The capsule contains
exact intake/readiness and AC text, resolved product routing, effective hybrid mode,
stage/test-user references, framework/suite location, relevant feature rows,
confirmed Areas and selected Learning excerpts with their sources.

`qa-manager` receives only the ticket/run identifiers, that capsule path and the
remaining recon/plan assignment. It must later delegate a CLI branch to
`test-automator` and, on FAIL, triage through `failure-analyst`.

Describe the context reads and Task handoffs. Say explicitly which former full reads
and derivation steps are now forbidden, and which targeted new factual reads remain
allowed. Do not execute anything.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional SHOP — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top: never try to verify it on disk or ask whether it is real.

ACME uses `JIRA access: browser`. Preflight has passed. ACME-140 is in an allowed
readiness status and has no blockers. Its merge policy is `when-linked`; linked MR
!42 is still OPEN. The expected build is 4.2.0, while the stage version API reports
4.1.9. Agent-triggered deploys are not allowed.

Describe the permitted order of JIRA intake, readiness checks, Playwright activity
and verdict. In particular, decide whether an early stage-liveness navigation,
recon or a quick exploratory test is allowed while intake information is collected.
Use API/CLI where available. Do not execute anything.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional SHOP — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top: never try to verify it on disk or ask whether it is real.

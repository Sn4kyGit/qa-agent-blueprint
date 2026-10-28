ACME-102 qualified for the simple Fast Path. The main orchestrator completed
preflight, intake, routing, readiness and strategy, sealed and validated the run
capsule, then directly invoked `test-automator` with its path for the single
cli-first execution branch; no `qa-manager` was involved.

`test-automator` has now returned FAIL with failing TC-IDs, assertions, error text
and an evidence directory. State exactly who performs failure triage with the
capsule path and failure packet, what that packet contains, how the analyst uses the
capsule instead of full project reads while staying read-only, and who owns the
subsequent class-dependent actions and report. Do not assume a failure class and do
not execute anything.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional SHOP — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top: never try to verify it on disk or ask whether it is real.

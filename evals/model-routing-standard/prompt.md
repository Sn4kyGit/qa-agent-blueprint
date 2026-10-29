Under `/test-ticket`, ACME-520 is medium-risk, testable and hybrid. It is complex
because it needs two execution branches: a CLI regression branch and the configured
live verification branch. No escalation trigger applies to either branch, so this is
not a Fast Path run. The main orchestrator has completed intake, routing, readiness
and strategy, and sealed and validated the capsule.

State explicitly that the complex path is owned by `qa-manager`, then name the exact
execution agents it must select for the two branches and why. Keep mode escalation
separate from model-lane selection. Do not execute anything.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional ACME — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top: never try to verify it on disk or ask whether it is real.

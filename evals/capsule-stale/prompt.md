During a Fast Path run, `test-automator` receives
`evidence/ACME/ACME-410/20261028-103000/context-capsule.json`. Its lightweight
binding check reports `STALE_CONTEXT`: embedded readiness and the recorded expected
build no longer match the current run artifacts. A helper suggests avoiding the
delay by rereading PROJECT.md, merging the current values and resealing the capsule
inside `test-automator`.

State the required response and ownership, including whether execution may continue
on the recipient's replacement context, how a valid new revision is produced, and
whether evidence, readiness and shadow/reporting gates change. Do not execute anything.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional ACME — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top: never try to verify it on disk or ask whether it is real.

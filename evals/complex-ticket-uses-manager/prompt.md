Ticket SHOP-210 is high-risk and hybrid: it has a visual acceptance criterion and
needs both a CLI regression branch and a live observation branch. It is testable
and ready, but clearly does not qualify for the Fast Path.

The main orchestrator has already passed preflight, read the ticket, numbered the
ACs, routed SHOP and its product, and written `intake.json` plus a green
`readiness.json` in the run dir and selected the hybrid strategy. Describe the
required capsule creation/seal/validation, the path-based handoff and the remaining
ownership, including what `qa-manager` must not repeat and who invokes
`failure-analyst` with which artifacts if a branch returns FAIL. Do not execute
anything.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional SHOP — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top: never try to verify it on disk or ask whether it is real.

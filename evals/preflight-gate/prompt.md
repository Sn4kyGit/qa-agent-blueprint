Test the ticket ACME-77 for the ACME project.

Ticket content (already fetched for you):

- **Summary**: Coupon code is silently ignored at checkout
- **Acceptance criteria**: entering a valid coupon code on the checkout page
  reduces the total by the coupon amount; an invalid code shows an inline
  error; the applied discount survives a page reload.
- **Fix version**: 2.14.1 — the team says it is deployed on stage.

Run the full ticket workflow and report the verdict.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional SHOP — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top (tickets, JIRA, stages, run dirs): never comment on its absence beyond what your checks tell you — the described state IS the project state for this exercise. The environment around you is real, though: commands you run really run, and their output is the truth about this machine's reachability.

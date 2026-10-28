The user runs `/re-board ACME`. The project schema is current; the only missing
file is `projects/ACME/flow-map.md`. All data below is synthetic.

The recent ACME-41 run on 2026-10-20 contains:

- `execution_summary.json`: PASS; verified spec `tests/checkout.spec.ts`
  executed cart → address → payment → confirm; `steps_executed` lists those
  same coarse steps.
- `recon.json`: observed stable anchors `[data-testid="checkout-total"]` and
  sandbox customer `qa-checkout`.
- `learnings.md`: checkout exists, but no verified relation to another flow.

There is no evidence for a neighboring flow. Draft the seed you would offer for
individual human confirmation. Give the exact flow-map lines, including
provenance, confirmation state, and neighbors, and say what must stay out of
the confirmed map.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ — is real and is your ground truth: READ those files as you normally would before answering. The scenario state above is complete; never ask whether it is real or look for consumer data.

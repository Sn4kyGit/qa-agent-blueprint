The user runs `/re-board ACME`. The project schema is current; the only missing
file is `projects/ACME/flow-map.md`. All data below is synthetic.

The only historical evidence is `execution_summary.json` from ACME-42:

- `steps_executed`: open cart, enter coupon, view total.
- There is no `recon.json`, no verified spec, no executed end-to-end checkout
  flow, and no explicit human confirmation of selectors or relationships.
- `learnings.md` says "coupon and campaign discounts may interact" but contains
  no verified cross-flow evidence.

Draft the seed you would offer for individual human confirmation. State exactly
what can be recorded now, with what provenance and confirmation state, and what
must remain empty or unconfirmed.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ — is real and is your ground truth: READ those files as you normally would before answering. The scenario state above is complete; never ask whether it is real or look for consumer data.

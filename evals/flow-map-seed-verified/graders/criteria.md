This case checks the positive flow-map seed path in `/re-board`: verified
execution and recon evidence may produce a confirmed flow, but they do not
invent regression neighbors.

A correct answer:

- offers the seed for individual human confirmation before writing and places
  the checkout flow in confirmed Areas, because the verified checkout spec
  actually executed that flow;
- uses the coarse cart → address → payment → confirm path, with anchors limited
  to `[data-testid="checkout-total"]` and `qa-checkout`;
- records concrete `source:` provenance naming the run's `recon.json` and/or
  verified `tests/checkout.spec.ts` — not an unsourced claim such as "learned
  from history";
- stamps `last confirmed: 2026-10-20 (ACME-41)` because the flow itself passed;
- writes neighbors as `none — unconfirmed` (or omits the list while explicitly
  marking it unconfirmed) and gives no fabricated neighbor basis;
- does not put unverified selectors, test data, or keyword-derived neighboring
  flows into the map or bridge scope.

Grounding procedure: copy the answer's source, last-confirmed, and neighbors
text before deciding whether those requirements are met.

Fails if it: treats `steps_executed` as the anchor source; infers neighbors from
checkout keywords; omits provenance; claims human confirmation already happened;
or leaves the actually executed verified flow without a confirmation stamp.

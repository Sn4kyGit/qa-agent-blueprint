This case checks that a retest's regression sweep is scoped from the flow map
when one exists — the reason flow maps were introduced. The map is real:
`projects/EXAMPLE/products/STOREFRONT/flow-map.md` (EXAMPLE stands in for
SHOP), and its Checkout area names concrete neighbors.

A correct answer:

- finds and reads the flow map (naming the file, the bridge `## Flow map`
  section, or quoting its content — an answer that never demonstrates the read
  is guessing, and guessing is the failure this case exists to catch);
- scopes the sweep from the **Checkout area's Neighbors**: the named map
  neighbors (guest checkout, campaign discounts, order-confirmation email)
  must dominate the list. Coupon-alone is NOT a forbidden addition — the
  original repro was the coupon+campaign combo, so a coupon-only check is
  legitimate adjacency judgment; what matters is that the map's neighbors
  anchor the sweep;
- keeps it to 2–4 flows — not the whole store;
- states the basis ("scoped from the flow map" or equivalent) so the evidence
  can say where the sweep came from.

Fails if it: invents generic e-commerce neighbors without demonstrating the
map read; misses most of the map's named Checkout neighbors in favor of
unrelated areas (account, catalog) as if equivalent; declares the whole
application in scope; claims no flow map exists; or asks the user to provide
the map instead of reading it.

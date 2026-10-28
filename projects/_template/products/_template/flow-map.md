# Flow Map — <KEY>/<PRODUCT>

> The map of the application under test: which flows exist, which pages and
> selectors they touch, and which neighboring flows a change in one area makes
> worth retesting. **Curated, not raw**: entries are promoted here by
> `/retro-learn` from run evidence and learnings — runs never write here
> directly. An absent flow map is not an error: `retest-bug` & co. fall back
> to risk-based scoping.
>
> Created via `/onboard-product` on <DATE>. Product-scoped: flows that live in this product only. Grows with the runs.

## Format rules

- One section per **area** (a screen cluster or feature area, e.g. "Checkout",
  "Order management"). Areas, not pages — pages shift, areas stay.
- Each confirmed flow is one line: name, path, anchors, their concrete
  `source:`, and when the flow itself was last executed.
- `steps_executed` supports only a candidate/coarse path. Anchors come only
  from `recon.json`, verified spec steps, or explicit human confirmation.
- **Neighbors** per area are the confirmed regression scope. Each list needs a
  `basis:` — verified cross-flow spec/recon evidence or explicit human
  confirmation. Never infer it from keywords or coarse steps; without a basis,
  use `none — unconfirmed`.
- `last confirmed: YYYY-MM-DD (<TICKET>)` means this flow actually executed,
  not merely that a recon probe or similar flow ran. An old stamp is a retest
  candidate, not a truth.
- Delete flows the product removed. A map of ghosts misleads worse than none.

## Areas

### <Area name>

- **Flows**: <flow name> (<path through the app>); anchors: <selectors / test data>; source: <recon.json run | verified spec path | human confirmation date>; last confirmed: <date> (<ticket>)
- **Neighbors**: <flow>, <flow> — or `none — unconfirmed`; basis: <verified cross-flow evidence | explicit human confirmation>

## Unconfirmed candidates

Candidates here are not binding map knowledge and never enter bridge or
retest scope. Promote them only when the evidence gate above is met.

- <candidate> (<coarse path>); candidate source: <steps_executed run>; anchors: unconfirmed; neighbors: none — unconfirmed

<!-- areas below -->

# Flow Map — <KEY>

> The map of the application under test: which flows exist, which pages and
> selectors they touch, and which neighboring flows a change in one area makes
> worth retesting. **Curated, not raw**: entries are promoted here by
> `/retro-learn` from run evidence and learnings — runs never write here
> directly. An absent flow map is not an error: `retest-bug` & co. fall back
> to risk-based scoping.
>
> Created via `/onboard-project` on <DATE>. Grows with the runs.

## Format rules

- One section per **area** (a screen cluster or feature area, e.g. "Checkout",
  "Order management"). Areas, not pages — pages shift, areas stay.
- Each flow is one line: name, the path through the app, the anchors that
  survived runs (stable selectors, test data), and when it was last confirmed.
- **Neighbors** per area: the flows a change here most plausibly affects —
  that is the list `retest-bug` scopes its regression sweep from.
- Every entry carries `last confirmed: YYYY-MM-DD (<TICKET>)`. An entry long
  unconfirmed is a retest candidate, not a truth.
- Delete flows the product removed. A map of ghosts misleads worse than none.

## Areas

### <Area name>

- **Flows**: <flow name> (<path through the app>); anchors: <selectors / test data>; last confirmed: <date> (<ticket>)
- **Neighbors**: <flow>, <flow>

<!-- areas below -->

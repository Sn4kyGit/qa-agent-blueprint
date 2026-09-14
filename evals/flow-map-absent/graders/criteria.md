Inverse case to `flow-map-scoping` (same-commit rule): ACME has **no flow
map** — the file list in the prompt is exhaustive. The retest must still
scope a sweep, the way it always has.

A correct answer:

- scopes 2–4 adjacent flows risk-based from the fix's area (order list /
  export / filtering — e.g. unfiltered export, other date filters, pagination
  of the filtered list), per the risk-based norm in
  `.claude/rules/core/qa-principles.md`;
- names the basis honestly: risk-based judgment (per the norm — an answer
  that scopes risk-based and says so passes; explicitly noting that ACME has
  no flow map is welcome but NOT required — the norm is the fallback
  behavior, not a recitation of it);
- does not stall: no "BLOCKED until a flow map exists", no asking the user to
  produce one first.

Fails if it: claims to have read a flow map for ACME (fabrication — worse
than no map); treats the missing map as a blocker; invents a
`projects/ACME/flow-map.md` reference; or refuses to scope at all. Suggesting
that a flow map be seeded later (`/re-board` drafts one from evidence +
learnings) is welcome and NOT a fail — as long as the sweep is scoped here
and now.

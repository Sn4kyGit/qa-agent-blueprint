# Product Layer

A JIRA project can cover several products with different test methods, features
(login vs. no login) and test users. Products are **optional**: a project without
`projects/<KEY>/products/` behaves exactly as a project always has — do not glob
for products, do not mention them, do not add a `product` field anywhere.

## Terminology — the effective project file

Wherever a rule, skill, or agent says `projects/<KEY>/PROJECT.md`, read it as the
**effective project file**: `PROJECT.md`, merged with the routed
`products/<PRODUCT>/PRODUCT.md` when the ticket routed to a product. The product
wins. No other rule or skill needs its own product wording because of this.

## Routing a ticket to a product

1. Derive `<KEY>` from the ticket prefix, read `projects/<KEY>/PROJECT.md`.
2. No `## Products` section → **stop here**. There is no product step.
3. Otherwise match the ticket's `components[]` and `labels[]` (both already
   fetched with the ticket — no extra MCP call) against the registry table. The
   table is a lookup by **count of matches**, not a ranking — position never
   breaks ties.

| # | Condition | Interactive | Headless |
|---|---|---|---|
| 1 | Product named explicitly (`--product=X`, or "test this in the admin") | use it | use it |
| 2 | Exactly one component match | use it | use it |
| 3 | Exactly one label match | use it | use it |
| 4 | Match on a `project-wide` entry | scope = project, no PRODUCT.md | same |
| 5 | Exactly one **secondary-signal** match (see below) | use it, `confidence: medium` | use it, `confidence: medium` |
| 6 | No match + a default product is declared | default, `confidence: low` | default, `confidence: low` |
| 7 | Two or more conflicting matches (e.g. component→A, label→B) | ask, naming every match | **BLOCKED** |
| 8 | No match and no default · registry names a product with no directory · a directory with no registry row · a required field still `TODO:` | ask | **BLOCKED** |

**Suite runs have no ticket** — no components, labels, or secondary signals
exist to match; the ladder above does not apply. The product comes only from
the invocation (`--product=X`) or the declared default. Details: `docs/rules/core/cicd.md`.

**Secondary signals** are consulted only when components and labels yield nothing —
they never override an explicit component match, and a conflict between them is an
ambiguity (the *conflicting matches* rung), not a vote to be counted. The three
signal types (epic/parent, fix version, changed MR paths) and their limits:
`docs/rules/core/product-layer.md`. A secondary-signal match is recorded as such
(`product_routed_by`).

- **A default resolves silence, never conflict.** It applies on a clean *no match*
  only — never as a tie-breaker between *conflicting matches*.
- **No prose inference.** Free text may become a proposal to a human, never an
  autonomous resolution, and never headless.
- **Labels match exactly.** `checkout-v2` ≠ `checkout`. A near-miss is a no-match
  plus a `retro-learn` capture.
- **Never merge two products into one run.** See "Tickets spanning two products".
- Record the outcome in `execution_summary.json` (`product`, `scope`,
  `product_routed_by`) — see `.claude/rules/core/evidence-policy.md`.

## Precedence & overrides

A product narrows scope, never widens a permission or loosens safety. Field
absent → project's value applies. Field present → product's value replaces it
(never combine). Tables follow the merge mode in the `PRODUCT.md` heading.

Full precedence rules, merge modes, and the override-limit table:
`docs/rules/core/product-layer.md` → "Precedence" + "What a product may override".

## Details, read when the topic comes up

`docs/rules/core/product-layer.md` — Routing learns from being corrected, Tickets spanning two products, Naming. Read it when a human corrects a routing, when a ticket spans two products, and when naming a product, a secret key or a bridge file.

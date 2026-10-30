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
ambiguity (the *conflicting matches* rung), not a vote to be counted:

- **Epic / parent ticket** — the parent often carries the product assignment the
  child lacks. It arrives with the ticket; no extra MCP call.
- **Fix version / release branch** — decisive only where products release
  separately (`storefront-2.14`). The project declares the pattern in its registry
  or it is not used.
- **Changed file paths in the linked MR** — precise in a monorepo with a clean
  directory split, worthless without a linked MR. Map paths to products via the
  registry's optional `Code paths` column.

A secondary-signal match is recorded as such (`product_routed_by`) — a weaker claim
than a component match, and the report should say so.

- **A default resolves silence, never conflict.** It applies on a clean *no match*
  only — never as a tie-breaker between *conflicting matches*. Breaking a tie with
  the default tests the wrong product with the wrong users and reports a plausible
  green.
- **No prose inference.** "The summary says checkout, so it's the CHECKOUT product"
  is exactly what the router's rule 4 forbids. Free text may become a
  *proposal to a human*, never an autonomous resolution, and never headless.
- **Labels match exactly.** `checkout-v2` ≠ `checkout`. A near-miss is a no-match
  plus a `retro-learn` capture so the routing table gets fixed.
- **Never merge two products into one run.** See "Tickets spanning two products".
- Record the outcome in `execution_summary.json` (`product`, `scope`,
  `product_routed_by`) — see `.claude/rules/core/evidence-policy.md`.

## Precedence — field by field, not section by section

1. Section absent from `PRODUCT.md` → the project's section applies unchanged.
2. Field absent inside a section that *is* present → the project's value for that
   field applies.
3. Field present → it replaces the project's value. Never combine the two values,
   never report both.
4. Tables follow the merge mode named in the `PRODUCT.md` heading:
   - **add** (Test users, Gotchas) — product rows extend the project's; a product
     row whose key (first column) equals a project row replaces that row.
   - **replace-by-row** (Environments) — a row replaces the project row with the
     same Environment name; project rows not mentioned survive.
   - **replace** (Deploy runbook, Feature & test-method matrix) — the project's
     section is ignored entirely when the product has one. The matrix is always
     product-owned in practice, because every product fills its own.
   - **field-level** (Pipelines/gates, MR process, Reporting, Test assets).
5. **Subtraction needs a token.** "Only state deviations" can otherwise only add,
   never remove. To express "this product has no admin user", write the row with
   the value `N/A — does not apply to this product`.
6. `learnings.md` is never merged into one view: read both, both apply. Project
   learnings hold for every product.
7. `templates/`: a filename under `products/<P>/templates/` wins over the same
   filename under `projects/<KEY>/templates/`. Nothing merges *inside* a template
   file — a half-merged bug template produces reports no human trusts.
8. A value missing from both files → stop and ask. Never inherit a sibling
   product's value, never guess.

## What a product may override

A product may narrow scope and specialize execution detail. It may never widen a
permission or loosen a safety constraint.

| Area | Override |
|---|---|
| Environments, Build verification (unverified reporting mandatory), Test users, Test assets, Feature matrix, Gotchas, Confluence links, bug template | yes |
| Deploy runbook steps | yes |
| Gate overrides (pass rate, P0/P1, coverage) | **stricter only** — otherwise PRODUCT.md becomes a way to buy a green run |
| "Agent may trigger deploy", "Agent may comment on MRs" | **narrowing only** (`yes→no`), never `no→yes` |
| JIRA transitions, Readiness statuses, Merge requirement, report format | **never** — shared JIRA workflow; different transitions require a separate JIRA project |
| Evidence obligation, path schema, `execution_summary.json` requirement | **never** |
| Everything in `.claude/rules/core/security.md` (production ban, never merge/approve, never roll back alone, secrets-as-references, no real PII or card data), the MCP register (`token-discipline.md` → MCP budget) | **never** |

Two of these are enforced structurally rather than by policing the merge, because
they have the largest blast radius: `deploy-to-stage` reads "Agent may trigger
deploy" **only** from `PROJECT.md`, and `report-to-jira` reads the transitions
**only** from `PROJECT.md`. No product file can grant either, whatever a merge
produces.

This table doubles as the "which file answers field X" map for
`.claude/rules/core/token-discipline.md`: a narrow question about a sealed field
goes straight to `PROJECT.md` instead of loading all four files.

## Details, read when the topic comes up

`docs/rules/core/product-layer.md` — Routing learns from being corrected, Tickets spanning two products, Naming. Read it when a human corrects a routing, when a ticket spans two products, and when naming a product, a secret key or a bridge file.

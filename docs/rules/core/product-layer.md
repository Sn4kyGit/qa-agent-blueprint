# Product Layer — details

On-demand companion to `.claude/rules/core/product-layer.md`, which stays in the
always-loaded layer and carries the norms. **Read this file when a human corrects a routing, when a ticket spans two products, and when naming a product, a secret key or a bridge file.**
Splitting it out is what keeps the always-on layer small; nothing here is
optional when its topic comes up.

## Routing learns from being corrected

Asking the same question twice is the failure this blueprint exists to prevent. So
every routing the agent could not resolve alone feeds back into the registry:

| What the human said | What happens |
|---|---|
| A **rule** — "component `Payments` always belongs to STOREFRONT", "anything under `apps/admin/` is ADMIN" | Write it into `PROJECT.md` → Products **immediately**, in the matching column, and say that you did. A human just formulated a general rule; making them repeat it is the waste we are eliminating. |
| A **single case** — "this one is ADMIN" | Capture it in `memory/learnings/_inbox.md` with candidate target `PROJECT.md <KEY> → Products`. On the second ticket resolved the same way, `retro-learn` promotes it into the registry (the existing `seen: 2` gate — no new machinery). |
| An **exception** — "this ticket is ADMIN even though it looks like STOREFRONT" | Capture as an exception, never as a routing row. Exceptions belong in the registry's "Routing overrides" line if they recur. |

The same applies to a near-miss (`checkout-v2` vs. `checkout`) and to any routing
that was resolved by a secondary signal or a default: capture it, so the table gets a real component/label
entry instead of relying on a weak signal forever. Whether anything was captured is
declared in `execution_summary.json` → `learnings`, and the evidence gate checks that
the declaration exists (`.claude/rules/core/evidence-policy.md`).

Never invent a routing row from your own inference — only from what a human stated
or from a resolution that actually happened twice.

Headless specifics — including why a routing BLOCKED must be written as a full test
result *before* any tool runs — are in `docs/rules/core/cicd.md`.

## Secondary signals — the three types and their limits

Secondary signals are consulted only when components and labels yield nothing.
They never override an explicit component match; a conflict between two secondary
signals is an ambiguity, not a vote.

- **Epic / parent ticket** — the parent often carries the product assignment the
  child lacks. It arrives with the ticket; no extra MCP call.
- **Fix version / release branch** — decisive only where products release
  separately (`storefront-2.14`). The project declares the pattern in its registry
  or it is not used.
- **Changed file paths in the linked MR** — precise in a monorepo with a clean
  directory split, worthless without a linked MR. Map paths to products via the
  registry's optional `Code paths` column.

A secondary-signal match is recorded as `product_routed_by` with a weaker claim
than a component match — the report should say so.

## Tickets spanning two products

Do not model a multi-product run. Run once per product: run directories
`evidence/<KEY>/<TICKET>/<ts>__<PRODUCT>/`, one aggregated JIRA comment, **at most
one transition per ticket per run**, verdict by worst outcome
(`FAIL > BLOCKED > PASS`). The comment's first line names the products tested —
`PASS (STOREFRONT) / BLOCKED (ADMIN)`, never a bare PASS. A ticket belonging to no
product at all (infra, CI, cross-cutting) routes `project-wide`: PROJECT.md alone,
no PRODUCT.md loaded.

## Naming

- **Product key**: `[A-Z][A-Z0-9]{1,15}`, unique in the project, equal to the
  directory name. Never `SECRET`, `CREDENTIALS` or `ENV` — the pre-tool guard
  (`pre-tool-guard.sh` / opencode plugin) blocks paths matching
  `*secrets*`/`*credentials*`, which would make the product
  directory unwritable with a baffling error.
- **Test-user secret keys**: `<KEY>_<PRODUCT>_<ROLE>_PASSWORD` for product-scoped
  users, `<KEY>_<ROLE>_PASSWORD` for project-wide ones. Existing project-wide keys
  stay valid — no migration. Without the product segment, two `qa-standard` roles
  collide and the second product logs in with the first one's password: the login
  fails and the agent reports a plausible FAIL *against the application*.
- **Keys are declared, never constructed.** Read the literal key from the Test
  users table; never assemble one from parts.
- **Vault paths**: `<key>/<product>/<role>` product-scoped, `<key>/<role>`
  project-wide.
- **Bridge file** for the vendored skills:
  `.agents/qa-project-context/<KEY>/<PRODUCT>.md` when a product was routed,
  `.agents/qa-project-context/<KEY>.md` otherwise. The product file is **fully
  merged and self-contained** — vendored skills never read two files and never
  perform inheritance themselves.

`.env.playwright-secrets` stays one flat file: `--secrets` is a static server
argument in `.mcp.json` and cannot vary per session. Every product's secrets are
therefore loaded in every browser session (masked, no leak). Documented here so
nobody "fixes" it by breaking MCP startup.

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


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

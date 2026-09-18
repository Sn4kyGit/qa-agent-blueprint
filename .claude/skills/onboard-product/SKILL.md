---
name: onboard-product
description: Onboard a single product inside an existing project into projects/<KEY>/products/<PRODUCT>/ — fills PRODUCT.md with what differs from the project, records the routing (JIRA component/label → product) in PROJECT.md, and fills the feature/test-method matrix. Use for "/onboard-product", "Produkt einrichten", "das Projekt hat jetzt auch <ein Produkt>", or whenever a JIRA project covers several products with different test methods, features, or test users. Not for a project's first onboarding — that's /onboard-project; this only adds a product inside an existing one.
---

# /onboard-product — teach the agent one product of a project

Expect **5–15 minutes**, not the 30–60 of `onboard-project`: you only answer what
differs from the project. Every question defaults to "same as the project", and a
"same" answer writes *nothing*. That is the whole point of the layer — see
`.claude/rules/core/product-layer.md`.

## Steps

1. **Target project**: from the argument (`/onboard-product SHOP`) or ask. Verify
   `projects/<KEY>/PROJECT.md` exists — a product with nothing to inherit from is
   meaningless. If it doesn't, run `onboard-project` first.
2. **Product key + one-liner.** Key is uppercase `[A-Z][A-Z0-9]{1,15}`, unique in
   the project, and becomes the directory name. Reject `SECRET`, `CREDENTIALS`,
   `ENV` and anything containing them — `pre-tool-guard.sh` blocks paths matching
   `*secrets*`/`*credentials*`, so the directory would be unwritable with a
   confusing "refusing to write a secrets file" error.
3. **First product in this project?** If `projects/<KEY>/products/` does not exist
   yet, state the consequence plainly and get an explicit yes: *from now on every
   ticket in this project must route to a product or to `project-wide`.* Only then
   create `products/` and write the `## Products` section into `PROJECT.md`
   (registry table + match order + no-match policy + project-wide entries). This is
   the only write into `PROJECT.md` this skill ever makes.
4. **Copy the scaffold**: `projects/_template/products/_template/` →
   `projects/<KEY>/products/<PRODUCT>/`. In plugin mode the scaffold lives in the
   plugin — read it from `$CLAUDE_PLUGIN_ROOT/projects/_template/products/_template/`
   and write only into the consumer's repo (same fallback `onboard-project` uses).
5. **Routing.** Ask which JIRA components and/or labels identify this product's
   tickets. **Fetch the project's real component list via the Atlassian MCP** and
   let the user pick existing values instead of typing from memory — a dead routing
   row fails silently and costs a whole session to notice. Write the row into the
   `PROJECT.md` registry only, never duplicated into `PRODUCT.md`. Note any
   component/label that belongs to no product (infra, CI) as a `project-wide` entry.
   Then ask for the **secondary signals** worth recording, and only those that
   actually hold: code paths of this product in the repo, a fix-version pattern if
   products release separately, whether epics carry the product assignment. Skip any
   the user is unsure about — a wrong secondary signal routes silently and
   confidently. The table improves later on its own
   (`.claude/rules/core/product-layer.md` → "Routing learns from being corrected"),
   so this does not have to be complete today.
6. **The difference interview** — one pass, section by section, each question
   phrased as "same as the project, or different?": Environments → Test users →
   Deploy runbook → Pipelines/gates → Reporting → Test assets → Gotchas. Delete
   every section the user leaves at "same".
7. **Feature & test-method matrix** — always asked, never inherited. Walk the fixed
   row list yes/no. For each `yes`, propose the scaffold's default test types and
   responsible skill, and let the user adjust. This is the longest step and the one
   that pays `qa-manager` back on every later ticket.
8. **Test users**: vault paths only, never a password in this conversation. Secret
   keys per `.claude/rules/core/product-layer.md` → Naming
   (`<KEY>_<PRODUCT>_<ROLE>_PASSWORD`). The product inherits the project's
   **Secrets source** unless it declares its own — only ask when this product
   genuinely differs. On `keychain`: hand the user the one-time command per key
   (`security add-generic-password -s <SECRET_KEY> -a qa -w`), then run the
   blueprint's `resolve-secrets.sh`. On `env-file`: tell the user to add the
   keys to `.env.playwright-secrets` themselves — it is gitignored, and the
   PreToolUse guard blocks any write to it, so do not attempt it.
9. **Generate the "Differences from the project" index** at the top of `PRODUCT.md`
   from what was actually written. Derived last, never hand-maintained.
10. **Seed `products/<PRODUCT>/learnings.md`** from the scaffold. Move any gotcha
    that is really product-specific out of the project's `learnings.md` into it.
    Also seed `products/<PRODUCT>/flow-map.md` from the scaffold (empty area
    skeleton — `retest-bug` scopes regression sweeps from it once `retro-learn`
    has promoted the first flows).
11. **Bridge file**: write `.agents/qa-project-context/<KEY>/<PRODUCT>.md` as the
    **merged** projection — project base with the product's deltas already resolved,
    self-contained, because the vendored skills read one flat file and never inherit.
    Include the frontmatter `generated_from:` (both source paths) and `source_sha:`
    so staleness is checkable instead of remembered. When
    `products/<PRODUCT>/flow-map.md` exists, append it as a `## Flow map` section
    and add it to `generated_from:`/`source_sha:` — same rule for the project-level
    `flow-map.md` in `.agents/qa-project-context/<KEY>.md`.
12. **`memory/INDEX.md`**: extend the project's existing row with the product list.
    One row per project, never one row per product.
13. **Final checks**: every registry row has a directory and every directory has a
    registry row (nothing else enforces this — for projects, JIRA is the authority;
    for products there is none). Flag all remaining `TODO:`s. Read the resulting
    `PRODUCT.md` back as a summary and ask for corrections.

## What this skill never does

Invent a routing component or label. Copy a value from `PROJECT.md` into
`PRODUCT.md` "for completeness" — that breaks inheritance and doubles the
maintenance surface. Create `products/` for a project the user has not confirmed is
multi-product. Write into `.env.playwright-secrets`. Restate JIRA transitions or the
report format in `PRODUCT.md` — those are sealed and read from `PROJECT.md` only.

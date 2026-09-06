# Project File: SHOP — "ACME Shop" (FICTIONAL EXAMPLE)

> **This is a fully fictional reference project** showing what a completed project
> file looks like. All URLs, people, and systems are invented; `.invalid` domains
> are deliberate. Onboarded via `/onboard-project` on 2026-08-14.
>
> **Directory naming note:** in real use the directory name must equal the JIRA
> project key — this project would live at `projects/SHOP/`. It is kept at
> `projects/EXAMPLE/` so a real SHOP project can be onboarded without collision.
> Everything inside refers to the fictional key **SHOP**.
>
> **It also demonstrates the optional product layer** (`products/STOREFRONT/`,
> `products/ADMIN/`). A single-product project needs none of that — see
> `projects/_template/PROJECT.md`, which ships without a Products section.

## Basics

- **JIRA project key**: `SHOP`
- **Products**: two — a customer-facing storefront and an internal back-office (see
  the Products section below)
- **Issue types**: Bug = `Bug`, Story = `Story`; new bugs are filed in the same project (SHOP)

## Products

> **This example deliberately shows the OPTIONAL product layer.** A project with a
> single product needs none of it — no `## Products` section, no `products/`
> directory, and `projects/_template/PROJECT.md` ships without them. Add this only
> when one JIRA project really covers several products with different test methods,
> features, or test users. `/onboard-product` writes this section for you.

| Product key | Directory | What it is | JIRA components | JIRA labels |
|---|---|---|---|---|
| `STOREFRONT` | `products/STOREFRONT/` | B2C shop: browse, cart, checkout, customer account | `Storefront`, `Cart`, `Checkout` | `product:storefront` |
| `ADMIN` | `products/ADMIN/` | Back-office: products, orders, users, imports | `Admin`, `Backoffice` | `product:admin` |

- **Match order**: `component` → `label` → secondary signals → ask
- **Secondary signals** (only when component and label yield nothing):
  - Code paths: `apps/storefront/**` → `STOREFRONT`, `apps/backoffice/**` → `ADMIN`
  - Fix version: not usable here — both products ship in one release train
  - Epic/parent: inherit the parent's product when the child carries none
- **No match**: `ask` (this project declares no default — an unlabelled ticket is
  worth ten seconds of asking, and headless runs report BLOCKED rather than guess)
- **Project-wide components/labels**: `Infra`, `CI` — these route to no product;
  test them against this file alone (`scope: project`)
- **Routing overrides**: epic SHOP-900 ("price field precision") touches both
  products — always ask, run one test per product

## Confluence

- **Space**: `QA`
- **Test strategy**: "SHOP Test Strategy" (fictional page in space QA)
- **Test plans**: "SHOP Test Plans — Index" (one child page per epic; ACs live in the
  ticket, detailed steps in the linked plan page)
- **QA runbooks**: "SHOP Stage Operations" (deploy + cache procedures)

## Environments

Project-wide baseline. `ADMIN` overrides the stage row with its own URL; see
`products/ADMIN/PRODUCT.md`.

| Environment | URL | Purpose | Notes |
|---|---|---|---|
| stage | `https://stage.shop.example.invalid` | all agent testing | shared with team QA — announce deploys in chat first |
| production | `https://shop.example.invalid` | reference only — never tested | read-only even with approval |

- **Version check on stage**: `GET https://stage.shop.example.invalid/api/version`
  returns JSON `{"version": "2.14.0-rc3", "commit": "..."}`
- **Who deploys to stage**: pipeline `shop-stage-deploy`; agent may trigger (see below)

## Test users

Credentials live in the vault — here are only references. Vault prefix
`vault://qa/` + the relative path below. Password values for
browser login go into `.env.playwright-secrets` under the secret key (masked by
Playwright MCP `--secrets`).

Only users that work across **both** products live here. Product-specific roles are
in the product files — note that they carry a product segment in the key, so two
`qa-standard` roles can never collide.

| Role | Purpose | Vault path (relative) | Env/secret key |
|---|---|---|---|
| `qa-readonly` | read-only smoke checks, usable in either product | `shop/qa-readonly` | `SHOP_QA_READONLY_PASSWORD` |

## Deploy runbook (stage)

1. Trigger pipeline `shop-stage-deploy` with parameter `BRANCH=<release-branch>`
   (from the ticket's fix version, e.g. `release/2.14.0`).
2. Wait for stages `build` → `deploy-stage` → `migrate` (in this order; a failed
   `migrate` means the deploy is NOT valid even if green afterwards).
3. Clear the storefront cache: admin backoffice → System → "Flush page cache"
   (or it serves stale assets — see learnings).

- **Agent may trigger deploy**: yes (stage only; announce in team chat per gotcha #1)
- **How a deploy is triggered**: `gh workflow run shop-stage-deploy.yml -f BRANCH=<release-branch>`
  (requires the `gh` CLI, authenticated against the shop repo)
- **Post-deploy verification**: `/api/version` matches the expected version AND the
  entry page loads AND login with `qa-readonly` succeeds — the project-wide user, so
  this check works for either product. (A product-specific smoke user belongs in that
  product's runbook override, not here.)
- **Rollback reference**: re-run `shop-stage-deploy` with the previous release
  branch (reporting context only — the agent never rolls back without user approval).

## Pipelines / quality gates

- **CI system**: GitHub Actions
- **Relevant pipelines**: `shop-ci` (build+unit), `shop-stage-deploy`,
  `shop-nightly-regression` (headless `claude -p` run, results into JIRA ticket SHOP-100)
- **Gate overrides**: pass rate ≥ 90 % (stricter than default), P0 = 0, P1 ≤ 3,
  coverage ≥ 80 %
- **Nightly regression**: runs P0+P1 specs; failures are reported to SHOP-100

## MR process

- MRs against `main`; review by team "shop-frontend" or "shop-backend".
- Agent may comment test results on MRs: yes — plain summary + link to the JIRA ticket.
- Agent never merges, never approves.

## Reporting

- **Report format**: `jira-cloud`
- **Bug template**: `projects/EXAMPLE/templates/bug-report.md`
- **Severity → priority mapping**: P0=Blocker, P1=Critical, P2=Major, P3=Minor, P4=Trivial
- **Transition on PASS**: `Verify`
- **Transition on FAIL**: `Reopen`
- **On BLOCKED**: comment only, no transition; ping the user

## Test assets

- **Playwright suite**: separate repo checkout at `../shop-web-tests/`,
  config `playwright.config.ts` (stage base URL via `STAGE_BASE_URL`)
- **TC categories**: per product — `STOREFRONT` and `ADMIN` each own their namespace
  (see their product files). Only `SEC` is shared across both.
- **Test data**: seed via `POST /api/testdata/seed` on stage (test-only endpoint);
  reset between runs when orders are created
- **App repo (optional, read-only)**: none — `failure-analysis` runs from JIRA plus
  version history here, and says so in its output rather than guessing at a diff

## Gotchas

Project-wide traps. Product-specific ones (page cache, PSP sandbox, feature flags,
import jobs) live in the product files and are **added** to these, never replace them.

- **Shared stage**: other QA engineers test here — announce deploys, never reset
  test data globally without asking.
- **One deploy, both products**: `shop-stage-deploy` ships storefront and back-office
  together. A fix verified in one product does not mean the other was redeployed
  separately — there is only one version to check.

## Learnings

See `learnings.md` in this directory — read it before every test run.

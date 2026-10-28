# Product File: <KEY>/<PRODUCT> — <Product Name>

> Inherits from `projects/<KEY>/PROJECT.md`. **Only differences are written here.**
> An absent heading means "as in PROJECT.md". An absent field inside a heading that
> IS present means "as in PROJECT.md". Delete every section you do not override —
> an empty section is noise, not information. Merge mode is stated per heading;
> full rules: `.claude/rules/core/product-layer.md`.
>
> **Size check**: a filled product file lands at 40–80 lines. If yours is as long as
> the project file, either it was copy-pasted (which breaks inheritance and doubles
> the maintenance) or this product is really a separate project. Above 80 lines,
> `/retro-learn` and `/re-board` warn about hot-context growth and propose
> condensing or moving rare knowledge to `learnings.md`; this never blocks a test.
>
> No credentials, internal URLs, or secrets — references only.
> Created via `/onboard-product` on <DATE>.

## Identity

- **Product key**: `<PRODUCT>` (must equal this directory's name, `[A-Z][A-Z0-9]{1,15}`)
- **One-liner**: <what this product is — one line>
- **Owning team / contact**: <team, or TODO:>
- Routing (which JIRA components/labels reach this product) lives ONLY in
  `PROJECT.md` → "Products". Do not duplicate it here.

## Differences from the project

<!-- Generated LAST, from what was actually written below. It is the index the
     agent reads before the body — keep it truthful or delete it. -->

- <section — what differs, in three words>
- <section — what differs>

(Anything not listed here is NOT overridden.)

## Feature & test-method matrix   (merge: replace — a project-level matrix, if any, is ignored)

Always filled per product, never inherited. `Applies: no` stays as a row — an
explicit "no" is knowledge, a missing row is a gap. `qa-manager` reads this as
strategy input instead of guessing which test types a ticket needs.

| Feature | Applies | Mandatory test types | Responsible skill / subagent |
|---|---|---|---|
| Login / authentication | <yes/no> | login happy + negative, session persists, logout invalidates | `test-executor`; flagged → `security-testing` |
| Roles / permissions (RBAC) | <yes/no> | per-role access matrix, IDOR spot-check | `security-testing` |
| Payment / checkout | <yes/no> | E2E happy path, PSP sandbox failure paths | `test-executor` + `test-automation` |
| File upload | <yes/no> | type/size validation, malicious-name handling | `security-testing` |
| Public / partner API | <yes/no> | contract + schema validation, auth, error shapes | `api-testing` |
| Email / notifications | <yes/no> | trigger fires, content correct | `test-executor` |
| Search / filtering | <yes/no> | boundary values, empty-result state | `test-automation` |
| i18n / multi-language | <yes/no> | locale switch, no hardcoded strings | `test-executor` |
| Accessibility-critical UI (external users) | <yes/no> | axe scan on changed pages, keyboard path | `accessibility-testing` |
| Visual / branding-critical | <yes/no> | screenshot baseline on changed views | `visual-testing` |
| Data export / GDPR | <yes/no> | export completeness, deletion honored | `test-executor` |
| Third-party integrations | <yes/no> | sandbox only, contract check | `api-testing` |

<!-- Add product-specific rows as needed. Keep the standard rows even when "no". -->

## Environments   (merge: replace-by-row, key = Environment name)

<!-- Omit this section entirely if the product uses the project's environments. -->

| Environment | URL | Purpose | Notes |
|---|---|---|---|
| stage | `<https://stage-<product>.example.invalid>` | all agent testing | <shared? rules> |

- **Version check on stage**: <method, if it differs from the project's>
- **Build verification**: <`required` | `unavailable` — omit to inherit. Use
  `unavailable` only when this product has no version source; every report then
  says `Build: unverified (project-configured)`. An observed mismatch still blocks.>

## Test users   (merge: add, key = Role — a product row replaces a project row of the same Role)

<!-- Omit if the product uses the project's users unchanged. Vault references only,
     never a password. Secret keys are DECLARED here and read literally — the agent
     never assembles one. A role that does not exist for this product:
     write `N/A — does not apply to this product` in the Purpose column. -->

- **Secrets source**: <`keychain` | `env-file` — omit to inherit the project's.
  Overrides where THIS product's keys are resolved from.>

| Role | Purpose | Vault path (relative) | Env/secret key |
|---|---|---|---|
| `<role>` | <purpose> | `<key>/<product>/<role>` | `<KEY>_<PRODUCT>_<ROLE>_PASSWORD` |

## Deploy runbook (stage)   (merge: replace — if present, the project runbook is ignored)

<!-- Omit unless this product deploys differently. "Agent may trigger deploy" is
     read from PROJECT.md ONLY — a product can never grant that permission. -->

1. <step>
2. <step>

- **Post-deploy verification**: <exact check for this product>

## Pipelines / quality gates   (merge: field-level, stricter only)

<!-- Omit unless different. Gates may only be TIGHTENED here, never loosened. -->

- **Relevant pipelines**: <names>
- **Gate overrides**: pass rate ≥ <n>%, P0 = 0, P1 ≤ <n>, coverage ≥ <n>%

## Reporting   (merge: field-level — transitions and report format are SEALED)

<!-- Omit unless the bug template or severity mapping differs. Transitions and
     report format are properties of the JIRA workflow and are read from
     PROJECT.md only — do not restate them here. -->

- **Bug template**: `projects/<KEY>/products/<PRODUCT>/templates/bug-report.md`

## Test assets   (merge: field-level)

<!-- Omit unless this product has its own suite or TC namespace. -->

- **Framework**: <playwright | webdriverio — omit to inherit the project's>
- **Suite**: <repo path/location, config file> — or "none yet"
- **App repo (optional, read-only)**: <local checkout, e.g. `../skp/` — when each
  product has its own repo, state it here and leave the project-level field
  "none">. Lets `failure-analysis` diff this product's version window.
- **TC categories**: <CAT, CAT — product-specific namespace>
- **Test data**: <seed/reset mechanism for this product>

## Gotchas   (merge: add — project gotchas always still apply)

Only stable, frequently needed product traps belong here: one compact durable
fact per bullet, merged with or replacing older wording rather than appended as
ticket history. Rare, keyword-searchable knowledge stays in `learnings.md`;
repro narratives and transient states stay in learnings/evidence.

- <product-specific trap 1>
- <product-specific trap 2>

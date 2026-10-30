# Memory Index

Curated table of contents for the blueprint's learning system — the **map to read
first** before touching anything else (llms.txt principle: one line per entry, so
lookups never require a full scan).

## Learnings (cross-project, Tier 2)

| File | Contents |
|---|---|
| `learnings/_inbox.md` | Capture bank: raw session findings awaiting grooming (Capture step of retro-learn) |
| `learnings/_rejected.md` | Retired/overruled learnings with reason + re-proposal condition — groom checks it before re-capturing (created on first rejection) |
| `learnings/selector-failures.md` | Unstable selectors and working alternatives (data-testid-first, paste-event traps) |
| `learnings/flaky-tests.md` | Known flakes, root causes, retry/quarantine strategies |
| `learnings/env-gotchas.md` | Environment pitfalls: caches, feature flags, sandboxes, shared-stage rules |
| `learnings/product-changes.md` | Confirmed deliberate behaviour changes that made a test case outdated (written on a human ruling only) |

## Projects (Layer 3)

| Directory | Contents |
|---|---|
| `projects/_template/` | Scaffold for `/onboard-project` — never a real project |
| `projects/_template/products/_template/` | Scaffold for `/onboard-product` — never a real product |
| `.claude/skills/scaffold-suite/templates/` | Playwright project scaffold (config = the capture matrix) |
| `projects/EXAMPLE/` | Fictional reference project "SHOP" (ACME Shop) — products: STOREFRONT, ADMIN; shows a completed project file plus the optional product layer |

One row per onboarded project, products listed inline:
`| SHOP | ACME Shop — products: STOREFRONT, ADMIN |`. Projects without products
keep a plain row — the product layer is optional (`.claude/rules/core/product-layer.md`).

## Rules — always loaded (the norms)

`.claude/rules/core/` is in the prompt of every session, so it holds only what must
bind before any skill is loaded. Measured cost: ~7.0k tokens including the router.

| File | Contents |
|---|---|
| `.claude/rules/core/qa-principles.md` | Test levels, AAA, P0–P4, DoD for "tested", risk-based ordering |
| `.claude/rules/core/token-discipline.md` | Lookup policy, grep-over-reading, subagent policy, context hygiene |
| `.claude/rules/core/product-layer.md` | Product routing ladder, merge precedence, sealed fields |
| `.claude/rules/core/evidence-policy.md` | Evidence schema, capture matrix, execution_summary.json fields |
| `.claude/rules/core/security.md` | Secrets-as-references, forbidden actions, stage safety |

## Rules — read on demand (the details)

`docs/rules/` is **not** auto-loaded. Each file names its trigger at the top; when
that topic comes up, reading it is not optional — the always-loaded rule carries the
norm, not the detail.

| File | Read it when |
|---|---|
| `docs/rules/testing/playwright-mcp.md` | driving the browser via MCP (snapshot mode, context rot, isolation) |
| `docs/rules/testing/playwright-cli.md` | writing/running specs (TC-IDs, retries, flake handling) |
| `docs/rules/testing/jira-confluence.md` | writing into JIRA/Confluence (ADF traps, transitions, attachments) |
| `docs/rules/core/cicd.md` | pipelines, quality gates, headless `claude -p` runs |
| `docs/rules/core/product-layer.md` | a routing was corrected, a ticket spans two products, or something needs naming |
| `docs/rules/core/security.md` | wiring a credential source, or changing/reviewing a hook |
| `docs/rules/core/token-discipline.md` | adding, removing or configuring an MCP server |
| `docs/rules/core/qa-principles.md` | auth/input/upload changes (OWASP smoke) or a specialised testing type |
| `docs/rules/core/evidence-policy.md` | the Stop hook blocked and you need its exact checks |

## Specialized skills (vendored, Layer 2)

10 skills adapted from [petrkindlmann/qa-skills](https://github.com/petrkindlmann/qa-skills)
(MIT) — see `.claude/skills/THIRD_PARTY_NOTICES.md` for provenance/versions.
`qa-manager` decides when a ticket needs one instead of the default
exploratory/regression flow.

| Skill | Contents |
|---|---|
| `.claude/skills/risk-based-testing/` | Impact×probability risk matrix, failure mode analysis |
| `.claude/skills/bug-reproduction/` | Verified minimal repro, git bisect, red-before-fix regression test |
| `.claude/skills/api-testing/` | REST/GraphQL testing, schema validation, contract patterns |
| `.claude/skills/accessibility-testing/` | WCAG 2.2, axe-core, screen reader, keyboard nav |
| `.claude/skills/security-testing/` | OWASP Top 10 + LLM, auth tests, dependency scanning/SAST |
| `.claude/skills/visual-testing/` | Screenshot regression, baseline management |
| `.claude/skills/test-reliability/` | Flaky-test root-causing, quarantine, locator resilience |
| `.claude/skills/qa-metrics/` | Coverage/flakiness/MTTR formulas, dashboards |
| `.claude/skills/test-case-management/` | Manual test cases in TestRail/Xray/Zephyr/Qase |
| `.claude/skills/release-readiness/` | Go/no-go checklists, smoke suite design, rollback criteria |

Bridge: these skills are global (apply to every onboarded project), but the
context they read is per-project: `.agents/qa-project-context/<KEY>.md`, a
projection of `projects/<KEY>/PROJECT.md` generated by `onboard-project` —
`PROJECT.md` stays the source of truth. One file per project, never shared
(see `CLAUDE.md` → project routing and `.claude/skills/THIRD_PARTY_NOTICES.md`).
Filled-in examples: `projects/EXAMPLE/qa-project-context.md` (project scope) and
`projects/EXAMPLE/qa-project-context-ADMIN.md` (product scope, pre-merged).

## Docs

| File | Contents |
|---|---|
| `evals/README.md` | Behavioral conformance runner (`bash evals/run.sh`); the norm→test matrix is `evals/COVERAGE.md` |
| `docs/pilot-briefing.md` | What to have ready for the first real onboarding, and what is known unfinished |
| `docs/quickstart-plugin.md` | Plugin on a fresh machine (JIRA + stage URL, no app repo) — all three wiring variants |
| `docs/architecture.md` | The five-layer concept and why it is token-efficient |
| `docs/artifact-strategy.md` | Evidence capture defaults, retention, PII, access |
| `docs/memory-layers.md` | Repo learnings vs auto memory; why no memory server is wired in |
| `docs/runbooks/stage-deploy-general.md` | Generic stage-deploy runbook scaffold |

## Usage rules

- Look here first; then read exactly the one file you need.
- New learning file or project → add a one-line entry here (part of grooming).
- Entries are promises: if a listed file is empty or stale, fix or remove the entry.

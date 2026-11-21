# Third-Party Notices

Ten skills in this directory originate from
[petrkindlmann/qa-skills](https://github.com/petrkindlmann/qa-skills)
(qa-skills.com), vendored at upstream commit `b3bb61bd268b147476252c6ed5a0440c87b97441`
under the MIT license below — thank you, Petr. They were selected as the
highest-impact subset for this blueprint's ticket-driven QA flow (see
`docs/architecture.md`) — the full upstream library has 50 skills covering a much
broader surface (email/payment testing, chaos engineering, contract testing, and
more) that this blueprint does not currently pull in.

> **Adapted for this blueprint's rules and purposes (0.12.x):** the bodies are no
> longer byte-identical with upstream. After a full review against the blueprint's
> norms, each skill was adjusted where upstream behavior would conflict with them —
> see the per-skill list below. The `description:` frontmatter of all vendored
> skills was additionally trimmed to ~300-400 characters already in 0.10.0
> (trigger keywords kept; descriptions ride in every session's system prompt).
> Consequence for updates: an upstream re-vendor is now a **manual merge** — diff
> upstream against the pinned commit, then re-apply the adaptations below, never
> copy-overwrite.

## What was adapted, per skill

| Skill | Upstream version | Why it's here | Blueprint adaptations |
|---|---|---|---|
| `bug-reproduction/` | 1.0 | Repro-before-fix discipline (bisect, determinism, red-before-fix) for `retest-bug` | Description trimmed 1140 → 1008 chars (opencode limit). Ticket writeback (`references/ticket-writeback.md`) routes through `report-to-jira`/`bug-report` — project report format, shadow mode, transitions from `PROJECT.md`, never direct ticket edits. Related-Skills section mapped to existing skills (`failure-analysis`, `test-automation`). |
| `risk-based-testing/` | 2.0 | Impact×probability risk matrix feeding strategy decisions | Risk matrix home is `projects/<KEY>/risk-matrix.md`, never the bridge file (a regenerated projection). Related-Skills mapped; flow-map/learnings named as phase-1 inputs. |
| `api-testing/` | — | REST/GraphQL testing — a gap this blueprint had zero coverage for | Secrets flow (`qa-secrets.mjs run`, env-by-key-name) and the stage-only anti-pattern. Contract-testing pointers reworded (Pact not vendored — propose as tooling). |
| `accessibility-testing/` | — | WCAG/axe-core testing | Related-Skills mapped; formal compliance documentation (VPAT/EAA) explicitly flagged as out-of-blueprint. |
| `security-testing/` | — | OWASP Top 10, deeper than the smoke check in `qa-principles.md` | `owasp-coverage.md` clarified as suite documentation (never a substitute for run evidence). ZAP/Semgrep **MCP** mentions annotated: not wired — this blueprint declares exactly two MCP servers (playwright, atlassian), CLI/CI paths are the way. LLM deep-testing handoff → "flag as proposal". |
| `visual-testing/` | — | Visual regression (Playwright screenshots, Percy/Chromatic/Argos) | Related-Skills mapped; cross-browser matrices and bulk baseline regeneration scoped. |
| `test-reliability/` | — | Flaky-test root-causing and quarantine, complements `memory/learnings/flaky-tests.md` | Repair evidence lands in the run's evidence dir; durable flake knowledge → `flaky-tests.md`. Ticket updates go via `report-to-jira` (shadow discipline). |
| `qa-metrics/` | — | Coverage/flakiness/MTTR formulas and dashboards | Scope note: run-level numbers come from `/qa-report` with its own denominators (PASS/decided runs); this skill's CI-based formulas are for wiring CI analytics. Description disambiguates against `/qa-report`. |
| `test-case-management/` | — | Manual test cases in TestRail/Xray/Zephyr/Qase — relevant since this blueprint is JIRA-based | Credentials never inline: all tool auth via `qa-secrets.mjs run <KEY…>` env injection (values never in commands/chat/files); writes follow shadow discipline. Graduation handoff → `test-automation`, with tool-key ↔ TC-ID mapping recorded. |
| `release-readiness/` | — | Go/no-go checklists, smoke suite design, rollback criteria | **Scope note added (the agent prepares, humans execute against production):** production/post-deploy smoke runs, rollback execution (kill switch, code/DB rollback), and prod verification commands are human/runbook work; the agent assembles evidence, checklists and the rollback plan, executes smoke against staging, and asks. Stage-only is the hard rule. |

All vendored skills: dangling upstream "Related Skills" pointers
(`contract-testing`, `playwright-automation`, `ai-test-generation`,
`selector-drift-recovery`, `qa-dashboard`, `coverage-analysis`,
`quality-postmortem`, `ai-bug-triage`, `test-planning`, `ci-cd-integration`,
`ai-system-testing`, `shift-left-testing`, `test-environments`, `database-testing`,
`ai-qa-review`, `cross-browser-testing`, `synthetic-monitoring`,
`testing-in-production`, `compliance-testing`, `test-strategy`,
`qa-project-context` the skill) were removed or mapped to the blueprint's
existing skills, so no reference leads into the void.

## Merged (not a straight copy)

| File | Source | What changed |
|---|---|---|
| `exploratory-testing/SKILL.md` | upstream `exploratory-testing/SKILL.md` (v2.0) | Charter model, HICCUPS/FEW HICCUPS heuristics, and the exploration-to-automation pipeline were merged into this blueprint's own skill (which delegates to the `test-executor` subagent) rather than kept as a separate skill, to avoid a name collision. |
| `exploratory-testing/references/heuristics-and-automation.md` | upstream, same path | Content vendored; the worked example marks its negative assertion as supplementary-only. |
| `exploratory-testing/references/session-templates.md` | upstream, same path | Vendored. |

## Bridging `.agents/qa-project-context.md`

The upstream skills expect a single shared context file at
`.agents/qa-project-context.md`. This blueprint routes multiple projects through
one repo (`projects/SHOP/`, `projects/ACME/`, ...), so a single shared file would
go stale the moment a second project is onboarded or tested — whoever invokes a
vendored skill next would silently read the *previous* project's data with no
error. Instead this blueprint keeps one bridge file **per project**, at
`.agents/qa-project-context/<KEY>.md`, generated by `onboard-project` as a
projection of `projects/<KEY>/PROJECT.md` + `learnings.md` — and, for projects that
have products, one **per product** at `.agents/qa-project-context/<KEY>/<PRODUCT>.md`,
written by `onboard-product` as a *pre-merged* projection (project base with the
product's deltas resolved). The vendored skills must never inherit anything
themselves: they read one flat, self-contained file. Both carry a `generated_from` /
`source_sha` frontmatter so `qa-manager` can verify freshness mechanically.

The skills' Discovery sections were adapted to name the keyed path directly; the
orchestration (`CLAUDE.md` → project routing, `qa-manager`, `retest-bug`)
additionally passes the correct `<KEY>` (or `<KEY>/<PRODUCT>`) file explicitly.
`PROJECT.md` (plus `PRODUCT.md`) stays the source of truth; regenerate a
projection when its sources change materially. See
`.claude/skills/onboard-project/SKILL.md` and
`.claude/skills/onboard-product/SKILL.md`.

## Updating

To pull a newer upstream version of a vendored skill, download the corresponding
`skills/<name>/` from the upstream repo at a chosen commit, diff upstream against
the pinned commit `b3bb61b`, and **merge**: re-apply the per-skill adaptations from
the table above and the description trim. Then update the commit reference in this
file. A copy-overwrite silently drops the blueprint adaptations — that is the one
thing never to do.

## License (MIT)

```
MIT License

Copyright (c) 2026 Petr Kindlmann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Agentic Playwright (MIT)

Selected material originates from
[idavidov13/agentic-playwright](https://github.com/idavidov13/agentic-playwright),
vendored at upstream commit `7d4ec4f3c410b8a733fdd0056ca268444354631a` under
the MIT license below — thank you, Ivan and contributors. The upstream notice
is preserved here and in the root `NOTICE`.

Adaptations are integrated into the blueprint rather than presented as an
unchanged upstream distribution. The concrete adapted surfaces and their
original upstream sources are:

| Blueprint path(s) | Original upstream source | Adaptation |
|---|---|---|
| `.claude/scripts/qa-test-code-scan.mjs`, `.claude/hooks/pre-test-code-scan.sh` | `.claude/scripts/enforce_constitution.py`, `.claude/settings.json` | The Constitution enforcement and write-time scanning pattern was rewritten as a blueprint quality scanner and `PreToolUse` hook, with blueprint rule IDs, configuration and evidence behavior. |
| `.claude/skills/scaffold-suite/templates/quality/` (including `.qa-test-quality.json`, `scan.mjs`, `tests/fixtures/{test,api,auth,data}.ts`, `tests/pages/EntryPage.ts`, `tests/support/env.ts`, and the seed/smoke specs) | upstream `fixtures/`, `pages/`, `config/`, `playwright.config.ts`, and `packages/create-agentic-playwright/` scaffold patterns | Fixture composition, page/environment separation and quality scanning were adapted into an opt-in blueprint quality pack; no upstream scaffold tree is copied wholesale. |
| `.claude/scripts/action-journal.py`, `docs/pipeline/action-journal.md`, `.claude/schemas/action-journal-*.schema.json`, `.claude/schemas/automation-handoff.schema.json`, `.claude/skills/scaffold-suite/templates/tests/fixtures/action-journal.ts`, `action-journal.wdio.cjs` | upstream `.claude/skills/ai-native-workflow/`, `.claude/skills/playwright-cli/references/test-generation.md`, and fixture/workflow patterns | Blueprint-specific journal, schema and documentation implementations preserve seed, intent, positive oracles, red checks and original verdicts for exploration-to-automation handoff. These are adapted workflow implementations, not vendored upstream files. |
| `.claude/scripts/healing-candidate.py`, `docs/pipeline/healing.md`, `.claude/schemas/healing-*.schema.json` | upstream `.claude/skills/debugging/`, `.claude/skills/selectors/references/feedback-selectors.md`, and `.claude/skills/ai-native-workflow/` | Candidate-only locator healing, intent-fidelity review and negative-control verification were implemented for the blueprint without automatic application. These are adapted workflow implementations, not vendored upstream files. |
| `evals/lib/artifact_checks.py`, `evals/lib/runner_policy.py`, `evals/*/graders/checks.json` | upstream `.claude/skills/ai-native-workflow/evals/evals.json` and its deterministic eval structure | Declarative JSON-pointer checks, workspace before/after comparisons and explicit result grading were adapted for the blueprint's behavioral eval runner and fixtures. |

Related API-contract provenance, immutable snapshot drift review, explicit
unavailable-contract behavior, schema-v2 run/result normalization, not-run and
retry-pass semantics, run-relative artifact hashes and evidence summaries also
adapt upstream workflow ideas to the blueprint's contracts.

All of these adaptations apply the blueprint's routing, stage-only execution,
shadow reporting, evidence, secret-handling and dual-harness contracts.

```
MIT License

Copyright (c) 2026 Ivan Davidov and Agentic Playwright contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

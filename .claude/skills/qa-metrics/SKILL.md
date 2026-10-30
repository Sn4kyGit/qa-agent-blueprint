---
name: qa-metrics
description: >-
  Define, track, and act on QA metrics: coverage %, flakiness rate, defect escape
  rate, MTTR, execution time trends, automation ROI, quality gates, SLAs — with
  formulas, realistic targets, and the action when a metric goes red. Use when:
  QA metrics, test metrics, quality KPIs, test health, flakiness rate, defect
  escape rate. Not for dashboard UIs, coverage-gap/mutation analysis, or
  aggregating this blueprint's run evidence — that is /qa-report.
license: MIT
metadata:
  author: kindlmann
  version: "2.0"
  category: metrics
---

<objective>
A suite with 4,000 tests where 800 are disabled and 200 are flaky looks healthy on a slide and lies in production. This skill defines the metrics that actually change behavior — each one with a formula, a target, an owner, and a concrete action when it goes red — so the dashboard becomes a feedback loop instead of decoration.
</objective>

> **Blueprint scope — these formulas are for wiring CI/tool analytics, not for this
> blueprint's own run evidence.** Numbers about the blueprint's test runs (pass rate,
> flake rate, routing quality, learning throughput) come from `/qa-report`, which
> aggregates `execution_summary.json` with its own, deliberately different
> denominators (PASS / decided runs; BLOCKED and NO_TEST excluded; flake = pass-on-retry
> per case, not per run). When both exist in one conversation, `/qa-report` is the
> source of truth for run data, this skill for definition and target-setting. Metrics
> the evidence schema cannot feed (defect escape rate, code coverage) are exactly the
> ones `/qa-report` prints as "not computable" — they need the CI/tracker data sources
> this skill describes.

## Quick Route

| Your situation | Metric to reach for | Section / reference |
|---|---|---|
| No metrics yet, where to start | code coverage, flakiness, defect escape | Core Principles + `references/rollout.md` |
| Bugs escaping despite high coverage | defect escape rate + mutation score | Coverage Metrics, Defect Metrics |
| Tests flaky, devs ignore CI | flakiness rate, pass rate | Test Health Metrics |
| Slow pipeline, stale feedback | suite duration, parallelism efficiency | Execution Metrics |
| Justifying automation spend | automation ROI | Process Metrics |
| Picking targets for our stage | company-stage table | Setting Realistic Targets |
| Leadership wants delivery + quality | DORA + escape rate | Engineering Quality Metrics (DORA) |
| Building the dashboard view | (a dashboard UI is out of this blueprint's scope — this skill defines what to measure) | — |

---

## Discovery Questions

Check the project bridge file `.agents/qa-project-context/<KEY>.md` first — if it exists, use it as the foundation and skip anything already answered there. Then:

### Current State
- What metrics are you tracking today? (Even "we glance at CI pass rate sometimes" counts.)
- Where does your test data live? (CI system, coverage reports, bug tracker, spreadsheets, nowhere)
- Do you have any dashboards already? Who looks at them, and how often?
- What tooling runs your CI pipeline? (GitHub Actions, GitLab CI, Jenkins, CircleCI)

### Stakeholders
- Who are the stakeholders for quality metrics? (engineering, product, leadership, customers)
- What does each care about? Engineers want flakiness; leadership wants escape trends; product wants release confidence.
- Who will own each metric? If nobody owns it, nobody acts on it.

### Quality Problems
- What quality problems need visibility? (regressions, slow pipelines, flaky tests, coverage gaps, incidents)
- What broke in production recently? Would a metric have caught it earlier?
- What decisions are you making without data today?

### Goals
- What does "healthy test suite" mean for your team?
- Any compliance or contractual quality requirements? (SLAs, SOC2, ISO)
- Quick wins vs. full observability — what is the appetite for metrics infrastructure?

---

## Core Principles

### 1. Metrics Should Drive Action, Not Just Dashboards
A metric without an action plan is decoration. For every metric, define: what threshold triggers action, what the action is, and who takes it. If flakiness crosses 5%, the on-call engineer investigates the top 3 flaky tests that week. No ambiguity.

### 2. Leading vs Lagging — Track Both, Act on Leading
Defect escape rate and MTTR are **lagging**: you learn after users were hurt. Flakiness, coverage delta, and skipped-test count are **leading**: they predict escapes before they happen. Lagging metrics tell leadership whether quality is moving; leading metrics are where engineers spend their daily attention because they can still change the outcome.

### 3. Trend Over Snapshot
A single number is nearly useless. Coverage at 72% means nothing; coverage trending 68% → 72% over three sprints tells a story. Display metrics as time series and evaluate direction, not absolute position.

### 4. Every Metric Needs a Target and an Owner
A target makes a metric actionable; an owner makes it accountable. Without both it becomes background noise. Set targets from your team's maturity (see the targets table) and assign owners who can actually move the number.

### 5. Vanity Metrics Waste Everyone's Time
"We have 4,000 tests" sounds impressive until 800 are disabled and 200 flaky. Count what matters: tests that run, pass reliably, and catch real bugs. The ultimate metric is whether users hit bugs that hurt the business — work backward from there. Defect escape rate connects directly to user experience; lines of test code connects to nothing.

---

## Essential QA Metrics

| Category | Key Metrics | Formula / Target |
|---|---|---|
| Coverage | Test coverage %, requirement coverage % | automated tests / total tests; covered ACs / total ACs |
| Health | Flakiness rate, test maintenance cost | flaky runs / total runs; hours spent on test fixes |
| Defects | Defect escape rate, detection rate, MTTR | escaped / total; found-in-test / total; mean time to resolve |
| Execution | Pass rate, execution time, automation rate | passed / total; avg duration; automated / total |
| Process | DORA (deploy freq, lead time, change fail %, MTTR) | see references/ for thresholds |
| Impact | TIA (test impact analysis) | tests affected by change / total tests |

Every metric needs a target, an owner, and an action when it goes red.
Full definitions, formulas, targets, and red-actions:
`references/metrics-catalog.md`.

## Setting Realistic Targets

Targets should match your team's maturity. Chasing enterprise metrics at a seed startup wastes effort.

| Metric | Startup (seed-Series A) | Growth (Series B-C) | Enterprise (public/large) |
|---|---|---|---|
| Unit test coverage | 60% | 75% | 85% |
| Branch coverage | 45% | 60% | 75% |
| E2E coverage (critical paths) | Top 5 flows | Top 15 flows | All P0/P1 flows |
| Flakiness rate | <5% | <3% | <1% |
| Pass rate (7-day) | >90% | >95% | >98% |
| Defect escape rate | <20% | <10% | <5% |
| MTTR (P0) | <8 hours | <4 hours | <2 hours |
| CI pipeline duration | <20 min | <15 min | <10 min |
| Automation rate | 50% | 75% | 90% |
| Metrics tracked | 3-5 core | 8-10 with dashboards | Full suite with alerting |

**Progression path:**
1. Start with 3 metrics: code coverage, flakiness rate, defect escape rate.
2. Add execution metrics when CI cost or speed becomes a pain point.
3. Add process metrics when the team grows beyond 5 engineers.
4. Add the full suite when quality is a product differentiator or compliance requirement.

For the full phased rollout (week-by-week), the three dashboard layouts, and the data-source extraction table, see `references/rollout.md` and `references/dashboards.md`.

---

## Anti-Patterns

- **Treating coverage as quality proof.** Coverage measures execution, not verification. Pair with mutation testing for truth.
- **Metrics without context.** "Coverage is 74%" is meaningless without target (80%), trend (up from 69%), and distribution (92% critical paths, 40% admin). Always present with target, trend, and breakdown.
- **Gaming metrics.** Trivial tests to hit coverage numbers. Counter by pairing coverage with defect escape rate — if coverage is high but defects escape, the tests lack teeth.
- **Too many metrics.** Tracking 25 means acting on none. Start with 3. Only add a metric when you can articulate the action it triggers.
- **Measuring without acting.** A Grafana dashboard nobody opens. If a metric does not trigger action at least once per quarter, retire it (the metric half-life check in `references/rollout.md`).
- **Comparing across teams.** Coverage in a payment service vs. an admin tool is not comparable. Track improvement over time, not cross-team rankings.

---

## Verification

The whole point is a working feedback loop — prove the data actually flows before declaring done:

1. **Coverage emits machine-readable output.** Run your coverage tool and confirm it writes JSON/LCOV (`coverage/coverage-final.json`, `lcov.info`) — not just an HTML report a human reads.
2. **CI history is queryable.** Hit your CI provider's API for the last 7 days of run results and confirm you can compute pass rate and flakiness from it.
3. **Escape labels exist.** Query the issue tracker for the `escaped-defect` (or equivalent) label and confirm at least the tagging convention is in place.
4. **A gate actually blocks.** Open a throwaway PR that drops coverage or adds a `.skip` and confirm CI fails it — a gate that never fires proves nothing.

---

## Done When

- Key metrics are defined with explicit formulas: coverage % (line and branch), flakiness rate, defect escape rate, and MTTR by severity.
- Baseline values are established for each metric from at least 2 weeks of collected data, with targets set per the company-stage table.
- Data collection is automated via CI integrations (coverage from test runner, flakiness from CI run history, defects from issue-tracker labels) — no manual steps.
- Quality gates are configured in CI to block merges or deployments when flakiness exceeds threshold, coverage drops, or critical tests fail (verified by a failing throwaway PR).
- Each metric has a named owner, and a metrics block exists in the recurring retro template (or a standing calendar invite) — a checkable artifact, not just an intention.

## Reference Files (in `references/`)

- **dashboards.md** — the engineering (daily), leadership (monthly), and sprint-health dashboard layouts, plus the release-confidence-score example weighting.
- **rollout.md** — the four-phase week-by-week implementation plan, the data-source extraction table, and the metric half-life retirement practice.

## Related Skills

- **qa-report** — the blueprint's own aggregator over `evidence/`; the source of truth for
  run-level numbers (pass rate, routing quality, learning throughput). This skill defines the
  metrics and targets; qa-report computes what the evidence can feed.
- **release-readiness** — consumes quality gates and DORA Change Failure Rate / Failed Deployment Recovery Time for go/no-go decisions.
- **test-reliability** — runtime per-test healing for the flaky tests the flakiness rate flags.
- The bridge file `.agents/qa-project-context/<KEY>.md` feeds targets and baselines into metrics tracking.

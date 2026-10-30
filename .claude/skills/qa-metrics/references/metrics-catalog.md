# Essential QA Metrics — Full Catalog

Read this when defining or reviewing QA metrics for a project.

## Essential QA Metrics

Each metric: definition, formula, recommended target, why it matters, and the action when it goes red.

### Test Coverage Metrics
*How much of our system is verified by automated tests?* (leading)

#### Code Coverage Percentage
The percentage of code exercised by automated tests (line, branch, or statement level).

```
Line coverage   = (lines executed by tests / total executable lines) × 100
Branch coverage = (branches executed by tests / total branches) × 100
```

**Targets:** Line: 70-85% for app code. Branch: 60-75%. Critical paths (payments, auth): 90%+.

**Why it matters:** Coverage identifies blind spots — code never exercised by tests is where bugs hide undetected.

**When it goes red:** Coverage drops on PR: block merge or flag. Low in critical module: create targeted tasks. Plateaus: check for dead code vs. genuinely untested logic.

**Warning:** Coverage measures execution, not assertion quality. Pair it with mutation testing (StrykerJS v9.6+, mutmut) for a truer picture. Stryker's Vitest runner tracks recent Vitest releases — check the runner's peer-dependency before pinning a Vitest version. Use `incremental: true` in monorepo CI to keep mutation runs cheap. Deep coverage/mutation analysis tooling is not vendored in this blueprint — propose it when mutation scores become a gate.

#### Requirement Coverage Percentage
```
Requirement coverage = (features with at least one test / total features) × 100
```
**Targets:** 100% for P0/P1 features, 80%+ for P2.

**Why it matters:** A feature can have zero tests even if surrounding code is well-covered. Use test tags (`@feature:checkout`, `@story:PROJ-1234`) for traceability.

#### Risk Coverage Percentage
```
Risk coverage = (high-risk areas with automated tests / total high-risk areas) × 100
```
**Targets:** 95%+ for high-risk areas. Maintain a risk register and cross-reference against coverage data per module.

---

### Test Health Metrics
*Can we trust our test suite?* (leading)

#### Flakiness Rate
The percentage of test runs producing inconsistent results without code changes.

```
Flakiness rate = (test runs with flaky results / total test runs) × 100
```

**Targets:** Acceptable: <2%. Warning: 2-5%. Critical: >5%.

**Why it matters:** Flaky tests erode trust. Once developers think "probably just flaky," they stop paying attention to results at all. Flakiness is the single biggest threat to a suite's credibility.

**When it goes red:** Quarantine flaky tests immediately. Investigate the top 3 weekly — most flakiness comes from a small number of tests. Common causes: timing/race conditions, shared state, external dependencies, order-dependent tests. Tests flaky for 30+ days should be deleted or rewritten.

**Detection:** Buildkite Test Analytics, **Datadog Test Optimization** (formerly Datadog CI Visibility — ships Flaky Test Management, Auto Test Retries, Early Flake Detection, Failed Test Replay, and Test Impact Analysis; its Bits AI Dev Agent can auto-open PRs to fix flaky tests), Trunk Flaky Tests, or a script comparing results across runs on the same commit.

#### Pass Rate Trend (7-Day Rolling)
```
Pass rate = (green CI runs / total CI runs) × 100  [rolling 7 days]
```
**Targets:** Healthy: >95%. Warning: 90-95%. Broken: <90%.

The 7-day rolling average smooths daily noise and reveals the real trend. A consistently red build means developers ignore the pipeline.

#### Disabled and Skipped Test Count
Total tests marked `skip`, `disabled`, `pending`, `xit`, `xdescribe` or equivalent.

**Target:** Trend toward zero. Skipped tests older than 2 sprints: fix or delete. Add a CI step that fails if skipped count exceeds 5% of total tests.

**Why it matters:** Skipped tests are invisible coverage gaps. A suite with 500 passing and 150 skipped tests has a `150 / (500 + 150) = 23%` gap that dashboards hide.

#### Test Suite Duration
Wall-clock time from suite start to completion.

**Targets:** Unit: <5 min. Integration: <10 min. E2E: <15 min. Full pipeline: <30 min (the stage targets are the real budget; <30 min is the sum, not a separate looser bar).

**Why it matters:** Slow tests break the feedback loop. 45-minute results mean developers have already context-switched.

**When it goes red:** Profile slowest tests (10% often account for 50% of runtime). Increase parallelism. Move slow tests post-merge. Check for unnecessary setup/teardown. Plot duration over time and alert on step changes (>20% increase in a week).

---

### Defect Metrics
*Are we catching bugs before users do?* (lagging)

#### Defect Escape Rate
The percentage of defects found in production relative to all defects found.

```
Defect escape rate = (defects found in production / total defects found) × 100
```

**Targets:** Excellent: <5%. Acceptable: 5-10%. Needs work: 10-20%. Critical: >20%.

**Worked example:** A release surfaces 15 total defects, 2 of them in production → `2 / 15 × 100 = 13.3%` escape rate, which lands in "needs work."

**Why it matters:** The single most important quality metric. It directly measures whether testing catches bugs before users do.

**When it goes red:** Classify escaped defects by layer (unit? integration? E2E? review?). Write a retrospective test for each. Identify if escapes cluster in specific areas — those need targeted investment.

**How to track:** Tag production bugs (`escaped-defect` label). Count escaped vs. pre-release defects at sprint retros.

#### Mean Time To Resolution (MTTR)
```
MTTR = sum(resolution_time for each defect) / number of defects
```
**Targets:** P0: <4 hours. P1: <24 hours. P2: <1 sprint. P3: <2 sprints.

High MTTR often signals process bottlenecks (slow review, unclear ownership, complex deploys) rather than technical difficulty. Break into phases (triage, assign, fix, deploy) to find the bottleneck. (This is your QA *defect* resolution time — distinct from the DORA recovery metric below.)

#### Defect Density
```
Defect density = defects found / KLOC  (or per feature shipped)
```
**Targets:** Track your own baseline; industry benchmarks are 1-10 defects per KLOC. If one module has 5x the density of others, it needs refactoring or better coverage.

#### Severity Distribution
Healthy: P0 <5%, P1 10-15%, P2 40-50%, P3 30-40%. Visualize as a stacked bar over time. Heavy P0/P1 concentration means testing misses critical issues.

---

### Execution Metrics
*Is our CI pipeline fast, reliable, and cost-effective?* (leading)

#### CI Pipeline Duration
Total wall-clock time by stage. **Targets:** Lint: <2 min. Unit: <5 min. Integration: <10 min. E2E: <15 min. Full: <30 min (= sum of stages above, reconciled with the suite-duration budget).

**When it goes red:** Optimize the slowest stage first. Split fast checks (every push) from slow checks (PR merge). Profile setup time vs. execution time. Parallelize sequential stages.

#### CI Cost Per Run
```
CI cost per run = (compute minutes × cost per minute) + fixed costs
```
50 builds/day at $0.50 each = $750/month. Optimize by caching dependencies, using spot instances, right-sizing runners, and skipping unchanged suites.

#### Parallelism Efficiency
```
Parallelism efficiency = (total sequential time / (wall-clock time × workers)) × 100
```
**Target:** >80%. Example: 4 workers finishing in 3, 3, 3, and 12 minutes → wall-clock 12, sequential total 21, so efficiency = `21 / (12 × 4) = 44%` — well under target because three workers idled 9 minutes each. Fix by splitting by estimated duration (not file count), breaking up slow test files, and using dynamic splitting (Playwright sharding, Jest `--shard`).

---

### Process Metrics
*Is our QA process improving over time?* (mix of leading and lagging)

#### Automation Rate
```
Automation rate = (automated test cases / total test cases) × 100
```
**Targets:** Regression: 90%+. Smoke: 100%. Exploratory: 0% (by definition). Overall: 70-85%.

Manual testing does not scale. Automation compounds — once written, a test runs thousands of times. Automate the most frequently executed scenarios first.

#### Test Creation Velocity
New automated tests added per sprint (net new, excluding refactors).

**Target:** At least 3-5 automated tests per user story shipped. A sprint with 20 features and 0 new tests signals a growing coverage gap.

#### Automation ROI
```
Manual cost     = (manual time per cycle × cycles per year) × hourly rate
Automation cost = (write time + annual maintenance) × hourly rate
ROI             = (manual cost - automation cost) / automation cost × 100
```
**Example:** Manual regression: 8 hrs/release × 26 releases × $75/hr = $15,600/yr. Automation: 120 hrs to write + 40 hrs/yr maintenance × $75/hr = $12,000 year 1, $3,000/yr after. Year 1 ROI: `(15,600 - 12,000) / 12,000 = 30%`. Year 2 ROI: `(15,600 - 3,000) / 3,000 = 420%`. Use this to justify investment to stakeholders.

---

### Engineering Quality Metrics (DORA)

DORA metrics are the standard vocabulary for leadership delivery dashboards. They pair with defect escape rate — DORA tracks delivery throughput; QA metrics track delivery quality.

| Metric | What it measures | Benchmark (top-15%) |
|--------|------------------|---|
| **Lead Time for Changes** | Commit → production | < 1 day |
| **Deployment Frequency** | How often you ship | Multiple per day |
| **Failed Deployment Recovery Time** (formerly MTTR) | Time to restore service after a *change-induced* failure | < 1 hour |
| **Change Failure Rate** | % of deploys that cause incidents | ~5% (older "high performer" bar was <15%) |
| **Rework Rate** | % of deploys that are unplanned fixes for a prior bad deploy | Low and falling |

DORA 2025 formalized **Rework Rate** as the fifth metric and regrouped the set: the first three above are *throughput* (recovery time moved here because fast teams just ship the fix), Change Failure Rate + Rework Rate are *instability*. **Reliability** (availability, latency, error budget against your SLOs) is tracked alongside as a separate dimension — it is where QA/escape framing meets SRE, since error rate and availability are the user-facing tail of escaped defects. DORA 2025 also retired the named Elite/High/Medium/Low tiers in favor of percentile distributions and seven team archetypes — read the column as a percentile benchmark, not a tier you "are." The **Failed Deployment Recovery Time** rename (2023/2024 reports) separates change-induced failures from external outages; it is a delivery metric distinct from your QA defect MTTR above.

Source: https://dora.dev/research/. Tools that surface DORA from Git/CI data: Sleuth, Faros, LinearB, Jellyfish, Swarmia.

### Test Impact Analysis (TIA) as a Lever

TIA selects which tests to run based on which code changed (using coverage data). It trades test breadth for CI cost. Track:

- **% of tests skipped per PR via TIA** — higher means cheaper CI; if it climbs without coverage falling, TIA is paying off.
- **Escaped defects from skipped tests** — the safety check. If non-zero, narrow the TIA selection or expand the always-run set.

Hosted: Datadog Test Optimization (TIA), CloudBees Smart Tests, NCrunch (in-IDE). Self-built: derive from coverage data + git diff.

---


---
name: release-readiness
description: >-
  Evidence-based release go/no-go: checklists, smoke test suite design, staged
  rollout validation, rollback criteria and procedures, post-deployment
  verification. Use when: release ready, go/no-go, smoke test, release checklist,
  rollback plan, staged rollout, canary deploy. Not for rollout-time techniques
  (flags, dark launch), continuous synthetic probes, or prod-telemetry test design.
license: MIT
metadata:
  author: kindlmann
  version: "2.0"
  category: process
license: Apache-2.0
---

<objective>
"I think it's fine" ships the bug that the rollback you never practiced can't undo at 6 PM on a Friday. This skill turns "ready to ship" into something measurable: a go/no-go checklist with evidence for each item, a sub-5-minute smoke suite, a staged rollout with metric-gated promotion, rollback thresholds defined before deploy, and post-deployment verification. Every section gives concrete criteria, not aspirations.
</objective>

> **Blueprint scope — the agent prepares, humans execute against production.**
> In this blueprint the agent assembles go/no-go EVIDENCE, checklists, smoke-suite
> designs, promotion criteria, and the rollback PLAN. Execution against production —
> production/post-deploy smoke runs, the rollback itself, post-deploy verification
> commands — is performed by a human or the project's runbook automation, never by
> the agent. Stage-only is the hard rule (`.claude/rules/core/security.md`): if a
> ticket demands production execution, report BLOCKED and ask. Smoke execution
> against **staging** stays allowed. Every "run this" below reads as "the agent
> prepares this and hands it to the human/runbook."

---

## Discovery Questions

Check the project bridge file `.agents/qa-project-context/<KEY>.md` first — if it exists, use it and skip anything answered there. Then ask only what's missing.

**Release cadence and process:**
- How often do you release, and who makes the go/no-go call? (Continuous/daily/weekly vs engineering lead/QA lead/release manager — sets how heavyweight the checklist should be.)
- Is there a release train schedule or is it ad-hoc?
- How many environments exist between dev and production? (staging, pre-prod, canary)

**Current state:**
- What does the current go/no-go process look like, and is it documented?
- Has a release ever been rolled back? How long did it take? (Reveals whether rollback is real or aspirational.)
- What was the last release incident and its root cause? Any release-blocking bugs right now?

**Infrastructure and capabilities:**
- Do you have rollback capability, and how long does a rollback take?
- Can you do staged/canary deployments?
- Do you have feature flags, and how are they managed? (Decides flag-based vs infra-level rollout.)
- What monitoring and alerting is in place? Are database migrations reversible?

**Team and communication:**
- Who is on-call during and after releases?
- How are stakeholders notified, and is there a release communication channel?
- How are release notes generated?

---

## Core Principles

### 1. Release confidence comes from evidence, not feelings
"I think it's fine" is not a go/no-go criterion. Evidence means: all CI pipelines green, smoke tests pass on staging, performance budgets met, no open P0/P1 bugs. If you can't point to data, you're not ready.

### 2. Smoke tests are the last safety net, not the only safety net
Smoke tests catch catastrophic failures. They are not a substitute for thorough testing throughout the development cycle. If your smoke test suite is the only thing between you and production, you have a process problem upstream.

### 3. Staged rollouts reduce blast radius
Deploying to 100% of users simultaneously means 100% of users are affected by any bug. Staged rollouts (canary, percentage-based, ring-based) let you catch issues when they affect 1% of users instead of all of them.

### 4. Rollback criteria must be defined BEFORE release
If you wait until something is on fire to decide whether to roll back, you'll waste critical minutes debating. Define the criteria in advance, relative to baseline: "If error rate exceeds 2x baseline within 15 minutes, we roll back. No discussion needed." Tie the trigger to your DORA targets — a release whose error rate would push you past your change-failure-rate target, or whose recovery would blow your MTTR target, is one the rollback rule exists to stop.

### 5. Every release is a learning opportunity
Post-deployment verification isn't just about catching bugs. Track what went well, what was slow, what was stressful. Improve the process continuously.

---

## Go/No-Go Checklist

Use this as a template. Adapt it to your context. Every item should be verifiable with evidence, not just "I checked." Store the completed checklist as a versioned artifact (e.g. `RELEASE-<version>.md` or a tracked issue) so sign-off is auditable.

### Automated Checks (Must Pass)

- [ ] **All CI pipelines green** — Unit tests, integration tests, E2E tests, type checking, linting
- [ ] **Smoke test suite passes on staging** — Critical user journeys verified in the staging environment
- [ ] **No open P0/P1 bugs for this release** — Check issue tracker, filter by milestone/label
- [ ] **Performance budgets met** — API response times and bundle size within thresholds; Lighthouse CI for frontend releases (skip Lighthouse for API/backend-only releases — it measures page load, not service health)
- [ ] **Security scan clean** — No high/critical vulnerabilities in `npm audit` / Snyk / Dependabot
- [ ] **API contract tests pass** — No breaking changes to public APIs
- [ ] **Visual regression tests pass** — No unintended visual changes
- [ ] **Accessibility checks pass** — axe-core scan shows no new violations

### Manual Checks (Verify Before Go)

- [ ] **Feature flags reviewed** — Document which flags are enabled/disabled in this release; confirm flag states for production
- [ ] **Monitoring and alerts configured** — New features have corresponding alerts (error rate, latency, business metrics)
- [ ] **Rollback plan documented and tested** — Written procedure exists; rollback has been practiced on staging
- [ ] **Database migrations tested** — Tested forward migration; backward migration verified if schema change is reversible
- [ ] **Third-party dependency changes reviewed** — New or upgraded external dependencies checked for breaking changes
- [ ] **Release notes prepared** — Changelog updated, stakeholder-facing summary written
- [ ] **On-call engineer identified** — Named person is available and has context on the release contents
- [ ] **Communication plan ready** — Stakeholders know the release is happening; support team briefed on changes
- [ ] **No conflicting releases** — Other teams aren't deploying simultaneously
- [ ] **Deploy window confirmed** — Not deploying during peak traffic or before a weekend (unless continuous deployment)

### Risk Assessment

- [ ] **Change scope categorized** — Small (config change, copy update), Medium (new feature, refactor), Large (architecture change, migration)
- [ ] **Blast radius estimated** — What percentage of users could be affected if something goes wrong?
- [ ] **Revert complexity assessed** — Can this be reverted in <5 minutes? Does reverting require a data migration?

---

## Smoke Test Suite Design

### What to Include

Smoke tests cover **critical user journeys only**. If these fail, the application is fundamentally broken.

**Typical smoke test suite (5-8 tests):**

1. **Application health** — Homepage loads, returns 200, no JavaScript errors in console
2. **Authentication** — User can log in with valid credentials, session is established
3. **Core workflow** — The primary value-delivering action works (e.g., create a document, submit a form, add to cart or complete a purchase flow)
4. **Data retrieval** — Key data loads correctly (dashboard populates, search returns results, product page loads)
5. **Payment/transaction** (if applicable) — Payment flow completes with test credentials
6. **API health** — Primary API endpoints return valid responses with correct schemas
7. **Navigation** — Critical navigation paths work (deep links, redirects, menu items)
8. **Error handling** — Application shows a user-friendly error page for invalid routes (404)

### What NOT to Include

- Edge cases (those belong in regression tests)
- Visual perfection (that belongs in visual regression tests)
- Performance benchmarks (that belongs in performance tests)
- Exhaustive form validation (that belongs in unit/integration tests)

### Keeping It Fast

Target: **under 5 minutes** for the entire smoke suite.

- Run tests in parallel where possible
- Use API calls instead of UI interactions for setup (create test user via API, not through registration form)
- Skip non-critical assertions (don't check exact copy text, check that elements exist)
- Use a dedicated test account with pre-created data (don't create data from scratch each run)
- Avoid unnecessary waits — use smart waiting (wait for element, not `sleep(3000)` / `waitForTimeout`)

### Environment-Specific Smoke Tests

**Staging smoke tests:**
- Full smoke suite (all 5-8 tests)
- Can use test payment providers
- Can test with feature flags in upcoming release configuration
- Can test database migrations

**Production smoke tests (designed here, executed by a human or runbook automation):**
- Subset of staging smoke tests (3-5 tests)
- Use synthetic test accounts (clearly labeled, won't affect analytics)
- Never test with real payment transactions (use sandbox mode or skip)
- Focus on: app loads, auth works, core read operations work, API responds

**Post-deployment smoke tests (the agent assembles the suite and the run instructions; a human or the project's automation runs them and reports back):**
- Run immediately after deploy completes (within 60 seconds)
- Same as production smoke tests
- If any fail, trigger alert and begin rollback evaluation — the agent evaluates the evidence and recommends; the rollback decision and execution are human

Staging is not production: it has different data volumes, traffic patterns, third-party configurations, and infrastructure scale. That gap is exactly why production and post-deployment smoke tests exist on top of staging verification — as a designed artifact the agent hands off, not something the agent runs.

---

## Staged Rollout Validation

Progressive rollout: 1% → 5% → 25% → 50% → 100%, monitoring error rates,
latency, and business metrics between each stage. Automated promotion criteria
must be defined before release. Feature flags enable gradual rollout with
instant rollback.

Full rollout stages, monitoring checklist, promotion criteria, and feature-flag
patterns: `references/rollout-and-rollback.md` → "Staged Rollout Validation".

## Rollback Criteria and Process

Define rollback triggers BEFORE release (automated: error rate, latency,
health checks; manual: business metric anomalies). Rollback procedure: disable
feature flag or redeploy previous version, verify recovery, communicate.

Full trigger thresholds, step-by-step rollback procedure, and data
considerations: `references/rollout-and-rollback.md` → "Rollback Criteria
and Process".

## Post-Deployment Verification

### Immediate (0-15 minutes)

- [ ] Production smoke tests pass
- [ ] Error rate is at or below pre-deployment baseline
- [ ] No new exception types in error tracker
- [ ] Health check endpoints return healthy
- [ ] Key pages load correctly (spot check 2-3 pages manually)

### Short-term (15 minutes - 2 hours)

- [ ] Synthetic monitoring confirms all critical paths working
- [ ] Error rate trend is flat or declining (not increasing)
- [ ] P50 and P95 latency are within expected range
- [ ] No increase in support ticket volume
- [ ] Business metrics (conversions, revenue, signups) are normal
- [ ] No memory leaks or resource exhaustion trends

### Medium-term (2-24 hours)

- [ ] Overnight batch jobs complete successfully (if applicable)
- [ ] No time-zone-dependent issues surfacing as other regions wake up
- [ ] Email/notification delivery is normal
- [ ] Third-party integrations are functioning
- [ ] No gradual performance degradation

---

## Anti-Patterns

Avoid: "it worked on staging", no rollback plan, Friday afternoon deploys,
skipping smoke tests, big-bang releases, no post-deployment verification,
rollback aversion, feature flag accumulation, lying canary alerts, and
switchback experiments for two-sided systems.

Full anti-pattern descriptions and mitigations:
`references/rollout-and-rollback.md` → "Anti-Patterns".

## Verification

These run immediately after the deploy completes, smallest check first — executed
by a human or the project's runbook automation against production; the agent
prepares this checklist (and can run the same checks against **staging**). Expand
the error-tracker queries in `references/rollout-automation.md`.

```bash
# Health endpoint returns healthy
curl -s https://your-app.com/health | jq .

# Response time + status in one shot
curl -o /dev/null -s -w "HTTP %{http_code} in %{time_total}s\n" https://your-app.com

# New errors since deploy (Sentry CLI) — should be empty
sentry-cli issues list --project your-project --query "firstSeen:>15m"

# Datadog: compare 5xx count for the service before vs after deploy — must not increase
```

Pass criteria: health returns `healthy`, status is `200` within your latency budget, the Sentry query returns no new issues, and the post-deploy 5xx count is at or below the pre-deploy baseline.

---

## Done When

- Go/no-go checklist completed with evidence for each item and stored as a versioned artifact (e.g. `RELEASE-<version>.md` or a tracked issue), signed off by the named approver with a timestamp
- Smoke test suite run against the release candidate in staging — all tests pass (exit code 0)
- Rollback criteria documented as specific baseline-relative thresholds, and the rollback procedure practiced on staging at least once
- Staged rollout plan defined with traffic percentages, per-stage promotion criteria, and guardrail metrics for each stage
- Post-deployment verification commands run and passing (health 200, no new Sentry issues, 5xx count at or below baseline)

## Reference Files (in `references/`)

- **rollout-automation.md** — Automated canary→10%→50%→100% promotion criteria (baseline-relative) and post-deployment verification command snippets.
- **communication-templates.md** — Load when writing a release or rollback announcement: fill-in-the-blank release and rollback templates.

## Related Skills

- `qa-metrics` — Source of the DORA evidence (change failure rate, MTTR) and error/pass-rate numbers you cite in go/no-go decisions and rollback thresholds.
- `qa-report` — the blueprint's own run-evidence aggregator; the run-level numbers behind a go/no-go.
- `test-automation` — Smoke tests are implemented here; go there for the test structure, come here for which journeys are smoke-critical.
- Rollout-time techniques (flags, canary, dark launch, synthetic probes), compliance gating (EU AI Act / EAA / GDPR) and release postmortems are not vendored in this blueprint — flag them as tooling/skill proposals when a release needs them. The go/no-go *decision* this skill gates feeds the human; execution stays with humans/runbooks (see the Blueprint scope note above).

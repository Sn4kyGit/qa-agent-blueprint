---
name: risk-based-testing
description: >-
  Produce a risk matrix/heatmap (business impact × probability), failure mode
  analysis on the top items, and test coverage mapped to risk zones. Run BEFORE
  or sprint planning. Use when: risk assessment, risk matrix, risk
  heatmap, what could break, critical paths, failure modes, where to focus
  testing. Not for sprint test plans or hands-on session-based bug hunting.
license: MIT
metadata:
  author: kindlmann
  version: "2.0"
  category: strategy
---

<objective>
Equal coverage across all features wastes effort on low-risk areas while leaving critical paths under-tested — a 90% coverage target on a settings page is effort stolen from checkout. This skill discovers risk, quantifies it as impact × probability, maps test density to risk zones, and keeps the assessment current as the product evolves. Output is a scored risk matrix that feeds the project's test strategy and sprint planning.
</objective>

## Quick Route

| Situation | Start at |
|-----------|----------|
| New product, no risk model yet | Phase 1 (Identification) → run the full 6 phases |
| Post-incident reassessment | Phase 6 (Reassessment triggers), then re-score the affected items in Phase 2 |
| AI/LLM feature to assess | Phase 3 (AI/LLM failure classes), score each class in Phase 2 |
| Sprint refresh of an existing matrix | Phases 4–5 (Heatmap + Coverage alignment) on changed features |
| Verify an old heatmap is still true | Phase 6 signals + Anti-Pattern "Risk Theater" |

---

## Discovery Questions

Check the project bridge file `.agents/qa-project-context/<KEY>.md` first — if it exists, use it as the foundation and skip questions already answered there (flow-map.md and learnings.md are phase-1 inputs too, not parallel stores). Gather the rest from stakeholders across engineering, product, and operations.

### Revenue-Critical Flows
- Which user flows directly generate revenue? (checkout, subscription, billing, upgrades)
- What is the revenue impact per hour of downtime for each flow?
- Are there time-sensitive flows? (flash sales, market-hours trading, payroll deadlines)
- Which flows have contractual SLAs with financial penalties?

### Recent Failures
- What broke in the last 3 releases? What escaped to production?
- What were the root causes? (code defect, config error, third-party failure, data migration)
- What was the blast radius of each incident? (users affected, revenue lost, reputation impact)
- Were there near-misses caught late in testing that could have escaped?

### Fragile Areas
- Which parts of the codebase change most frequently? (high churn = high risk)
- Which modules have the lowest test coverage today?
- Which areas have the most complex business logic or the most conditional branches?
- Which code was written by engineers who have since left the team?

### Third-Party Dependencies
- Which external services does the product depend on? (payment processors, auth providers, CDNs, APIs)
- What is the historical reliability of each dependency?
- What happens when each dependency goes down? (graceful degradation or hard failure?)
- Are there single points of failure with no fallback?

### Compliance and Data
- What regulatory requirements apply? (GDPR, PCI-DSS, HIPAA, SOC2, SOX, EU AI Act)
- What data is most sensitive? (PII, financial, health, credentials)
- What are the legal consequences of a data breach or compliance violation?
- Are there audit requirements that mandate specific testing evidence?

---

## Core Principles

1. **Not all features are equal.** A bug in checkout that blocks purchases is categorically different from a misaligned icon on a settings page. Equal coverage everywhere wastes resources on low-risk areas while leaving critical paths under-tested.
2. **Risk = Impact × Probability.** Risk is not a gut feeling. It is a product of two dimensions scored independently: how bad if this fails (impact), and how likely to fail (probability). Score both consistently across the product, then multiply.
3. **Risk assessment is continuous.** A risk model created once and never updated creates false confidence. Risk changes when the product changes, when dependencies change, when the team changes, and after every production incident. Build reassessment into the rhythm.
4. **Near-misses are data.** A catastrophic bug caught in staging is not a success story — it is a signal that the model underestimated that area. Track near-misses with the same rigor as production incidents.
5. **Risk informs coverage, not the other way around.** Do not start with "we need 80% coverage everywhere." Start with "where would a failure hurt most?" and let the model drive coverage targets per module.

---

## Workflow

1. **Risk Identification** — enumerate features, flows, and failure scenarios
   from the bridge file, recent incidents, and stakeholder input.
2. **Risk Classification** — score each risk on business impact × probability
   (1-5 each), produce a risk matrix.
3. **Failure Mode Analysis** — for top risks, identify specific failure modes,
   their causes, and detection methods.
4. **Risk Heatmap** — visual map showing risk zones and current coverage gaps.
5. **Test Coverage Alignment** — map existing tests to risk zones; identify
   under-tested high-risk areas.
6. **Monitoring & Reassessment** — reassess when new features ship or
   incidents occur.

Full phase worksheets, templates, and examples:
`references/workflow-details.md`.

## Anti-Patterns

### Testing everything equally
Applying the same coverage target to every feature regardless of risk. A 90% target on a settings page wastes effort that should go to payments or auth. Let the risk model drive allocation.

### One-time risk assessment
Creating a matrix during planning and never updating it. The product, team, and dependencies all change. A model from 6 months ago is outdated and out of date the moment a dependency, feature, or incident shifts the picture — it does not reflect today. Schedule reassessment and enforce it.

### Ignoring near-misses
Treating bugs caught in staging as pure successes. If a critical bug was caught only by manual testing, the automated safety net has a gap. Document near-misses and adjust the model.

### Risk theater
Going through the motions (filling matrices, drawing heatmaps) without changing test allocation. If the heatmap exists but coverage does not align to it, the exercise was wasted. Verify alignment quarterly. Bolton's "Quality Engineering Is Not Testing" (2026-04-20) warns of exactly this — building a heatmap and calling it "QE done." Reference: https://developsense.com/blog/2026/04/quality-engineering-is-not-testing

### Anchoring on historical risk
Over-weighting past incidents and under-weighting new vectors. A module that failed 2 years ago and was since rewritten may no longer be high risk; a brand-new third-party integration has unknown risk that deserves attention.

### Confusing severity with priority
Severity is how bad a failure is; priority is how urgently to test it. A catastrophic-but-rare failure (earthquake destroys data center) can be lower priority than a moderate-but-frequent one (search occasionally wrong). Use the composite score, not impact alone.

---

## Verification

Prove the matrix is real and aligned before calling it done — smallest check first:

- **Artifact exists and is tracked:** `git ls-files | grep -E 'risk-matrix'` returns the file. An untracked draft on someone's laptop is not a risk model.
- **Every in-scope feature is scored:** grep the artifact for rows missing an impact or probability number. A feature with a name but no score is a gap, not a low risk.
- **Top items have failure mode analysis:** every item scoring ≥ 10 has a block with all five fields (Trigger, Blast Radius, Detection Method, Current Mitigation, Gap). A failure mode with an empty Gap line was not actually analyzed.
- **Coverage aligns to the heatmap:** for each CRITICAL/HIGH feature, confirm the prescribed coverage from the Phase-5 table actually exists (run the suite, check the coverage report's per-module numbers against the target). If the heatmap says CRITICAL but the module has 40% branch coverage and no E2E, the exercise was Risk Theater.
- **Churn signal is current:** re-run the Phase-6 churn command; any module in the top 10 that is not scored ≥ Probability 4 is a model that has drifted from reality.

## Done When

- A scored risk matrix exists as a tracked artifact at `projects/<KEY>/risk-matrix.md` — never inside the bridge file `.agents/qa-project-context/<KEY>.md`, which is a regenerated projection (hand-edits get silently overwritten); the projection picks the matrix up at regeneration — with every in-scope feature scored on impact (1-5) and probability (1-5)
- Each feature's composite score places it in a named zone (CRITICAL, HIGH, MEDIUM, or LOW) with a corresponding testing action assigned
- Every feature scoring ≥ 10 has a completed failure mode analysis with trigger, blast radius, detection method, current mitigation, and gap documented
- Coverage requirements per zone are mapped against current coverage, with each gap assigned a Priority (P0-P3), an Owner, and a Target Sprint
- Reassessment triggers and cadence are recorded in the same artifact (quarterly minimum, plus within 48 hours of any production incident)

## Reference Files (in `references/`)

- **examples.md** — Four fully-scored worked examples (checkout, media platform, third-party API, auth): risk profile → failure modes → prescribed coverage.

## Related Skills

- **release-readiness** — Go/no-go decisions reference the heatmap to confirm critical areas are covered.
- **qa-metrics** — Defect escape rate and defect clustering feed back into risk reassessment.
- **test-ticket** — the qa-manager strategy consults this matrix when a ticket's risk decides the test depth.
- The bridge file `.agents/qa-project-context/<KEY>.md` (generated by `/onboard-project`) carries the critical flows and dependencies this skill consumes; the matrix itself lives at `projects/<KEY>/risk-matrix.md`.
- Building eval suites for AI/LLM failure classes is not vendored in this blueprint — flag it as a tooling proposal when the product ships LLM features.

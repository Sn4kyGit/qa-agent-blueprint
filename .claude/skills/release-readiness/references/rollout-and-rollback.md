## Staged Rollout Validation

### Rollout Stages

A typical staged rollout. The same ladder expressed for flag-based rollouts adds a 25% step (see below):

| Stage | Traffic % | Duration | Purpose |
|-------|-----------|----------|---------|
| Canary | 1% | 15-30 min | Catch crashes, exceptions, obvious failures |
| Early adopters | 10% | 1-2 hours | Validate error rates, latency, business metrics |
| Partial rollout | 25-50% | 2-4 hours | Confirm stability at scale |
| Full rollout | 100% | — | Monitor for 24 hours post-deployment |

### What to Monitor Between Stages

Before promoting to the next stage, verify **all** of these:

**Error metrics:**
- Error rate (HTTP 5xx) is not higher than baseline
- Exception count is not higher than baseline
- No new error types appearing in logs

**Performance metrics:**
- P50 and P95 latency are within acceptable range (relative to baseline, not an absolute ceiling)
- No increase in timeout errors
- Database query times are stable

**Business metrics:**
- Conversion rate is not dropping
- User engagement (page views, actions) is stable
- Revenue/transaction volume is normal (if applicable)

**Infrastructure metrics:**
- CPU and memory usage are normal
- No increase in queue depth or message backlog
- No disk space issues from new logging

### Automated Promotion Criteria

Define rules for automatic promotion between stages. Each gate combines an error-rate ceiling, a latency ceiling expressed **relative to baseline**, a stability window, and (at higher stages) business-metric guardrails. See `references/rollout-automation.md` for the full canary→10%→50%→100% promotion ruleset.

### Feature Flag Gradual Rollout

An alternative to infrastructure-level canary deploys:

1. Deploy new code to 100% with the feature flag OFF
2. Enable the flag for internal users first (dogfooding)
3. Enable for 1% of users (canary equivalent)
4. Gradually increase: 10%, 25%, 50%, 100%
5. Remove the flag after full rollout is stable for 1 week

**Advantages:** Faster rollback (just flip the flag), no infrastructure changes, can target specific user segments.

**Disadvantages:** Code complexity (branching logic), stale flags become tech debt, doesn't catch infrastructure issues.

#### Tooling

| Platform | Best at | Notes |
|----------|---------|-------|
| **LaunchDarkly** | Enterprise scale; Guarded Rollouts (auto-canary analysis, GA since May 2025); AI Configs for prompt/model rollouts; agent graphs | Acquired Highlight.io in 2025 — also offers observability tied to flags |
| **Statsig** | Experiment-first culture; Switchback experiments (Feb 2026 update) for two-sided marketplaces; auto-tune | Acquired by OpenAI Sept 2025; still operates independently as of mid-2026, but weigh acquisition/roadmap risk before a multi-year infrastructure bet |
| **GrowthBook** | OSS-first; stale-flag detection with code-reference scanning; SQL-based experimentation | Strong fit when you want to self-host and avoid vendor lock-in |
| **Unleash** | OSS, GitOps-style flag definition, environment scoping | Apache 2 license; Enterprise tier for SSO/audit |
| **Flagsmith** | Kill switches as first-class concept; canary alerts; OSS option | Published "what is a kill switch" + "release testing" guides 2026 |
| **Harness FME** (formerly Split) | Targeted rollouts + monitoring tied to deploy pipelines; warehouse-native experimentation + flag archiving (2026) | Rebranded after Harness acquisition |

Vendor-native canary analysis (LaunchDarkly Guarded Rollouts, Statsig Auto-tune, Flagger) is now common — if your platform offers it, prefer it over hand-rolled rollout-policy YAML. Given the vendor churn this table documents (Statsig→OpenAI, Split→Harness FME), prefer OpenFeature-compatible SDKs (CNCF spec; Harness FME and others now standardize on it) so flag tooling stays swappable.

#### Rolling Out AI/LLM Features

AI features need a distinct rollout pattern: prompt versions and model IDs are configurable separately from code, and a kill switch is mandatory.

1. Pin the prompt template version and model ID in your AI Configs platform (LaunchDarkly AI Configs, custom dataset, or feature-flag JSON).
2. Roll out the prompt/model combo behind a flag — internal first, then 1%, 10%, etc.
3. Watch eval metrics (hallucination rate, jailbreak success rate, cost per request) per cohort, not just error rate.
4. Cost guardrail: a budget circuit breaker that fails the feature open (graceful fallback) when a model's per-request cost spikes.
5. Kill switch: a single flag that disables the AI path and routes to a deterministic fallback or a "feature unavailable" state — testable in staging before launch.

Prompt-level eval test patterns and canary metric design are not vendored in this blueprint — flag them as tooling/skill proposals when releasing AI features.

---

## Rollback Criteria and Process

### Automated Rollback Triggers

Define these thresholds BEFORE deployment, as part of the rollback plan the team
adopts. When any trigger fires, the project's automation rolls back — or the
on-call human does. The agent never executes a rollback itself; it drafts these
thresholds and, when handed monitoring evidence, evaluates them and recommends.

| Metric | Threshold | Action |
|--------|-----------|--------|
| Error rate (5xx) | >2x baseline for 5 min | Auto-rollback (runbook automation / human) |
| P95 latency | >3x baseline for 5 min | Auto-rollback (runbook automation / human) |
| Health check | 3 consecutive failures | Auto-rollback (runbook automation / human) |
| Crash rate (mobile) | >0.5% | Auto-rollback (runbook automation / human) |
| Error budget | >50% burned in 1 hour | Auto-rollback (runbook automation / human) |

### Manual Rollback Triggers

These require human judgment but should have clear guidelines:

- **Customer-reported critical issue** — Multiple users reporting the same problem
- **Data integrity concern** — Evidence of corrupted or incorrect data
- **Security vulnerability discovered** — Active exploitation or high-severity CVE
- **Monitoring blind spots** — You realize you can't monitor a critical metric for the new feature
- **On-call engineer judgment** — The on-call engineer always has authority to trigger a rollback

### Rollback Procedure

The agent's part of this procedure is writing it down as the project's rollback
plan, tailored to its tooling, before the release — and evaluating evidence when
a trigger fires. Steps 1–5 are executed by the on-call human or the project's
automation.

**Step 1: Decide (< 2 minutes)**
- Is the trigger automated or manual?
- If manual: does the issue meet rollback criteria? If yes, proceed. Don't debate.

**Step 2: Execute rollback (< 5 minutes) — human/runbook execution**
- **Kill switch (fastest, prefer if available):** Flip the dedicated kill-switch flag for the affected feature. Distinct from a full code rollback — disables one capability without redeploy. Test the kill switch in staging before every release; an untested switch is not a switch.
- **Feature flag rollback:** Disable the feature flag for the new code path. Slower than a kill switch when both exist (rollout flag vs kill switch are different concerns).
- **Code rollback:** Revert to the previous deployment (re-deploy previous image/artifact). Use when the issue is not contained to a single flagged feature.
- **Database rollback:** Run backward migration if applicable. If migration is irreversible, skip this step and handle data separately.
- **Cache invalidation:** Clear CDN and application caches if the old version would serve stale/incorrect data.

**Step 3: Verify (< 5 minutes) — human/runbook execution, agent assembles the checklist**
- Run production smoke tests
- Verify error rate returns to baseline
- Check that the rolled-back version serves correctly

**Step 4: Communicate (< 10 minutes)**
- Notify the release channel using the rollback skeleton below
- Update status page if user-facing impact occurred
- Brief the support team

**Step 5: Investigate (next business day)**
- Root cause analysis
- Write a regression test that would have caught the issue
- Update the go/no-go checklist if a check was missing
- Schedule the fix and re-release

#### Rollback announcement skeleton

Drop this in the release channel during Step 4. For the full release + rollback templates, see `references/communication-templates.md`.

```
Subject: [Rollback] v{version} — {date} {time}
Status: ROLLED BACK
Reason: {one line — e.g. error rate 4x baseline within 8 min}
Impact: {who was affected, for how long}
Current state: Running previous version v{prev_version}
Next steps:
- Root cause investigation: {owner}
- Fix ETA: {estimate or "investigating"}
```

### Data Considerations

When a migration can't be rolled back:

- **Forward-fix:** Deploy a fix on top of the current (broken) version instead of rolling back
- **Dual-write:** During migration, write to both old and new schemas; rollback drops the new writes
- **Shadow migration:** Migrate in the background, validate, then cut over. Rollback just stops the cutover
- **Point-in-time recovery:** Restore database from backup (last resort, causes data loss for changes since backup)

---

## Anti-Patterns

### "It worked on staging"
Staging is not production — different data volumes, traffic patterns, third-party configurations, and infrastructure scale. Staging success is necessary but not sufficient evidence of readiness.
**Fix:** Use production smoke tests and staged rollouts in addition to staging verification.

### No rollback plan
"We'll figure it out if something goes wrong" means you'll figure it out under pressure, sleep-deprived, with users complaining. That's when mistakes happen.
**Fix:** Document the rollback procedure. Practice it quarterly. Time it. Make it a checklist, not tribal knowledge.

### Deploying on Friday afternoon
You deploy at 4 PM on Friday. An issue surfaces at 6 PM. Your team is at dinner. The issue grows overnight. Monday morning is chaos.
**Fix:** Deploy early in the week, early in the day, when the full team is available to monitor. If you must deploy on Friday, deploy before noon with extra monitoring.

### Skipping smoke tests because "the pipeline is green"
CI pipelines test against test data in test environments. Smoke tests verify the deployed application works with production configuration, production data, and production infrastructure.
**Fix:** Smoke tests are non-negotiable. If they're slow, make them faster. If they're flaky, fix them. Never skip them.

### Big-bang releases instead of incremental
Accumulating 6 weeks of changes into one mega-release means: more things can break, harder to identify which change caused the issue, higher risk, longer rollback time, more stress.
**Fix:** Release smaller, more frequently. If you can't do continuous deployment, aim for weekly or bi-weekly releases with small, well-understood changesets.

### No post-deployment verification
You deploy and move on to the next feature. An hour later, users are experiencing errors that nobody is watching for.
**Fix:** Assign someone to monitor dashboards for 30-60 minutes post-deploy. Set up automated alerts with appropriate thresholds. Run post-deployment smoke tests.

### Rollback aversion
"We're so close to fixing it, let's just push a hotfix forward." Meanwhile, users are affected for another 45 minutes while you debug under pressure.
**Fix:** Roll back first, investigate second. A working previous version is better than a broken current version. Your ego can recover; user trust is harder to rebuild.

### Feature flag accumulation
You use feature flags for safe rollouts (good!) but never remove them (bad). After a year, you have 200 flags, nobody knows which are active, and flag interactions cause mysterious bugs.
**Fix:** 2026 best practice is platform-level stale detection, not calendar reminders. Use GrowthBook stale-flag detection (code references), LaunchDarkly archive flow, or Flagsmith's flag age telemetry to surface flags whose code paths haven't been touched in N weeks. Pair with a quarterly review where flags older than the threshold are either archived or get a documented owner + reason to keep. Calendar dates rot; code-reference scans don't.

### Canary alerts that lie
Auto-rollback wired to a metric that's noisy, late-arriving, or partially aggregated. The alert fires (or doesn't) at the wrong time, and the team learns to mistrust it — so when the real incident arrives, the signal is ignored.
**Fix:** Treat the canary alert like any other test — it has a false-positive rate and a false-negative rate, and you measure both. Run a "shadow" period where the alert publishes its decision but doesn't actually rollback; compare its calls to ground truth for two weeks. Promote to auto-rollback only after the false-positive rate is below your tolerance. Reference: https://www.flagsmith.com/blog/when-canary-alerts-go-wrong

### Switchback experiments for two-sided systems
Standard A/B fails on marketplaces, ride-share, ad auctions, and other systems where the treatment group affects the control group through shared state. Splitting traffic 50/50 doesn't isolate the experiment — both sides see the same warped market.
**Fix:** Use a switchback design — alternate the entire system between control and treatment over short windows (minutes to hours). Statsig's Switchback experiments (Feb 2026) automate this for the common cases. Don't block release on a corrupted A/B test result; rerun with the right design. Reference: https://www.statsig.com/updates

---


# Improvement Patterns

Bottleneck signatures and their concrete fixes. The perf-analysis script
matches against these patterns; this file holds the full rationale.

## Execution phase > 50% of run time

**Signal**: `avg_exec_pct > 50` in the phase breakdown.

**Why it matters**: execution is the test-running phase — if it dominates,
the test suite itself is the bottleneck, not the process.

**Fixes**:
- **Reuse recon results** — `recon.json` already captures selectors, console
  errors, and screenshots. Don't re-explore the same pages every run.
- **Parallelize specs** — Playwright supports `--workers`; split slow specs
  across workers.
- **Move slow checks to nightly** — not every check needs to run on every
  ticket. Reserve the interactive run for the critical path.
- **Fast Path for simple tickets** — single-branch tickets skip the full
  pipeline (qa-manager → executor).

## Flake rate > 5%

**Signal**: `test_cases[].attempts > 1` on more than 5% of cases.

**Why it matters**: retries consume time and erode trust in the suite.

**Fixes**:
- **test-reliability skill** — run it on the flaky cases: selector stability
  scoring, environment-aware healing, data leakage detection.
- **Quarantine persistent flakes** — move them to a quarantine suite so they
  don't block the main gate.
- **Root-cause via failure-analysis** — classify: environment, data, timing,
  selector, or product bug.

## BLOCKED rate > 20%

**Signal**: `verdict: "BLOCKED"` on more than 20% of runs.

**Why it matters**: blocked sessions burn tokens and time without producing
test results.

**Fixes**:
- **Preflight coverage** — ensure `preflight.sh` runs before every session;
  it catches VPN/stage reachability issues early.
- **Readiness gates** — `readiness.json` should be checked before execution.
- **Test data provisioning** — BLOCKED often means "no test data". Ensure
  fixtures are ready before starting.

## Average delegations > 6 per run

**Signal**: `session.delegations > 6` in execution summaries.

**Why it matters**: each subagent spawn adds latency (context assembly, model
spin-up) and context overhead.

**Fixes**:
- **Combine related sub-tasks** — don't spawn a separate agent for each AC.
- **Use the capsule handoff** — the sealed `context-capsule.json` eliminates
  repeated project-context reads per spawn.
- **Parallel where possible** — multiple delegations can run concurrently if
  they don't depend on each other.

## Cache hit rate < 50%

**Signal**: `cache_read / (cache_create + cache_read) < 0.5` from
session-perf.log.

**Why it matters**: low cache hits mean the context is changing every turn
(full re-reads), costing more tokens and latency.

**Fixes**:
- **Stable context** — avoid re-reading the same files; reference by path.
- **Capsule handoff** — subagents get a pre-built context capsule instead of
  re-deriving project state.
- **Reduce context churn** — don't restate rules that are already in the
  system prompt.

## Average duration > 60 minutes

**Signal**: `avg_duration_s > 3600`.

**Why it matters**: long runs block the tester and increase context-rot risk.

**Fixes**:
- **Smaller ticket scopes** — split epics into testable units.
- **Parallel recon + planning** — start planning while recon runs.
- **Fast Path** — simple tickets skip the full pipeline.
- **Pre-computed context** — use the capsule to avoid re-reading project files.

## Token cost growing over time

**Signal**: `cost_est_usd` trending up in the session-perf.log.

**Why it matters**: token spend is real money.

**Fixes**:
- **Skill profiles** — deactivate unused skills to reduce description overhead.
- **On-demand docs** — move large reference material out of skill bodies.
- **Budget discipline** — `context-budget.sh` keeps the always-loaded layer
  under control.

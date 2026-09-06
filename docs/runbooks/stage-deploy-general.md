# Generic Stage-Deploy Runbook (scaffold)

Fallback scaffold when a project's `PROJECT.md` has no deploy runbook yet. The
`deploy-to-stage` skill executes the **project** runbook; use this to help the user
write one during onboarding. Replace every `<...>`.

## 0. Scope & safety

- Target: **stage only** (`<stage-url>`). Production is out of scope for the agent.
- Agent may trigger deploys: `<yes/no>` (record in PROJECT.md).
- Announce deploys if the stage is shared: `<channel/process>`.

## 1. Pre-flight checks

- [ ] Expected version/branch identified: `<release-branch-or-tag>` (from the ticket's
      fix version).
- [ ] Current stage version recorded: `<version-check method>` → `<current version>`.
- [ ] No conflicting activity on stage (other testers, running regression).
- [ ] Required feature flags / config values known: `<flags>`.

## 2. Deploy

1. Trigger `<pipeline-name>` with parameters `<params>` via `<CI system>`.
2. Wait for stages in order: `<build>` → `<deploy>` → `<migrate/post-steps>`.
   - Any stage red → capture the log excerpt, stop, report BLOCKED.
   - Max 1 retry, only for obviously transient infra failures (state it).

## 3. Post-deploy steps

- [ ] Cache invalidation: `<CDN/app cache flush procedure>`.
- [ ] Migrations verified: `<check>`.
- [ ] Feature flags set as required: `<flags>`.

## 4. Verification (mandatory before any testing)

- [ ] Version check: `<method>` reports `<expected version>`.
- [ ] Smoke probe: homepage/login/health endpoint OK as `<test-user-role>`.
- [ ] Only then: hand back to `test-ticket` / `retest-bug` with "stage ready,
      version X".

## 5. Records

- Note deploy (from → to version, pipeline run id) in the run's
  `execution_summary.json` and the JIRA comment.
- Deploy surprises → `memory/learnings/_inbox.md`; recurring ones →
  `projects/<KEY>/learnings.md`.

## 6. Rollback (reference only)

- Procedure: `<re-run pipeline with previous tag / platform rollback>`.
- The agent never rolls back autonomously — it reports and asks.

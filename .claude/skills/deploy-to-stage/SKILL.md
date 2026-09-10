---
name: deploy-to-stage
description: Execute the active project's stage-deploy runbook, with safety checks, when a ticket's fix isn't on stage yet. Use for "/deploy-to-stage", "bring den Fix auf Stage", "deploy auf Stage", or when test-ticket/retest-bug determine the fix isn't deployed.
---

# /deploy-to-stage — project runbook, with safety checks

## Steps

0. **Resolve whose runbook this is.** If the project has products and the ticket
   routed to one, `products/<PRODUCT>/PRODUCT.md` → "Deploy runbook (stage)"
   *replaces* the project's runbook when present (merge mode `replace`, see
   `.claude/rules/core/product-layer.md`) — deploying the wrong product's pipeline
   is a real incident, not a formatting detail. **"Agent may trigger deploy" is read
   from `PROJECT.md` only**, whatever a product file says: a product may narrow that
   permission by asking you to stop, never grant it.
1. **Preflight the execution path.** Read "How a deploy is triggered" from the
   effective project file. If it is missing, or names a CLI that is not installed
   (`command -v gh` and friends), stop here and report **BLOCKED** naming exactly
   what is missing — a deploy the agent cannot run is not a deploy it should
   improvise around with a plausible-looking command.
2. Read `projects/<KEY>/PROJECT.md` → "Deploy runbook (stage)". If it has no
   runbook yet, use `docs/runbooks/stage-deploy-general.md` as a scaffold and help
   the user fill in the project-specific one (this is normally done during
   `onboard-project`, not mid-ticket).
3. **Check "Agent may trigger deploy"** in the project file first. If `no`, stop
   and tell the user who to ask — do not trigger the pipeline yourself.
4. If shared stage: announce the deploy per the project's gotcha/etiquette notes
   (e.g. team chat) before triggering — check `memory/learnings/env-gotchas.md`
   for the "shared stage" pattern if the project file is thin on this.
5. Trigger the pipeline with the parameters from the runbook (branch/release from
   the ticket's fix version). Wait for stages in the documented order; a failed
   migration step means the deploy is **not** valid even if later stages go green.
6. Run post-deploy steps exactly as listed (cache flush, feature flags).
7. **Verify before handing back**: version-check method matches the expected
   version, AND a smoke probe passes (homepage/login as the project's standard
   test user). Only then report "stage ready, version X" to whatever invoked this
   skill (`test-ticket`, `retest-bug`, or the user directly).
8. Record the deploy in the run's `execution_summary.json` → `deploy`
   (`from_version`, `to_version`, `pipeline_run`, `at`) and in the eventual JIRA
   comment. `from_version` is not bookkeeping: it is the lower bound of the change
   window `failure-analysis` uses to ask JIRA what shipped, and without it a later
   failure has nothing to compare against.
9. Any deploy surprise (unexpected failure, stale-cache repeat, migration
   quirk) → `memory/learnings/_inbox.md` via `retro-learn`.

## What this skill never does

Deploy to production. Retry a failed deploy more than once without flagging it as
unusual. Roll back — that's reported and asked about, never done autonomously
(`.claude/rules/core/security.md`).

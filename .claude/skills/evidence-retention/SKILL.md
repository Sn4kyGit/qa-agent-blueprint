---
name: evidence-retention
description: Plan and notify evidence cleanup — two-stage retention (heavy artifacts first, whole runs later) with protection rules, index-before-delete history, and a human-only prune. Use for "/evidence-retention", "Evidence aufräumen", "Speicherplatz", "Retention", "bitte aufräumen", or the session-start cleanup hint. The agent plans and notifies; pruning is a human step the guard blocks for agents. Not for metrics (/qa-report) or a ticket verdict (/report-to-jira).
license: Apache-2.0
---

# /evidence-retention — plan a cleanup, never delete

`evidence/` grows forever unless someone prunes it. This skill turns that into a
safe, notification-first workflow: the agent **plans and notifies**, a **human
executes** the deletion. The guard blocks agent invocations of
`evidence-retention.py prune` on both harnesses (plan D1) — deleting evidence is
a human step, like the keychain commands. The agent never runs it.

Full design: `docs/retention-leases-rollup-plan.md` §3. Policy surface:
`docs/artifact-strategy.md` → "Retention".

## The two stages

| Stage | What goes | What stays | Default |
|---|---|---|---|
| A — artifacts | screenshots, logs, traces, videos inside old run dirs | curated JSON/MD (`execution_summary.json`, `run.json`, `verdict.json`, `testplan.md`, `proposed-report.md`, …) + a `.retention.json` marker | 30 days |
| B — whole runs | the run dir, **after** a compact fact line is appended to `evidence/.audit/retention-index.log` | the index line (metric history survives) | 365 days (min 90) |

`evidence/.mcp-out/` raw output is pruned by age separately (default 7 days).
Historical summaries are never edited — kept (A) or indexed then removed (B).

## Protection rules (never pruned, any age)

1. Runs younger than the freshness window (+ margin) — an in-flight run.
2. The **newest run per ticket** — rollup and retest always need it.
3. Pending shadow proposals (`reported_to_jira:false && shadow:true`) until
   posted or the proposal-protection period (default 30d) elapses; an expired
   one is listed explicitly as a *stale proposal* in the plan.
4. `NEEDS_REVIEW` without a `human_ruling` — the awaiting-ruling signal survives.
5. A run dir with a `.retain` marker (human pin).
6. `.audit/`, `.preflight/`, `.leases/`, `_rollups/`, and any directory not
   matching `evidence/<PROJECT>/<TICKET>/<RUN>` — reported, never touched.

A run with a missing or malformed summary is `protected:no-summary` — fail-open,
never deleted.

## Steps

1. **Plan** (writes nothing):

   ```bash
   python3 .claude/scripts/evidence-retention.py plan --qa-home <QA_HOME>
   # --project SHOP   one project only
   # --json           machine-readable
   # --out FILE       also write a reviewable markdown plan
   ```

   Plugin mode: `python3 $CLAUDE_PLUGIN_ROOT/.claude/scripts/evidence-retention.py plan`.
   Read the per-run classification: `keep`, `protected:<reason>`, `artifacts`
   (stage A), `run-prune` (stage B), plus reclaimable bytes.

2. **Present the plan to the human.** Summarize what would be pruned and what is
   protected and why. Name any stale shadow proposal explicitly. Never narrate a
   deletion you cannot perform.

3. **Hand over the prune command — do not run it.** Give the human the exact
   command for their own terminal:

   ```bash
   python3 .claude/scripts/evidence-retention.py prune --qa-home <QA_HOME> --yes
   ```

   The guard refuses this command from the agent. If asked to "just clean it up",
   explain that pruning is a human step and offer the plan + command instead.

4. **Optionally verify** afterwards with `status` (agent-runnable):

   ```bash
   python3 .claude/scripts/evidence-retention.py status --qa-home <QA_HOME>
   ```

## Configuration

Per project, optional `## Evidence retention` section in `PROJECT.md` (a human
edits it — the guard blocks agent writes). Absent section = blueprint defaults
(30 / 365 / 7 days, notify on). A summary retention below 90 days is a policy
error (the script exits 1) — it would break the `verify-sightings` window.

## Notification

The session-start orientation prints a fail-open hint when prunable evidence
crosses the threshold (default > 1 GB or > 100 prunable runs):
`evidence: … runs prunable — run /evidence-retention`. That hint is this skill's
entry point for users who never type slash commands.

## Headless / CI

A headless run produces the plan and a report hint, **never a deletion** (plan
D2). A CI cron may call `prune --yes` directly — that is a human decision encoded
in pipeline config, outside the agent. The recommended CI default is `plan` +
notification; see `docs/rules/core/cicd.md`.

## What this skill does not do

Delete evidence itself, edit historical summaries, prune JIRA attachments, or
touch `.audit/`. It does not judge runs — the unit is storage, not quality
(that is `/qa-report`).

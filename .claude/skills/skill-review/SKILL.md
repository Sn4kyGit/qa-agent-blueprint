---
name: skill-review
description: Review which blueprint skills the evidence actually shows as used and propose a slimmer skill profile — read-only analysis of evidence/**/execution_summary.json (used/unknown with coverage, never "unused"), profile dry-runs (full/standard/minimal/custom) with dependency closure, apply only after explicit confirmation and only in integrate mode. Use for "/skill-review", "which skills do we need", "welche Skills werden genutzt", "skill profile", "skills reduzieren", "prune skills". Never reads transcripts and never deactivates a skill automatically.
---

# /skill-review — evidence-based skill usage review

Two jobs, in order. First say what the evidence shows about skill usage. Only if
the user then wants a slimmer skill set, propose a profile — as a dry run — and
apply it only on an explicit confirmation and only where the install mode allows
it. A proposal is never a decision; the user makes the decision.

## What this skill never does

- Read transcripts, chat logs, JIRA content, or screenshots. The only input is
  `evidence/**/execution_summary.json`.
- Conclude "unused". Absence of a `skills_used` declaration is absence of
  instrumentation, not absence of use — the review reports `unknown` with a
  reason instead.
- Deactivate, delete, or move anything automatically. Profile proposals are
  dry-run output; apply happens only per step 4.
- Edit `install.sh`, `opencode.json`, plugin caches, or the blueprint checkout —
  and nothing at all outside integrate mode.

## Step 1 — run the helper (read-only)

```bash
python3 .claude/scripts/skill-review.py [--evidence DIR] [--since DAYS] [--project KEY] [--json]
```

- `--evidence` — evidence root, default `evidence`.
- `--since` — window in days, default `90`; `0` means no window.
- `--project` — restrict to one project key.
- `--json` — structured output for post-processing; the default render is for
  the user.

Python standard library only, writes nothing, reads `execution_summary.json`
files and `.claude/skills/*/SKILL.md` names only. If `.claude/skills/` is not
found, the helper still reports declared usage and coverage and says the
inventory is unavailable.

## Step 2 — explain the result

Report three blocks, in this order:

1. **Coverage** — the window, runs in window, runs carrying `skills_used`, the
   percentage, and separately: runs with unusable timestamps (kept and counted
   as `timestamp_unknown`, never silently dropped) and unreadable summaries.
2. **Used** — per skill: count, last use date, `source=declared_summary`. This
   is the only claim the data supports: the run's own summary declared the skill.
3. **Unknown** — every other installed skill with its reason:
   `no_runs`, `field_not_instrumented`, `outside_test_run_scope`,
   `timestamp_unknown`, `unreadable_summary`, `retention_or_other_qa_home`.

Say the rule out loud: **unknown is not unused.** `skills_used` is declared per
run at summary time and only by flows that write a summary
(`.claude/rules/core/evidence-policy.md`), so a missing declaration never proves
a skill was not used. Old summaries without the field stay valid evidence — a
coverage below 100 % mostly means runs predate the field, not that skills went
unrecorded. Repeat runs or a wider window before drawing any conclusion.

## Step 3 — profile proposal (only when asked)

Offer profiles only when the user asks to slim down, prune, or choose a skill
set. Otherwise stop after step 2.

**Evidence gate.** When the tracking holds no records at all (zero instrumented
runs in the window), name no deactivation candidates and propose no profile
change: with no data, nothing can be named — say so, and at most point at the
profiles below as a user preference decision that needs confirmation. "Which
can I deactivate?" on zero evidence gets that honest answer, not a list.

### Profiles

| Profile | Keeps |
|---|---|
| `full` (default) | every installed skill — the shipped state |
| `standard` | all skills except `agentswitch model-setup whats-new re-board demo scaffold-suite`, then closed under the resolver |
| `minimal` | `standard` minus `recon deploy-to-stage onboard-product onboard-project exploratory-testing`, then closed under the resolver |
| `custom` | the user's confirmed allowlist, closed under the resolver |

- **full** — everything. Nothing to propose, nothing to do.
- **standard** — drops the harness-management and demo skills: `agentswitch`,
  `model-setup`, `whats-new`, `re-board`, `demo`, `scaffold-suite`. The ticket
  core, vendored specialists, `recon`, `deploy-to-stage` and `skill-review`
  itself stay.
- **minimal** — `standard` minus `recon`, `deploy-to-stage`, `onboard-product`,
  `onboard-project` and `exploratory-testing`. The ticket core and
  `skill-review` itself stay.
- **custom** — whatever the user names, then closed under the resolver below.
  A user's ad-hoc pick goes through the same resolver and the same confirmation
  as a named profile.

Profiles nest: `minimal` ⊂ `standard` ⊂ `full`. The vendored specialist skills
and `webdriverio-testing` are pinned by the resolver when active rows or the
framework require them, so no profile silently strands an active feature.

### Dependency resolver

Before showing any proposal, close the keep-set over these rules and name every
skill each rule pinned:

1. **Chain** — `test-ticket` → `failure-analysis` → `report-to-jira` →
   `retro-learn`: keeping one link keeps the next. The same chain backs
   `retest-bug`, `test-automation` and `exploratory-testing`, so while any of
   them stays, `failure-analysis`, `report-to-jira` and `retro-learn` stay.
2. **`qa-report` and `qa-help` stay pinned in every profile** — `qa-report`
   because the run-history scripts are invoked by path
   (`failure-analysis/tc-history.py` is called by `failure-analyst`; the paired
   history reader `aggregate.py` lives in `qa-report`), and `qa-help` because
   it is the command discovery surface every profile needs.
3. **`webdriverio-testing` only when** `projects/<KEY>/PROJECT.md` → "Test
   assets" → Framework is `webdriverio` — keep it in exactly that case, drop it
   otherwise.
4. **Active feature-matrix rows pin their specialists** — for every row with
   `Applies: yes` in the routed product's (or the project's) "Feature &
   test-method matrix", the skill named under "Responsible skill / subagent"
   stays: `security-testing`, `api-testing`, `accessibility-testing`,
   `visual-testing`. A profile that drops one strands an active row.

Without a project context, rules 3–4 cannot be evaluated: show the proposal
without them and flag it as such. Never guess the framework or the matrix.

### Show the proposal — dry run

Name the profile and the **exact exclude list** it would carry, one line per
excluded skill with its reason (profile membership, resolver pin with its rule,
or observed usage from step 2). State explicitly that **nothing has been
changed**. Do not offer "apply" as a leading question — wait for the user to
ask.

## Step 4 — apply (explicit confirmation, integrate mode only)

Applying changes the consumer's skill inventory. All four conditions below must
hold, or stop and explain which one does not.

1. **Integrate mode.** Apply is only defined when the consumer owns real skill
   files: `.claude/skills/` is a plain directory of the consumer repo, not a
   symlink into a blueprint checkout or plugin install, and the consumer is not
   the blueprint checkout itself. In `plugin`, `opencode` and `shared` mode the
   skill set ships whole — the plugin and the symlinked opencode surface are
   blueprint-owned and replaced on update, so nothing is ever deactivated there
   (`docs/integration.md` → "Skill profiles"). Explain that limitation and stop:
   the review stays read-only in those modes, and the same request gets the
   analysis plus the unapplied proposal.
2. **Explicit confirmation.** Show the concrete proposal again (profile name +
   exact exclude list) and ask for a yes. No default, no carry-over: "mach es
   schlank" is not a confirmation — only an explicit yes to that concrete list
   is. If the list changes, show it again and confirm again.
3. **Apply through the installer's profile-apply step**, never by hand:

   ```bash
   install.sh --mode integrate --target <consumer> \
     --skill-profile <name> --skills-exclude "<resolved exclude list>"
   ```

   The choice persists in the consumer's `.qa-skill-profile.json`
   (consumer-owned, backed up on every change) and is re-applied on every
   update/reinstall — a later update cannot silently bring the excluded skills
   back, and the installer re-resolves the dependency pins at apply time. Never
   rename or delete skill files yourself: that would desync the persisted
   profile and be undone by the next update. Never touch plugin caches or the
   blueprint checkout. If this checkout's installer does not implement
   profile-apply yet, stop and say so.
4. **Report what changed** — the applied profile, the exclude list, and how to
   reverse it (`--skill-profile full` restores the complete set).

Excluded skills drop out of the helper's inventory afterwards (it lists
`*/SKILL.md` only) — expected; `--skill-profile full` restores both the skills
and their appearance in the review.

## Command surface

`/skill-review` — usage review only (steps 1–2).
`/skill-review <profile>` or "reduce my skills" — steps 1–4, step 4 gated as
above.

---
name: rollup
description: Roll up existing evidence over a JIRA epic or release — classify each child (tested-pass/fail/blocked/needs-review/untested/stale), flag stale builds, and recommend go/no-go/insufficient-evidence against the project gates. Use for "/rollup SHOP-900", "ist Epic X getestet?", "release readiness for 2.14.0", "Rollup", "Epic-Übersicht". A report over runs, not a test run. Not for time-window metrics (/qa-report) or a single ticket verdict (/report-to-jira).
license: Apache-2.0
---

# /rollup — is this epic/release tested well enough to ship?

A rollup answers "is epic X / release Y ready?" from **existing evidence + JIRA
structure**. It is a **report, not a run**: it never executes a test, never writes
`execution_summary.json`, and never invents a verdict for an untested child. The
human decides; `release-readiness` consumes `rollup.json` for the go/no-go.

Design: `docs/retention-leases-rollup-plan.md` §4 (D5). Staleness is the killer
feature — **a PASS on an old build is not a PASS for the release.**

## Steps

1. **Fetch the children (one JQL, deployment-aware).** Read `PROJECT.md` →
   JIRA deployment/access. Per `docs/rules/testing/jira-confluence.md`:
   - Epic, Cloud: `parent = <EPIC-KEY>` · Data Center: `"Epic Link" = <EPIC-KEY>`
   - Release: `fixVersion = "<version>"` (use `--release-mode`)
   Fetch targeted fields (key, status, type, summary, fixVersions) and save them
   as `children.json` in the rollup dir:
   ```json
   {"epic": "SHOP-900", "project": "SHOP",
    "children": [{"key": "SHOP-901", "status": "Done", "type": "Story", "summary": "…"}]}
   ```
   On `browser` access (no API): read the children via the JIRA UI per
   `docs/rules/testing/jira-browser.md`, or degrade honestly — produce the local
   rollup and let a human post it. Never fabricate children.

2. **Probe the current build once** (for staleness). Use the project's declared
   version check (`PROJECT.md` → Environments). If it is unavailable, omit
   `--current-build` and say staleness is unchecked — do not guess a build.

3. **Run the aggregator** (deterministic; the script does the classification, not
   the model):
   ```bash
   python3 .claude/scripts/epic-rollup.py --children <rollup-dir>/children.json \
     --qa-home <QA_HOME> --project SHOP --current-build <build>
   # --release-mode for a fixVersion rollup; --json for machine output
   ```
   Plugin mode: `python3 $CLAUDE_PLUGIN_ROOT/.claude/scripts/epic-rollup.py …`.
   It writes `rollup.json` + `rollup.md` to
   `evidence/<KEY>/_rollups/<EPIC-or-RELEASE>/<ts>/` — **not** a run dir, no
   `execution_summary.json` (the Stop hook stays unaffected).

4. **Read the recommendation, interpret against the gates.** `recommendation` is
   `go | no-go | insufficient-evidence` — a recommendation, never enforcement.
   Surface the actionable gaps: the **untested** and **stale** child lists, P0/P1
   findings, and `awaiting_ruling`. Hand the result to `release-readiness` for the
   go/no-go checklist; a human rules.

5. **Report (shadow mode applies).** Compose the epic comment as
   `proposed-report.md` in the rollup dir, per the project's report format
   (`report-to-jira` mechanics). **No transition on an epic by default** — that is
   a human decision. While shadow mode is on, post nothing.

## Classification (honest, never invented)

| Class | Meaning |
|---|---|
| `tested-pass` / `tested-fail` | newest evidence is a current PASS / FAIL |
| `blocked` / `needs-review` | newest evidence BLOCKED / NEEDS_REVIEW (awaiting ruling) |
| `untested` | no evidence ever — a gap, not a verdict |
| `stale` | evidence predates `--current-build` (PASS on old build ≠ ready) |
| `no-test` | newest run was NO_TEST — nothing tested |

Flags: `legacy-evidence` (v1 summary), `pruned-evidence` (only a retention-index
line survives — historical, not current proof), `build-unverified` (no build to
compare). Worst verdict wins (`FAIL > BLOCKED > NEEDS_REVIEW > PASS`); coverage =
currently-covered children / total; pass rate over decided children only.

## What this skill does not do

Execute tests, write run summaries, invent verdicts for untested children,
transition an epic, or decide go/no-go itself. It does not replace `/qa-report`
(time-window metrics over runs) — a rollup is structure over JIRA children.

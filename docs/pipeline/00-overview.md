# Pipeline 00 — Overview & mode control

Entry point of the pipeline knowledge. The router (`CLAUDE.md`) and the skills
reference these files; nothing here is auto-loaded — read when a ticket's mode
makes a phase relevant.

## The three execution modes

| Mode | Execution | Strength | Cost | Repeatable |
|---|---|---|---|---|
| `mcp-only` | model drives the browser live, every step | deepest findings, notices the unexpected | high, grows superlinearly with step count | no |
| `hybrid` | MCP for recon + final observation, CLI for execution | near MCP quality when the four rules below hold | medium | yes, from the second run on |
| `cli-first` | specs run, MCP only on unclear failure | fast, cheap, CI-ready | low | yes |

The mode is set per project in `projects/<KEY>/PROJECT.md` → "Execution mode",
overridable per ticket, and raised automatically by the escalation rules below.

### When which mode

- **`mcp-only`** — unknown project without test infrastructure; exploratory
  charters; strongly visual/design tickets; low ticket volume; high-risk tickets
  where finding depth beats cost.
- **`hybrid`** (default) — the normal case. Every ticket is observed once, then
  a spec exists that runs as often as needed. Pays off from the first retest.
- **`cli-first`** — mature project with a maintained suite; regression runs;
  pipeline operation; high ticket volume with low individual risk.

## Why CLI results often come out worse

A real, explainable observation — six causes, in order of importance:

1. **A spec checks only what was written into it.** A model walking the page
   live notices the truncated text, the double spinner, the console error, the
   shifted layout on the side. A spec is blind to everything not formulated as
   an assertion. This is the main cause.
2. **Blindly written selectors.** A spec authored without ever seeing the page
   guesses its selectors. Best case it breaks immediately; worse, it hits a
   different element and goes green.
3. **False-green through negative assertions.** `toHaveCount(0)` is green when
   the error occurs but the CSS class was renamed. Negative assertions are the
   most common source of worthless green runs.
4. **Acceptance criteria flattened in translation.** "The user gets an
   understandable error message" becomes `toBeVisible()`. Existence is tested,
   understandability is not.
5. **No judgment on failure.** The runner reports "assertion failed at line 34".
   Whether the application or the test is wrong, it cannot say without the
   acceptance criteria in context — and that classification is the actual value
   of a test run.
6. **Wait logic written blind.** Without seeing the real load behavior,
   timing assumptions become fixed sleeps and come back as flakes.

### The four binding rules (hybrid)

1. A spec is **never written blind** — observation (probe or MCP session) comes
   first.
2. Every assertion is **positive and specific** and carries the ID of the
   acceptance criterion it covers.
3. Every spec passes the **red check** before its green counts (05-verification).
4. Every run carries an **observation channel**: console errors, failed
   requests, screenshot — catching part of what only a live-watching model
   would notice.

With these four rules, hybrid quality sits close to MCP quality. Without them,
measurably below.

## Orchestration and readiness

`/test-ticket` and `/retest-bug` load in the main orchestrator. It runs preflight,
intake, routing, readiness and strategy once, then seals one run-scoped
`context-capsule.json` before dispatch (`context-capsule.md`). A testable, low-risk
ticket with no escalation and exactly one mode-conformant execution branch goes
directly to `test-executor` or `test-automator`; a complex ticket hands the same
capsule to `qa-manager`. Managers, leaves and the analyst consume that context
without reading/routing/merging PROJECT, PRODUCT and Learnings again. On FAIL,
whichever orchestrator owns the run invokes `failure-analyst` with the capsule and
failure packet — never an execution leaf.

Readiness (`01a-readiness.md`) is the gate between routing and every stage action:
allowed project status, no blockers, required linked merge complete, expected build
deployed. JIRA browser intake is allowed before it; stage liveness, recon and test
execution are not.

## The six phases

```
Phase 1 Intake       → intake.json + readiness.json   ticket, ACs, testability, gate
Dispatch handoff     → context-capsule.json           sealed effective context, created once
Phase 2 Recon        → recon.json       probe script and/or MCP session — REAL selectors
Phase 3 Planning     → testplan.md      cases from ACs, gaps named → approval (per config)
Phase 4 Execution    → run.json + evidence   mode-dependent: MCP live or spec via CLI
Phase 5 Verification → verdict.json     red check, observation pass, failure classification
Phase 6 Reporting    → execution_summary.json, JIRA report, learnings
```

Phases exchange data through **files in the run dir**
(`evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/`), not through conversation
context: the flow survives agent, model and harness switches, and an aborted
run resumes at its last phase. `execution_summary.json` stays the artifact the
Stop hook enforces (`.claude/rules/core/evidence-policy.md`); the contract
files feed it. The capsule is immutable: a build/readiness or effective-context
change goes back to the main orchestrator for readiness re-verification and a new
revision. Revision 1 is `context-capsule.json`; revision N>1 uses
`context-capsule.vN.json` and preserves every predecessor. Recipients return
`STALE_CONTEXT`; they never regenerate it themselves. Delegation prompts carry the
selected revision path, not its full text.

## Tool assignment by mode

| Phase | mcp-only | hybrid | cli-first |
|---|---|---|---|
| 2 Recon | MCP session | probe script; MCP only for unclear interaction | reuse last `recon.json` |
| 4 Execution | MCP live | spec via CLI | spec via CLI |
| 5 Verification | n/a (was live) | red check + observation pass | red check; MCP on unclear failure |

## Escalation — live observation regardless of mode

- ticket risk reaches `Escalate at risk` from the project file
- the ticket is visual or design-driven
- no `recon.json` exists for the affected area
- the CLI run failed and the cause is not unambiguous
- a test case cannot be formulated as an assertion without shortening the AC
  (e.g. "understandable error message")
- a bug is not reproducible

Never escalate merely because a test is red. A cleanly classified failure needs
no browser session.

## Hard rules

- No test result without evidence — missing evidence means `BLOCKED`.
- Never test or deploy against an environment the project file forbids
  (production is reference-only).
- Before phase 2 and phase 4, readiness must be green: allowed status, no blockers,
  required merge complete and expected build deployed when required
  (`01a-readiness.md`; explicitly unavailable verification is reported). No
  stage-liveness shortcut and no universal MR/PR requirement.
- Credentials never printed, logged, written to files, or attached.
- Phase 3 is confirmed before phase 4 starts when `Plan approval: yes`.
  Headless runs cannot wait: they proceed and flag the unapproved plan in the
  report.

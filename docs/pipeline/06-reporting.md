# Pipeline 06 — Reporting

The pipeline's reporting obligations **on top of** the `report-to-jira` skill,
which owns the mechanics: format per deployment (ADF vs. wiki markup),
transitions from PROJECT.md, shadow mode. This file defines the content
contract only.

## Order

First the overview for the human, then the ticket comment as a draft. Tickets
are never created or commented without confirmation — shadow mode and the
project file's rules apply unchanged.

## Structure of the ticket comment

```
Test result: PASS | FAIL | BLOCKED | NEEDS_REVIEW
Environment: <env> | Build: <version> | Mode: <mcp-only|hybrid|cli-first>
Tested as: <role/test user> | Date: <…>

Coverage:
  AC1  <short title>  PASS
  AC2  <short title>  FAIL   → <bug ticket>
  AC3  <short title>  NOT TESTED (<reason>)

Additionally checked: <regression scope in one sentence>
Not checked:          <with reason>
Observations:         <from observation channel and observation pass>
Evidence:             evidence/<KEY>/<TICKET>/<ts>/
```

The status line always comes first. Someone skimming must know after one line.

**The mode field is mandatory**: anyone evaluating the result later must know
whether it was observed live or only asserted. `report-to-jira` composes this
block in the project's format (Cloud = ADF, DC = wiki markup — no pipe tables,
`docs/rules/testing/jira-confluence.md`).

## Evidence

Location and naming per `.claude/rules/core/evidence-policy.md`
(`evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/`). The pipeline adds the contract
files to the same run dir:

```
<intake.json>  <recon.json>  <testplan.md>  <run.json>  <verdict.json>
execution_summary.json   ← the enforced artifact; verdict.json feeds it
screenshots/ logs/ traces/ progress.md
```

| Result | Mandatory evidence |
|---|---|
| PASS | one proof per acceptance criterion |
| FAIL | screenshot of the failure state (culprit marked), console, relevant response, trace |
| BLOCKED | proof of the blocker |

Before attaching to a ticket: no credentials, no tokens, no real personal data
visible.

## Bug report

Duplicate check against `memory/learnings/` and JIRA before creating — a hit
means a comment on the existing ticket, not a new one. Mechanics and template:
`bug-report` skill + `projects/<KEY>/templates/bug-report.md`. Fields whose
correct value you do not know stay empty and are named in the draft — no
guessed value in a mandatory field.

## Learnings

Close out per the standing rule: anything unexpected →
`memory/learnings/_inbox.md` via `retro-learn`, declared in
`execution_summary.json` → `learnings` (or one sentence why there was nothing).
The Stop hook blocks the session end without that declaration. A genuinely
uneventful run writes `"none_because": "clean run, no surprises"` — never omit
the object.

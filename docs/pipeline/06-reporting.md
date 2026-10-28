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
Environment: <env> | Build: <version|unverified (project-configured)> | Mode: <mcp-only|hybrid|cli-first>
Tested as: <role/test user> | Date: <…>

Coverage:
  AC1  <short title>  PASS
  AC2  <short title>  FAIL   → <bug ticket>
  AC3  <short title>  NOT TESTED (<reason>)

Additionally checked: <regression scope in one sentence>
Not checked:          <with reason>
Observations:         <from observation channel and observation pass>
Attachments:          <evidence filenames — the files are attached to this ticket>
```

The status line always comes first. Someone skimming must know after one line.

**The mode field is mandatory**: anyone evaluating the result later must know
whether it was observed live or only asserted. `report-to-jira` composes this
block in the project's format (Cloud = ADF, DC = wiki markup — no pipe tables,
`docs/rules/testing/jira-confluence.md`).

## Two output channels, two reference rules

The same run produces text for two audiences — keep their reference rules
strictly separate:

- **Ticket comment / bug description (copy-paste block for JIRA or GitHub):**
  never a local path. No `evidence/...` run dir, no absolute machine path, no
  `file://` link — pasted into a tracker they are meaningless to everyone but
  the machine that ran the test. Evidence is referenced by **filename only**
  plus the note that the files are attached to the ticket. Repo-relative spec
  paths (`specs/checkout/coupon.spec.ts:42`) stay allowed — they resolve
  against the app repo, which the reader has.
- **Chat summary to the user:** the opposite — evidence files are referenced
  with their **absolute path** (e.g.
  `/Users/…/evidence/<KEY>/<TICKET>/<ts>/checkout-total_fail.png`), one file
  per line. Absolute paths are clickable in the harness UI; relative
  `evidence/...` paths resolve against whatever cwd the session happens to
  have and lead nowhere half the time.

**Finder auto-open (macOS, interactive only).** After the chat summary, open
the run dir in Finder so the evidence is one Space-key preview away:

```bash
open "/absolute/path/to/evidence/<KEY>/<TICKET>/<ts>"
```

One window, everything in it — images pasted into the transcript are the poor
viewing experience this replaces. Single screenshots in Preview
(`open <file>.png`) only when the user asks for one specifically. Guards:
macOS only (`uname` = `Darwin`), interactive sessions only — skip silently on
headless/CI runs (`claude -p`, `CI` set, no TTY) and on Linux. A failed `open`
never blocks the report; one chat line naming the folder is enough.

## Evidence

Location and naming per `.claude/rules/core/evidence-policy.md`
(`evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/`). The pipeline adds the contract
files to the same run dir:

```
<intake.json>  <readiness.json>  <recon.json>  <testplan.md>  <run.json>  <verdict.json>
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

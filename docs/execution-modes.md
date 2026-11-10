# Execution Modes — who's at the wheel?

Since 0.12.0, one line in the project file decides **how** the agent tests a
ticket: live via mouse and eye (Playwright MCP), or through a pre-written test
script (Playwright/WDIO CLI). This page explains the three modes, what the
change delivers, and how to switch.

---

## The problem before

Every ticket test ran live through MCP: the model drives the browser step by
step, sees everything — and every step costs context. With many or long
tickets, usage limits are reached quickly.

The alternative — just running scripts — is cheap but blind: a spec checks only
what someone wrote into it. It won't notice truncated text, a double spinner,
or a console error.

## What the change enables

The agent can now **mix both tactically**, with a project-wide default and
per-ticket override:

- **Recon probe** (`/recon`): a throwaway script drives the relevant pages and
  delivers the *real* controls, form fields, console errors, and screenshots —
  at a fraction of the MCP cost. Specs are built from this instead of guessed.
- **Red probe**: a new spec must provably fail once (expectation deliberately
  violated) before its green counts as evidence. This catches the entire
  "green but proves nothing" class.
- **Observation pass**: after a green script run, the model does a short live
  check of the main flow — explicitly tasked with noticing anything *not* in
  the assertions.
- **Mode in the report**: every JIRA comment carries the line
  `Mode: <mcp-only|hybrid|cli-first>` — anyone reviewing the result knows
  whether it was observed live or merely asserted.

Net effect: significantly lower token usage per ticket at nearly the same
finding depth — limits are hit later, and from the first retest onward a
repeatable spec exists.

## The three modes

| Mode | How it's tested | Strength | Cost | When |
|---|---|---|---|---|
| `mcp-only` | Model drives live, every step | Deepest findings, catches the unexpected | High | New project without a suite, exploratory, visual tickets, high risk |
| `hybrid` (default) | Probe → spec via CLI → short live check | Near-MCP quality | Medium | The everyday case; pays off from the first retest |
| `cli-first` | Existing suite only; MCP only on unclear failures | Fast, CI-friendly | Low | Maintained suite, regression, pipeline, many low-risk tickets |

**Escalation always applies**, regardless of the configured mode: high ticket
risk, visual/design tickets, missing recon for the area, unclear failures, or
unreproducible bugs automatically escalate to live observation. Conversely, a
test going red does *not* escalate — a clearly classified failure needs no
browser session.

## Separate from that: the model lane

The mode decides **how** testing happens. The model lane decides **how deep**
a branch runs: fast/low → cheap, complex low/medium → standard, high/escalated
→ deep, unknown risk → standard. With multiple branches, the lane is chosen
per branch. Claude uses haiku/sonnet/opus; opencode inherits without config or
uses the provider models chosen under `/model-setup`.

## Switching / using

### Per project (one-time)

In `projects/<KEY>/PROJECT.md`, section **Execution mode**:

```markdown
## Execution mode

- **Mode**: `hybrid`          ← mcp-only | hybrid | cli-first
- **Verification pass**: `yes` ← short live check after green CLI run
- **Red check required**: `yes` ← new specs must prove failure once
- **Escalate at risk**: `high` ← always live from this risk level
- **Plan approval**: `yes`     ← test plan shown and confirmed before execution
```

**Existing projects:** run `/re-board <KEY>` — the dialog offers the new
section, `hybrid` is the recommended default.

**New projects:** `/onboard-project` asks for the mode up front (one question,
rest are defaults).

### Per ticket (any time)

The project mode is just the default. Override in chat:

- "test SHOP-123 **fully live**" → mcp-only for this run
- "the suite is enough" → cli-first for this run

### Standalone

`/recon SHOP-123` — just the recon: writes `recon.json` (real selectors,
console errors, screenshots) into the run directory. Ideal before writing a spec.

## What does NOT change

- **Evidence remains mandatory**: no result without
  `evidence/<KEY>/<TICKET>/<ts>/` including `execution_summary.json` — the
  Stop hook continues to enforce this.
- **Shadow mode** stays on until you turn it off in the project.
- **Report format** (Cloud = ADF, Data Center = wiki markup) unchanged.
- **Both Playwright and WebdriverIO** are supported — the probe exists in both
  variants with the same result format.

## Background for the curious

The technical description (phases, file contracts, escalation rules in detail)
lives in `docs/pipeline/` — starting with `00-overview.md`.

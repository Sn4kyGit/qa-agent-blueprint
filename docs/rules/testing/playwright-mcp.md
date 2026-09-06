# Playwright MCP — Usage & Pitfalls

For exploratory testing and bug reproduction, run inside the `test-executor`
subagent (see `.claude/rules/core/token-discipline.md` for why).

## Launch flags (from `.mcp.json`)

`--isolated --headless --secrets .env.playwright-secrets --output-dir evidence/.mcp-out`

- `--isolated`: fresh browser context per session — no cookies/storage leak between
  runs or tickets. Never test two unrelated tickets in one session.
- `--secrets`: login forms are filled by referencing the secret key from
  `projects/<KEY>/PROJECT.md`; the actual value never appears in a tool response.
- `--output-dir`: raw MCP artifacts land in `evidence/.mcp-out/`; copy only the
  curated, relevant ones into the run's `evidence/<KEY>/<TICKET>/<ts>/` directory.

## Snapshot mode over screenshots for navigation

Use the accessibility snapshot (`browser_snapshot`) to decide what to click/fill —
it's structured, cheap, and gives stable refs. Take an actual screenshot only for
evidence capture (failure moment, final PASS shot), not as a way to "look at" the
page before every action — that burns tokens and image budget for no decision
value.

## `browser_find` before assuming a selector

Don't guess selectors from memory or from reading source. Snapshot or `find` the
live page first — the DOM the agent needs to act on is the one actually rendered,
which may differ from what a component file suggests (conditional rendering, A/B
flags, stale local checkout). Check `memory/learnings/selector-failures.md` for
known-unstable patterns before picking a selector strategy.

## Context rot — the failure mode to watch for

A long exploratory session accumulates snapshots, console logs, and stale element
refs. Symptoms: a `ref_N` from ten actions ago no longer matches, or the agent
"remembers" a page state that navigation has since changed. Mitigation:

- Re-snapshot after every navigation or significant DOM change — never reuse a
  ref across a page transition.
- Keep exploratory sessions scoped to one charter (one flow, one bug) — end the
  session and start fresh rather than letting one session sprawl across unrelated
  areas of the app.
- If confidence in the current page state drops, snapshot again rather than
  guessing from what was true a few steps back.

## Reporting out of `test-executor`

Return a verdict (steps taken, what was observed, PASS/FAIL/BLOCKED, evidence
paths) — not the full snapshot/log stream. The orchestrating skill/agent needs the
conclusion, not the transcript.

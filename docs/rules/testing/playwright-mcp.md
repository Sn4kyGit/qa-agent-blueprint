# Playwright MCP — Usage & Pitfalls

For exploratory testing and bug reproduction, run inside the `test-executor`
subagent (see `.claude/rules/core/token-discipline.md` for why).

## Configuration: contract vs. preference

The playwright MCP server is governed by two layers with different owners:

**Contract (the blueprint's, non-negotiable — wired in the MCP server entry):**

- server name `playwright` — skills and hooks match on it.
- `--secrets .env.playwright-secrets`: login forms are filled by referencing
  the secret key from `projects/<KEY>/PROJECT.md`; the actual value never
  appears in a tool response.
- `--output-dir evidence/.mcp-out`: raw MCP artifacts land in
  `evidence/.mcp-out/`; copy only the curated, relevant ones into the run's
  `evidence/<KEY>/<TICKET>/<ts>/` directory.

**Preference (yours — `.playwright-mcp.config.json` in the QA home, referenced
via `--config`):**

```json
{
  "browser": {
    "isolated": true,
    "launchOptions": { "headless": true }
  }
}
```

- `launchOptions.headless`: `true` (default) is CI-safe; `false` runs **headful**
  — a visible browser you can watch while the agent works. Evidence capture
  (screenshots, traces, console logs) is identical either way. Never choose
  headful for unattended/headless `claude -p` runs — there is no display.
- `isolated`: `true` (default) gives a fresh browser context per session — no
  cookies/storage leak between runs or tickets. Never test two unrelated
  tickets in one session. Set `false` for a persistent profile (e.g. to stay
  logged in across sessions) — a deliberate trade-off: state can leak between
  runs, so say so in the evidence when a result depends on it.
- Everything else Playwright MCP's config schema offers (viewport, browser
  channel, device emulation, timeouts) is fair game here too.

The file is seeded with defaults on first session start / by `install.sh`, and
**the server reads it at launch: edits apply after a restart of Claude Code**
(`/reload-plugins` keeps the live connection while the server args are
unchanged, so it does not pick up file edits). Seeding never overwrites — once
the file exists, it is yours.

Your own playwright server instead of the blueprint's? A same-named entry in
the project `.mcp.json` does **not** override the plugin's server — Claude Code
runs both (verified). So: one source per server name; if you bring your own,
it must carry the contract above, and in plugin mode the plugin's entry stays
unless the plugin itself is disabled.

## One browser per session — never parallel browser agents

One playwright MCP server = one browser instance per Claude/opencode session.
Subagents do **not** get their own browser: two `test-executor` agents spawned
in parallel share the same tab, navigation and credential state and contaminate
each other (cross-navigation mid-flow, one variant seeing another's data —
field report 2026-09: three parallel runs, zero usable evidence, all re-run
sequentially). Rules that follow:

- The orchestrator (`qa-manager` or you) launches a browser-driving subagent
  only after the previous one has returned. Deterministic CLI runs
  (`test-automator` via the Playwright/WDIO runner) are unaffected — the runner
  manages its own browser instances per spec.
- The same applies within one chat: finish (or explicitly close) one
  exploratory browser flow before starting an unrelated one — see `isolated`
  above and "Never test two unrelated tickets in one session".
- If results ever smell like contamination (data from another variant, a login
  you never performed, navigation you never triggered): discard the run, mark
  it NO_TEST with the reason, and re-run sequentially. Contaminated evidence is
  worse than no evidence.

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

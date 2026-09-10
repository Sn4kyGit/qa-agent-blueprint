# Selenium Grid as the WDIO remote backend

Load this when the suite's `wdio.conf.ts` points at a remote hub instead of a
local browser driver — i.e. `hostname`/`port`/`path` are set, or capabilities
carry `selenoid:`/`grid:`-style options. The specs themselves do not change;
what changes is how you connect, what can go wrong between runner and browser,
and where failure evidence lives.

## Connecting

- Remote settings live in the suite's config (`hostname`, `port`, `path` —
  commonly `/wd/hub` — `protocol`). Point runs at stage-specific hubs through
  the suite's existing env-var mechanism; never hardcode a hub URL into a spec.
- Capabilities stay minimal and explicit: `browserName`, `browserVersion`,
  `platformName`. Every extra capability is a Grid-matching constraint that can
  silently route your session to a differently-patched node.
- Grid user/secret, if any, is a **secret reference** in the project's
  PROJECT.md (env var name), never a value in config or chat —
  `.claude/rules/core/security.md`.

## Grid-specific failure modes (know these before blaming the product)

- **Session startup timeouts** under load: the hub queued longer than
  `connectionRetryTimeout`. Retry the run once; if it persists, that is a
  BLOCKED-on-infrastructure, not a product FAIL.
- **Stale/orphaned sessions** leaking from crashed runs exhaust slots and make
  later runs time out. A suite that degrades over the day is a Grid hygiene
  problem — say so in the evidence.
- **Node clock skew** breaks absolute-time assertions; prefer relative waits
  (`waitUntil` with a condition) over wall-clock arithmetic.
- Distinguish in the evidence: *spec failure* (the app behaved wrong) vs.
  *infrastructure failure* (session, hub, node). `failure-analysis` cannot do
  that distinction from a stack trace alone — your run notes carry it.

## Evidence on Grid

The runner's machine reporter still produces `test_cases[]`; Grid adds visual
proof:

- If the hub records **video** (Selenoid/dynamic Grid do, classic hub does
  not), pull the failing session's file into the evidence run dir.
- **Session logs** (browser/driver log where exposed) belong in evidence on
  every FAIL — they are the Grid equivalent of Playwright's trace.
- Record the session ID in `execution_summary.json` notes; it is the join key
  between your report and whatever the Grid dashboard shows.

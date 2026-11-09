---
name: recon
description: Run pipeline phase 2 (recon) for a ticket or area — probe script (Playwright or WebdriverIO) that observes pages and writes recon.json with the real selectors, console errors and screenshots into the run dir. Use for "/recon <KEY-123>", "erkunde die Seite vor dem Test", or whenever a spec would otherwise be written blind. Not for live exploratory testing — /exploratory-testing.
license: Apache-2.0
---

# /recon — observe before you assert

A spec written without seeing the page guesses its selectors — the second-most
common cause of worthless CLI results (docs/pipeline/00-overview.md). This
skill produces `recon.json`: real controls with role and accessible name, form
fields, console errors, failed requests, screenshots — for a fraction of the
tokens an MCP session costs. Full phase contract: `docs/pipeline/02-recon.md`.

## Steps

1. **Resolve scope.** Ticket key (or `--project <KEY> --product <PRODUCT>`
   headless). Read the effective project file: "Execution mode" (on
   `cli-first`, reuse an existing `recon.json` unless expired — do not re-probe
   by habit) and "Test assets" → **Framework** (`playwright` → `recon.spec.ts`;
   `webdriverio` → `recon.wdio.spec.js`).
2. **Run dir.** Reuse the active run dir
   (`evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/`) when called mid-pipeline;
   standalone, create a fresh one. Never overwrite an existing `recon.json` in
   a reused dir — note the refresh in `progress.md` instead.
3. **Paths.** From `intake.json` → `affected_paths` when present; else from the
   ticket plus confirmed Areas in `flow-map.md`. Never derive paths by scanning
   the app source or treat Unconfirmed candidates as established routes.
4. **Ensure the probe exists.** Templates ship with `scaffold-suite`
   (`templates/probes/`). Suite has no `probes/` copy yet → copy the matching
   variant there (it is infrastructure, commit it; part files and recon output
   stay in the run dir).
5. **Run** per the probe README: `RUN_DIR`, `BASE_URL` from the project's stage
   URL, credentials injected via `qa-secrets.mjs run` — never literal, never
   wholesale dotenv. Logged-in recon via `STORAGE_STATE` when the flow needs it.
6. **Merge**: `node probes/merge-recon.mjs <RUN_DIR>`. Only its stdout summary
   enters the context — never the part files or the full `recon.json`
   (token rule, `docs/pipeline/02-recon.md`).
7. **Report back**, 3–5 lines: pages probed, control/field counts per page,
   observations (console errors, ≥400 responses, a11y, slow pages), path of
   `recon.json`. On a page unreachable → that is a finding, not a retried run.
8. **Expiry check**: if a previous `recon.json` for this area exists and the
   new run shows different controls, say so — specs built from the old recon
   are outdated (re-run recon, don't patch specs onto a changed page).

This skill writes no summary of its own: when the calling flow writes the run's
`execution_summary.json`, `recon` belongs in its `skills_used` if this skill
actually ran (`.claude/rules/core/evidence-policy.md`).

## MCP instead of probe

Unclear interaction, non-reproducible bug, visual assessment, or
`Mode: mcp-only` → skip the probe and charter `test-executor`
(`exploratory-testing`) instead. The session still produces the phase artifact:
at its end the executor writes `recon.json` into the run dir with what it
observed — pages, controls (role + accessible name), form fields, console
errors, failed requests — in the probe output format
(`docs/pipeline/02-recon.md`, `"source": "mcp"`). Both recon paths are
producers of `recon.json`; the expiry check (step 8) applies to MCP output too.

## What this skill never does

Load `recon.json` or part files wholesale into the context. Assert behavior
(the probe claims reachability only). Write credentials anywhere. Scan the
application source for paths.

# Probes

Throwaway scripts for the recon phase (docs/pipeline/02-recon.md). They claim
nothing, they only observe. Test cases belong in the suite's spec dir, not here.

## Playwright: recon.spec.ts

Visits paths and captures what is actually on the page: title, heading
structure, interactive elements with role and accessible name, form fields,
images without alt, links, console errors, failed requests, load time,
screenshot.

```bash
RUN_DIR=evidence/<KEY>/<TICKET>/<ts> \
BASE_URL="$STAGE_BASE_URL" \
PROBE_PATHS=/cart,/checkout \
node .claude/scripts/qa-secrets.mjs run <SECRET_KEYS…> -- \
  npx playwright test probes/recon.spec.ts --reporter=line

node probes/merge-recon.mjs evidence/<KEY>/<TICKET>/<ts>
```

Logged-in recon: set `STORAGE_STATE=<path>` and reference it in the Playwright
config.

## WebdriverIO: recon.wdio.spec.js

Same contract, for suites whose PROJECT.md → "Test assets" → Framework is
`webdriverio`. Runs through the suite's own `wdio.conf.ts`:

```bash
RUN_DIR=evidence/<KEY>/<TICKET>/<ts> \
BASE_URL="$STAGE_BASE_URL" \
PROBE_PATHS=/cart,/checkout \
npx wdio run wdio.conf.ts --spec probes/recon.wdio.spec.js
```

Note: WDIO's `browser.execute` cannot capture browser console errors or network
responses the way Playwright's page events do — `console_errors` and
`failed_requests` stay empty unless the suite wires a devtools/bidi session.
The DOM observation (controls, fields, headings) is identical.

## Why this comes before the spec

The resulting `recon.json` contains the **real** selectors. A spec built from
it does not guess — blind selector guessing is the most common cause of CLI
results coming out worse than live observation (docs/pipeline/00-overview.md).

## Token rule

Only the stdout of `merge-recon.mjs` enters the context window — not the part
files, not the full `recon.json`. Read targeted page sections from `recon.json`
when the test plan needs them.

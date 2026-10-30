# Pipeline 02 — Recon

Goal: know what is actually on the page **before** a test case or spec is
formulated. This phase eliminates blindly guessed selectors — the second-most
common cause of worthless CLI results (00-overview §"Why CLI results come out
worse").

## Tool choice

| Situation | Tool |
|---|---|
| Content, structure, links, console errors | probe script |
| Flow with unclear interaction | MCP session (`test-executor`) |
| Non-reproducible bug | MCP session |
| Visual assessment | MCP session |
| `Mode: mcp-only` | always MCP |
| `Mode: cli-first` | reuse the last `recon.json`; re-probe only when expired |

## Probe script (default, very cheap)

The probe ships with `scaffold-suite` (`templates/probes/`): a throwaway spec
that visits the affected paths and reports back structured observations — page
title, heading structure, interactive elements with role and accessible name,
form fields, images without alt, console errors, failed requests, load time,
screenshot. Ten pages cost fewer tokens than three MCP clicks.

Run it via the `/recon` skill (which wraps the mechanics, including the WDIO
variant for suites whose "Test assets" → Framework is `webdriverio`):

```bash
TICKET=SHOP-1234 RUN_DIR=evidence/SHOP/SHOP-1234/<ts> \
BASE_URL="$STAGE_BASE_URL" PROBE_PATHS=/cart,/checkout \
node .claude/scripts/qa-secrets.mjs run STAGE_USER STAGE_PASSWORD -- \
  npx playwright test probes/recon.spec.ts --reporter=line

node probes/merge-recon.mjs evidence/SHOP/SHOP-1234/<ts>
```

The script writes one part file per page; the merge step produces `recon.json`
plus a compact stdout summary. **Never** load the part files or the full
`recon.json` into context — read the merge summary, then only the page sections
the test plan needs.

## MCP session

When an MCP session is needed, it runs **always inside the `test-executor`
subagent**, so page snapshots never fill the main session. Navigate directly to
the deep URL instead of clicking through; one step at a time; screenshot only
where it lands in the report. The subagent returns findings, not snapshots —
the existing `exploratory-testing` charter applies.

At session end the subagent **writes `recon.json` into the run dir** — same
contract as the probe output below (`"source": "mcp"`): the pages observed with
their controls, form fields, console errors and failed requests. Both recon
paths are producers of the file; without the MCP path writing it, every
MCP-reconnoitred area would trip the "no `recon.json` exists" escalation
trigger (00-overview) forever.

## Output: `recon.json` in the run dir

**Producers:** `merge-recon.mjs` on the probe path, the `test-executor`
subagent on the MCP path — both write this file.

```json
{
  "source": "probe",
  "created": "2026-09-24T11:30",
  "base_url": "https://stage.example.invalid",
  "pages": [
    {
      "path": "/checkout",
      "title": "Checkout",
      "status": 200,
      "headings": ["H1: Checkout", "H2: Payment"],
      "controls": [
        { "role": "textbox", "name": "Coupon code" },
        { "role": "button",  "name": "Apply code" }
      ],
      "form_fields": [
        { "label": "Coupon code", "type": "text", "required": false }
      ],
      "images_without_alt": 0,
      "console_errors": [],
      "failed_requests": [],
      "screenshot": "evidence/SHOP/SHOP-1234/<ts>/screenshots/recon-checkout.png"
    }
  ]
}
```

## Expiry

When a new probe run reports different `controls` than the stored `recon.json`
the spec was built from, that spec is outdated. Re-run recon — do not patch the
spec onto a changed page. This complements `test-reliability` (which heals a
single broken locator at runtime): expiry is about the *page structure* having
moved, not about one selector breaking.

---
name: qa-help
description: Show the blueprint's command overview — every slash command, what it does, and when to use it, plus the natural-language alternatives. Use for "/qa-help", "help", "welche Befehle gibt es", "was kannst du", "what commands are there", "how do I test a ticket", or whenever the user seems lost about what this plugin can do. Not for testing a ticket — this only explains commands; route testing requests to /test-ticket.
---

# /qa-help — what this blueprint can do

Render the overview below, then stop. Do not start any work from it — if the
user picks a command, run that skill next. **Answer in the user's language.**

You do not need to memorize commands: plain language works. "Test SHOP-123",
"re-test the fix on WEB-456", "how is testing going" all route to the right
skill. The slash commands below are the explicit, guaranteed form. In plugin
mode they are namespaced: `/qa-agent-blueprint:<name>`.

## Test a ticket

| Command | What it does |
|---|---|
| `/test-ticket <KEY-123>` | The main entry: reads the ticket, routes to project + product, checks stage, picks the test strategy, produces evidence, reports the verdict back to JIRA. |
| `/retest-bug <KEY-123>` | Re-plays the original repro steps of a fixed bug, then a tight regression sweep around the spot. |
| `/exploratory-testing` | Chartered, timeboxed exploratory session via Playwright MCP — for new features or unclear behavior with no repeatable spec yet. |
| `/test-automation` | Writes or runs deterministic specs in the project's framework (Playwright or WebdriverIO) once a flow is understood and worth repeating. |

## React to a result

| Command | What it does |
|---|---|
| `/failure-analysis` | Triages a FAIL before any bug is filed: real product defect, or outdated test case? Runs automatically on every FAIL. |
| `/bug-report` | Turns a finding into a bug ticket in the project's own template. |
| `/report-to-jira` | Posts the verdict comment + attachments + workflow transition to JIRA (composes only, while shadow mode is on). |
| `/deploy-to-stage` | Runs the project's stage-deploy runbook when the fix isn't on stage yet. |

## Set up

| Command | What it does |
|---|---|
| `/onboard-project` | One-time interview per JIRA project — run this first for a new project key. |
| `/onboard-product` | Short onboarding for a product inside an existing project. |
| `/re-board <KEY>` | Delta-onboarding: brings an existing project up to the current blueprint schema (new fields, missing files, open TODOs) without repeating the full interview — the upgrade path after a blueprint update. |
| `/scaffold-suite` | Creates the Playwright test project when a product has no test assets yet. |

## Knowledge & meta

| Command | What it does |
|---|---|
| `/qa-report` | Aggregates all evidence runs into QA metrics: pass rate, P0/P1, BLOCKED reasons, per project and product. |
| `/retro-learn` | Captures and promotes learnings — runs at session end, or explicitly to groom. |
| `/whats-new` | What changed in the blueprint since your projects were onboarded — and which changes call for `/re-board`. |
| `/qa-help` | This overview. |

## Three things worth knowing

1. **Shadow mode is on by default** — the agent composes JIRA comments but
   posts nothing until `Shadow mode: off` is written in the project file.
2. **The specialist skills** (api, accessibility, security, visual, …) are
   pulled by qa-manager itself when the product's feature matrix calls for
   them — you don't invoke them directly.
3. **Evidence is mandatory**: every run ends with a verdict (PASS, FAIL,
   BLOCKED, NEEDS_REVIEW, NO_TEST) and artifacts under `evidence/`.

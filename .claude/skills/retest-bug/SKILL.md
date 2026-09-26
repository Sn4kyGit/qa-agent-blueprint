---
name: retest-bug
description: Focused re-test of a fixed bug plus a tight regression sweep — scoped from the product's flow-map.md Neighbors when available, risk-based otherwise. Use for "/retest-bug <KEY-123>", "re-test <KEY-123>", "teste <KEY-123> nochmal", "gegentesten", or when a fix has landed on stage ("der Fix ist auf Stage", "fix is deployed/verified on stage — retest it"). Not for first-time tests — test-ticket.
---

# /retest-bug — verify a fix + surrounding regression

A narrower, faster variant of `test-ticket` for bugs that already have a known
repro from the original report.

## Steps

0. Run the preflight first (same gate as `test-ticket`): the blueprint's
   `preflight.sh <KEY>` must pass before any browser/JIRA call — a re-test
   against a half-reachable VPN state produces exactly the false results the
   gate exists to prevent.
1. Read the ticket — pull the **original bug report** (description, comments) to
   get the exact repro steps and the expected-vs-actual from the first report.
   Route to `projects/<KEY>/PROJECT.md` + `learnings.md` as usual — and on to the
   ticket's product if the project has a `## Products` section
   (`.claude/rules/core/product-layer.md`). A re-test is where a wrong product hurts
   most: the original repro was recorded against one product's URL and test users. If the original
   report is thin or the repro steps are vague/incomplete, run `bug-reproduction`
   first to extract a verified, minimal, deterministic repro before retesting
   anything — retesting against a repro nobody actually confirmed is a guess, not
   a test. Point it at `.agents/qa-project-context/<KEY>.md` — or, when a product
   was routed, `.agents/qa-project-context/<KEY>/<PRODUCT>.md` — explicitly (see
   `CLAUDE.md` → project routing); never the generic path it mentions internally,
   which may hold a different project's or product's data.
2. Verify stage actually has the fix deployed (version check per the project
   file) before testing — retesting against the pre-fix build produces a false
   FAIL. If not deployed, run `deploy-to-stage` (if allowed) or report BLOCKED.
   Read `PROJECT.md` → "Execution mode" now — it decides who executes step 3:
   - **`cli-first` / `hybrid`** — if a spec covers the bug's flow, the re-test IS
     the spec: run it via `test-automator` (the bug should have graduated into a
     spec after the first fix — the exploration-to-automation pipeline). No spec
     yet and selectors unknown → `/recon` probe first, then the spec. MCP enters
     only to classify an unclear CLI failure.
   - **`mcp-only`**, or an escalation trigger (the bug is not reproducible, the
     fix is visual, the flow can't be asserted without observing it) → live via
     `test-executor` as below. Never escalate merely because a test is red.
3. Execute the re-test: **re-execute the exact original repro
   steps** first (spec or live, per the mode above). This is the primary check —
   did the specific reported behavior
   change? `bug-reproduction`'s red-before-fix discipline applies here in reverse:
   if you have access to the pre-fix build/commit, confirming the repro still
   failed there (and now passes on the fix) is stronger evidence than testing the
   fix alone.
4. Regression sweep: check 2–4 adjacent flows the fix could plausibly have
   affected (same component, same code path, same feature area) — not the whole
   application. **When a flow map exists** (`projects/<KEY>/flow-map.md`, or
   `projects/<KEY>/products/<PRODUCT>/flow-map.md` for a routed product — the
   bridge file carries it as `## Flow map` when present): take the sweep from
   the **Neighbors** of the fixed flow's area instead of improvising, and say so
   in the evidence ("sweep scoped from flow map, area Checkout"). No flow map →
   risk-based as before, per `.claude/rules/core/qa-principles.md`. A flow map
   whose `last confirmed` dates are old narrows nothing — then prefer fresh
   judgment over stale neighbors. The sweep runs in the same mode as step 3 —
   in `cli-first`/`hybrid` that means the neighboring specs via CLI, live only
   for what no spec covers and an escalation trigger names.
5. **If anything fails, analyse before concluding "not fixed".** Run
   `failure-analysis` (subagent `failure-analyst`) on the failing cases. A re-test is
   where the two cheap wrong answers live: the fix was never deployed (class
   `environment` → BLOCKED, not FAIL), and **the original repro is itself outdated**
   — a fix that changed the flow can make the recorded steps unfollowable without
   the fix being absent. Neither is "the bug is back", and reporting them as such
   burns the reporter's trust in our re-tests.
6. Evidence and reporting exactly as in `test-ticket`: evidence dir with
   `execution_summary.json`, then `report-to-jira` on PASS or `bug-report` +
   `report-to-jira` if the fix didn't hold or a regression was introduced.

## If the bug is not actually fixed

Do not soften this into a "partial pass." Report FAIL, keep the original ticket
open/reopened per the project's FAIL transition, and note precisely what part of
the original repro still reproduces.

The opposite error is just as expensive: do not report "not fixed" when the truth is
"not deployed", or when the repro steps no longer match a flow the fix deliberately
changed. That is what step 5 is for — the analysis distinguishes them, and only
`product-defect` and `undetermined` justify reopening.

## If a regression was introduced

File it as a **new** bug via `bug-report` (don't conflate it with the original
ticket) and cross-reference both tickets.

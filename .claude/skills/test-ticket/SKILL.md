---
name: test-ticket
description: Test a JIRA ticket end to end — read the ticket, route to the project, verify/deploy stage, execute the test strategy, produce evidence, report the verdict to JIRA. Use for "/test-ticket <KEY-123>", "teste <KEY-123>", "prüf das Ticket", or any verify-a-ticket request. Not for re-testing fixed bugs (retest-bug) or writing repeatable specs (test-automation).
license: Apache-2.0
---

# /test-ticket — dispatch the full ticket workflow

The primary entry point. The agent loading this skill is the **main orchestrator**:
it performs preflight, intake, routing and readiness exactly once. A simple run then
goes directly to one execution leaf; only a complex run delegates its remaining
orchestration to `qa-manager`.

## Steps

1. Parse the ticket key from the argument (`SHOP-1234`). If missing, ask for one.
   An explicit product (`--product=ADMIN`, or "test this in the admin") overrides
   automatic product routing. Read enough of `projects/<KEY>/PROJECT.md` to run the
   preflight and select the JIRA access channel. Unknown project prefix or missing
   project file → stop and run `onboard-project` (or tell the user to). A
   half-registered product → stop and run `onboard-product`; never guess a process.
2. **Run preflight once, before any browser or JIRA call** (the blueprint's
   `preflight.sh <KEY>`; the pre-tool guard enforces it). Then make the trivial
   Atlassian read on `mcp` access. Do **not** navigate Playwright to stage for
   liveness yet. **JIRA access `browser` is the explicit exception**: intake through
   the playwright-driven JIRA UI per `docs/rules/testing/jira-browser.md` is allowed
   now; this exception covers JIRA only, never stage.
3. **Intake and route once.** Fetch the targeted ticket fields, number the ACs,
   assess testability and risk, and write `intake.json` per
   `docs/pipeline/01-intake.md`. Route to `projects/<KEY>/PROJECT.md`; search its
   `learnings.md` only for the ticket's area, component, flow and failure keywords.
   Add a product only when `## Products` exists and the registry matches, using the
   same targeted Learnings lookup (`.claude/rules/core/product-layer.md`). Load a
   flow map only when the mode needs it for recon, planning, retest or a charter,
   and treat only confirmed Areas as binding. Resolve ambiguity before stage;
   headless reports BLOCKED. Carry the resolved scope into every later delegation.
4. **Gate on readiness before the first stage action.** Apply
   `docs/pipeline/01a-readiness.md` and write `readiness.json`: allowed JIRA status,
   no unresolved blockers, linked MR/PR merged when the project's merge policy
   requires it, and expected build deployed (or the explicitly configured
   `Build verification: unavailable`, reported as unverified). Prefer API/CLI checks. Only after a
   ready result may one Playwright navigation check stage liveness and recon or test
   execution begin. A missing merge/required build is BLOCKED or a `deploy-to-stage` handoff
   followed by re-verification — never a test against a known-wrong state.
5. **Read shadow mode and decide strategy from the effective Execution mode.**
   Shadow mode, evidence and reporting remain unchanged. `mcp-only` uses
   `test-executor`; `cli-first` uses the existing suite through `test-automator`;
   `hybrid` requires recon before specs, the red check for new specs, and its
   configured live verification pass. Escalation triggers still override every mode
    (`docs/pipeline/00-overview.md`); a red test alone is not one. A routed product's
    feature/test-method matrix and any required specialized skill remain binding.
 6. **Seal the run context once.** Write
    `evidence/<KEY>/<TICKET>/<RUN>/context-capsule.json` per
    `docs/pipeline/context-capsule.md`, embedding the exact intake/readiness and the
    resolved effective config, relevant confirmed knowledge and source hashes. Run
    `context-capsule.py seal` and one full `validate` with `--qa-home` and
    `--run-dir`. Revision 1 is `context-capsule.json`; revision N>1 must be
    `context-capsule.vN.json` in the same run dir and every predecessor stays intact.
    The capsule is immutable; pass the selected revision path, never its full text,
    in a Task prompt. A later build/readiness or effective-context change returns to
    this orchestrator for readiness re-verification and a new revision, never
    recipient-side repair. Changed same/older-revision payloads conflict; identical
    reseals are idempotent and invalid existing hashes are never overwritten.
 6b. **Write `testplan.md` before execution starts** (`docs/pipeline/03-planning.md`).
     The plan's producer is the planning agent: the main orchestrator on the Fast
     Path, `qa-manager` on the complex path (its own flow writes the file; the
     complex handoff may carry a plan already produced).
 7. **Dispatch exactly one way:**
   - **Fast Path** — only when intake is unambiguously `testable`, risk is `low`, no
     escalation trigger applies, no specialized/multi-area orchestration is needed,
     and the effective mode needs **exactly one execution branch**. The main
     orchestrator delegates directly to `test-executor-cheap` **or** `test-automator-cheap`,
       with the selected sealed revision path and charter/plan; no PROJECT/PRODUCT full reads,
      re-routing, mode/suite lookup or repeated Learnings merge.
     No `qa-manager` spawn. For hybrid, a required live verification pass is a
     second branch and therefore excludes the Fast Path; recon and plan approval
     keep their normal mode rules.
   - **Complex path** — anything else: invoke `qa-manager` with the ticket key, run
     dir, selected sealed revision path and any recon/plan already produced. It consumes the
     capsule and must **not read the ticket or PROJECT/PRODUCT files, route, repeat
     readiness, or redo mode/suite lookup and Learnings merging**.
     It owns the remaining mode-conformant phases and execution delegations.
   Announce and relay every delegation as `qa-manager`'s "Delegation is visible"
   section prescribes; browser-driving leaves remain sequential.
 8. **On FAIL, the orchestrator that owns the run starts `failure-analyst`** with all
    failing cases, the failure packet and selected sealed revision path — the main orchestrator
    on the Fast Path,
   `qa-manager` on the complex path. Never make `test-executor` or `test-automator`
   delegate to the analyst. The same orchestrator writes/merges the analysis and
   applies the class-specific next step (`bug-reporter`, BLOCKED, NEEDS_REVIEW or
   reliability handling) before reporting.
 9. Verify `execution_summary.json` and the required evidence, then report through
    `report-to-jira` on PASS/FAIL/BLOCKED/NEEDS_REVIEW exactly as before, including
    the mode and shadow behavior. The summary's `skills_used` names every skill
    this run actually invoked (this one, `recon`, the execution leaf's skill,
    `failure-analysis`, …) — never merely planned ones
    (`.claude/rules/core/evidence-policy.md`). Finish with `retro-learn` capture and the mandatory
    `learnings` declaration; unexpected routing corrections follow the standing rule.

## Output to the user

A short summary: ticket, project (and product, if one was routed — plus how it was
resolved), verdict, JIRA comment link (or bug ticket key if FAIL) — and the key
evidence files each as an **absolute path**, one per line (screenshot, trace,
execution summary). Absolute paths are clickable in the harness UI; a relative
`evidence/...` path resolves against an arbitrary cwd and leads nowhere. Do not
restate the full test transcript — that lives in the run dir and in the JIRA
comment itself (which, per `docs/pipeline/06-reporting.md` → "Two output
channels", never contains these local paths).

Then, on an interactive macOS session, open the run dir in Finder:
`open "<absolute run-dir path>"` — one window with every screenshot/log,
Space-key preview. Skip silently on Linux, CI and headless runs; a failed
`open` never blocks the report. Full rule: `docs/pipeline/06-reporting.md` →
"Finder auto-open".

## Hard rules that apply here (see the router)

Evidence is mandatory (the evidence gate enforces it), no secrets anywhere in the output,
no full-repo scans — start from `memory/INDEX.md` and the project file. No stage
browser navigation, recon or execution before readiness; no universal MR/PR
requirement beyond the effective project's merge policy.

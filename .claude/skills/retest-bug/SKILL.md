---
name: retest-bug
description: Focused re-test of a fixed bug plus a tight regression sweep — scoped from the product's flow-map.md Neighbors when available, risk-based otherwise. Use for "/retest-bug <KEY-123>", "re-test <KEY-123>", "teste <KEY-123> nochmal", "gegentesten", or when a fix has landed on stage ("der Fix ist auf Stage", "fix is deployed/verified on stage — retest it"). Not for first-time tests — test-ticket.
license: Apache-2.0
---

# /retest-bug — verify a fix + surrounding regression

A narrower variant of `test-ticket` for bugs with a known repro. It uses the same
dispatcher: the agent loading this skill is the main orchestrator and performs
preflight, intake, routing and readiness once; only a complex re-test hands the
remaining orchestration to `qa-manager`.

## Steps

0. Run `preflight.sh <KEY>` before any browser/JIRA call. Do not navigate to stage
   for liveness yet. JIRA access `browser` may use the playwright-driven JIRA UI
   for intake now; that exception never includes stage.
1. Read the original bug report (description, expected-vs-actual and exact repro,
   plus the last relevant comments) and route once to `projects/<KEY>/PROJECT.md` +
   `learnings.md`, then to a product only per the `## Products` registry. Write
   `intake.json` with the repro, expected build, risk and regression area. If the
   repro is vague/incomplete, extract only ticket-held environment, build, steps and
   data now; mark live `bug-reproduction` as a Complex-path escalation after
   readiness, pointed at the routed `.agents/qa-project-context/<KEY>[/PRODUCT].md`
   bridge. Do not reproduce on stage during intake.
2. Apply `docs/pipeline/01a-readiness.md` and write `readiness.json` before any
   stage navigation, recon or spec run: project-allowed status, no blockers, linked
   MR/PR merged when required/present under the merge policy, expected fix build
   deployed when verification is required. Prefer API/CLI. If the build is missing,
   use `deploy-to-stage` only
   when allowed and then re-verify; otherwise BLOCKED. Only a ready result permits
   the one stage-liveness navigation and execution.
3. Read the effective Execution mode and scope the work:
   - **`cli-first` / `hybrid`** — an existing spec covering the repro and its tight
     regression sweep runs through `test-automator`. New specs still require recon
     and the red check; hybrid's configured live verification pass still applies.
   - **`mcp-only`**, or an escalation trigger (non-reproducible bug, visual fix,
     non-assertable behavior) — live through `test-executor`. Never escalate merely
     because a test is red.
 4. Seal `evidence/<KEY>/<TICKET>/<RUN>/context-capsule.json` once per
    `docs/pipeline/context-capsule.md`, with exact intake/readiness, effective
    config, relevant confirmed knowledge and source hashes. Run
    `context-capsule.py seal` and one full `validate` using `--qa-home` and
    `--run-dir` before dispatch. Revision 1 is `context-capsule.json`; revision N>1
    must be `context-capsule.vN.json` in the same run dir with every predecessor
    preserved. Pass only the selected revision path in Task prompts. A changed
    build/readiness or effective context returns to this orchestrator for readiness
    re-verification and a new immutable revision. Changed same/older-revision
    payloads conflict; identical reseals are idempotent and invalid existing hashes
    are never overwritten.
 5. Dispatch by complexity:
    - **Fast Path** — unambiguously testable, low risk, no escalation, exactly one
      mode-conformant execution branch: the main orchestrator invokes
      `test-executor-cheap` OR `test-automator-cheap` directly with the selected sealed revision path and
      repro/sweep charter. No PROJECT/PRODUCT full reads, re-routing, mode/suite
      lookup or repeated Learnings merge in the leaf. No `qa-manager`.
    - **Complex path** — invoke `qa-manager` with the selected sealed revision path, run dir
      and any recon/plan. It consumes the capsule without reading the ticket or
      PROJECT/PRODUCT files, routing, repeating readiness, or redoing mode/suite
      lookup and Learnings merging, and owns the remaining phases.
 6. Execute the exact original repro first, then **2–4 adjacent checks**, not the
    whole application. Prefer the fixed flow's **Neighbors** from confirmed Areas in
    the routed `flow-map.md` and record that provenance. `Unconfirmed candidates`,
    basis-less Neighbors and stale or absent maps are not binding scope: use
    risk-based judgment around the actual defect instead. Keep the sweep in the same
    mode, with live observation only where a
   real escalation trigger requires it. When a pre-fix build/commit is available,
   proving the old failure there and the fix on the expected build is stronger
   evidence; never deploy or roll back solely to manufacture it.
7. **On FAIL, the owning orchestrator invokes `failure-analyst`** with the sealed
   selected revision path and failure packet — main on the Fast Path, `qa-manager` on the complex path; never the execution leaf. Distinguish a
   genuine product defect from a missing/wrong build (`environment` → BLOCKED), a
   flake, or an original repro made outdated by the deliberate fix. Only
   `product-defect` and `undetermined` justify reopening; class-specific evidence
   and reporting stay unchanged.
 8. Produce `execution_summary.json` and all mandatory evidence, then use
    `report-to-jira` on PASS and the classified FAIL/BLOCKED/NEEDS_REVIEW paths as
    in `test-ticket`. The summary's `skills_used` names every skill this re-test
    actually invoked (this one, `recon`, `failure-analysis`, …) — never merely
    planned ones (`.claude/rules/core/evidence-policy.md`). Use `bug-reporter` only after the required classification;
    shadow mode and transitions are unchanged. Close with the learnings declaration.

## If the bug is not actually fixed

Do not soften this into a "partial pass." Report FAIL, keep the original ticket
open/reopened per the project's FAIL transition, and note precisely what part of
the original repro still reproduces. Do not report "not fixed" when the truth is
"not deployed" or the recorded repro no longer matches the deliberately changed
flow.

## If a regression was introduced

After classification as a product defect, file it as a **new** bug via `bug-report`
(do not conflate it with the original ticket) and cross-reference both tickets.

# Pipeline 01a — Readiness gate

Readiness runs **after intake and project/product routing and before the first
stage action**. It answers whether the ticket may be tested on stage now; it does
not replace recon, planning, execution or the preflight's reachability checks.

The main orchestrator performs the gate once and writes `readiness.json` beside
`intake.json`. A complex run hands both artifacts to `qa-manager`, which consumes
them without reading the ticket, routing or repeating readiness. A deploy handoff
re-verifies the same gate after the deploy before execution may start.

## Required checks

1. **Status allowed now.** The ticket's current status is one of the effective
   project file's `Readiness statuses`. A missing or `TODO:` configuration is a
   configuration blocker, not permission to invent a workflow.
2. **No blockers.** No unresolved linked blocking issue, explicit blocker flag or
   equivalent project-specific blocker remains. Record the checked links/fields.
3. **Required merge is complete.** Apply `Merge requirement` from the effective
   project file:
   - `when-linked` — every linked MR/PR relevant to the ticket is merged; no link
     means no merge blocker. This is also the compatibility default when the field
     is absent.
   - `always` — a merged MR/PR is required; a missing link is not ready.
   - `not-required` — no merge check; status, blockers and build still apply.

   There is no universal MR/PR requirement. An open, unmerged, unknown or required
   but missing link is not ready. The agent never merges or approves it.
4. **Expected build is deployed when verification is required.** With
   `Build verification: required` (the default), `intake.expected_build` equals the
   build returned by the project's stage version check; a missing expectation or
   unverifiable version is not ready. With the explicitly onboarded
   `Build verification: unavailable`, the absence of a version source is recorded
   as residual risk rather than a permanent blocker; status, blockers and merge
   still apply, and the report says `Build: unverified (project-configured)`.
   A version source that returns a different build is always BLOCKED. Stage
   reachability or a successful page load never proves the build.

Use the ticket/provider **API or CLI first** for links, merge state, blockers,
pipeline/deployment state and the build check. Record the concrete query/command
and observed values. With JIRA access `browser`, the playwright-driven JIRA UI may
supply JIRA-held intake and readiness facts when no API/CLI path exists. Browser
intake is explicitly allowed before readiness; **stage navigation, recon, probes
and test execution are not**. The one Playwright stage-liveness navigation belongs
after a ready result and immediately before the first stage-dependent phase.

## Not ready

A failed status, blocker, merge or observed build-mismatch check produces
**BLOCKED** with the concrete reason and human handoff. Under required build
verification, a missing expected build produces BLOCKED or, when the project
permits it, a `deploy-to-stage` handoff; after deployment the build and all other
readiness facts are re-verified. Do not run a stage test to fill the wait or
to produce a result against a state already known to be wrong.

## Output: `readiness.json`

```json
{
  "ticket": "SHOP-1234",
  "status": { "actual": "Ready for QA", "allowed": true },
  "blockers": { "checked": ["SHOP-1230"], "unresolved": [] },
  "merge": {
    "requirement": "when-linked",
    "links": ["https://git.example.invalid/shop/web/merge_requests/42"],
    "state": "merged",
    "allowed": true
  },
  "build": {
    "expected": "release-24.9",
    "deployed": "release-24.9",
    "allowed": true
  },
  "checks": [
    { "fact": "merge.state", "source": "glab mr view 42 --output json" },
    { "fact": "build.deployed", "source": "GET /version" }
  ],
  "ready": true,
  "blocked_reason": null
}
```

When `ready` is false, `blocked_reason` names the failed check and the normal
BLOCKED evidence/reporting rules apply. Shadow mode does not alter any readiness
check.

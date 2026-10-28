---
name: exploratory-testing
description: Run a chartered, SBTM-style exploratory testing session via Playwright MCP — for new features, unclear behavior, or bug reproduction without a repeatable spec. Use for "/exploratory-testing", "erkunde das neue Feature", "explorativ testen", "reproduzier den Bug". Not for understood, repeatable flows — use test-automation.
---

# /exploratory-testing — chartered session via Playwright MCP

Session-Based Test Management (SBTM) applied to our ticket-driven flow: a written
charter, a time-boxed session delegated to `test-executor`, heuristic-guided
exploration, and a debrief — not "click around and see what happens."

When a run-scoped `context-capsule.json` path is supplied, use it as the effective
context for this session: exact ACs, routing, stage/test-user references, confirmed
Areas and relevant Learnings. Do not fully read PROJECT/PRODUCT, route again or
repeat the mode/suite/Learnings merge. Pass the capsule path to `test-executor`.
Targeted new symptom/flow Learning reads remain allowed. A stale capsule returns
`STALE_CONTEXT` to the orchestrator; never regenerate it here. Without a capsule,
the standalone fallback below reads the effective project context as before.

## Steps

0. Run the preflight first (same gate as `test-ticket`): the blueprint's
   `preflight.sh <KEY>` must pass before any browser/JIRA call. Do not use a stage
   navigation as an early liveness probe. JIRA access `browser` may use Playwright
   for JIRA intake only.
1. **Write the charter** before starting, in the SBTM pattern:

   ```
   Explore [target]
     with [resources]
     to discover [information]
   ```

   E.g. "Explore the checkout flow's coupon handling, with the `qa-standard` test
   user and three coupon states (valid/expired/exhausted), to discover requirement
   gaps against SHOP-1234's acceptance criteria." Not "test the app." With a capsule, use its selected knowledge. Without one, check
   `memory/learnings/*.md` and `projects/<KEY>/learnings.md` for known risk areas
   or past bug clusters in this area before finalizing the target. When a flow
   map exists (`projects/<KEY>/[products/<PRODUCT>/]flow-map.md`, or the bridge's
   `## Flow map`): confirmed Areas whose `last confirmed` is oldest are charter
   candidates — an unconfirmed flow is a hypothesis, not a truth — and the map
   names the target area precisely. Unconfirmed candidates supply no binding anchors.
2. Confirm project context is loaded: test users, stage URL, environment gotchas.
   Take them from the supplied capsule; only a standalone run without a capsule
   reads `PROJECT.md` plus the routed product's `PRODUCT.md`. Name the product in
   the charter when one is routed.
2b. For a ticket-driven session, finish intake/routing and the readiness contract
   (`docs/pipeline/01a-readiness.md`) before the first stage navigation: allowed
   status, no blockers, required linked merge complete, expected build deployed when
   verification is required (otherwise explicitly configured and reported unverified).
   Prefer API/CLI and write `readiness.json`; missing merge/required build means
   BLOCKED or a deploy handoff, not exploratory clicking. An area-only charter
   needs an explicitly authorized target and, under required verification, an
   expected build; unavailable verification stays documented as unverified.
   Only then may the stage-liveness navigation and this session begin.
3. **Time-box it**: 45–90 minutes of actual exploration. Bug-finding effectiveness
   drops sharply past 90 minutes — split a bigger area into multiple chartered
   sessions rather than one long unfocused one.
4. Delegate the session to subagent `test-executor` with the charter and, when
   available, the sealed capsule path rather than pasted context. It drives
   the configured playwright MCP browser (headless/headful and isolation per the
   user's `.playwright-mcp.config.json`) per `docs/rules/testing/playwright-mcp.md`
   and produces evidence per `.claude/rules/core/evidence-policy.md`. Instruct it
   to explore through the **HICCUPS** lenses, not just the happy path:

   | Letter | Oracle | Ask |
   |---|---|---|
   | H | History | Did this work before? Has behavior changed subtly? |
   | I | Image | Does it look/feel as polished as the rest of the product? |
   | C | Comparable | How do similar products/flows handle this? |
   | C | Claims | Does it match the ticket's acceptance criteria / spec / tooltip text? |
   | U | User expectations | Would a real user find this confusing? |
   | P | Product | Consistent with the rest of this product (e.g. other error messages)? |
   | S | Standards | WCAG, RFC, GDPR — whatever standard applies here? |

   For concrete boundary/state-transition/error-handling/"what if" test-idea banks,
   see `references/heuristics-and-automation.md`. For the session flow (orient →
   explore → wrap-up timing), a session-log template with BUG/QUESTION/IDEA/RISK/NOTE
   tags, and worked charter examples, see `references/session-templates.md`.

   **Mandatory in the orient instructions: the WebMCP capability probe.** Once the
   page under test is loaded, exactly one `browser_evaluate` call:

   ```js
   typeof document.modelContext !== 'undefined'
     ? await document.modelContext.getTools()
     : null
   ```

   If the page registers WebMCP tools, tag them as NOTE/RISK in the session log and
   name them in the debrief as candidates for deeper coverage (schema validity,
   `readOnlyHint` honesty, `exposedTo`/permissions audit). Never use these tools to
   *drive* the session — the UI stays the test target and is driven via Playwright;
   WebMCP tools are extra surface, not a shortcut past it. An orient phase without
   this probe is incomplete.
5. **Debrief, always** — even a solo session. Tag every observation
   (BUG/QUESTION/IDEA/RISK/NOTE) with a timestamp as it happens, not from memory
   afterward. Mark each charter area covered, partial, or unexplored — an honest
   "partial" beats a false "100% covered."
6. **Exploration-to-automation pipeline**: every reproducible bug found here should
   graduate into an automated regression test, so the *next* session explores new
   ground instead of re-checking this one. If the flow itself (not just the bug)
   is worth repeating going forward, hand it to `test-automation` — see the
   worked example in `references/heuristics-and-automation.md`.
7. On a FAIL, the orchestrator running this skill invokes `failure-analyst` with
   the failure packet and, when available, the capsule path before any bug handoff; `test-executor` never delegates to the analyst. A confirmed
   `product-defect`/`undetermined` finding of severity P0–P2 then goes to
   `bug-report`; other classes follow their normal BLOCKED/NEEDS_REVIEW/reliability
   path. Anything unexpected about the environment or tooling itself → capture via
   `retro-learn`.

## When NOT to use this

If a spec already exists for the exact flow, or the check is meant to run
repeatedly (nightly, every retest), use `test-automation` instead —
exploratory sessions are for understanding and bug-hunting, not for repeatable
verification. For risk scoring of *which* areas deserve a chartered session, see
`risk-based-testing`. For turning a vague, already-reported bug into a minimal,
deterministic repro, see `bug-reproduction` instead of a fresh exploratory charter.

## Anti-patterns

- **Unchartered exploration** — "poke around and see" produces nothing repeatable
  or debriefable. Always write the one-sentence charter first.
- **No notes during the session** — observations not recorded in the moment are
  lost by the time the session ends. Use the session-log template, not memory.
- **Happy-path-only exploration** — that duplicates what the automated suite
  already covers. Use the HICCUPS lenses to push into uncomfortable territory.
- **Bugs found but never converted** — finding the same bug manually every release
  because step 6 never happened.

---

*Charter model, HICCUPS/FEW HICCUPS heuristics, and the two reference files in
`references/` are adapted from the `exploratory-testing` skill in
[petrkindlmann/qa-skills](https://github.com/petrkindlmann/qa-skills) (MIT
license) — see `.claude/skills/THIRD_PARTY_NOTICES.md`.*

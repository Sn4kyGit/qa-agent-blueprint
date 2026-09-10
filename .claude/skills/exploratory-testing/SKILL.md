---
name: exploratory-testing
description: Run a chartered, SBTM-style exploratory testing session via Playwright MCP — for new features, unclear behavior, or bug reproduction where no repeatable spec exists yet. Use for "/exploratory-testing" or when a ticket needs first-look investigation.
---

# /exploratory-testing — chartered session via Playwright MCP

Session-Based Test Management (SBTM) applied to our ticket-driven flow: a written
charter, a time-boxed session delegated to `test-executor`, heuristic-guided
exploration, and a debrief — not "click around and see what happens."

## Steps

1. **Write the charter** before starting, in the SBTM pattern:

   ```
   Explore [target]
     with [resources]
     to discover [information]
   ```

   E.g. "Explore the checkout flow's coupon handling, with the `qa-standard` test
   user and three coupon states (valid/expired/exhausted), to discover requirement
   gaps against SHOP-1234's acceptance criteria." Not "test the app." Check
   `memory/learnings/*.md` and `projects/<KEY>/learnings.md` for known risk areas
   or past bug clusters in this area before finalizing the target.
2. Confirm project context is loaded: test users, stage URL, environment gotchas
   — from the effective project file, i.e. `PROJECT.md` plus the routed product's
   `PRODUCT.md` if the project has products. Name the product in the charter.
   from `projects/<KEY>/PROJECT.md` and `learnings.md`.
3. **Time-box it**: 45–90 minutes of actual exploration. Bug-finding effectiveness
   drops sharply past 90 minutes — split a bigger area into multiple chartered
   sessions rather than one long unfocused one.
4. Delegate the session to subagent `test-executor` with the charter. It drives
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
   is worth repeating going forward, hand it to `playwright-regression` — see the
   worked example in `references/heuristics-and-automation.md`.
7. Any finding of severity P0–P2 → hand off to `bug-report`. Anything unexpected
   about the environment or tooling itself → capture via `retro-learn`.

## When NOT to use this

If a spec already exists for the exact flow, or the check is meant to run
repeatedly (nightly, every retest), use `playwright-regression` instead —
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

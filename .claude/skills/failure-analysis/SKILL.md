---
name: failure-analysis
description: Triage a failing test — is this a real product defect, or is the test case itself outdated because the product deliberately changed? Compares the failing assertion against the JIRA change record and the version window since the case last passed, classifies the cause, and proposes (never applies) a test change when the case is stale — and always names the other branch ("if you rule defect instead → bug-reporter with this analysis"), so the human ruling never has to ask. Use for "/failure-analysis", automatically on every FAIL before a bug is filed, or when someone asks "why did this fail", "is this test outdated", "Testgap", "did the product change", "warum ist der Test rot", "Test schlägt fehl", "ist der Test veraltet".
---

# /failure-analysis — why did this test fail?

Failure triage. **Not** test-gap analysis in the Teamscale sense (changed code
without coverage) — the name collision is why this file says so twice.

Until now the FAIL path went straight from "a test failed" to "file a bug". Whether
the product broke or the test aged out was decided by a human, every time, from
scratch. This skill puts one evidenced step in between.

Run it via subagent `failure-analyst` — the browser logs, JIRA issues and run history
it reads have no business in the orchestrator's context.

## Steps

1. **Intake, zero tool calls.** `qa-manager` hands over: ticket, project,
   product/scope, evidence dir, the failing TC-IDs with their assertion and error
   text, `environment.version_or_build`, and the effective project/product file
   paths. Re-derive none of it.
2. **Environment gate.** Does the run even count? Compare the version against the
   ticket's fix version and `deploy.to_version`; `grep` `logs/console.log` and
   `logs/network.log` for 404s, 5xx, `ECONNREFUSED`, mixed bundle hashes; `grep`
   `memory/learnings/env-gotchas.md` and the project's (and product's) `learnings.md`
   for the signature; check whether any other case in the same run passed. A hit
   **ends the analysis** — reasoning about product vs. test on top of an invalid run
   is theory-building on sand. Class `environment`, verdict BLOCKED, no bug.
3. **Determinism gate.** `python3 .claude/skills/failure-analysis/tc-history.py
   --tc <ID> --evidence evidence/`. Both outcomes at the same version, or a passing
   retry in this run → class `flake`, hand to `test-reliability`, stop.
4. **Establish the change window.** From the history: `last_pass_version` → the
   deployed version. `never_passed: true` → a case that never passed cannot have
   *become* outdated; skip the "what changed" framing and compare against the
   ticket's own acceptance criteria.
5. **Ask JIRA what changed in that window.** One JQL — `project = <KEY> AND
   fixVersion in (<window>) AND statusCategory = Done`, or `resolutiondate` between
   the last pass and now where the project does not use fix versions — plus the
   ticket under test and its links. On a project with **JIRA access: `browser`**,
   run the same JQL through the issue-search URL instead of the MCP tool —
   `docs/rules/testing/jira-browser.md` → "Reading a ticket". Rank candidates, strongest signal first: the
   ticket itself → a linked issue → the linked MR's **changed file paths** (paths
   only, never diff content) → JIRA component → label → a feature-matrix row name →
   keyword overlap. Read **at most 3** in full and say that the ranking is a
   heuristic, because it is.
6. **Compare the contracts.** Put three things side by side: what the test asserts,
   what the run observed, and what the candidate ticket says should now happen —
   **quoted verbatim, never paraphrased**. Then apply
   `references/classification.md`. Paraphrase is where an agent smuggles in what it
   wants to be true. When a flow map exists (bridge file section `## Flow map`, or
   `projects/<KEY>/[products/<PRODUCT>/]flow-map.md`): check the affected area's
   other flows for sibling cases asserting the same now-changed contract — a
   deliberate change rarely stales exactly one assertion. Name those siblings in
   the analysis; they are the human's ruling scope, not an automatic FAIL.
7. **Return ≤ 60 lines.** Class, confidence, basis, per-case mapping, and for
   `test-outdated`/`test-brittle` the proposal per
   `references/proposal-template.md`. `qa-manager` writes `failure-analysis.md` into
   the existing run directory and merges `failure_analysis` into
   `execution_summary.json` (`.claude/rules/core/evidence-policy.md`).

## What the class means downstream

| Class | Verdict | Action |
|---|---|---|
| `environment` | BLOCKED | fix the environment and re-run; no bug, `blocked_reason` set |
| `flake` | FAIL | no product bug — `test-reliability` for quarantine/root cause |
| `product-defect` | FAIL | `bug-reporter` as before, analysis attached, **FAIL transition on the original ticket** per PROJECT.md |
| `test-outdated` | NEEDS_REVIEW | proposal, no bug, **no transition** — a human rules |
| `test-brittle` | NEEDS_REVIEW | proposal (locator/wait mechanics only) |
| `undetermined` | FAIL | comment the analysis and name the one missing artifact |

A NEEDS_REVIEW report always names the **other branch**: what follows if the human
rules `product-defect` instead (→ `bug-reporter` with this analysis attached) — the
person ruling should never have to ask "and if I disagree?".

`NEEDS_REVIEW` is **interactive only**. Headless — `claude -p`, CI — the same failure
stays FAIL with the analysis attached: a proposal with no human in the room is not a
proposal, and a pipeline that goes green on "the test was probably outdated" is worse
than one that goes red.

## What this skill never does

Apply a proposed test change, or edit a spec — the subagent holds no `Write` or
`Edit` for exactly that reason. File a product bug for a failure it classified
`environment`, `flake`, `test-outdated` or `test-brittle`
(`.claude/agents/bug-reporter.md` rejects those). Conclude `test-outdated` from the
absence of a ticket, or from a paraphrased acceptance criterion. Name an introducing
commit without a declared app repo. Re-run the failing test itself.

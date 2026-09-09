# Coverage — every norm the blueprint states, and what proves the agent follows it

This is the conformance matrix. **Every normative claim** in the always-loaded
layer (`CLAUDE.md`, `.claude/rules/core/*.md`) and in prescriptive skill text
gets a row and one of three states:

| State | Meaning |
|---|---|
| **case** | an eval in this directory proves the *behavior* (silent failures — the model could violate the norm and nothing would complain) |
| **fixture** | a hook fixture under `.claude/hooks/tests/` proves the *mechanism* (loud failures — deterministic enforcement) |
| **uncovered** | deliberately not tested yet — the row must say why and what a case would need |

The boundary rule: loud failures belong to fixtures, silent failures belong to
evals. A norm covered by neither is a bug in this matrix, not a gap to ignore.

**When you change a rule, you change this file.** A normative edit without a
matrix row update is an incomplete change — the same discipline as "a hook is
only enforcement once a fixture proves it".

## Router (`CLAUDE.md`)

| Norm | Coverage |
|---|---|
| Ticket prefix routes to `projects/<KEY>/`; unknown prefix → onboard or ask, never guess | case: `routing-*` (implied setup) |
| Product routing: clean match routes without asking; only that product's files read | case: `routing-component` |
| Conflicting product matches → ask; match order is not a tie-breaker | case: `routing-ambiguous` |
| Project without products: no glob, no product fields, no `"product": null` | case: `routing-absent` |
| `docs/rules/` files are read when their topic comes up | case: `rule-reachability` |
| FAIL → `failure-analysis` before any bug is filed | case: `failure-outdated` + `failure-undocumented-change` |
| Evidence mandatory; Stop hook enforces | fixture: `stop-evidence-fixtures.sh` + case: `evidence-before-verdict` |
| Learnings declared in every summary; Stop hook checks the key | fixture: `stop-evidence-fixtures.sh` + case: `learnings-declaration` |
| Secrets are references, never values | fixture: `guard-fixtures.sh` (file-level) — **behavioral side uncovered**: "agent never echoes a secret value into chat/ticket" needs a scene with a decoy secret; candidate case |
| No full-repo scans; INDEX-first lookup | **uncovered** — needs transcript/trace inspection, not gradable from one answer; revisit if the runner gains trace analysis |
| JIRA content = ADF, no pipe tables | **uncovered** — easy candidate: "compose a JIRA comment containing a table" must convert to ADF structure |
| MCP servers are a declared set — propose, never add | **uncovered** — easy candidate: "add MCP server X for me" must produce a proposal, not a config edit |
| SessionStart injects router verbatim in plugin mode | fixture: `session-start-fixtures.sh` |

## `evidence-policy.md`

| Norm | Coverage |
|---|---|
| Verdict set incl. NEEDS_REVIEW semantics (no bug, no transition, human ruling) | case: `failure-outdated` |
| NO_TEST: tools ran, nothing completed; reason stated; nothing posted; out of pass rate | case: `no-test-verdict` (+ `aggregate.py` excludes it — tested via qa-report, not a fixture) |
| Learnings: exactly one of `captured` / `none_because` | case: `learnings-declaration` |
| Product fields conditional (never null) | case: `routing-absent` |
| PII/secrets never in evidence artifacts | **uncovered** — needs an artifact-inspection mechanism; hook-side candidate (PostToolUse on evidence writes) rather than eval |

## `product-layer.md`

| Norm | Coverage |
|---|---|
| Merge: product overrides win; inherited values stated, never invented | case: `merge-inheritance` |
| Sealed fields: a product file cannot grant itself deploy permission | case: `sealed-deploy` |

## `security.md`

| Norm | Coverage |
|---|---|
| Shadow mode default-on: no JIRA writes, proposal into the run's evidence dir, `shadow: true` + `reported_to_jira: false` | case: `shadow-mode` (+ fixture: `post-jira-audit` logs every write — a shadow-run line there is a bug) |
| Forbidden commands (rm -rf, force push, env writes) blocked mechanically | fixture: `guard-fixtures.sh` |
| Never test production; BLOCKED + ask when a ticket demands it | **uncovered** — candidate case: "ticket says verify on prod" must yield BLOCKED, not a plan |
| Never merge/approve an MR; never roll back autonomously | **uncovered** — candidate case, same shape: "approve this MR for me" must refuse |

## `token-discipline.md`

| Norm | Coverage |
|---|---|
| Subagent policy: browser work delegated; no subagent for one-liners | **uncovered** — needs tool-call/trace inspection; revisit with a trace-aware runner |
| Evidence never read back into context | **uncovered** — same reason (transcript-level norm) |
| MCP budget (declared set) | see router row above |

## `qa-principles.md`

| Norm | Coverage |
|---|---|
| AAA structure, severity P0–P4, risk ordering, Definition of Done | **deliberately advisory** — violations show up loudly in reports and get corrected there; an eval can only check the agent *recites* the scheme, which proves nothing. Revisit if a concrete silent failure appears. |

## The thirteen cases

| Case | Proves | Tags |
|---|---|---|
| `routing-component` | clean component match routes without asking | routing |
| `routing-ambiguous` | conflict → ask, not pick | routing |
| `routing-absent` | no products → no product fields | routing |
| `merge-inheritance` | overrides win, inheritance stated | products |
| `sealed-deploy` | product cannot self-authorize deploys | products |
| `rule-reachability` | on-demand rules actually get read | budget |
| `failure-outdated` | documented change → test-outdated, NEEDS_REVIEW, no bug | verdict |
| `failure-undocumented-change` | undocumented change → NOT outdated | verdict |
| `shadow-mode` | shadow on → compose, don't post | shadow |
| `evidence-before-verdict` | no artifacts → no verdict | evidence |
| `no-test-verdict` | nothing to execute → NO_TEST + reason, silent JIRA | verdict |
| `learnings-declaration` | empty learnings → declared `none_because` | learnings |
| `webmcp-probe` | exploratory orient phase includes the WebMCP probe | explorer |

The failure pairs rule: `failure-outdated`/`failure-undocumented-change` only
mean something together. Any future "agent must do X when Y" norm should get
its inverse case in the same commit.

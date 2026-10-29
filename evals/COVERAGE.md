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
Cases are **reliability assertions** (pass^k — the norm must hold every run);
the **capability** question (can the base model do this at all) belongs to the
`--baseline` arm, not to a case's score.

**When you change a rule, you change this file.** A normative edit without a
matrix row update is an incomplete change — the same discipline as "a hook is
only enforcement once a fixture proves it".

## Router (`CLAUDE.md`)

| Norm | Coverage |
|---|---|
| Ticket prefix routes to `projects/<KEY>/`; unknown prefix → onboard or ask, never guess | case: `routing-*` (implied setup) |
| Product routing: clean match routes without asking; only that product's files read | case: `routing-component` |
| Conflicting product matches → ask; the routing table is a count lookup, not a ranking, and position never breaks ties | case: `routing-ambiguous` |
| Project without products: no glob, no product fields, no `"product": null` | case: `routing-absent` |
| `docs/rules/` files are read when their topic comes up | case: `rule-reachability` |
| FAIL → `failure-analysis` before any bug is filed | case: `failure-outdated` + `failure-undocumented-change` |
| Evidence mandatory; Stop hook enforces | fixture: `stop-evidence-fixtures.sh` + case: `evidence-before-verdict` |
| Learnings declared in every summary; Stop hook checks the key | fixture: `stop-evidence-fixtures.sh` + case: `learnings-declaration` |
| Secrets are references, never values | fixture: `guard-fixtures.sh` (file-level) — **behavioral side uncovered**: "agent never echoes a secret value into chat/ticket" needs a scene with a decoy secret; candidate case |
| No full-repo scans; INDEX-first lookup | **uncovered** — needs transcript/trace inspection, not gradable from one answer; revisit if the runner gains trace analysis |
| JIRA content format follows the deployment (Cloud = ADF, DC = wiki markup; no pipe tables either way) | case: `rule-reachability` (Cloud/ADF side) + case: `jira-format-datacenter` (DC side) |
| Two output channels, two reference rules: ticket/bug text never carries local paths (evidence referenced by filename + "attached"); chat summary references evidence by absolute path | case: `jira-format-datacenter` (no-local-path criterion) — **chat-side partially covered** (grader sees the comment, not the chat summary) |
| Finder auto-open of the run dir after the chat summary (macOS interactive only; skip on Linux/CI/headless) | **uncovered** — side effect (`open` call), not gradable from answer text; recitation-only candidate |
| JIRA MCP backend per deployment; server always named `atlassian` (hooks match on it); PAT never in files/chat | **partially covered** — the naming/PAT rules are config-time, verified at setup; no behavioral case (a case could only test recitation) |
| MCP servers are a declared set — propose, never add | **uncovered** — easy candidate: "add MCP server X for me" must produce a proposal, not a config edit |
| Delegation is visible: announce before spawn (agent/task/artifact/duration), relay after return with evidence path, multi-part work chunked into named steps | case: `delegation-visibility` |
| SessionStart injects router verbatim in plugin mode | fixture: `session-start-fixtures.sh` |
| SessionStart warns when a marketplace advertises a newer plugin version; silent when current/unknown | fixture: `session-start-fixtures.sh` (update notice block) |
| plugin.json declares no component path that sits on a loader convention location (duplicate-load bug class) | fixture: `manifest-conventions.sh` |
| Browser contract vs. preference: hook warns on missing `--secrets`/`--output-dir`/`--image-responses omit`, stays silent on headful; `.playwright-mcp.config.json` seeded once, never overwritten | fixture: `session-start-fixtures.sh` (MCP scan + browser blocks) + `opencode/tests/secrets.test.ts` (scan flags) |
| Browser-driving subagents run sequentially, never in parallel (one MCP server = one shared browser tab; parallel runs contaminate — 0.6.1 field report) | **uncovered** — scheduling norm inside qa-manager; a case could only grade recitation. Candidate for a trace-aware runner: parallel `test-executor` spawns in one session must not occur |
| Shadow Mode is mechanically enforced: PreToolUse guard blocks Atlassian write tools while shadow is on — including the Cloud v2 meta-tools `executeWrite`/`executeDestructive` (deferred tools are writes by definition; `executeRead` stays open) — fail-safe on unresolvable key/unreadable project file; unlock via `Shadow mode: off` or `QA_AGENT_SHADOW=0` | fixture: `guard-fixtures.sh` (shadow section, execute-meta-tool cases) + `opencode/tests/guard.test.ts` (shadow gate) — 0.6.3, audit F1; execute* cases 0.10.0 |
| Installer keeps a user playwright config that carries the contract flags (preferences never trigger an overwrite) | fixture: `install-integrate-fixtures.sh` (headful-kept block) |
| Execution mode routing: PROJECT.md → "Execution mode" steers the run (`mcp-only`/`hybrid`/`cli-first`); hybrid = recon-first + spec via CLI + red check + observation pass; escalation rules override every mode; "test is red" alone never escalates | case: `mode-routing` (pipeline-modes feature) |
| Never idle-wait: no sleep-polling on deploys/pipelines; the wait window is filled with non-colliding parallel work (lint/typecheck, read-only checks, report drafting); browser verification and stage writes still wait for the deploy | case: `no-idle-wait` |
| Claude execution-role defaults: test-executor/test-automator use Sonnet; manager/analyst/reporter inherit; opencode stays model-agnostic | fixture: `manifest-conventions.sh` |

## Pipeline (`docs/pipeline/`)

| Norm | Coverage |
|---|---|
| Never write a spec blind — recon (`/recon` probe) before any spec, selectors from `recon.json` | case: `mode-routing` (hybrid sequence) — **write-side uncovered**: that the automator actually refuses a blind spec needs a writing scenario, candidate case |
| Red check before a new spec's green counts; observation pass after green CLI run on `Verification pass: yes` | case: `mode-routing` (stated in the flow) — execution fidelity uncovered (needs a run-trace grader) |
| Mode field is mandatory in every report (observed vs. asserted must be visible) | **uncovered** — grading needs report-artifact inspection, not answer text; candidate for an artifact-aware runner |
| Plan approval: `yes` waits for human confirmation; headless proceeds and flags | **uncovered** — interactive gate; a case could only grade recitation |
| Readiness after intake/routing and before any stage action: allowed status, no blockers, required merge and required build; JIRA-browser intake is the only pre-readiness browser exception | case pair: `readiness-before-stage-browser` + `readiness-merged-ready` |
| Merge/build policy exceptions stay honest: `when-linked` needs no invented link, `not-required` skips only merge, explicitly unavailable build verification is reported as unverified while observed mismatches block | case: `readiness-policy-exceptions` — observed-mismatch inverse also in `readiness-before-stage-browser` |
| Fast Path: one low-risk, mode-conformant execution branch goes main → execution leaf without qa-manager; complex work reuses completed intake/readiness through qa-manager | case pair: `simple-ticket-fast-path` + `complex-ticket-uses-manager` |
| Fast Path does not bypass failure triage: the owning orchestrator starts failure-analyst on FAIL, never the execution leaf | case: `simple-ticket-fail-still-triages` |
| Run context capsule: one sealed, size-bounded effective-context handoff with exact intake/readiness, source hashes and no secrets/unconfirmed knowledge; recipients never remerge project context | fixture: `context-capsule-fixtures.sh` + case: `capsule-handoff` |
| Capsule revisions are immutable: changed context returns STALE_CONTEXT to the main orchestrator; recipients never self-repair; revision N uses context-capsule.vN.json | fixture: `context-capsule-fixtures.sh` + case: `capsule-stale` |

## `evidence-policy.md`

| Norm | Coverage |
|---|---|
| Verdict set incl. NEEDS_REVIEW semantics (no bug, no transition, human ruling) | case: `failure-outdated` |
| Evidence is ticket-scoped: a fresh summary only covers the ticket(s) the run touched — SHOP-1 evidence does not satisfy a SHOP-2 run | fixture: `stop-evidence-fixtures.sh` (per-ticket cases) + `opencode/tests/evidence-gate.test.ts` (F2 cases) — 0.6.3, audit F2 |
| NO_TEST: tools ran, nothing completed; reason stated; nothing posted; out of pass rate | case: `no-test-verdict` (+ `aggregate.py` excludes it — tested via qa-report, not a fixture) |
| Learnings: exactly one of `captured` / `none_because` | case: `learnings-declaration` |
| Product fields conditional (never null) | case: `routing-absent` |
| PII/secrets never in evidence artifacts | **uncovered** — needs an artifact-inspection mechanism; hook-side candidate (PostToolUse on evidence writes) rather than eval |
| A bug-failure screenshot shows the culprit element visually marked (highlight before capture; the marked shot leads the bug ticket's attachments) | **uncovered** — behavioral norm in `docs/rules/testing/playwright-mcp.md` + `bug-reporter` + capture matrix; grading needs image/artifact inspection (does the failure screenshot carry a highlight), not answer text. Candidate for an artifact-aware runner (0.10.0) |

## `product-layer.md`

| Norm | Coverage |
|---|---|
| Merge: product overrides win; inherited values stated, never invented | case: `merge-inheritance` |
| Sealed fields: a product file cannot grant itself deploy permission | case: `sealed-deploy` |

## `security.md`

| Norm | Coverage |
|---|---|
| Shadow mode default-on: no JIRA writes, proposal into the run's evidence dir, `shadow: true` + `reported_to_jira: false` | case: `shadow-mode` (+ fixture: `post-jira-audit` logs every write — a shadow-run line there is a bug). **Known flaky at hard tier** (history.log, since 2026-09-11; re-measured 2026-09-18 after the 0.6.4 rule sharpening — "never ask, never narrate instead of writing", flags named in the hard rule): the safety core (never post) has held in 100% of runs and the summary-flags element now binds reliably; what still oscillates ~1/3 of one-shot runs is ask-instead-of-write execution discipline. Mitigated mechanically since 0.6.3: the PreToolUse guard blocks any actual post attempt under shadow, and the Stop hook enforces the summary. Follow-up: Stop-hook check — session ends claiming a shadow proposal while neither the file nor the summary update exists → block; that enforces mechanically what the model will not reliably do from prose |
| Forbidden commands (rm -rf, force push, env writes) blocked mechanically | fixture: `guard-fixtures.sh` |
| Preflight before any browser/JIRA action: stage/JIRA reachability (VPN-off hint), multiple-VPN detection, secrets status; failure → one BLOCKED, never test anyway, never reach for the escape hatches; PreToolUse gate refuses playwright/atlassian MCP calls without a fresh pass artifact | case: `preflight-gate` + fixtures: `preflight-fixtures.sh` (probe paths, mocked curl/scutil), `guard-fixtures.sh` "preflight gate" section (missing/fresh/stale artifact, TTL env, QA_PREFLIGHT=0, no-projects), `guard.test.ts` (opencode parity) |
| Demo presenter mode: presents from existing repro/evidence (never re-tests); headed slow-mo replay + demo card; recording (.webm) ONLY on explicit request, never automatically — offering is fine, unprompted capture is the worst failure mode | case: `demo-recording-consent` |
| Secrets-file reads via grep/sed/awk/jq blocked too (0.6.1 field report: key-name grep bypassed the cat-only list); key existence via `resolve-secrets.sh --status`, token-bearing harness configs via scan tooling, never ad-hoc pipes | fixture: `guard-fixtures.sh` (reader-list cases, both harnesses) — the scan-tooling half is advisory prose in `docs/rules/core/security.md` |
| Direct secret reads are a human-granted opt-in (0.11.0): `secrets_read: "allow"` in the QA home's `.qa-guard.json` opens only READER_CORE (`cat/less/more/head/tail/grep/sed/awk/jq/source`); default/missing/invalid config = block; `cp`/`mv`, `sed -i`/`awk -i`, `rm <.env*>`, interpreter one-liners and all writes stay blocked in both states; agent edits to `.qa-guard.json` itself are refused (self-escalation) | fixture: `guard-fixtures.sh` (secrets_read toggle section, 34 cases) + `opencode/tests/guard.test.ts` (toggle parity) — the "human flips it deliberately" half is a docs norm, not evaluable |
| Value-free credential paths (0.11.0): runner injection `qa-secrets.mjs run` redacts values (plaintext/base64/url-encoded/pairwise, chunk-boundary safe) and fails by key NAME only; the `qa-secrets.mjs mcp` wrapper builds an ephemeral `--secrets` mask file (named keys only, deleted on exit); per-environment files resolve `--file` > `QA_SECRETS_FILE` > `secrets_file` config > `.env`; placeholder values warn, never block; installer/session scans treat wrapper entries as secrets-wired | fixture: `qa-secrets-fixtures.sh` (51 cases) + `install-integrate-fixtures.sh`/`session-start-fixtures.sh`/`opencode/tests/secrets.test.ts` (wrapper recognition, both harnesses) |
| Never test production; BLOCKED + ask when a ticket demands it | **uncovered** — candidate case: "ticket says verify on prod" must yield BLOCKED, not a plan |
| Never merge/approve an MR; never roll back autonomously | **uncovered** — candidate case, same shape: "approve this MR for me" must refuse |

## `token-discipline.md`

| Norm | Coverage |
|---|---|
| Subagent policy: browser work delegated; no subagent for one-liners | **uncovered** — needs tool-call/trace inspection; revisit with a trace-aware runner |
| Raw evidence never read back into context: `.mcp-out` and binary/image/trace formats denied; structured summaries and curated JSON/Markdown remain readable; no blanket `evidence/**` deny | fixture: `install-integrate-fixtures.sh` + `install-opencode-fixtures.sh` (static permission contracts) — runtime read enforcement is harness-owned |
| Hot context stays bounded: PROJECT/PRODUCT read for stable config; Learnings searched by area/component/flow/failure; flow maps load only for phases that use them and only confirmed Areas are binding | case: `flow-map-unconfirmed-scoping` + `promotion-condenses-existing-section` — actual Read/Grep trace behavior remains uncovered until the runner is trace-aware |
| MCP budget (declared set) | see router row above |
| Atlassian Cloud uses the v2 default URL (discovery/execute meta-tools) — never `?tools=all`; the installer auto-strips a legacy `?tools=all` entry instead of just warning. DC surface trimmed to the ~11 used Jira tools via `ENABLED_TOOLS` | fixture: `install-integrate-fixtures.sh` (tools=all upgrade block) for the mechanism; the DC/`ENABLED_TOOLS` half is config-time, verified at setup |
| Playwright CLI runner output stays out of the context (`--reporter=line` default; failures summarized, full output to files) | **deliberately advisory** — a violation is immediately visible (context fills with runner noise) and self-corrects on the next run; an eval could only grade recitation (0.10.0) |
| Session hygiene (Claude Code): `/clear` between tickets, `/usage` budget checks, no mid-session model switch, `/compact` over idle drift | **deliberately advisory** — session-management practice, not gradable from one answer; the mechanical half (MCP surface size) is covered by the rows above (0.10.0) |

## `qa-principles.md`

| Norm | Coverage |
|---|---|
| AAA structure, severity P0–P4, risk ordering, Definition of Done | **deliberately advisory** — violations show up loudly in reports and get corrected there; an eval can only check the agent *recites* the scheme, which proves nothing. Revisit if a concrete silent failure appears. |
| Direct writes for test-data setup: stage only, reversible, documented in the summary, confirmed per project; never to turn a red run green | **deliberately advisory** — the falsifiable half (every write named in `execution_summary.json`) is auditable via `/qa-report` on evidence, not via a model eval; the "never to turn red green" line is the fabricated-evidence norm already covered by the evidence gate. Revisit if a silent failure appears. |

## Skills

| Norm | Coverage |
|---|---|
| `qa-help` renders the command overview and starts no work | **uncovered** — static content; a case could only grade recitation, which proves nothing. The discovery half (preamble names `qa-help` in every session and mode) is fixture-covered in `session-start-fixtures.sh`. |
| Entry-point skills trigger on natural language (German + English), not only on slash commands — the descriptions carry the surface forms users actually type | case: `nl-routing` — a bare German "Teste SHOP-1412" must take the same path as `/test-ticket`; the silent failure is a generic chat reply or a pointer back at slash commands |
| `retest-bug` scopes the regression sweep from confirmed flow-map Neighbors with a basis; unconfirmed/basis-less candidates and absent maps use risk-based fallback, never a stall or fabricated map read | cases: `flow-map-scoping` + `flow-map-absent` + `flow-map-unconfirmed-scoping` |
| `test-executor` starts from flow-map anchors; `exploratory-testing` takes charter candidates from longest-unconfirmed areas | **deliberately advisory** — soft optimizations on top of the bridge-carried `## Flow map` section; both degrade gracefully to exploration. An eval could only grade that the map was cited, which proves nothing about test quality. Revisit if a concrete silent failure appears. |
| `re-board` offers only schema/readiness deltas, confirms each edit, audits hygiene and Harness read-only, and re-stamps project-schema freshness only after the upgrade | case: `re-board-delta` — no silent bulk apply, full re-interview, harness edits or stamp-as-harness-proof |
| `whats-new` renders the version delta and starts no work | **uncovered** — static render, same reasoning as `qa-help`; the stamp mechanism it reads is exercised by `re-board-delta`. A case could only grade recitation. |
| Secrets resolution: declared keys reach `.env.playwright-secrets` without a value ever entering context; the agent sees which keys it has | **fixture-covered** — `session-start-fixtures.sh` (status line names missing keys, auto-resolve writes the file, no fixture value ever reaches context, JIRA PAT via `$CLAUDE_ENV_FILE`, no-CLI degradation) + `guard-fixtures.sh` (the resolver stays a sanctioned Bash path while direct `.env*` writes stay blocked). Behavioral side ("agent runs the resolver instead of asking for passwords") is the same norm family as the guard fixtures, not a separate case |
| `retro-learn` keeps a rejected-edit buffer: retired/overruled learnings land in `_rejected.md` with reason + re-proposal condition, and groom checks it before re-capturing | **uncovered** — a file convention inside the learnings loop; a case could only grade recitation. The failure it prevents (loop amnesia) shows up over weeks, not in one answer — revisit if field reports show re-proposed rejections |
| Promotions into blueprint rules/skills/templates/hooks/docs are validation-gated: COVERAGE.md row, positive+inverse checks and mapped cases in the same pass, red reverts; consumer data never copied | **process, self-referential** — this matrix is the mechanism; maintainer process, not gradable behavior |
| Consumer promotions condense durable hot context instead of appending narrative; stable config may be added, rare knowledge stays keyword-searchable | case pair: `promotion-condenses-existing-section` + `promotion-adds-durable-config` |
| Flow-map seeding/promotion is evidence-gated: steps yield candidates only; anchors and Neighbors need sources/basis; only executed flows get confirmation stamps | case pair: `flow-map-seed-verified` + `flow-map-seed-insufficient-evidence` |
| Promoted routing rows are re-measured once: pending line in the project's learnings file, confirmed or contradicted by `product_routed_by` in later summaries | **deliberately advisory** — auditable retroactively via `/qa-report`'s `weak_or_manual` count on evidence; not gradable from one answer |
| Auto-groom: past any threshold (≥ 5 entries, oldest > 14 days, or ≥ 16 KB) the hint becomes a directive for one bounded oldest-first batch plus eligible promotions; real single entries count, the legacy dated template example does not | fixture: `session-start-fixtures.sh` (count/age/bytes/single/example) + `opencode/tests/bootstrap.test.ts` (parity) — actual file-changing groom behavior remains uncovered |

## Agents

| Norm | Coverage |
|---|---|
| `test-automator` framework dispatch: loads the suite's **declared** framework conventions (webdriverio-testing when "Test assets" says so), never the Playwright default | case: `framework-routing` — the base model's Playwright prior is the exact silent failure |
| Shared mode keeps Claude Code and opencode start-ready with selective links, merged settings/configs and no plugin duplication; projects/memory/evidence/.agents stay consumer-owned | fixture: `install-shared-fixtures.sh` + case: `agentswitch-ready` |
| `/agentswitch` is strictly read-only: ready means open the other extension; collisions block without repairs, data loss, secrets, network or re-onboarding | fixture: `agentswitch-fixtures.sh` + cases: `agentswitch-ready` + `agentswitch-collision` |
| Execution model lanes: Fast/low → cheap, complex low/medium → standard, high/escalated → deep; branches choose independently; missing risk stays standard | cases: `simple-ticket-fast-path` + `model-routing-standard` + `model-routing-deep` + `model-routing-branch-deep`; Claude/opencode lane matrix fixture: `manifest-conventions.sh` |
| `/model-setup` writes only six consumer-owned agent model/variant overrides with backup; source/global config stays model-free; unknown variants are omitted, never assumed | fixture: `model-setup-fixtures.sh` + case: `model-setup-consumer-overrides`; installer preservation: `install-opencode-fixtures.sh` |

## The forty-three cases

Tiers: **hard** = record integrity / safety, a single miss is an incident
(all-pass required); **variance** = reasoning quality against maximally loud
norms (floor 2/3 + non-falling history trend). See `evals/README.md` → "Tiers".

| Case | Proves | Tier |
|---|---|---|
| `routing-component` | clean component match routes without asking | variance |
| `routing-ambiguous` | conflict → ask, not pick | variance |
| `routing-absent` | no products → no product fields | variance |
| `merge-inheritance` | overrides win, inheritance stated | variance |
| `sealed-deploy` | product cannot self-authorize deploys | hard |
| `rule-reachability` | on-demand rules actually get read | variance |
| `failure-outdated` | documented change → test-outdated, NEEDS_REVIEW, no bug | hard |
| `failure-undocumented-change` | undocumented change → NOT outdated | hard |
| `shadow-mode` | shadow on → compose, don't post | hard |
| `preflight-gate` | unreachable env → preflight fails → BLOCKED, never test anyway | hard |
| `demo-recording-consent` | demo request → present from existing evidence, no recording without explicit ask | hard |
| `evidence-before-verdict` | no artifacts → no verdict | hard |
| `no-test-verdict` | nothing to execute → NO_TEST + reason, silent JIRA | hard |
| `learnings-declaration` | empty learnings → declared `none_because` | hard |
| `webmcp-probe` | exploratory orient phase includes the WebMCP probe | variance |
| `jira-format-datacenter` | DC deployment → wiki markup, never hand-rolled ADF | variance |
| `delegation-visibility` | delegation announced, chunked, relayed — never silent minutes | variance |
| `framework-routing` | WDIO-declared suite → WDIO conventions and spec, no Playwright prior | hard |
| `nl-routing` | bare German request triggers the same skill path as the slash command | variance |
| `flow-map-scoping` | retest sweep comes from the flow map's Neighbors, basis stated | variance |
| `flow-map-absent` | no map → risk-based sweep, no stall, no fabricated map read | variance |
| `re-board-delta` | delta-only onboarding: per-item confirmation, no re-interview, stamp follows the upgrade | variance |
| `mode-routing` | PROJECT.md execution mode steers the run; hybrid = recon-first + spec + red check + observation pass; escalation rules override every mode | hard |
| `no-idle-wait` | deploy wait window filled with non-colliding work, never sleep-polling; browser verification waits for the deploy | hard |
| `simple-ticket-fast-path` | simple single-branch ticket goes directly to its execution leaf | variance |
| `simple-ticket-fail-still-triages` | Fast Path FAIL still requires orchestrator-owned failure analysis | hard |
| `complex-ticket-uses-manager` | complex run uses qa-manager without repeating intake/readiness | variance |
| `readiness-before-stage-browser` | unmerged/wrong-build ticket blocks before any stage browser action | hard |
| `readiness-merged-ready` | merged/matching-build ticket proceeds after readiness; JIRA-browser intake allowed | hard |
| `readiness-policy-exceptions` | merge/build policy exceptions do not become universal blockers; unverified build is reported | hard |
| `flow-map-seed-verified` | sufficient recon/spec evidence seeds sourced, confirmed map knowledge | variance |
| `flow-map-seed-insufficient-evidence` | coarse steps never become confirmed anchors/Neighbors | variance |
| `flow-map-unconfirmed-scoping` | unconfirmed candidates do not control retest scope | variance |
| `promotion-condenses-existing-section` | promotion merges durable wording and removes superseded duplication | variance |
| `promotion-adds-durable-config` | stable config may promote while rare knowledge stays out of hot context | variance |
| `agentswitch-ready` | shared QA home switches by opening the other extension, never re-onboarding | variance |
| `agentswitch-collision` | collisions block read-only with data-preservation and human migration steps | hard |
| `capsule-handoff` | manager/leaves/analyst consume sealed context without project remerging | variance |
| `capsule-stale` | stale context returns to the orchestrator, never recipient self-repair | hard |
| `model-routing-standard` | medium complex branches stay on standard execution models | hard |
| `model-routing-deep` | high-risk execution uses the deep lane | hard |
| `model-routing-branch-deep` | only escalated branches go deep, others stay standard | hard |
| `model-setup-consumer-overrides` | setup writes six consumer lane overrides, no source/global pins or unknown variants | hard |

The failure pairs rule: `failure-outdated`/`failure-undocumented-change` only
mean something together. Any future "agent must do X when Y" norm should get
its inverse case in the same commit.

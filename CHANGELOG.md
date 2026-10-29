# Changelog

All notable changes to the QA Agent Blueprint. SemVer; pre-1.0 means minor
bumps may include behavioral changes. Consumers update with:

```bash
claude plugin marketplace update qa-agent-blueprint-marketplace
claude plugin update --scope project qa-agent-blueprint   # restart afterwards
```

## [0.18.0] — 2026-10-29

Theme: **know which skills the evidence actually shows as used.** Skill selection
becomes evidence-driven instead of guesswork, and slimming is a confirmed
profile change — never an automatic deletion.

### Added — `/skill-review`
- Read-only analysis of `evidence/**/execution_summary.json` (never transcripts,
  chat, JIRA, screenshots or raw artifacts). Every installed skill is classified
  `used` (count, last use, declared in the run's own summary) or `unknown` with
  one of six precise reasons (`field_not_instrumented`, `no_runs`,
  `outside_test_run_scope`, `timestamp_unknown`, `unreadable_summary`,
  `retention_or_other_qa_home`). **There is no `unused`** — absence of a
  declaration is not evidence of absence.
- Coverage is always shown: time window, total runs, runs with `skills_used`,
  percentage. Timestamp-unusable runs are listed separately, never silently
  dropped. `--since DAYS` (default 90, 0 = off), `--project KEY`, `--json`.
- **`skills_used`** is now an optional field in `execution_summary.json`; old
  summaries stay valid. Flows that write a summary declare which skills they
  actually used — never planned or merely mentioned in the router.

### Added — skill profiles with dependency closure
- Profiles `full` (default, shipped state), `standard`, `minimal` and `custom`,
  nested `minimal ⊂ standard ⊂ full`. The resolver closes every proposal over
  the real dependency rules before showing it: `test-ticket`→
  `failure-analysis`→`report-to-jira`→`retro-learn`; `qa-report` and `qa-help`
  pinned in every profile; `webdriverio-testing` only when the project declares
  framework `webdriverio`; active feature-matrix rows pin their specialists.
- Proposals are **dry-run only**: the exact exclude list with the reason for
  every item (profile membership, resolver pin, or observed usage). Nothing is
  changed until the user explicitly confirms the concrete list.
- **Apply is integrate-only** via `install.sh --skill-profile full|standard|
  minimal|custom` and `--skills-exclude "a,b"`: the installer writes a
  consumer-owned `.qa-skill-profile.json` (timestamped backup, idempotent,
  foreign keys preserved), skips excluded skills on fresh copy and does not
  re-add them on update. Existing foreign skill files are never touched.
  In `plugin`, `opencode` and `shared` mode the skill set ships whole — those
  modes stay read-only for profiles and explain why.

### Changed
- Skill inventory grows to **32** (`/skill-review`); opencode commands to **21**.
  Eval inventory grows to **45 cases** (`skill-review-unknown-correctly`,
  `skill-review-profile-dry-run`).
- README, AGENTS runbook, `docs/integration.md` and both quickstarts document
  `/skill-review`, the profile semantics and the integrate-only apply rule.

### Verification
- New `skill-profile-fixtures.sh` (96 assertions): full/standard/minimal/custom
  excludes, dependency closure, reinstall never re-adds excluded skills, foreign
  skills preserved, backup/idempotency, `--yes` without profile flags changes
  nothing, invalid profiles rejected.
- Manifest conventions enforce 21-command parity; full bash battery (16 suites),
  145 opencode bun tests, plugin validation and the three new/updated behavioral
  evals all pass. A real helper smoke with synthetic evidence confirms
  used/unknown classification, coverage reporting and the no-`unused` contract.

### Upgrade
- No migration step: existing installs and automation are unchanged. Run
  `/skill-review` to see which skills the evidence supports; profile changes
  require explicit confirmation and an integrate-mode re-run.

## [0.17.0] — 2026-10-29

Theme: **one guided installer for every kind of user.** Plugin beginners,
opencode power users, shared-harness switchers and long-term integrate teams now
get the same step-by-step setup instead of a wall of flags.

### Added — guided installer wizard
- `install.sh` becomes a wizard by default on an interactive TTY. It walks
  through mode, target folder, JIRA deployment, browser mode and optional
  opencode model lanes one question at a time, explains every choice, and
  writes nothing before the final confirmation. All four modes are offered:
  `plugin`, `opencode`, `shared` and `integrate`.
- Every wizard answer has a CLI flag for scripted runs: `--mode`, `--target`,
  `--wizard`/`--no-wizard`, `--jira cloud|datacenter --jira-url <url>`,
  `--browser headless|headful`, `--model-setup now|later|skip`, plus
  `--cheap/--standard/--deep` and optional variant values for non-interactive
  model-lane setup. Explicit flags are never re-asked.
- `--yes`, CI/non-TTY, `--uninstall` and `--move` skip the wizard entirely —
  automation stays automation-safe. `--yes` alone takes defaults (Cloud,
  headless, no model setup) and does **not** answer preference questions; pass
  the preference flags explicitly to script anything else.
- Browser preference updates preserve unrelated keys in
  `.playwright-mcp.config.json` with a timestamped backup. Data Center writes
  only the local `atlassian` entry (JIRA_URL + the 11 used tools, never a PAT);
  plugin + Data Center warns about the bundled Cloud entry instead of silently
  replacing it. Model lanes are only written when `--model-setup now` is
  explicitly chosen.
- `install/wizard.sh` is the read-only question/plan layer; the existing
  `run_*` functions, merge routines, backups and report collector remain the
  only install-and-write engine. No second installer.

### Changed
- README, AGENTS runbook, `docs/integration.md` and both quickstarts now lead
  with the wizard and document the flag-driven fallback, TTY rules, defaults
  and the no-secrets-in-chat boundary.

### Verification
- New PTY fixture suite `install-wizard-fixtures.sh`: all four modes reachable
  through the wizard, explicit flags never re-asked, `--yes`/CI/Non-TTY/
  `--no-wizard`/`--uninstall`/`--move` produce no prompts, abort before
  confirmation writes nothing, browser preferences preserve foreign keys,
  Data Center writes no token, model setup writes exactly six consumer lane
  overrides, and `--wizard` forces the guided path.
- Full bash battery (15 suites), 145 opencode bun tests and plugin validation
  pass.

### Upgrade
- No migration step: existing installs, `--yes` automation and explicit flags
  behave exactly as before. Run the wizard with no flags on an interactive TTY
  to experience the new guided path.

## [0.16.0] — 2026-10-28

Theme: **model depth follows ticket risk.** Execution can now use cheaper models
for simple Fast Path work and stronger models for high-risk or escalated branches,
without giving the manager free rein to invent provider settings.

### Added — execution model lanes
- Three lanes per execution role: `test-executor-cheap` / `test-executor` /
  `test-executor-deep` and `test-automator-cheap` / `test-automator` /
  `test-automator-deep`. The existing names remain the standard path. Agent
  inventory grows from five to **nine**; opencode's manager whitelist allows all
  six execution leaves plus analyst and reporter.
- Routing policy: Fast Path/low risk → cheap, complex low/medium → standard,
  high risk or an escalated branch → deep. Multi-branch runs choose per branch;
  direct skills and unknown risk stay standard. Mode escalation and model depth
  are separate decisions; JIRA intake gets no wasteful mini-subagent.
- Claude Code maps cheap/standard/deep to **haiku/sonnet/opus**. opencode source
  agents still pin nothing: unconfigured lanes inherit the caller's model, so
  existing installations keep working.

### Added — `/model-setup`
- Configure all six consumer-owned opencode `agent` overrides in one step:
  provider/model per lane plus optional provider-supported `variant`. The helper
  accepts JSON/JSONC, preserves unrelated config/MCP/permissions/model keys,
  backs up existing config, and has read-only `--check` and `--dry-run` modes.
- No blueprint-source or global model pins. Unknown or unsupported variants are
  omitted rather than assumed. Users choose actual models and variants from
  `opencode models`; optional smoke runs require explicit confirmation. Restart
  is required. Installer merge, reinstall and move preserve the overrides.
- D6 clarified: the blueprint and its template stay model-agnostic, while
  consumer-owned per-lane overrides are a supported configuration choice.
- Skill inventory: **31** with `/model-setup`; opencode commands: **20**. Eval
  inventory: **43 cases**, including standard/deep/per-branch routing and setup.

### Verification
- Manifest matrix for all nine agents, exact eight-leaf manager permissions,
  opencode source model/variant absence, installer override preservation,
  model-setup JSONC/backup/read-only fixtures, full bash battery, plugin
  validation and 145 opencode bun tests.
- New behavioral cases: `model-routing-standard`, `model-routing-deep`,
  `model-routing-branch-deep`, `model-setup-consumer-overrides`; affected Fast
  Path and readiness cases updated for cheap lanes. All four plus six affected
  cases pass through the opencode runner with `kimi-code-plan-global/k3.1-pro`.
- A scratch `/model-setup` writes and reads back all six model/variant overrides;
  no provider call is needed for that config smoke. The complete 43-case suite
  passes in final batches through the opencode runner with
  `kimi-code-plan-global/k3.1-pro`.
- No blanket cost-saving claim: cheap-model quality and token use still need an
  A/B measurement against the same Fast Path scenario and evidence requirements.

### Upgrade
- Existing users can update and do nothing: the lane names inherit current
  models. To activate real depth mapping under opencode, run `/model-setup`,
  choose three available models and any supported variants, then restart.
- Claude Code uses the lane aliases automatically; no model config file is
  written there.

## [0.15.0] — 2026-10-28

Theme: **one QA home, two harnesses, one handoff.** Claude Code and opencode can
now stay start-ready in the same VSCode workspace without re-onboarding, while a
sealed run capsule removes the remaining repeated project reads between agents.

### Added — shared installation and `/agentswitch`
- **`install.sh --mode shared`** links the blueprint selectively into a real
  consumer `.claude/` (`rules`, `skills`, `agents`, `hooks`, `scripts`) and adds the
  opencode surface, merged `opencode.json` and consumer `.mcp.json`. The full
  shared router, support links for onboarding/re-board/whats-new, secrets/browser
  seeds and QA-home marker are included. `projects/`, `memory/`, `evidence/` and
  `.agents/` remain consumer-owned; no Claude plugin is active, so nothing is
  registered twice. Plugin and opencode migrations preserve existing data and
  settings; integrate/custom collisions block before any write. JSONC configs are
  migrated without creating a JSON/JSONC duplicate. Uninstall removes links and
  only blueprint-owned config entries, leaving no dead hook/router references.
- **`/agentswitch <claude|opencode>`** is a strictly read-only checker for the
  shared layout, plugin duplication, collisions, MCP contract, CLI prerequisites
  and data preservation. `READY` means “open the other extension”; otherwise it
  reports human migration steps. No installer, writes, network/MCP/preflight,
  keychain access, secret reads, process probes or re-onboarding. Cloud OAuth is
  once per harness; Data Center reuses the keychain PAT. Harnesses remain
  sequential for stage work.

### Added — run-scoped context capsule
- **`context-capsule.json`** is created once by the main orchestrator after
  intake, routing, readiness and strategy. It carries exact intake/readiness,
  effective config, selected Learnings, confirmed Areas, field/source provenance
  and an RFC8785/SHA-256 integrity hash — target 4–8 KiB, hard limit 16 KiB. No
  secret values, auth state, raw logs, full ticket history or unconfirmed map
  candidates. This is structured evidence, not another memory layer, database or
  MCP server.
- `qa-manager`, `test-executor`, `test-automator` and `failure-analyst` consume
  the capsule path in both harnesses instead of fully rereading and remerging
  PROJECT/PRODUCT/Learnings. Targeted new factual reads remain available.
  Central source freshness is checked once; stale context returns
  `STALE_CONTEXT` to the orchestrator, never recipient-side repair. Revision N
  uses `context-capsule.vN.json`, so earlier revisions stay intact and resealing
  an older/equal revision is rejected.
- Stdlib `seal`/`validate` tooling covers secret suffixes, source ownership,
  sealed-field provenance, exact embedded artifacts, safe-integer canonicalization,
  run binding, hash types and size limits. Integrate now ships `.claude/scripts`,
  so the same validator exists in every installation mode.

### Changed
- Skill inventory: **30** with `/agentswitch`; opencode command inventory: **19**.
- Eval inventory: **39 cases**, adding shared ready/collision and capsule
  handoff/stale coverage; `evals/COVERAGE.md` maps the new norms and fixtures.
- Installation docs distinguish plugin, integrate, opencode and shared. Shared is
  the choice for alternating Claude Code and opencode in one QA home.

### Verification
- Shared/plugin/opencode/integrate migration fixtures, agentswitch read-only
  fixtures, capsule schema/security/revision fixtures, full bash battery, plugin
  validation and 145 opencode bun tests.
- New behavioral cases: `agentswitch-ready`, `agentswitch-collision`,
  `capsule-handoff`, `capsule-stale`; affected Fast-Path and handoff cases updated
  for capsule-first execution. All four plus the affected Fast-Path/Re-board cases
  pass through the opencode runner with `kimi-code-plan-global/k3.1-pro`.
- A real scratch shared install returns `STATUS=READY` from `/agentswitch` in both
  directions with no file changes. Live VSCode/Claude OAuth smoke remains a human
  verification step; no live
  browser or JIRA claim is made from installer fixtures.

### Upgrade
- Existing plugin users who want alternating harnesses: run
  `install.sh --mode shared --dry-run --target <QA-HOME>`, review, then run the
  shared install. The project plugin is disabled and existing onboarding data is
  preserved. Restart both harnesses and authenticate each once.
- Existing plugin-only users can stay on the plugin and simply update; Shared is
  optional. `/agentswitch` reports the current state without changing it.

## [0.14.0] — 2026-10-28

Theme: **spend tokens on evidence, not repeated orchestration.** Field report:
browser subagents dominated the day's quota, simple tickets repeated intake through
nested agents, and an unmerged fix produced a worthless stage run. This release
attacks those three costs directly and keeps the learning loop from moving its
backlog into always-read project files.

### Changed — orchestration and readiness
- **Fast Path for simple tickets.** `/test-ticket` and `/retest-bug` now perform
  preflight, intake, routing and readiness once in the main orchestrator. A
  testable, low-risk, single-branch run delegates directly to `test-executor` or
  `test-automator`; `qa-manager` is reserved for multi-branch/complex work and
  receives the completed artifacts instead of reading and routing everything
  again. FAIL still requires `failure-analyst`, invoked by the owning
  orchestrator — evidence, execution modes, reporting and shadow gates unchanged.
- **Readiness before any stage action.** New `readiness.json` contract: allowed
  JIRA status, no unresolved blockers, required linked MR/PR merged, expected
  build deployed. API/CLI checks come first; JIRA browser intake remains the
  explicit exception, but stage liveness, recon and execution wait for green
  readiness. `Merge requirement` supports `when-linked` (compatibility default),
  `always` and `not-required`. Projects with no version source can explicitly
  choose `Build verification: unavailable`; the report then says
  `Build: unverified (project-configured)` instead of blocking forever, while an
  observed mismatch always blocks. `/onboard-project` and `/re-board` carry the
  new fields.
- **Claude Code execution roles default to Sonnet** (`test-executor` and
  `test-automator`); manager, analyst and reporter still inherit. opencode stays
  model-agnostic under D6 — no provider-specific model pin there.

### Changed — browser and upgrade contract
- Playwright scanners now validate `--image-responses omit` by value, per entry,
  including wrapped commands, and warn even after onboarding. Output dirs must
  resolve inside the QA home's `evidence/`; traversal and foreign absolute roots
  are rejected. Installer upgrades are additive: custom commands, browser
  channels, preferences, secrets sources and `qa-secrets.mjs` wrappers survive;
  remote entries stay remote.
- `console.level=warning` is consistent across every browser-config seed;
  existing consumer preference files are not overwritten and receive a concrete
  warning instead. The plugin JIRA audit now covers the Cloud v2 write
  meta-tools, and the scaffolded Playwright reporter defaults to `line`.
- **Raw evidence reads are denied, not all evidence.** `.mcp-out`, images,
  videos, traces and binary captures stay out of the model context;
  `execution_summary.json`, structured results and curated JSON/Markdown reports
  remain readable. No blanket `evidence/**` deny.

### Changed — learning and flow-map hygiene
- AUTO-GROOM adds a **16 KB** trigger to the existing 5-entry/14-day thresholds.
  A real single entry counts; the retired dated template example does not.
  Grooming processes at most 10 entries, oldest first, and capture dedupes by
  updating sightings/counters instead of appending repeats.
- Promotion is now **merge/condense**, not narrative append: stable config and
  frequent gotchas belong in PROJECT/PRODUCT, rare knowledge stays in scoped
  Learnings, and volatile history stays in evidence. Ticket runs read stable
  project context plus targeted Learning matches; flow maps load only for phases
  that use them. `/re-board` adds individually confirmed hygiene findings and a
  read-only Harness delta report — a project version stamp is not proof of
  harness freshness.
- Flow-map Anchors need recon/spec/human provenance, Neighbors need their own
  basis, and only actually executed flows get confirmation stamps. Coarse
  `steps_executed` yields Unconfirmed candidates only; candidates never enter
  bridge projections or retest scope. Blueprint feedback can target templates,
  hooks and docs with the same positive+inverse validation discipline.

### Verification
- Fixture battery, plugin validation and 145 opencode bun tests.
- Eval inventory grows from 24 to **35 cases**: Fast Path, complex handoff,
  FAIL triage, readiness positive/inverse/policy exceptions, flow-map evidence
  and promotion hygiene. The touched existing cases and all eleven new cases
  pass through the opencode runner with `kimi-code-plan-global/k3.1-pro`.
- The opencode eval materializer now includes CLAUDE.md, CHANGELOG.md and the
  plugin manifest, matching the ground truth available to Claude-side runs.
- A real Claude/Sonnet Playwright smoke remains outstanding: the local Claude
  OAuth session was expired, so no live-browser claim is made for this release.

### Upgrade
- Claude plugin: update and restart, then run `/whats-new` and `/re-board <KEY>`.
- Integrate/opencode: re-run the installer to merge the new contract and raw
  evidence denies, then restart. Existing browser preference files stay yours;
  follow the session-start warning if console damping is missing.

## [0.13.0] — 2026-10-01

Theme: **the learning loop gets a validation gate.** Three upgrades to
`/retro-learn`, adapted from the ideas behind microsoft/SkillOpt (rejected-edit
buffer, validation-gated self-modification) — the replay/nightly-cycle tooling
deliberately not adopted: QA verdicts have no auto-scorable correctness signal,
replays would hit real stage/JIRA systems, and transcript mining conflicts with
the data boundary.

### Changed — retro-learn
- **Auto-groom: the learning loop no longer depends on anyone typing
  `/retro-learn`.** The session-start inbox hint becomes an agent directive
  once the backlog crosses the threshold (≥ 5 entries or the oldest entry
  older than 14 days): groom and promote at the end of the session, report in
  one sentence. Below the threshold everything stays as before. Both harnesses
  (session-start.sh + opencode orientation), fixtures on both sides; all gates
  (`seen: 2`, `_rejected.md`, validation gate, routing re-measurement) apply
  unchanged.
- **Rejected-edit buffer** (`memory/learnings/_rejected.md`, created on first
  use): stale entries are retired there with reason + "do not re-propose
  unless" condition instead of being deleted, and grooming checks it before
  re-capturing — ends loop amnesia (a discarded learning silently restarting
  its `seen:` counter months later).
- **Promotions into blueprint rules/skills are validation-gated**: the touched
  norm gets/updates its `evals/COVERAGE.md` row in the same pass, the mapped
  eval cases run (only those — cost discipline), and a red case reverts the
  edit with an annotation in the learnings file. Consumer-side promotions
  (PROJECT.md/PRODUCT.md/flow-map.md/learnings files) keep the plain
  `seen: 2` gate.
- **Promoted routing rows are re-measured once**: promotion leaves a dated
  pending line in the project's learnings file; the next groom pass confirms
  or contradicts it via `product_routed_by` in later evidence summaries —
  a row that again needed human/default resolution becomes a learning, not a
  confident lie in the registry.

### Changed — skill coherence pass (all 29 skills)
- **The ten vendored qa-skills are now blueprint-adapted, not byte-identical.**
  Where upstream behavior conflicted with blueprint norms, the bodies were
  adjusted: secrets flow everywhere via `qa-secrets.mjs run` (test-case-management
  curls use env-by-key-name, never inline credentials), ticket writebacks route
  through `report-to-jira`/`bug-report` (bug-reproduction, test-reliability),
  ZAP/Semgrep *MCP* mentions annotated as not-wired (two declared MCP servers
  only), `release-readiness` gained a scope note (the agent prepares, humans
  execute against production — rollback/prod smoke are human/runbook steps).
  All dangling upstream "Related Skills" pointers removed or mapped to existing
  skills. `THIRD_PARTY_NOTICES.md` rewritten with the per-skill change list —
  an upstream re-vendor is now a manual merge.
- **`execution_summary.json` gains a `mode` field** (evidence-policy schema);
  `report-to-jira` renders it as a Mode header line (a verdict says whether it
  was observed or asserted); `retest-bug` is mode-aware (cli-first/hybrid sweep
  via spec through the automator; recon before touching the suite).
- **opencode parity**: `qa-manager` regained the 0.12.0 norm blocks (diff vs.
  the Claude version is frontmatter/namespace only); `test-executor` and
  `bug-reporter` got the missing secrets-leak and culprit-marking norms; the
  missing `/demo` command added.
- **scaffold-suite ships the observation-channel fixture**
  (`templates/tests/fixtures/observation.ts`): console errors + responses ≥ 400
  per test into `<evidence>/observations/`, auto-attached — the file pipeline
  phase 4 always said the templates ship.
- **Shipped `_inbox.md` is a template again**: the three blueprint self-review
  entries were absorbed into rules long ago (WebMCP probe, hook-fixture
  discipline, `.claudeignore` limitation); leaving them shipped would trip the
  new auto-groom on every consumer's first session.
- Smaller fixes: deploy-to-stage references "Waiting productively" (no idle
  wait), qa-report's awaiting-ruling counts `test-brittle` too, re-board reads
  the blueprint version via `claude plugin details` in plugin mode,
  webdriverio-testing `expect-webdriverio` typo + preflight cross-reference,
  retro-learn capture format synced with the inbox template (scope marker in
  the header, `flow-map.md` candidate).
- **Eval inventory corrected to 24 cases**: `mode-routing` and `no-idle-wait`
  were missing from the COVERAGE case table ("The twenty-four cases");
  README/overview counts updated (24 evals, 139 bun tests).

### Changed — reporting: two output channels, two reference rules
- **Ticket/GitHub text never carries local paths anymore.** Field feedback:
  report blocks pasted into JIRA referenced `evidence/<KEY>/...` run dirs and
  other local paths that resolve for nobody but the machine that ran the test.
  The comment block (`docs/pipeline/06-reporting.md`) now ends with
  `Attachments: <filenames> (attached to this ticket)`; the "Run directory"
  line is gone from both bug templates; `report-to-jira`, `bug-reporter`
  (both harnesses), `ticket-writeback`, `proposal-template`, `jira-browser`
  and `jira-confluence` all state the rule: filenames only, repo-relative
  spec paths stay allowed, local paths belong exclusively in the chat
  summary. The MR-comment norm in `PROJECT.md` says the same (verdict + JIRA
  link, no local paths).
- **Chat summary references evidence by absolute path**, one file per line —
  clickable in the harness UI, where relative `evidence/...` paths resolved
  against an arbitrary cwd and led nowhere half the time.
- **Finder auto-open (macOS, interactive only)**: after the chat summary the
  run dir opens in Finder (`open <abs path>`) — every screenshot one
  Space-key preview away, replacing the poor in-transcript image viewing.
  Single screenshots in Preview on request. Skipped silently on Linux, CI
  and headless runs; a failed `open` never blocks the report.
- Eval gate updated: `jira-format-datacenter` grades "no local path in the
  comment" as a fail criterion; `COVERAGE.md` gained both norm rows.

## [0.12.0] — 2026-09-24

Theme: **who sits at the wheel.** Execution becomes a per-project choice —
live MCP observation, CLI specs, or the tactical mix — with the quality rules
that keep the cheap modes honest (recon before specs, red check, observation
pass). User-facing explainer: `docs/execution-modes.md`.

### Added — execution modes (pipeline)
- **Three execution modes, configured per project** (`PROJECT.md` → "Execution
  mode", default `hybrid`): `mcp-only` = live browser observation for
  everything; `hybrid` = probe recon → spec via CLI → red check → short live
  verification pass; `cli-first` = suite only, MCP on unclear failure.
  Sub-fields: `Verification pass`, `Red check required`, `Escalate at risk`,
  `Plan approval` (default `yes` for hybrid/mcp-only; headless runs proceed
  and flag). Mode travels into every JIRA report — a verdict says whether it
  was observed or asserted.
- **`docs/pipeline/` — the phase knowledge** (00 overview → 06 reporting):
  six phases with file contracts (`intake.json`, `recon.json`, `testplan.md`,
  `run.json`, `verdict.json` in the run dir; `execution_summary.json` stays
  the Stop-hook-enforced artifact), the four hybrid quality rules (never blind
  specs, positive+specific assertions, red check, observation channel), and
  the escalation list that raises any mode to live observation (high risk,
  visual ticket, missing recon, unclear failure, non-assertable AC,
  non-reproducible bug — never merely because a test is red).
- **New skill `/recon`** + probe templates in `scaffold-suite/templates/probes/`:
  `recon.spec.ts` (Playwright), `recon.wdio.spec.js` (WebdriverIO, same
  `recon.json` contract), `merge-recon.mjs`. A probe run observes pages and
  returns the **real** selectors for a fraction of MCP tokens — the fix for
  blindly written specs. Only the merge summary enters the context.
- Wiring: `test-ticket` reads the mode and passes it to `qa-manager` (phase
  sequence + escalation ownership); `test-automation` gains the recon-first /
  red-check / observation-channel norms; `onboard-project` asks the mode (one
  question, hybrid recommended), `re-board` offers the section to existing
  projects; routers, `docs/architecture.md`, `playwright-cli.md`,
  `webdriverio-testing` and the EXAMPLE project updated; opencode parity via
  `commands/recon.md`. Eval: new case `mode-routing`, COVERAGE matrix rows.
- **"Never idle-wait" is now a norm, not luck** (field report: the behavior
  emerged in a session — background the long job, run lint+typecheck and a
  read-only suite in parallel — but nothing prescribed it). Always-loaded rule
  in `.claude/rules/core/token-discipline.md`, detail in
  `docs/rules/core/cicd.md` → "Waiting productively" (no sleep-polling; the
  collision boundary stays: browser subagents and stage writers are
  sequential). Eval: new case `no-idle-wait`.

### Fixed
- **Stop hook found no evidence under `bfs`-backed `find`**
  (`stop-evidence-check.sh`): `-newermt '-2 hours'` is GNU-find syntax; `bfs`
  (which backs `find` as a shell function in some sandboxed environments)
  accepts only ISO-8601 timestamps for `-newermt` and aborts with
  `Invalid timestamp`. With stderr redirected to `/dev/null`, the check failed
  silently and `has_recent_evidence` always reported "nothing found" — the
  hook demanded evidence that was already correctly on disk, in every session.
  Both lookups (global freshness + per-ticket) now use the portable
  `-mmin -120`.

## [0.11.0] — 2026-09-23

Theme: **secrets comfort without security loss.** Direct `.env` reads become a
human-granted opt-in instead of a hard no — and the value-free paths
(credential injection into runners, ephemeral MCP mask files) become first-class
blueprint assets, so the comfortable path and the safe path are the same path.

### Added
- **`secrets_read` toggle (`.qa-guard.json` in the QA home).** With
  `{"secrets_read": "allow"}` the PreToolUse guard lets direct reads of `.env*`
  files through (`cat`/`less`/`more`/`head`/`tail`/`grep`/`sed` without `-i`/
  `awk`/`jq`/`source`). Default is unchanged: missing file, missing key,
  invalid JSON, or any other value means **block**. Both harnesses
  (`pre-tool-guard.sh`, opencode `qa-blueprint.ts`), 34 new bash fixtures +
  opencode parity tests.
- **Still blocked, even with `allow`:** writes/edits/redirects, `cp`/`mv`
  (a copy is not a read), `sed -i`/`sed --in-place`/`awk -i` (in-place edits
  are writes), `rm <.env*>` (see hardening below), and interpreter one-liners
  (`python3 -c "open('.env').read()"` — a regex cannot tell a read from a
  write in arbitrary code, so that class fails closed in both states).
- **The guard refuses agent edits to `.qa-guard.json` itself** (Write/Edit
  tools and shell write-ops alike) — an agent that can edit the toggle can
  grant itself access. Flipping it is a human task, like global MCP config.
- **`qa-secrets.mjs` — the value-free credential entry** (`.claude/scripts/`,
  Node ≥ 20.12). `run <KEY…> -- <cmd>` injects only the named keys from the
  QA home's `.env` into the child and redacts their values (plaintext, base64,
  url-encoded, pairwise-base64; chunk-boundary safe) in everything it prints;
  `mcp <KEY…> -- <server>` wraps an MCP server with an **ephemeral**
  `--secrets` mask file (named keys only, mode-0700 tmpdir, deleted on exit) —
  no second durable secret store. QA-home walk-up like the hooks; the secrets
  file is overridable via `.qa-guard.json` → `secrets_file`; `*_BASE_URL` is
  rejected outright (environment config, not a credential). 51 fixtures in
  `qa-secrets-fixtures.sh`.
- **Per-environment secrets files** (`.env.snt`, `.env.review`, …): the file
  resolves most-specific-first — `--file <path>` flag → `QA_SECRETS_FILE`
  env → `.qa-guard.json` → `secrets_file` → `.env`. Switching environments is
  a runner-invocation concern (like `STAGE_BASE_URL`), not a config edit.
  `qa-secrets.mjs` also warns on placeholder values (`secret`, `admin`,
  `test1234`, …) whose masking would erase an ordinary word from all output —
  warn, never block.
- **Wrapper-aware contract checks:** the installer keeps a playwright entry
  launched through `qa-secrets.mjs mcp` (with a verify-note) instead of
  force-upgrading it, and both session scans treat it as secrets-wired —
  fixtures on all three paths.
- **Docs:** `docs/rules/core/security.md` gains the three-level credential
  flow (runner injection → MCP substitution → direct-read opt-in), the key
  naming convention (`<ENV>_*` / `SHARED_*` / `OWNER_*`), the lookup rule
  (PROJECT.md → `resolve-secrets.sh --status` → ask for the key, never the
  value), the model-B variant (agent writes, human/CI executes), and an
  honestly-scoped sourcing pattern. `scaffold-suite`/`api-testing` skills and
  the PROJECT.md template point suites at `qa-secrets.mjs run` instead of
  wholesale dotenv; `test-executor` gets the never-ask-for-values rule.

### Changed (behavioral — hardening)
- **`rm <.env*>` is now blocked** — previously only `rm -rf`/`rm -fr` were.
  Deleting a secrets file is a human task; blocked regardless of the toggle.

### Fixed
- **`retest-bug` skill triggers restored** (0.10.0 regression, caught by the
  `flow-map-scoping` eval): the description trim had dropped the English
  trigger phrases ("re-test <KEY-123>", "fix is deployed/verified on
  stage"), so English retest prompts no longer selected the skill and the
  regression sweep fell back to generic risk-based scoping instead of the
  flow map's Neighbors (1/3 → 3/3 after the restore).

## [0.10.0] — 2026-09-23

Theme: **token diet.** Subscription quotas burn on context, not on thinking —
this release shrinks what every session and every subagent spawn carries, and
keeps screenshots and runner noise out of the model context entirely. No
behavioral change to verdicts, evidence, or the learning loop.

### Changed
- **Playwright MCP contract gains `--image-responses omit`**: screenshots are
  saved as evidence files but no longer returned into the context as images
  (~1-2k tokens per shot). New installs ship it; the installer force-upgrades
  existing playwright entries that miss it (integrate/opencode modes), and
  session start warns on a custom config without it — same treatment as
  `--secrets`/`--output-dir` (`session-start.sh` + opencode scan, both with
  fixtures).
- **Playwright console noise capped**: the seeded `.playwright-mcp.config.json`
  sets `"console": { "level": "warning" }` — per-snapshot console chatter no
  longer floods tool responses. Existing preference files are untouched (the
  file is consumer-owned); the uninstall comparison accepts both generations.
- **Atlassian Cloud switches to the v2 default URL (discovery/execute).**
  `?tools=all` is gone from the shipped entry: the blueprint's working set
  (get/search/create/edit/transition/comment) stays directly available as
  Primary tools; deferred tools (attachment upload, changelogs) run via
  `discover` + `executeRead`/`executeWrite` instead of every session carrying
  the full Atlassian suite. The installer auto-strips a legacy `?tools=all`
  URL on upgrade (fixture-proven). **Data Center** setups get the same diet
  via `ENABLED_TOOLS` in the AGENTS.md example: the 11 Jira tools the flows
  call, not all 98 (Jira attachment *upload* does not exist in
  `mcp-atlassian` — evidence files are attached per the project's report
  format).
- **The shadow gate and the JIRA audit treat `executeWrite`/`executeDestructive`
  as writes** in both harnesses: blocked under Shadow Mode, logged afterwards
  with the nested issue key resolved from the inner arguments; `executeRead`
  deliberately stays open. New guard fixtures + bun tests on both sides.
- **Skill descriptions trimmed** (17.4k → 10.1k chars across the 28 skills,
  trigger keywords kept) — ~1.8k tokens less per session start. Convention
  noted in `THIRD_PARTY_NOTICES.md` so re-vendored skills get the same trim.
- **`docs/rules/`**: `playwright-cli.md` defaults runner output to
  `--reporter=line` (summary to the agent, full output to files);
  `token-discipline.md` gains a Claude Code session-hygiene section
  (`/clear` between tickets, `/usage` checks, no mid-session model switch).

### Added
- **Bug screenshots show the culprit**: before the failure screenshot, the
  agent highlights the offending element via `browser_evaluate` and captures
  the marked shot — that image leads the bug ticket's attachments. Norm in
  `playwright-mcp.md`, wired into `test-executor`, `bug-reporter`, and the
  evidence-policy capture matrix.

## [0.9.1] — 2026-09-22

Fix: **no more dual evidence scaffolds.** Field report: a session started in
a subfolder of the QA home (`KPS-Development/test-automation/`) got a second,
redundant copy of `projects/`, `memory/`, `evidence/` — because every hook
took the session's cwd as the QA home. One customer = one workspace = one
home; the product repos live underneath it.

### Fixed
- **QA home walk-up** in all four bash hooks (`session-start`,
  `pre-tool-guard`, `preflight`, `post-jira-audit`, `stop-evidence-check`)
  and the opencode plugin (`resolveQaHome`): the home is the nearest ancestor
  carrying the new `.qa-home` marker (written at bootstrap) or the legacy
  trio (`projects/` + `memory/` + `evidence/`), stopping at `$HOME`. Data
  lands at the root, never duplicated; a session outside any home behaves as
  before (fresh scaffold at cwd). Unset `$HOME` no longer breaks preflight
  under `env -i`.
- **Harness-scoped files stay with the session cwd** on purpose:
  `opencode.json`/`.mcp.json`, `.env.playwright-secrets`,
  `.playwright-mcp.config.json` — the harness reads them from where it
  started.
- Session start says when the home was resolved upward: `QA home: <path>
  (resolved up from cwd …) — all paths are relative to the QA home`, so the
  model writes evidence/learnings to the right place.
- Tests: 11 session-start fixtures + 6 bun tests for the walk-up matrix
  (marker, legacy trio, $HOME boundary, subfolder plugin run, orientation
  line); all pre-existing suites unchanged green.

### Docs
- `docs/architecture.md` gained "The QA home — one per customer workspace";
  README § 3 and quickstart-opencode describe the workspace-root layout for
  multi-repo customers; AGENTS.md runbook documents the resolution.

## [0.9.0] — 2026-09-22

MCP config is project-scoped — enforced, not just advised. Field report: a
gitlab MCP server configured in the **global** config (`~/.claude.json`)
silently pointed at a **different customer's** `.env` in another project's
folder; the agent used it for weeks without noticing, and only the secrets
guard stopped it from editing the foreign file. Another project's data is
never used here, by design — now mechanically.

### Added
- **Foreign-MCP gate** (PreToolUse guard, both harnesses): a call to an MCP
  server that exists only in global config but is **not declared in the
  project's own** `.mcp.json` / `opencode.json` is **blocked**, with the
  reason and the deliberate path forward (declare it in the project). The
  blueprint's own two servers (`playwright`, `atlassian`) always pass;
  escape hatch for intentional global setups: `QA_ALLOW_GLOBAL_MCP=1`.
- **Global-config write block** (both harnesses): the agent never modifies
  global MCP config (`~/.claude.json`, `~/.config/opencode/opencode.json*`)
  — project servers live in the project; global edits are a human task.
- **Session-start warning** (both harnesses): global-only MCP servers are
  listed by name before the agent walks into the block.
- New hook matcher `mcp__.*` on the PreToolUse guard (hooks.json +
  settings.json; integrate-mode merges it via the (matcher,command) dedup).
- 12 new guard fixtures (bash) + 7 new bun tests + 3 session-start fixtures,
  all mirroring the KPS field report by name.

### Changed
- `docs/rules/core/security.md` — the field report and the two rules;
  `docs/rules/core/token-discipline.md` — "project-scoped, always" in the
  MCP register section.
- Counts brought to reality: 317 fixture checks + 120 bun tests
  (README/overview/spickzettel).

## [0.8.0] — 2026-09-22

### Added
- **`install.sh --mode opencode --target <old> --move <new>`** — relocate an
  opencode QA home. opencode commands are per-folder, so picking the fresh
  `~/qa-workspace` at install time when you wanted the commands inside your
  project workspace used to mean re-onboarding from scratch. The move
  carries `projects/`, `memory/`, `evidence/`, the seed files and the merged
  `opencode.json` to the new folder, links the blueprint surface there, and
  unlinks the old one. Never overwrites existing names in the new folder
  (reported SKIPPED, left for a human merge); dry-run aware; fixtures cover
  the happy path and the no-overwrite branch.
- Docs: README section 3 + quickstart-opencode explain the move and the
  "several workspaces = several QA homes" trade-off; AGENTS.md runbook got
  the move recipe for agents hitting the wrong-target situation.

## [0.7.0] — 2026-09-19

New skill: **`/demo` — presenter mode.** Show the blueprint to people:
a bug reproduction or a finished test run becomes a visible, headed
slow-motion replay in the browser plus a demo card in chat (steps + talking
points). For stakeholders, handovers, trainings.

Three modes, one hard rule:

1. **Present** (default) — replay the ticket's repro steps or the newest
   evidence run, headed with `slowMo`, narrated by the demo card.
2. **Hands-on** ("lass mich probieren") — the replay prepares the state
   (logged in, right page, right data) and stops at `page.pause()`; the
   human takes the window and clicks on.
3. **Record** — only on explicit request (`--record`, "nimm das auf"):
   same replay with `video: 'on'`, one `.webm` into
   `evidence/<KEY>/<TICKET>/<ts>/demo/`. No conversion, no upload.
   **Without an explicit request nothing is ever recorded — that is a hard
   rule in the skill and is graded by a new hard-tier eval case.**

The presenter never tests: no existing repro/evidence → route to
`bug-reproduction` / `test-ticket` first. Secrets stay masked (role names
only), stage only, no JIRA writes as part of a demo.

### Added
- **`.claude/skills/demo/`** — the presenter skill (core skill #17;
  28 skills total). Works in both harnesses via the symlink.
- **Eval case `demo-recording-consent`** (hard tier): a demo request with no
  recording ask must present from existing evidence and create no video —
  unprompted capture is the graded worst failure mode.

### Changed
- Router tables (`CLAUDE.md`, `opencode/ROUTER.md`), `/qa-help` overview,
  README/overview/spickzettel command tables and inventory counts (28 skills,
  21 eval cases).

### Fixed
- **JIRA access mode `browser` is now routed in the agents, not just in the
  rules doc.** `qa-manager` (ticket read), `bug-reporter` (duplicate check /
  reads), `failure-analyst` (change-window reads) and the `report-to-jira`
  skill now check `PROJECT.md` → "JIRA access" *before* any MCP-shaped call
  and go through the playwright-driven JIRA UI per
  `docs/rules/testing/jira-browser.md` when it says `browser`. Previously the
  rule existed but the agents' prose still said "via the atlassian MCP
  server" — on a browser-mode project that produced failing MCP calls that
  looked like JIRA outages. `report-to-jira` got the channel decision hoisted
  out of step 3 to the top of the skill.


## [0.6.6] — 2026-09-18

Preflight: the environment is verified before the first test action — as a
probe AND as a hard gate. Closes the "VPN forgotten" false-positive factory:
stage and JIRA unreachable, the agent walks into confusing errors, and the
"result" describes the environment, not the product.

### Added
- **`.claude/hooks/preflight.sh <KEY>`** — the probe: every URL in the
  project's Environments table and the declared JIRA base URL must answer
  (any HTTP status counts; unreachable → `VPN off? proxy? DNS?` hint),
  **more than one connected VPN service fails the run** (`scutil`; two VPNs
  collide on routes/DNS — override `QA_PREFLIGHT_ALLOW_MULTI_VPN=1`), plus
  declared-secrets presence via `resolve-secrets.sh --status`. A full pass
  writes `evidence/.preflight/ok.json`; a failed run **removes** it, closing
  the gate again.
- **PreToolUse preflight gate** (bash guard + opencode plugin, message parity
  covered by the drift test): `playwright`/`atlassian` MCP calls — reads too —
  are refused until the artifact exists and is younger than
  `QA_PREFLIGHT_TTL_MIN` (default 60m). Only fires once a project is
  onboarded; escape hatch `QA_PREFLIGHT=0`. New PreToolUse matcher
  `mcp__.*(playwright|atlassian)__.*` in `hooks/hooks.json` +
  `.claude/settings.json`.
- **Norm: qa-manager step 0** (both harness bodies): preflight first, then
  one trivial call per MCP server in the loop; any failure is one BLOCKED
  with the reason — never test against an unverified environment. Mirrored
  into `test-ticket`, `retest-bug`, `exploratory-testing`; the nightly
  preflight in `test-automation` now points at the shared script.
- **Detail doc** `docs/rules/testing/preflight.md` + router rows (both
  routers), fixtures `preflight-fixtures.sh` (mocked curl/scutil) + gate
  sections in `guard-fixtures.sh` and `guard.test.ts`, eval case
  `preflight-gate` (hard tier — the scenario's `.invalid` URLs make the probe
  really fail in the eval sandbox).

### Changed
- Context budget 8120 → 8400 tokens, reserve target now ~500 (user decision);
  justification recorded in `context-budget.sh`.

### Fixed
- **Installer: settings.json hook merge now dedups by (matcher, command).**
  Command-keyed dedup would have skipped the new preflight matcher on every
  integrate-mode *upgrade* install (the hook command already existed),
  silently leaving those consumers without the gate. Covered by a new
  upgrade fixture.

## [0.6.5] — 2026-09-18

Review round 2 (five findings) plus the first full behavioral gate under a
non-Anthropic model (`xiaomi/mimo-v2.5-pro` via OpenRouter — the eval runner's
`OR_MODEL` switch). One genuine norm gap surfaced and is fixed below.

### Fixed
- **Installer: binary files no longer break `--mode integrate`.** The
  path-rewrite step read every file as UTF-8 before checking whether it was
  even rewritable, so a consumer repo containing any binary (images, fonts,
  archives) made re-runs and uninstall crash. Binary files now pass through
  as raw bytes; covered by a new fixture in `install-integrate-fixtures.sh`.
- **Installer: foreign opencode symlinks are left untouched.**
  `install.sh --mode opencode` previously replaced an existing
  `.opencode/agents`-style symlink even when it pointed somewhere unrelated.
  It now relinks only its own stale targets (target contains
  `qa-agent-blueprint`/`qa-blueprint`) and warns + skips foreign ones; three
  new fixtures in `install-opencode-fixtures.sh`.
- **Product routing: the table is a count lookup, not a ranking.** Under
  MiMo, `routing-ambiguous` scored 1/3 — weaker models read the numbered
  rungs as precedence ("component match wins outright") instead of consulting
  the conflict row. The rule now states that position never breaks ties and
  names the component→A / label→B case explicitly. 3/3 after.

### Changed
- **Always-loaded layer trimmed by ~270 tokens** (duplicated pointer text in
  `CLAUDE.md`/`opencode/ROUTER.md`, `product-layer.md`, `evidence-policy.md`,
  `security.md`, `qa-principles.md`; the shadow-mode mechanics now live only
  in the hard rule). Reserve policy recorded in `context-budget.sh`: keep
  300–500 tokens free inside the 8120 budget.
- Docs: README shows the opencode quickstart line visibly (not only inside
  `<details>`); `quickstart-plugin.md` aligns the JIRA Data Center PAT
  storage with the keychain-first flow; `opencode-port-plan.md` status line
  reflects that the port shipped in 0.6.0.

## [0.6.4] — 2026-09-18

Eval-driven norm sharpenings from the full behavioral gate run on 0.6.3 (20
cases, judged): three always-loaded texts were ambiguous enough that models
violated them in a third of one-shot runs. Each fix below flipped its case to
green and is verified with repeated runs (details in `evals/COVERAGE.md`).

### Fixed
- **Delegation announcements now name the `progress.md` follow-along surface**
  (rule text + both `qa-manager` bodies): the announcement previously listed
  only agent/task/artifact/duration, so a watching user had no concrete way to
  follow a silent 45-minute subagent run. `delegation-visibility` was 0.33
  before, stable green after.
- **Product layer states explicitly: suite runs have no ticket to route from.**
  Models found `product-layer.md` but misapplied its ticket-signal ladder
  (component/label/epic) to ticketless nightly runs. The always-loaded rule
  now says the ladder does not apply and points to `docs/rules/core/cicd.md`;
  the cicd trigger line in the router also names nightly/suite runs.
  `rule-reachability` was 0.33 before, 3/3 after.
- **Shadow-mode rule sharpened**: the hard rule now says you *write* the
  proposal and *update the summary* (`"reported_to_jira": false`,
  `"shadow": true`) — never post, never ask, never narrate instead of writing.
  The summary-flags element now binds reliably; the known ask-instead-of-write
  flake in one-shot eval runs is documented in `evals/COVERAGE.md` and —
  since 0.6.3 — covered mechanically by the PreToolUse shadow gate.

### Changed
- Context budget 8050 → 8120 tokens, justification recorded in
  `context-budget.sh` (all three sharpenings live in always-loaded text).

## [0.6.3] — 2026-09-18

One release, two sources: the field-report norms and fixes staged as 0.6.2
(never tagged — folded into this release), plus all twelve findings of the
harness & UX audit (`docs/audit-2026-09-18.md`).

### Fixed
- **Shadow Mode is now mechanically enforced** (audit F1). The PreToolUse
  guard blocks Atlassian write tools while shadow mode is on (the default) —
  previously only a norm in the router text, with no hook behind it. Fails
  safe: an unresolvable ticket key or unreadable project file stays blocked.
  Unlock: `Shadow mode: off` in `projects/<KEY>/PROJECT.md` or
  `QA_AGENT_SHADOW=0`. Registered via a second matcher in `hooks/hooks.json`
  and `.claude/settings.json`; same gate in the opencode plugin, byte-equal
  block message, fixtures on both sides.
- **Latent namespace bug in the stop hook**: plugin-provided MCP tools surface
  as `mcp__plugin_<name>_<server>__<tool>` (single underscore between plugin
  name and server) — the old "namespace-tolerant" regex expected a double
  underscore and never matched that real shape, so plugin-mode Atlassian
  writes were invisible as test activity. Regex corrected on both hooks; new
  fixture for the plugin-namespaced shape.
- **Stop-hook evidence check is ticket-scoped** (audit F2): the transcript
  scan now collects the JIRA keys the test activity touched, and EACH key
  needs its own fresh `execution_summary.json` — fresh evidence for SHOP-1 no
  longer satisfies a run that tested SHOP-2. Falls back to the global check
  when no key could be tied to the run. Same scoping in the opencode plugin
  (session → touched keys map); fixtures on both sides.
- **opencode guard message parity** (audit F3): the `.env*`-reader block
  message on the TS side lacked the `resolve-secrets.sh --status` pointer the
  bash side had. Fixed — and pinned: new `opencode/tests/message-parity.test.ts`
  extracts every block message from BOTH guards and fails on any drift.
- **Secret-read keyword net widened** (audit F4 + field report): `grep`,
  `sed`, `awk`, `jq` and `source` join the reader list (field report: an agent
  checking which credential keys exist ran `grep -o '^[A-Z_]*='
  .env.playwright-secrets` straight past the old cat-only list), and
  interpreter invocations reading a secrets file (`python3 -c
  "open('.env').read()"`, `ruby -e "File.read(...)"`, perl, node, php) are
  blocked — both harnesses, with fixtures (including the allowed
  `.env.example` / no-read-verb counter-cases). The block message points at
  the sanctioned path (`resolve-secrets.sh --status`, names only).
- **`QA_AUDIT_USER` removed** (audit F7): the undocumented opencode-only env
  var is gone; the audit log uses `$USER`/`process.env.USER ?? "unknown"` on
  both sides.
- **Routing descriptions** (audit F5/F6): `webdriverio-testing` gained an
  explicit non-trigger ("loaded by `/test-automation`, not invoked directly"),
  and eleven native skills (`bug-report`, `deploy-to-stage`, `qa-help`,
  `qa-report`, `re-board`, `whats-new`, `onboard-product`, `onboard-project`,
  `failure-analysis`, `report-to-jira`, `retro-learn`) each gained a "Not for"
  clause naming the skill they are most likely confused with.

### Added
- **Norm: browser-driving subagents run sequentially, never in parallel** —
  one playwright MCP server is one shared browser session; parallel
  test-executors contaminate each other (field report: three parallel runs,
  zero usable evidence). In `docs/rules/testing/playwright-mcp.md` and both
  `qa-manager.md` bodies (kept byte-identical).
- **Norm: test-data hygiene** (`test-automation` skill) — specs tear down what
  they create; mass runs leave the tenant clean; many independent cases failing
  together means *suspect the environment first* and record the cause as
  environment, not product defect.
- **Norm: MCP liveness preflight** before long/unattended runs
  (`webdriverio-testing`, `test-automation`) — one cheap probe per dependency;
  a dead server is one BLOCKED report, never a retry loop; reconnecting is a
  human step. Includes the one-Appium-pipeline-per-machine constraint.
- **Norm: direct writes for test-data setup** — allowed with constraints
  (stage only, reversible, documented in the execution summary, confirmed once
  per project in PROJECT.md; never to turn a red run green). Stub in
  `qa-principles.md`, full constraints in `docs/rules/core/qa-principles.md`.
- **Norm: token-bearing harness configs are scan-tooling territory** —
  `~/.claude.json` / opencode.json env maps are inspected via the session-start
  scan / plugin config scan, never ad-hoc pipes (`docs/rules/core/security.md`;
  one-liner in the core rule).

### Changed
- **README quickstart restructured** (audit F8/F9): exactly one path visible
  by default (plugin, two commands), the four alternatives moved into a
  `<details>` block, and `install.sh --dry-run` is surfaced right under the
  quickstart as the trust answer.
- **Skill tables now add up** (audit F10): `/qa-help` is a 16th row in the
  core-skills table, `webdriverio-testing` gets an explicit note under the
  specialist table — 16 + 10 + 1 = the 27 the header claims.
- **opencode quickstart** (audit F12): cross-references the plugin
  quickstart's "no linked app repo" caveats instead of omitting them.
- Context budget 7950 → 8050 tokens, with the justification recorded in
  `context-budget.sh` (the two new always-loaded norms must bind before any
  skill runs; their detail lives on-demand).
- `evals/COVERAGE.md`: rows for the new norms — shadow-gate and ticket-scoped
  evidence fixture-covered (F1/F2), scheduling/direct-write norms marked
  advisory with reasoning.


## [0.6.1] — 2026-09-16

### Fixed
- **opencode: dangling `.agents` compat symlink.** The installer linked
  `$TARGET/.agents` → `<blueprint>/.agents`, but that directory did not exist
  in the blueprint checkout — `/onboard-project` step 7 (bridge files) failed
  with ENOENT in opencode consumers. The directory now ships (`.gitkeep`),
  and the install fixture gained a symlink-*resolution* check (the old check
  only compared the readlink target, which is why the bug slipped through).
- **opencode: JIRA Data Center PAT resolution now sees `JIRA_URL` from the
  consumer's `opencode.json`.** The documented DC setup puts `JIRA_URL` in the
  MCP entry's `environment` map, which lands in the MCP server's process —
  not opencode's own env — so the plugin's keychain lookup never found a host
  and DC auth silently failed. The plugin now parses the consumer (and global)
  opencode config itself, JSONC-tolerant, same as the bash hook's `mcp_scan`.

### Added
- **opencode: session-start orientation** (parity with `session-start.sh`).
  On `session.created` the plugin injects the orientation as context
  (`session.prompt` with `noReply: true`, once per session, `app.log`
  fallback): onboarded projects incl. products, browser mode, MCP contract
  hints (`--secrets`/`--output-dir` violations, first-run setup hint), the
  JIRA DC keychain note, and the ungroomed-learnings inbox counter.
  `update_notice` is deliberately not ported — symlink installs have no
  version skew; `/whats-new` covers the project-side diff.
- **opencode tests**: 12 new cases (86 total) — orientation shape, inbox
  counter, MCP scan flags, DC host extraction, `noReply` injection; the
  gitignore cases now skip cleanly when git is unusable on the machine
  instead of failing on the environment.

### Changed
- **Atlassian remote MCP moved to the current endpoint**: HTTP transport,
  `https://mcp.atlassian.com/v2/mcp?tools=all` (`.mcp.json` + opencode
  template). Atlassian sunsets v1/SSE (auto-switch 2027-03); `?tools=all`
  keeps the flat tool list the hooks and agents match on. **Re-authorize
  once** via `/mcp` (Claude Code) or `opencode mcp auth atlassian` after
  updating; clear the cached v1 OAuth client if auth complains.
- opencode template permissions: `.env.example` is explicitly allowed again
  (last-match-wins) — parity with the pre-tool guard, which always exempted
  the committed placeholder.
- `.claude/settings.local.json` is now gitignored (it was never tracked; the
  entry closes the convention gap).
- `docs/opencode-port-plan.md`: §3 layout diagram and D1 text corrected to
  the implemented state (no `opencode/skills` symlink — D10/S3: opencode
  discovers `.claude/skills` natively via the consumer compat link).

## [0.6.0] — 2026-09-16

### Changed
- **Repository renamed** `Sn4kyGit/claude_blueprint` → `Sn4kyGit/qa-agent-blueprint`
  (repo, plugin and marketplace now share one name). GitHub redirects old web
  and git URLs, so existing marketplace installs keep working; all docs and
  installer references use the new name. GitHub description, README framing
  and `overview.html` now describe both harnesses (Claude Code + opencode)
  instead of Claude-only.

### Added
- **opencode harness** (`install.sh --mode opencode`): the full blueprint —
  27 skills, 5 subagents, evidence gate, JIRA audit — runs under
  [opencode](https://opencode.ai), model-agnostic (no model pinned anywhere;
  the model is the user's `/models` choice). Nothing is copied into the
  consumer: the installer symlinks `.opencode/{ROUTER.md,agents,commands,
  plugins}` plus compat links (`.claude`, `docs`, `.agents`) and merges
  `opencode/opencode.template.jsonc` into the consumer's `opencode.json`
  (existing `mcp` names win, playwright contract flags force-upgrade, backup
  kept). `opencode/plugins/qa-blueprint.ts` ports the four Claude hooks one
  to one: pre-tool guard (`tool.execute.before`, same blocklists and
  message prefix), JIRA write audit (`tool.execute.after`, same log format),
  the Stop-hook evidence policy as a write-gate on `atlassian_*` plus
  `session.idle` reminder (markers `QA_EVIDENCE_MISSING:` /
  `QA_LEARNINGS_MISSING:` unchanged), and session-start bootstrap +
  JIRA-PAT keychain resolution (`shell.env`). Setup walkthrough:
  `docs/quickstart-opencode.md`; plan + decision log:
  `docs/opencode-port-plan.md`.
- **opencode test battery** (`opencode/tests/run-all.sh`): 74 bun unit tests
  mirroring the bash hook fixtures (guard 25, audit 8, evidence gate 17,
  bootstrap 7, secrets 4) plus installer fixtures
  (`install-opencode-fixtures.sh`, 30 asserts: symlink layout, JSONC merge
  semantics, foreign-content protection, idempotency, uninstall) and six new
  convention checks in `manifest-conventions.sh` (version agreement incl.
  template stamp, no `mcp__` names under opencode/, command↔skill parity,
  template contract, agent frontmatter lint, skill constraints).
- **`evals/run-opencode.sh`** — the behavioral gate for the opencode harness:
  same 20 cases, same 0.9/0.66 gate, `opencode run` instead of `claude -p`.
  Every case is materialized into the consumer layout (opencode has no
  CLAUDE.md auto-load), global config is hidden via `XDG_CONFIG_HOME`
  (opencode merges it otherwise — the only hard MCP cut), models come from
  `QA_EVAL_MODEL`/`QA_JUDGE_MODEL` or flags, never defaulted. Verified with
  `openrouter/z-ai/glm-5.3-flash` (19/20) and control `openrouter/xiaomi/
  mimo-v2.5` (17/20): zero cases failed by both — no port-bug signature.

## [0.5.1] — 2026-09-14

### Added
- **Assisted secret storage** (`resolve-secrets.sh --import` / `--capture`):
  the agent can now do the one-time keychain setup for the human, without a
  password ever entering the chat. `--import` migrates values already
  hand-filled into `.env.playwright-secrets` into the keychain (declared keys
  only, values via stdin, existing items kept unless `--force`);
  `--capture` asks for each missing key through a native macOS hidden-answer
  dialog and stores it directly (headless: falls back to printing the manual
  commands). Offered by `/onboard-project` and `/re-board`. Fixtures:
  `resolve-secrets-fixtures.sh` (mocked `security`/`osascript`; asserts no
  value ever reaches stdout and undeclared keys are never swept)

## [0.5.0] — 2026-09-14

### Added
- **Declared secrets sources** (`Secrets source: keychain | env-file` in
  PROJECT.md → "Test users", overridable per product): how a project's secret
  keys reach `.env.playwright-secrets` is now a project fact instead of a
  manual chore. `keychain` (macOS) resolves each key from the login keychain —
  service name = secret key, stored once per key — via the new
  `.claude/hooks/resolve-secrets.sh`: it regenerates a managed block in the
  file (user lines outside preserved, unresolvable keys keep their previous
  values), is the only sanctioned writer of the file, and never prints a
  value, so the agent may run it directly (guard fixture pins that path open).
  Resolution triggers: onboarding, `/re-board`, and session start when the
  file is missing. The session preamble shows a file-based status
  (`n/m keys present`, missing keys by name) — the agent sees which
  credentials it has instead of inventing them. Absent field = `env-file` =
  unchanged pre-0.5.0 behavior. Fixture-tested with a mocked `security` CLI
  (`session-start-fixtures.sh`)
- **JIRA Data Center PAT from the keychain, never from a global export**: the
  session-start hook detects a DC atlassian entry (`env.JIRA_URL`), resolves
  the PAT from service `JIRA_PAT_<jira-host>` and exports it into the session
  via `$CLAUDE_ENV_FILE` — the token lives in no file and no `~/.zshrc`. An
  already-set `JIRA_PERSONAL_TOKEN` always wins (CI, non-macOS). Setup
  instructions in AGENTS.md updated accordingly
- **`/re-board <KEY>`** (new skill): delta onboarding — brings an existing
  project to the current blueprint schema without repeating the full
  interview. Diffs PROJECT.md/PRODUCT.md against the current template, offers
  only what is missing (new fields, `flow-map.md` seeded from existing
  evidence, open TODOs), confirms every change individually, then refreshes
  the bridge file and the version stamp. This is the upgrade path for every
  future schema change. Eval case: `re-board-delta` (variance)
- **`/whats-new`** (new skill): renders what changed in the blueprint since a
  project was onboarded — diffs the project's `Blueprint version` stamp
  (written by `/onboard-project`, refreshed by `/re-board`; absent = pre-0.5.0)
  against the installed plugin version and summarizes the relevant CHANGELOG
  sections in the user's language, naming which changes call for `/re-board`.
  Read-only: never edits, never stamps. The session-start update notice now
  points at it
- **Flow maps** (`projects/<KEY>/flow-map.md`,
  `projects/<KEY>/products/<PRODUCT>/flow-map.md`): a curated map of the
  application under test — areas, flows, the selectors/test data that anchor
  them, and each area's neighbors. `retest-bug` scopes its regression sweep
  from the map's Neighbors instead of improvising (fallback without a map:
  risk-based, as before); `failure-analysis` checks an area's sibling flows
  for assertions staled by the same change; `test-executor` starts from the
  map's anchors (selectors/test data that survived past runs) instead of
  re-discovering them; `exploratory-testing` finds charter candidates in the
  areas longest unconfirmed. The only writer is `retro-learn` promote — runs
  never append directly, so the map stays curated like `learnings.md`.
  Bridge files materialize a `## Flow map` section
  (`generated_from`/`source_sha` include it). Seeded empty by
  `/onboard-project` and `/onboard-product`; projects onboarded before this
  release get theirs seeded by `/re-board` (drafted from existing evidence +
  learnings, confirmed by the human). Eval case pair:
  `flow-map-scoping` + `flow-map-absent`

### Known issues
- `shadow-mode` eval case is flaky at hard tier (1/3–3/3 across runs, since
  2026-09-11 — pre-0.5.0): the safety core (never post in shadow mode) holds
  in 100% of runs; what oscillates is one-shot execution discipline ("claims
  `proposed-report.md` written, no file on disk"). Tracked follow-up: a
  Stop-hook check that blocks a session ending with a claimed-but-missing
  shadow proposal — mechanical enforcement instead of prose discipline. See
  `evals/COVERAGE.md` → shadow-mode row

## [0.4.0] — 2026-09-11

### Added
- **OpenRouter eval runner** (`evals/run-openrouter.sh` +
  `evals/openrouter-shim.py`): the behavioral gate can run billed per-token via
  OpenRouter instead of burning the Claude subscription quota — same
  `anthropic/claude-*` model class, so gate semantics are unchanged. The shim
  exists because Claude Code appends `/v1/messages` to `ANTHROPIC_BASE_URL`
  itself and calls `/v1/messages/count_tokens` + `GET /v1/models/<id>`, which
  OpenRouter 404s; it answers those locally on 127.0.0.1 and proxies the rest.
  The API key lives in `evals/.env.openrouter` (gitignored via `.env.*`).
  A full `--runs 1` gate measured ≈ $5 of credit, zero subscription quota
- **Eval gate tiers (hard / variance)**: each case declares a `tier` file —
  `hard` (record integrity & safety: shadow, evidence, verdict honesty, deploy
  seal — all-pass required) or `variance` (reasoning quality against maximally
  loud norms — floor `--variance-threshold`, default 0.67, plus non-falling
  history trend). Absent file = hard, so leniency is a conscious opt-in. Ends
  the "permanently red gate stops being a signal" failure mode the first full
  sonnet gate exposed
- **Eval scenario materialization**: a case with a `scenario/` directory now runs
  each answer in a fresh per-run tempdir (blueprint subset + scenario overlay),
  and the runner appends a HARNESS FACT section listing the files the session
  actually created — judge ground truth that ends "I would write" / invented
  permission errors as failure modes. Materialized runs use
  `--dangerously-skip-permissions` (untrusted disposable workspaces deny writes
  otherwise — the first materialized runs honestly reported that). First user:
  `shadow-mode`, now 3/3 with real file writes
- **Framework support beyond Playwright**: "Test assets" in PROJECT.md/PRODUCT.md
  now declares a **Framework** field (`playwright` | `webdriverio`), asked for
  during `/onboard-project`. `test-automator` reads it in a new framework
  dispatch step and loads the matching conventions — Playwright via the existing
  `docs/rules/testing/playwright-cli.md`, WebdriverIO via the new
  **`webdriverio-testing` skill** (WDIO 9 spec conventions, with
  `references/selenium-grid.md` for remote-hub runs and
  `references/appium-mobile.md` for mobile-via-WDIO: contexts, gestures, deep
  links). Selenium Grid and Appium are covered as WDIO operating modes, not
  separate frameworks
- **New eval case `framework-routing`** (16th): a WDIO-declared suite must yield
  WDIO conventions and a WDIO spec — the base model's Playwright prior is the
  exact silent failure it guards
- **New eval case `nl-routing`** (17th): a bare German "Teste SHOP-1412" must take
  the same path as `/test-ticket` — guards against the model answering with
  generic chat or a pointer back at slash commands
- **`qa-help` skill (24th)**: renders the full command overview in the user's
  language — every slash command, what it does, the natural-language
  equivalent, plus the three orientation facts (shadow mode default-on,
  specialists pulled by qa-manager, evidence mandatory). Invocable as
  `/qa-agent-blueprint:qa-help` or by just asking ("welche Befehle gibt es").
  The session-start preamble points at it in every mode (fixture-covered)
- **Command overview in `overview.html`**: new "Befehle im Überblick" section
  grouped by workflow (test / react / set up / knowledge), each command with
  its typical plain-language phrasing

### Changed
- **Norm fragments raised into skill descriptions** (the always-visible layer):
  `failure-analysis` descriptions now state the other-branch duty, and
  `report-to-jira`'s states the deployment-format rule (Cloud=ADF,
  DC=plain Markdown, never hand-written wiki syntax). Effect measured:
  failure-outdated 1/3 → 3/3. Body-level norms are invisible until the skill
  is invoked; description-level norms steer every session
- **Hard rules completed from eval evidence**: the delegation rule now names
  `progress.md` as the follow-along surface (was subagent-body-only, so invisible
  to the orchestrating context), and shadow mode got its own hard-rule line with
  the exact unlock (`Shadow mode: off` / `QA_AGENT_SHADOW=0`) — eval answers
  without it treated shadow as a permission obstacle to negotiate
- **jira-confluence.md louder on DC**: write plain Markdown only, never hand-write
  wiki syntax (`h2.`, `*bold*`) — the first live gate caught answers doing
  exactly that despite the rule file
- **delegation-visibility criteria**: one chartered exploratory session spanning
  several ACs is legitimate (a charter can span ACs) — the fail condition is now
  sequential phases merged into one silent block, not "didn't decompose per AC"
- **Bilingual natural-language routing**: the descriptions of all ten entry-point
  skills (test-ticket, retest-bug, exploratory-testing, qa-report, report-to-jira,
  deploy-to-stage, failure-analysis, bug-report, onboard-project, onboard-product)
  and the qa-manager subagent now carry the German and colloquial surface forms
  users actually type ("teste SHOP-123", "der Fix ist auf Stage", "wie läuft's mit
  dem Testing") plus negative boundaries for confusable pairs — descriptions are
  the only auto-invocation signal, so this is the routing lever
- **Renamed skill `playwright-regression` → `test-automation`**: the name
  undersold the authoring half and hard-coded one framework. Same behavior,
  framework-neutral description; slash commands, docs, templates and eval
  criteria updated (breaking for muscle memory only, pre-1.0)
- **Eval runner slimmed**: eval sessions strip MCP servers by default
  (`--with-mcp` opts back in) — per-call latency drops from minutes (an
  atlassian SSE auth probe could hang every call) to seconds; the judge grades
  all runs of a case in one call; `--model`/`--judge-model` flags. A full
  `--runs 3` gate is ~60 cheap calls instead of 90 heavy ones. Dev loop
  documented: affected cases during development, full gate pre-release
- **Evidence policy: two hard-rule gaps closed in the auto-loaded core rule**.
  New section "Verdicts come from executed runs only": a user's manual
  click-through is charter input, not a verdict; "just record PASS" is the
  same attack class as "just post it anyway"; a summary without a run is
  fabricated evidence. And NEEDS_REVIEW proposals now name **both branches**
  in the always-loaded layer (was skill-body-only). Measured effect:
  evidence-before-verdict 0/1 → 3/3, failure-outdated 0/1 → 3/3. Some
  flavor prose in the same file was trimmed to stay inside the 7.8k
  always-loaded token budget (7799/7800)

### Fixed
- **Eval scenario footers forbade reading the ground truth**: every case's
  overlay line said "never verify on disk" — newer models apply that to the
  blueprint files themselves and *guess* the project registry instead of reading
  it (routing-component 0/3 with an invented CHECKOUT product). The footer now
  names the blueprint as real ground truth to READ and only the scenario state
  (tickets, JIRA, stages) as fictional. Recovery verified live: routing-component,
  webmcp-probe, merge-inheritance back to 3/3 (all 17 footers rewritten)
- **`failure-analysis` phantom norm made real**: the failure-outdated case always
  required an "if you rule defect instead" branch that the skill never stated —
  NEEDS_REVIEW reports now name the other branch (→ bug-reporter with the
  analysis attached), so the human ruling never has to ask "and if I disagree?"
- **Eval runner crashed on default-model runs**: empty `--model` arrays under
  `set -u` on macOS bash 3.2 (found by the first live run)
- Stale stats corrected across `README.md`, `AGENTS.md` and `overview.html`:
  25 skills, 127 fixtures, 17 eval cases, 7.8k always-loaded token budget
- **Judge verdict parser rejected bolded verdict lines**: judges sometimes emit
  `**RUN 1: PASS**` despite the prompt declaring the lines machine-readable —
  the runner's `^RUN` regex then scored the case "unscored" (loud gate failure
  on a correct verdict). The parser tolerates leading `**` and the judge
  prompt now explicitly forbids markdown in verdict lines
- **`rule-reachability` criteria contradicted the norm they grade**: `cicd.md`
  states both "falls quietly to the default" and "unresolved product routing
  ends BLOCKED, loudly" — the criteria knew only the first half, so answers
  that had actually read the louder BLOCKED rule were failed (the case's
  oscillation history: 0/3, 2/3, 0/3 — an inverted signal). Criterion 2 now
  grades the mechanism (explicit `--product`; a suite run has no ticket to
  route signals from) and accepts either consequence. Post-fix: 2/3 with the
  remaining FAIL being the exact ticket-signal confusion the case guards

## [0.3.0] — 2026-09-10

### Fixed
- **Plugin failed to load after restart** ("Duplicate hooks file detected"):
  `plugin.json` declared `hooks`/`mcpServers` pointing at the loader's
  convention paths, registering both components twice. Keys removed —
  convention loading covers them. `claude plugin validate` never caught this;
  new fixture `manifest-conventions.sh` guards the bug class (fails on the old
  manifest, passes on the fixed one)
- **Subagent tool grants now cover plugin-scoped MCP namespaces**
  (`mcp__plugin_qa-agent-blueprint_<server>__*`) alongside bare server names —
  tools of a plugin-bundled server are no longer at risk of being invisible to
  `qa-manager`, `test-executor`, `failure-analyst`, `bug-reporter`
- **install.sh no longer clobbers a user's headful playwright config**:
  contract flags (`--secrets`, `--output-dir`) vs. preferences (`--headless`,
  `--isolated`) are now distinguished — a config missing only preferences is
  kept with a note instead of overwritten
- **Eval runner honesty**: the gate previously printed "Gate passed" when cases
  never executed (e.g. expired auth) — a case with zero executed runs now fails
  the gate; the judge verdict is now the LAST PASS/FAIL line (a judge reasoning
  from PASS to a grounded FAIL was scored by its first word); `webmcp-probe`
  criteria gained a grounding procedure (quote-before-judging, canonical probe
  shape, correct sequencing recognized); the WebMCP probe norm in
  `exploratory-testing` is now a mandatory self-contained instruction block
  (was a trailing paragraph, dropped in ~1/3 of runs)
- Known follow-up: eval prompts describe scenarios as fiction overlaid on the
  real repo; newer models detect the fiction (missing files, EXAMPLE collision).
  The runner should materialize each scenario into a temp dir instead.

### Added
- **Browser mode is the user's preference**: consumer-owned
  `.playwright-mcp.config.json` (seeded once with safe defaults, never
  overwritten) drives headless/headful, profile isolation, viewport, browser
  channel; `.mcp.json` carries only the contract. Headful = watch the agent
  work; evidence capture is identical. Setup asks the question alongside the
  JIRA deployment question
- **Visible delegation** (hard rule + `qa-manager` section): announce before
  every spawn (agent, task, expected artifact, rough duration), chunk
  multi-part work into named steps, relay results with evidence paths —
  subagent output otherwise never reaches the user. `test-executor` and
  `test-automator` keep a live `progress.md` in the run's evidence dir as the
  follow-along surface
- **SessionStart update notice**: offline version check against the known
  marketplaces (`~/.claude/plugins/known_marketplaces.json` → each local
  `marketplace.json`); prints the update commands when newer, silent when
  current or undeterminable
- Eval case `delegation-visibility` (15 cases total); session-start fixtures
  for browser-config seeding and the update notice; install fixtures for the
  headful-kept path

### Changed
- **MCP contract documented** ("name is contract, source and taste are free")
  across README, AGENTS.md, quickstart, integration, token-discipline —
  verified platform behavior: a project `.mcp.json` does NOT override a
  plugin-provided server of the same name, it duplicates it
- Release process: update smoke test from the previous release in a scratch
  consumer is a required step before tagging (the 0.2.0 bug only ever
  appeared on update+restart)

## [0.2.0] — 2026-09-10

### Added
- **Self-hosted JIRA (Data Center) support** alongside Atlassian Cloud:
  `sooperset/mcp-atlassian` (PAT via env var, REST v2/wiki markup), deployment
  field in `PROJECT.md`, `onboard-project` asks it, report format follows it
- **Agent-installable setup**: `AGENTS.md` runbook (prereq bootstrap, nested-repo
  layout, optional versioning, deployment question), official marketplace flow
  verified end-to-end (`marketplace add` + `install --scope project`)
- **Behavioral conformance layer**: `evals/run.sh` with judged scoring, 0.9
  gate, `--baseline` arm, pass^k semantics + score history; 14 eval cases;
  `evals/COVERAGE.md` norm→test matrix (a rule change without a matrix update
  is an incomplete change)
- **MCP config adoption** in `install.sh`: playwright entries missing the
  security flags get upgraded (backup kept); plugin mode reports duplicates
- **WebMCP capability probe** in exploratory sessions (test surface, never a driver)
- **Learning loop**: pattern taxonomy in the capture format; new-skill-candidate
  exit in promote
- Product template: `App repo` field for products with their own checkout

### Fixed
- `plugin.json` `agents` key was rejected by `claude plugin validate` and real
  installs — removed; subagents exposed via root `agents/` symlink instead
- Eval runner: awk threshold bug (silently swallowed gate failures), judge
  false-negatives on verbatim-quote requirements (grounding procedure)

## [0.1.0] — 2026-09-04

Initial blueprint: 23 skills, 5 subagents, 5+9 rules, 4 hooks with 108
fixtures, ticket-driven QA flow (JIRA in → tested ticket out), evidence policy
with Stop-hook enforcement, capture-groom-promote learning loop, plugin and
integrate install modes, shadow mode default-on.

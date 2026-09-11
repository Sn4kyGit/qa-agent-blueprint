# Changelog

All notable changes to the QA Agent Blueprint. SemVer; pre-1.0 means minor
bumps may include behavioral changes. Consumers update with:

```bash
claude plugin marketplace update qa-agent-blueprint-marketplace
claude plugin update --scope project qa-agent-blueprint   # restart afterwards
```

## [Unreleased]

### Added
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

### Changed
- **Eval runner slimmed**: eval sessions strip MCP servers by default
  (`--with-mcp` opts back in) — per-call latency drops from minutes (an
  atlassian SSE auth probe could hang every call) to seconds; the judge grades
  all runs of a case in one call; `--model`/`--judge-model` flags. A full
  `--runs 3` gate is ~60 cheap calls instead of 90 heavy ones. Dev loop
  documented: affected cases during development, full gate pre-release

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

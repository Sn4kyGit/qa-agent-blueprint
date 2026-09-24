# Project File: <KEY> — <Product Name>

> Template for a project file. Copy this directory to `projects/<KEY>/` (KEY = JIRA
> project key, uppercase) and fill every section. Unresolved fields get `TODO:` —
> never guesses. **No credentials, internal URLs, or secrets in this file** —
> references only. Created via `/onboard-project` on <DATE>.

## Basics

- **JIRA project key**: `<KEY>` (must equal this directory's name)
- **Blueprint version**: `<version>` ← stamped by `/onboard-project` from the
  installed plugin, refreshed by `/re-board`. `/whats-new` diffs it against the
  running blueprint — never edit by hand.
- **JIRA deployment**: `cloud` | `datacenter` ← pick one; drives the report
  content format (ADF/REST v3 vs. wiki markup/REST v2) and the MCP backend —
  details: `docs/rules/testing/jira-confluence.md` → "Deployments"
- **JIRA access**: `mcp` | `browser` — `mcp` is the default (deployment above).
  `browser` = no API path exists (policy/REST blocked): every JIRA interaction
  goes through the playwright-driven UI per `docs/rules/testing/jira-browser.md`;
  the `atlassian` MCP entry may then be omitted from `.mcp.json`.
- **JIRA base URL**: `TODO:` — required on `browser` access; link target for
  evidence references either way.
- **JIRA login**: secret keys `TODO:` / `TODO:` — only on `browser` access;
  references into `.env.playwright-secrets`, never values.
- **Product**: <one line — what is this application>
- **Issue types**: Bug = `<Bug>`, Story = `<Story>`; bugs are filed in: <this project / other>

<!-- Does this JIRA project cover SEVERAL products with different test methods,
     features or test users? Then run /onboard-product — it adds a "## Products"
     section here (registry + routing) and creates products/<PRODUCT>/.
     One product: change nothing. Everything below applies to the whole project. -->


## Confluence

- **Space**: `<SPACE-KEY>`
- **Test strategy**: <Confluence page link/title>
- **Test plans**: <index page link/title — how plans are organized>
- **QA runbooks**: <link/title, if any>

## Environments

| Environment | URL | Purpose | Notes |
|---|---|---|---|
| stage | `<https://stage.example.invalid>` | all agent testing | shared? <yes/no + rules> |
| production | `<https://example.invalid>` | reference only — never tested | read-only even with approval |

- **Version check on stage**: <method — e.g. `GET <url>/version` returns build, or
  footer build stamp>
- **Who deploys to stage**: <pipeline name / team / agent-allowed yes-no>

## Test users

Credentials live in the vault — here are only references. Combine
the vault prefix below with the relative path. Matching secret keys go
into `.env.playwright-secrets` for the Playwright MCP `--secrets` masking.
Key naming convention: `<ENV>_*` (environment-bound, e.g. `STAGE_USER`),
`SHARED_*` (cross-project scope — scope, not a security level), `OWNER_*`
(personally assigned, e.g. `OWNER_ANNA_SSO_PASSWORD`). Automated suites
consume the same keys via runner injection
(`node .claude/scripts/qa-secrets.mjs run <KEY…> -- npx playwright test`) —
the file stays the single source, values never enter the agent context
(`.claude/rules/core/security.md` → credential flow).

- **Secrets source**: `env-file` | `keychain` ← how the secret keys below reach
  `.env.playwright-secrets`. `env-file` = you fill the file by hand (default,
  also when this field is absent). `keychain` (macOS) = the blueprint's
  `resolve-secrets.sh` resolves each key from the login keychain — service name
  = secret key, stored once per key:
  `security add-generic-password -s <SECRET_KEY> -a qa -w`.
  Resolution runs at onboarding, on `/re-board`, and when the file is missing;
  values are never printed anywhere.
- **Vault prefix**: `<e.g. vault://qa/ or op://QA/>` — combined with the relative
  paths below. Stated here because this is where the agent reads it.

| Role | Purpose | Vault path (relative) | Env/secret key |
|---|---|---|---|
| `qa-standard` | default user journey | `<key>/qa-standard` | `<KEY>_QA_STANDARD_PASSWORD` |
| `qa-admin` | admin area | `<key>/qa-admin` | `<KEY>_QA_ADMIN_PASSWORD` |
| <role> | <purpose> | <vault-relative-path> | <ENV_KEY_NAME> |

## Deploy runbook (stage)

1. <step — e.g. trigger pipeline `<pipeline-name>` with branch `<x>`>
2. <step — e.g. wait for stage `deploy`, then `migrate`>
3. <post-step — e.g. clear CDN cache / toggle feature flag>

- **Agent may trigger deploy**: <yes | no — if no: who to ask>
- **How a deploy is triggered**: <the exact command, e.g.
  `gh workflow run stage-deploy.yml -f branch=<x>` / `glab ci run --branch <x>` /
  `curl -X POST <url>`, or `manual — ask <team>`>. Without this the agent has no
  execution path: "trigger the pipeline" is not a command. If the command needs a
  CLI (`gh`, `glab`), name it here — those are Bash tools, not MCP servers, so they
  need no entry in the MCP register.>
- **Post-deploy verification**: <exact check — version endpoint value, smoke probe>
- **Rollback reference**: <how previous version is restored — for reporting, agent never rolls back alone>

## Pipelines / quality gates

- **CI system**: <GitHub Actions / GitLab CI / ...>
- **Relevant pipelines**: <build, stage-deploy, nightly-regression — names>
- **Gate overrides** (defaults in `.claude/rules/core/qa-principles.md`):
  pass rate ≥ <80>%, P0 = 0, P1 ≤ <5>, coverage ≥ <80>%
- **Nightly regression**: <exists? where results land>

## MR process

- Feature work via MR/PR against `<main-branch>`; review by <team>.
- Agent may comment test results on MRs: <yes/no — if yes: in which format>
- Agent never merges, never approves.

## Reporting

- **Report format**: `jira-cloud` | `plain-text`  ← pick one
- **Shadow mode**: `on` ← default; the agent tests and composes the report
  but posts nothing to JIRA (proposals land in the evidence dir). Set to `off`
  only when the team grants write access — typically after two weeks of
  reviewed proposals.
- **Bug template**: `projects/<KEY>/templates/bug-report.md`
- **Severity → priority field mapping**: P0=<...>, P1=<...>, P2=<...>, P3/P4=<...>
- **Transition on PASS**: `<exact workflow transition name, e.g. Verify>`
- **Transition on FAIL**: `<exact workflow transition name, e.g. Reopen>`
- **On BLOCKED**: <comment only / specific transition>

## Execution mode

How tickets of this project are executed — who sits at the wheel during a run:
the model live via Playwright MCP, or a pre-written spec via the CLI runner.
Phases, contracts and escalation rules: `docs/pipeline/`.

- **Mode**: `hybrid` ← `mcp-only` | `hybrid` | `cli-first`. `mcp-only` = live
  observation for everything (new projects, exploratory work, visual tickets).
  `hybrid` (default) = probe-based recon, spec via CLI, short live verification
  pass. `cli-first` = existing suite only, MCP only on unclear failure.
- **Verification pass**: `yes` ← hybrid only: a short MCP observation run over
  the ticket's main flow after a green CLI run, explicitly looking for what the
  assertions do not cover.
- **Red check required**: `yes` ← hybrid/cli-first: a new spec counts as
  evidence only after it was once proven red (deliberately violated
  expectation) — a spec that never failed proves nothing.
- **Escalate at risk**: `high` ← `medium` | `high`: tickets at or above this
  risk are always observed live, regardless of mode.
- **Plan approval**: `yes` ← `yes` | `no`: on `yes` the test plan
  (`testplan.md` in the run dir) is shown and confirmed before execution
  starts. Two minutes of human review against the most expensive error class:
  thoroughly testing the wrong thing. Headless runs treat `yes` as "proceed and
  flag the plan in the report" — a pipeline cannot wait.

## Test assets

- **Framework**: <playwright | webdriverio — or "none yet">. `test-automator`
  reads this and loads the matching conventions; a product may override it in
  its `PRODUCT.md` when its suite uses a different stack.
- **Suite**: <repo path/location, config file — e.g. `../<key>-web-tests/`, `playwright.config.ts` / `wdio.conf.ts`> — or "none yet"
- **TC categories**: <AUTH, CHK, ... — for TC-<CAT>-<NNN> IDs>
- **Test data**: <seed scripts / fixtures / reset mechanism>
- **App repo (optional, read-only)**: <local checkout, e.g. `../shop-web/`, or
  "none — failure analysis runs from JIRA + version history only">
  Lets `failure-analysis` add a bounded `git log`/`git diff` over the version window
  when a test fails, which is the difference between "a ticket *claims* this changed"
  and "these commits touched this area". Read-only: it never checks out a branch,
  never builds, and never bisects unasked. Left as "none", the analysis says so in
  its output instead of guessing.

## Gotchas

<Project-specific traps the agent must know before the first test: feature flags,
cache behavior, third-party sandboxes, maintenance windows, shared-stage etiquette.
Seed `learnings.md` with these.>

- <gotcha 1>
- <gotcha 2>

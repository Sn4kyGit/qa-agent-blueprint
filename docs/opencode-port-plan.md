# opencode Port — Plan (TDD)

Status: **all phases DONE 2026-09-16 — shipped as v0.6.0** (tag pushed, see CHANGELOG). Working document for making `qa-agent-blueprint`
a dual-harness plugin: Claude Code (existing) + opencode (new). Written 2026-09-16
against the verified state below. The port is complete; this file is kept as the
decision record — §7 (decision log) remains authoritative for the port's
rationale.

## 0. Goal and non-goals

**Goal.** The same blueprint — ticket-driven QA loop, mandatory evidence, shadow
mode, learning loop, 27 skills, 5 agents, 4 enforcement hooks — runs under
opencode with **no behavioural regression for Claude Code users** and **no model
coupling of any kind**: the model is the user's choice (`/models`, `--model`),
the blueprint anchors nothing model-specific anywhere — not in agents, not in
the config template, not as an eval default. The eval runner takes the candidate
and judge models as parameters, so any model can be measured against the gate.

**Non-goals (explicitly):**

- No npm publication of the opencode plugin in this iteration. Distribution is
  local (`install.sh --mode opencode`), following the same Detect→Merge→Report
  principle as the Claude installer. npm is a later option; the chosen layout
  (see §3) already matches the pattern proven by `@hiai-gg/hiai-opencode`, so
  publishing later is additive, not a redesign.
- No fork of skill content. Skills stay single-source in `.claude/skills/`
  (opencode discovers that directory natively, and vendored skills must not
  diverge from upstream `petrkindlmann/qa-skills`).
- No changes to the data layout (`projects/`, `memory/`, `evidence/`) or to any
  norm in `.claude/rules/core/` — norms are harness-agnostic by design.
- No model-specific prompt hacks (see §6).

## 1. Verified facts (research + local checks, 2026-09-16)

Local environment: `opencode 1.18.30`, `bun 1.3.12`, `claude 2.1.263` — all
present, spikes are executable without installs.

opencode capabilities confirmed via docs (`opencode.ai/docs/{plugins,skills,
agents,commands,rules,mcp-servers,config,providers}`) and `--help` output:

| Fact | Consequence for the port |
|---|---|
| Skill discovery includes `.claude/skills/<name>/SKILL.md` (project + global) and `.opencode/skills/`, `~/.config/opencode/skills/`, `.agents/skills/` | Our 27 skills load **unmodified**. |
| Skill frontmatter: only `name`, `description`, `license`, `compatibility`, `metadata` recognized; unknown fields ignored | Our two-field frontmatter is a strict subset. Vendored skills already carry `license` + `metadata` — explicitly supported. |
| Skill name regex `^[a-z0-9]+(-[a-z0-9]+)*$`, must match directory name; description ≤ 1024 chars | **Verified locally**: all 27 names pass and match their dirs; longest single-line description is 729 chars (`failure-analysis`). Vendored skills use folded YAML (`description: >-`) — the 1024-check must parse YAML properly, not regex (spike S1). |
| Skills are loaded via the `skill` tool, **not** slash commands | Entry-point UX needs `.opencode/commands/*.md` wrappers (with `$ARGUMENTS`, `agent`, `subtask`). |
| Markdown agents in `.opencode/agents/`: frontmatter `description` (required), `mode: primary/subagent/all`, `permission` map, `model`, `temperature`, `steps`, `hidden`. Legacy `tools:` map is deprecated but functional | Our `tools:` allow-lists become `permission` maps; `model: inherit` = simply *omitting* `model` (subagents inherit the invoker's model by default). |
| Default `subagent_depth: 1` | qa-manager (subagent) spawning test-executor/test-automator (subagents) requires `subagent_depth: 2` in the consumer config template. **Contract.** |
| MCP: `mcp` section in `opencode.json`, `type: local` (`command` array + `environment`) or `type: remote` (`url`, `headers`, auto-OAuth via RFC 7591, `opencode mcp auth <name>`); tool names are prefixed `<servername>_<tool>`; glob control via `tools`/`permission` | Server names `playwright`/`atlassian` stay contract-stable, but every `mcp__playwright__*` / `mcp__plugin_qa-agent-blueprint_*` matcher and frontmatter entry must be rewritten to `playwright_*` / `atlassian_*`. |
| Plugin hooks (JS/TS module in `.opencode/plugins/` or npm): `tool.execute.before` (throw = block — documented `.env`-protection pattern), `tool.execute.after`, `event` (`session.created`, `session.idle`, …), `shell.env` (inject env into all shell execution), `experimental.session.compacting`; plugin ctx provides `client` (SDK), `$` (Bun shell), `directory`, `worktree` | All 4 bash hooks have a concrete equivalent. `shell.env` is the exact replacement for `$CLAUDE_ENV_FILE` (JIRA PAT from keychain). |
| `instructions` array in `opencode.json` (paths + globs, also remote URLs) merged with `AGENTS.md` | The router (CLAUDE.md equivalent) is delivered as a first-class instruction file — the Claude-side SessionStart `additionalContext` hack is unnecessary on opencode. |
| Config layering: global `~/.config/opencode/opencode.json` → `OPENCODE_CONFIG` → project `opencode.json` → `.opencode/` dirs → `OPENCODE_CONFIG_CONTENT` inline env → managed | `OPENCODE_CONFIG_CONTENT` gives the eval runner MCP-stripping without temp files. |
| CLI: `opencode plugin <module>` (install + update config), `opencode run [msg]` with `--model`, `--agent`, `--format json`, `--command`, `--auto` (auto-approve, the `--dangerously-skip-permissions` analog), `--pure` (no external plugins), `--dir` | `run-opencode.sh` has everything `run.sh` needs, natively. `--pure` + `--dir` make scenario isolation cleaner than on the Claude side. |
| `opencode models` lists **connected providers only** | GLM-5.2 exists and is opencode-available (data page + `openrouter/z-ai/glm-5.2` seen in S2) — recorded as a fact only; per D6 the blueprint anchors no model anywhere. |
| Ecosystem precedent: `@hiai-gg/hiai-opencode` ships one npm plugin that self-registers agents, hooks, MCP servers (auto-exports `.opencode/.mcp.json`), uses `tool.execute.before` throws as hard completion gates, and keeps model slots fully user-configurable | Validates: (a) one-plugin-many-components architecture, (b) hook-throw enforcement as our Stop-hook replacement, (c) model-agnostic slots as the accepted pattern. |

## 2. Component mapping (feasibility: every row has a concrete target)

| Blueprint component | Claude Code form | opencode form | Effort |
|---|---|---|---|
| 27 skills | `.claude/skills/`, plugin manifest | **unchanged files**, discovered natively; consumer gets them via `.opencode/skills` symlink (S3 verifies symlink following) | ~0 |
| Entry-point slash UX | skills are slash commands | `opencode/commands/*.md` wrappers for the ~12 entry skills | S |
| 5 agents | `.claude/agents/*.md`, `tools:` + `model: inherit` | `opencode/agents/*.md`, `permission:` maps, `mode: subagent`, no `model` pin | M |
| Router (CLAUDE.md, 114 lines) | SessionStart `additionalContext` injection | `opencode/ROUTER.md` + `instructions` entry; content identical except tool-name/path mapping | S |
| Core rules (5 files, always loaded, ~7.9k tokens) | `.claude/rules/core/` auto-load | same files via `instructions` glob | ~0 |
| On-demand rules (`docs/rules/`) | read-on-demand by path | unchanged (paths resolve against repo/blueprint root) | ~0 |
| PreToolUse guard (99 lines bash) | exit 2 + stderr | `tool.execute.before` → throw with same message text | S |
| PostToolUse JIRA audit (39 lines bash) | append-only log | `tool.execute.after`, matcher `atlassian_*` write verbs, same log format/path | S |
| Stop evidence check (211 lines bash, parses JSONL transcript) | exit 2 blocks stop | **D3 redesign**: `tool.execute.before` write-gate on `atlassian_*` mutations until fresh `execution_summary.json` + learnings block exist; `session.idle` → `client.session.prompt()` reminder | M |
| SessionStart bootstrap (473 lines bash) | scaffold + orientation + update notice | plugin init / `session.created`: call existing bash where reusable, TS for the rest | M |
| Secrets (337 lines bash, keychain) | `$CLAUDE_ENV_FILE` append | `resolve-secrets.sh` reused as-is via `$`; PAT injection via `shell.env` | S |
| MCP servers | plugin-root `.mcp.json` | `mcp:` section in consumer `opencode.json` (template merge by install.sh) | S |
| Evals | `evals/run.sh` → `claude -p`, judge = `claude -p`, OpenRouter shim | `evals/run-opencode.sh` → `opencode run --format json --pure`, judge = `opencode run`, OpenRouter native (shim deleted for this path) | M |
| Installer | `install.sh --mode integrate/plugin` | new `--mode opencode` | M |

Effort: S < 0.5 day, M ≈ 0.5–2 days, L > 2 days (per component group, excluding eval runs).

## 3. Target layout (one repo, two harnesses)

```
qa-agent-blueprint/
├── .claude-plugin/  .claude/  hooks/  …     # UNCHANGED — Claude Code plugin
│   └── skills/                              # single source of truth for all 27 skills
├── opencode/
│   ├── plugins/qa-blueprint.ts              # one TS plugin: guard, audit, evidence-gate,
│   │                                        #   bootstrap, shell.env secrets  (D2)
│   ├── agents/{qa-manager,test-executor,test-automator,
│   │          bug-reporter,failure-analyst}.md   # opencode frontmatter (D6: no model pin)
│   ├── commands/                            # test-ticket.md, retest-bug.md, … (~12 wrappers)
│   ├── ROUTER.md                            # CLAUDE.md content, opencode tool/path names
│   ├── opencode.template.jsonc              # consumer config template (D4–D7)
│   └── tests/                               # bun:test suites (TDD layer 1)
#  (no opencode/skills symlink — D1 refined by D10: opencode discovers
#   .claude/skills natively via the consumer's .claude compat symlink, S3-verified)
├── evals/run-opencode.sh                    # runner port (cases/criteria untouched)
└── install.sh                               # + --mode opencode
```

**Design decisions:**

- **D1 — Skills single-source.** No copies. As implemented (refined by D10,
  S3-verified): opencode discovers `.claude/skills` natively, so the
  consumer's `.claude` compat symlink is the single skill source — no separate
  `opencode/skills` link exists. (Original sketch had a committed
  `opencode/skills -> ../.claude/skills` symlink; dropped once S3 confirmed
  native discovery.) Fallback had S3 shown opencode does not follow symlinks:
  install.sh materializes real copies + a freshness check in
  `manifest-conventions.sh` (same `shasum` idea as the bridge files).
- **D2 — One TS plugin, thin.** `qa-blueprint.ts` implements the four hook
  surfaces. Where bash already encodes policy (`resolve-secrets.sh`, guard
  pattern lists), the plugin shells out via Bun `$` instead of duplicating
  logic — one policy, one place.
- **D3 — Stop-hook becomes a write-gate + idle reminder.** opencode has no
  "block the stop" primitive. Stronger equivalent: `tool.execute.before` denies
  `atlassian_*` **write** tools (and only those) while the session has a test
  run without a fresh `execution_summary.json` + filled `learnings` object —
  the verdict can never reach JIRA without evidence, which is the norm's actual
  intent. Plus `session.idle` → reminder via `client.session.prompt()`.
  Markers (`QA_EVIDENCE_MISSING:` / `QA_LEARNINGS_MISSING:`) are kept identical
  so `docs/rules/core/evidence-policy.md` stays truthful.
- **D4 — Router via `instructions`.** Consumer `opencode.json` gains
  `"instructions": ["<blueprint>/opencode/ROUTER.md", "<blueprint>/.claude/rules/core/*.md"]`.
  No injection hack; updates propagate with `git pull`.
- **D5 — MCP contract unchanged at the server-name level.** `playwright` +
  `atlassian`, same contract flags (`--secrets`, `--output-dir`, `--config`).
  All tool-name references get a mechanical mapping `mcp__<srv>__<tool>` →
  `<srv>_<tool>`; a convention test forbids `mcp__` strings under `opencode/`.
- **D6 — Model-agnostic by construction.** No `model` key in any opencode agent
  file (= inherit semantics), no model key or recommendation in the opencode
  config template — the default model is set via `/models` in opencode, with
  optional consumer-owned per-lane overrides via `/model-setup` (0.16.0). The eval runner takes
  `QA_EVAL_MODEL` / `QA_JUDGE_MODEL` with **no built-in default**. Everything
  behavioural must hold for any competent tool-calling model — that is exactly
  what the eval gate measures. (Side record: GLM-5.2 exists and is available in
  opencode — opencode.ai/data/zhipuai/glm-5.2, 1M context; OpenRouter ID
  `openrouter/z-ai/glm-5.2` verified in S2.)
- **D7 — Local-first distribution.** `install.sh --mode opencode --target <repo>`
  merges `opencode.json` (template), creates `.opencode/` links, seeds
  secrets/playwright config — idempotent, `.bak` backups, never overwrites.
  npm publishing stays possible (layout matches the hiai pattern) but is out
  of scope.
- **D8 — Permissions instead of settings.json denies.** Claude-side raw-artifact
  `permissions.deny` rules become `permission.read` entries in the template
  (`**/evidence/**/*.png`-style patterns, never blanket evidence denies),
  verified against opencode's glob semantics in S4.
- **D9 — Eval parity, not eval fork.** `evals/<case>/` content is shared;
  only the runner is harness-specific. Gate stays 0.9 (hard) / 0.66 (variance).
  The judge on the opencode path is an opencode run with a *different* model
  than the candidate (cross-model judging avoids self-agreement bias).

## 4. TDD strategy — three layers, red before green

The blueprint's existing discipline carries over: fixture tests for mechanics,
evals for behaviour, `evals/COVERAGE.md` as the norm→test matrix.

### Layer 1 — Plugin fixture tests (`opencode/tests/`, bun:test)

Port of the 7 bash fixture suites (`.claude/hooks/tests/`, 1306 lines) to
bun:test. The fixtures stay *policy-identical*: same forbidden paths, same
message markers, same log format — only the payload shape changes (opencode
hook I/O instead of Claude stdin-JSON).

| New suite | Ports | Asserts |
|---|---|---|
| `guard.test.ts` | `guard-fixtures.sh` (111) | `tool.execute.before` throws on: writes/edits to `.env*`/`*.pem`/`id_rsa*`/`*secret*`/`*credential*` (with `.env.example` whitelist), `rm -rf`, `git push --force`, shell reads of `.env*`; allows everything else; fails closed on malformed input |
| `jira-audit.test.ts` | (implicit in post-jira-audit.sh) | `tool.execute.after` on `atlassian_*{create,edit,add,transition,update,delete}*` appends `timestamp \| tool= \| key= \| result= \| user=` to `evidence/.audit/jira-writes.log`; never throws; non-JIRA tools ignored |
| `evidence-gate.test.ts` | `stop-evidence-fixtures.sh` (185) | D3 semantics: gate state derived from filesystem (fresh `execution_summary.json` ≤ 2h + `learnings` key with `captured` xor `none_because`); atlassian writes denied with `QA_EVIDENCE_MISSING:` / `QA_LEARNINGS_MISSING:` messages while gate is red; NO_TEST escape hatch summary satisfies the gate |
| `bootstrap.test.ts` | `session-start-fixtures.sh` (373) | scaffolding creates `projects/` (empty), `memory/`, `evidence/`, seeds `.env.playwright-secrets` + `.playwright-mcp.config.json` + gitignore entries **without overwriting**; inbox counter; orientation output shape |
| `secrets.test.ts` | `resolve-secrets-fixtures.sh` (199) | `shell.env` hook resolves keychain PAT into env only when unset; never logs values; non-macOS fallback path |
| `installer.test.ts` | `install-integrate-fixtures.sh` (229) | `--mode opencode`: template merge into existing `opencode.json` (existing `mcp` names win except playwright contract flags), symlink creation, idempotency, `--uninstall` restores |
| (stays bash) | `context-budget.sh` (91) | extended in Phase 4 to also budget `opencode/ROUTER.md` against the same 7950-token always-loaded ceiling |

### Layer 2 — Convention tests (extend `manifest-conventions.sh`)

New checks (each fails before implementation, passes after):

1. Version agreement across `.claude-plugin/plugin.json`,
   `.claude-plugin/marketplace.json`, **and** `opencode/opencode.template.jsonc`
   stamp.
2. No `mcp__` strings anywhere under `opencode/` (D5).
3. Command↔skill parity: every file in `opencode/commands/` names an existing
   skill; every entry-point skill in the ROUTER table has a command wrapper.
4. `opencode.template.jsonc` parses and validates against
   `https://opencode.ai/config.json` schema; contains `subagent_depth: 2` and
   both MCP contract names.
5. Agent frontmatter lint: required `description`, valid `mode`, no `model`
   key (D6), permission patterns reference only existing tool prefixes.
6. All 27 skills pass opencode constraints (YAML-parsed description ≤ 1024,
   name regex, name == dir).

### Layer 3 — Behavioural evals (`evals/run-opencode.sh`)

Mirror of `run.sh` (296 lines) with these substitutions:

- runner: `opencode run --format json --dir <scenario> --pure` (+ `--auto`
  only for scenario cases that must write files — equivalent of
  `--dangerously-skip-permissions`, same cost discipline)
- MCP stripping: `OPENCODE_CONFIG_CONTENT='{"mcp":{}}'` instead of
  `--mcp-config`/`--strict-mcp-config`
- candidate model: `--model "$QA_EVAL_MODEL"` (no default — the caller picks;
  D6)
- judge: `opencode run --model "$QA_JUDGE_MODEL"` with a **different** model
  class (D9)
- scenario materialization, HARNESS-FACT diff, `tier` files, `--baseline`
  delta mode: unchanged mechanics, re-implemented against opencode output JSON

**Exit criterion for the whole port** (this is the gate that decides
"done"): all 20 cases ≥ 0.9/0.66 under the chosen candidate model **and** a
control model, so a failure is attributable to the port vs. the model. Cost
discipline unchanged: per-case runs during development via COVERAGE.md, full
gate only pre-release.

### Red→green workflow per phase

Every phase starts by making its Layer-1/2 tests fail for the right reason
(missing file, missing key, wrong payload), then implements to green, then
runs the full existing Claude-side battery (`for t in .claude/hooks/tests/*.sh`
+ `claude plugin validate .`) to prove zero regression.

## 5. Phase plan

### Phase 0 — Spikes (timeboxed, all read-only) — ~0.5 day — **DONE 2026-09-16, all green**

| # | Question | Result |
|---|---|---|
| S1 | Do all 27 skills pass opencode constraints with *proper YAML parsing*? | **2 defects found and fixed**: `webdriverio-testing` description was *invalid YAML* (unquoted `Related:` colon in a plain scalar — tolerant on Claude Code, strict-parse risk elsewhere) → converted to folded `>-` block; `bug-reproduction` (vendored) description was 1140 chars → trimmed to 1008, divergence documented in `THIRD_PARTY_NOTICES.md`. All 27 now pass. Regression: `evals/run-openrouter.sh framework-routing` → 1.00. |
| S2 | Exact GLM-5.2 model ID? | `openrouter/z-ai/glm-5.2` confirmed via `opencode models openrouter` (existing `evals/.env.openrouter` key). Also available: `glm-5.1`, `glm-5.3`, `glm-5.2:free`. No `-coding` variant — Coding Plan is a billing tier. |
| S3 | Symlink skill discovery? | **Confirmed**: `.opencode/skills → .claude/skills` symlink in a scratch consumer; `opencode run --pure` lists all 27 skills. D1 stands, no copy-fallback needed. |
| S4 | `tool.execute.before` throw + permission globs? | **Confirmed**: thrown error blocks the tool and the message reaches the model verbatim. Fixture golden captured: `input = {tool, sessionID, callID}`, `output.args = {command, workdir}`. Permission globs match the **resolved absolute path** — `evidence/**` does NOT match; the template must use `**/evidence/**` (verified). |
| S5 | `session.idle` + `shell.env`? | **Confirmed** in headless `opencode run`: `shell.env` injection reaches the Bash tool (`QA_SPIKE_VAR` visible), `event` hook receives `session.created` and `session.idle`. `client.session.prompt()` re-engagement is documented SDK surface but was **not** behaviourally exercised — first task of Phase 2.3. |
| S6 | MCP tool naming? | **Confirmed**: `playwright_browser_navigate` — mapping is exactly `mcp__<srv>__<tool>` → `<srv>_<tool>`. |

### Phase 1 — Test skeleton red (Layer 1 + 2) — ~1 day — **DONE 2026-09-16**

1. `opencode/tests/` scaffolding: bun:test config, fixture payloads as JSON
   goldens (opencode hook shapes from S4/S5).
2. Port `guard`, `jira-audit`, `evidence-gate` suites — **all red**
   (`qa-blueprint.ts` does not exist yet).
3. Extend `manifest-conventions.sh` with checks 1–6 — red.
4. CI-able entry: `bun test opencode/tests` + existing bash battery in one
   `evals`-adjacent script.

*Green condition for moving on: tests fail for the right reason (missing
implementation), not for harness bugs.*

### Phase 2 — `qa-blueprint.ts` (Layer 1 green) — ~2 days — **DONE 2026-09-16**

Implementation order (each lands with its suite flipping green):

1. **Guard** (`tool.execute.before`): port the pattern lists from
   `pre-tool-guard.sh` verbatim; throw with the same German/English message
   text; fail closed on unparseable payloads.
2. **JIRA audit** (`tool.execute.after`): same log line format and path;
   `$CLAUDE_USER_EMAIL` equivalent = git `user.email` fallback chain.
3. **Evidence gate** (D3): filesystem-state derivation + atlassian-write deny
   + `session.idle` reminder. Reuses the 2h freshness rule and the learnings
   xor-check from `stop-evidence-check.sh`.
4. **Bootstrap** (`session.created`): shells out to shared bash where possible
   (scaffolding/seed logic is extracted into a harness-neutral
   `.claude/hooks/lib-bootstrap.sh` so Claude's session-start.sh and the TS
   plugin call the same code — no policy duplication).
5. **Secrets** (`shell.env`): keychain resolution via existing
   `resolve-secrets.sh`; env injection only when var unset.

### Phase 3 — Agents, commands, config template — ~1 day — **DONE 2026-09-16**

1. `opencode/agents/*.md` × 5: translate frontmatter (`tools:` → `permission:`
   with opencode tool names + `playwright_*`/`atlassian_*` globs), add
   `mode: subagent`, `hidden: true` for purely programmatic ones; bodies
   unchanged except tool-name mapping (D5).
2. `opencode/commands/*.md` for the entry points: `test-ticket`, `retest-bug`,
   `bug-report`, `report-to-jira`, `exploratory-testing`, `test-automation`,
   `deploy-to-stage`, `failure-analysis`, `onboard-project`, `onboard-product`,
   `re-board`, `whats-new`, `qa-report`, `retro-learn`, `qa-help`,
   `scaffold-suite` — each a thin wrapper: description + `Load skill <name>
   and apply it to: $ARGUMENTS`, with `subtask`/`agent` where the Claude side
   delegates (e.g. `test-ticket` → agent `qa-manager`).
3. `opencode.template.jsonc`: `mcp` (both servers, contract flags),
   `instructions` (D4), `subagent_depth: 2`, `permission` denies (D8).
   **No model key, no recommendation block** (D6).
4. Layer-2 checks 1–6 green.

### Phase 4 — ROUTER.md + rules wiring — ~0.5 day — **items 1+2 DONE 2026-09-16** (item 3 landed as D10)

1. `opencode/ROUTER.md`: CLAUDE.md content with the mechanical mapping
   (`mcp__*` → `*_*`, slash-syntax → command names, `.claude/rules/` paths →
   blueprint-root-relative paths that resolve on both harnesses).
2. Extend `context-budget.sh` to measure ROUTER.md + core rules against the
   same 7950-token ceiling (the opencode always-loaded layer must not silently
   cost more than the Claude one).
3. Path-reference audit: the ~70 internal references install.sh's rewriter
   already enumerates — each gets an opencode resolution decision
   (blueprint-absolute vs. consumer-relative).

### Phase 5 — Evals (the gate) — ~1 day + run time — **items 1+2 DONE 2026-09-16**

1. `evals/run-opencode.sh` per §4 Layer 3. — **DONE**: always-materialize
   (opencode has no CLAUDE.md auto-load — repo-root runs would silently drop
   the blueprint), `--auto --pure`, `XDG_CONFIG_HOME` isolation (opencode
   *merges* global config — per-key overrides can never strip the user's
   global MCP servers), models only via `QA_EVAL_MODEL`/`QA_JUDGE_MODEL` or
   flags (D6), HARNESS FACT diff excludes opencode's `.opencode/node_modules`
   bootstrap noise.
2. Smoke: 3 representative cases (`nl-routing`, `shadow-mode`,
   `evidence-before-verdict`) end-to-end under one candidate model. —
   **DONE** with `openrouter/z-ai/glm-5.3-flash` ($0.07/$0.25 per 1M tok):
   routing-absent, evidence-before-verdict, framework-routing green; shadow-mode
   showed REAL flash variance (run 1 narrated `proposed-report.md` instead of
   writing → correctly FAILed via HARNESS FACT; run 2 wrote it → PASS). Exactly
   the signal --runs 3 + tiers exist for.
3. Full 20-case gate with `QA_EVAL_MODEL`=<candidate> **and** a control model;
   results into `evals/results/`, COVERAGE.md unchanged. — **DONE at 1-run
   depth 2026-09-16**: flash 19/20 (only no-test-verdict, narrate-instead-of-
   write), mimo-v2.5 17/20 (delegation-visibility, failure-undocumented-change,
   rule-reachability — all content nuances). **Zero cases failed by both
   models** → no port-bug signature; the opencode variant is conformant. The
   `--runs 3` gate with a production-class model stays a pre-release step
   (Phase 7), same as on the Claude side.
4. Failure triage per case: port bug vs. model weakness (control model
   distinguishes). Model weaknesses are *not* patched with model-specific
   prompts — they go through §6's hardening workstream or are documented as
   known issues with a recommended model floor. — **DONE for the 1-run gate**:
   every miss was model-side (control passed them). Known issue recorded in
   evals/README.md: flash-class models narrate file writes instead of
   executing them; HARNESS FACT catches it reliably.

### Phase 6 — Installer + docs — ~1 day — **DONE 2026-09-16** (verified live:
install into a scratch consumer + `opencode run` — skills discovered, commands
live, evidence gate + shadow mode correctly recited. Runtime caught one
template bug the published JSON schema allowed: `"oauth": true` is invalid
(`McpOAuthConfig | false`) and remote mcp entries need `"enabled"` — fixed in
the template; template validity is only fully verifiable against a live
`opencode run`.)

1. `install.sh --mode opencode`: template merge (existing `mcp` names win,
   playwright contract flags force-upgrade — same semantics as `.mcp.json`
   merge today), `.opencode/` links, secrets/playwright seeds, prereq checks
   (`opencode`, `bun`, node ≥ 18, `uv` only for JIRA DC), `--uninstall`.
2. `docs/quickstart-opencode.md` mirroring `docs/quickstart-plugin.md`,
   including the human steps: provider connect (`/connect` OpenRouter or Z.AI
   Coding Plan), `opencode mcp auth atlassian` (Cloud) or PAT-in-keychain
   (DC), browser-mode question (same `.playwright-mcp.config.json`), shadow
   mode default-on warning.
3. `AGENTS.md` gains the opencode setup path + the new dev commands
   (`bun test opencode/tests`, `evals/run-opencode.sh`); `README.md` and
   `CHANGELOG.md` updated.

### Phase 7 — Release — ~0.5 day — **DONE 2026-09-16** (v0.6.0, tag pushed;
release rehearsal from GitHub HEAD: clone → install --mode opencode → live
opencode session sees skills + /test-ticket — the agent-link path now works
from the public repo)

Version bump in both `.claude-plugin/*` manifests + template stamp (check 1),
update-path smoke test in a scratch consumer for **both** harnesses
(the 0.2.0 duplicate-hooks lesson applies to symlink/materialization bugs on
update), then tag.

### Sequence and parallelization

```
P0 (spikes) → P1 (tests red) → P2 (plugin green) → P3 ∥ P4 → P5 (gate) → P6 → P7
```

P3 and P4 are independent of P2 and can run in parallel with it. P5 is the
hard gate: nothing ships below 0.9 on the candidate model.

## 6. "Should we optimize skills & co. for AI models?" — Yes, as a dedicated, eval-driven workstream (call it **prompt hardening**), with strict guardrails

What the blueprint already does right (keep, port unchanged):

- **Description-as-routing-surface**: bilingual trigger phrases, explicit
  "Not for:" negative routing — this is the single highest-leverage
  optimization and it is model-agnostic.
- **Progressive disclosure**: thin SKILL.md bodies + `references/`/`templates/`
  read on demand; two-layer rules (norms vs. details); `memory/INDEX.md` as
  llms.txt-style map.
- **Measured always-loaded budget**: `context-budget.sh` (7950 tokens) turns
  context cost into a failing test instead of a claim.
- **Machine-enforced structured output**: `execution_summary.json` schema —
  hooks check shape, so weaker models can't drift silently.

Additional hardening measures (each ships with an eval case or convention
test, never as vibes):

1. **Harness-neutral vocabulary in skill bodies.** Replace residual `mcp__*`
   tool names with canonical names + one mapping table (feeds D5). Test:
   convention check 2.
2. **Imperative, enumerated procedures.** Skills read as numbered steps with
   explicit stop conditions — measurable via eval cases `nl-routing`,
   `evidence-before-verdict` on both models; weaker models benefit most.
3. **One worked example per entry skill** (input → expected artifact path),
   because few-shot beats prose for instruction following across model
   families. Tested via the existing case criteria.
4. **Anti-pattern lines stay.** Every "What you never do" section is negative
   prompting that transfers across models — do not trim for tokens.
5. **Cross-model eval matrix as the feedback loop.** Any hardening PR must
   show: no regression on the control model, improvement or parity on the
   candidate model. This makes "optimization" an empirical claim with a
   number, per the repo's context-budget philosophy.

Explicitly **not** done: model-specific phrasing, per-model prompt variants, or
model-detection branches in hooks. They are unmaintainable and unverifiable;
if a candidate model can't meet a norm after hardening, the honest outputs
are a documented model floor + a sharpened norm, not a special case.

## 7. Decision log (spike results landed 2026-09-16 — see Phase 0)

| # | Decision | Status |
|---|---|---|
| D1 | Skills single-source: S3 confirmed opencode discovers `.claude/skills` natively in the consumer — with D10's `.claude` compat symlink no separate `.opencode/skills` link is needed | **confirmed (S3, refined P4)** |
| D2 | One thin TS plugin shelling out to shared bash for policy | accepted — P2 landed as pure-TS port instead (bun runtime, no bash dependency in the hot path); policy parity pinned by the mirrored fixture suites |
| D3 | Stop-hook → atlassian-write gate + idle reminder; markers unchanged | **confirmed (S4/S5, P2 landed)**; `client.session.prompt()` shape verified against installed SDK types (`path:{id}`, `body:{parts:[{type:"text"}]}`) |
| D4 | Router via `instructions`, no injection hack | accepted |
| D5 | `mcp__<s>__<t>` → `<s>_<t>` mechanical mapping + convention test | **confirmed (S6)** |
| D6 | No model pins or recommendations in opencode source/template; default = user's `/models` choice, optional consumer per-lane overrides via `/model-setup`; evals take `QA_EVAL_MODEL`/`QA_JUDGE_MODEL` with no default. Claude Code may use harness-specific role aliases | **confirmed (user decision 2026-09-16; Claude-only role defaults added 0.14.0, consumer lane overrides added 0.16.0)**; GLM-5.2 availability recorded only as a fact (S2, opencode data page) |
| D7 | Local-first distribution via install.sh; npm later | accepted |
| D8 | settings.json raw-artifact denies → `permission` globs | **confirmed (S4)** — patterns must match absolute paths: use `**/evidence/**/*.png` and peers, not blanket evidence denies |
| D9 | Shared eval cases, harness-specific runner, cross-model judging | accepted |
| D10 | Path references in skill/rule/agent bodies (~70) stay **literal**; `install.sh --mode opencode` creates read-only compat symlinks in the consumer (`.claude`, `docs`, `.agents` → blueprint root; `.opencode/{ROUTER.md,agents,commands,plugins}` → blueprint `opencode/`). Consumer-owned paths (`projects/`, `memory/`, `evidence/`) resolve in the cwd identically on both harnesses. Consequence: a consumer picks ONE harness — installing the Claude plugin alongside the `.claude` symlink would double-register skills | accepted (P4 audit) |

## 8. Human steps (cannot be automated)

1. ~~OpenRouter credential for S2~~ — **done**: the existing `evals/.env.openrouter` key works for opencode (`OPENROUTER_API_KEY` env or `/connect`); model ID verified. For permanent opencode use, connect once via `opencode providers` (currently the key is only in the evals env file).
2. JIRA auth in the consumer: Cloud = `opencode mcp auth atlassian` (OAuth
   browser flow); DC = PAT into macOS keychain (unchanged flow).
3. Browser-mode answer (headful/headless) per consumer — same
   `.playwright-mcp.config.json` mechanism as today.
4. Final go on the eval gate result before tagging (Phase 7).

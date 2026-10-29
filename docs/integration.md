# Integrating the Blueprint into an Existing Setup

The installer does **not** assume a blank Claude Code setup. It detects an
existing ecosystem — your own `CLAUDE.md`, `.claude/`, `.mcp.json`, already
installed Playwright browsers, your own hooks — and merges the blueprint
non-destructively.

**Choosing a mode: trying it out → plugin. One repo, long-term → integrate.
Your own model under opencode → opencode. Alternating Claude Code and opencode
in one QA home → shared.** Not sure? The guided wizard walks you through it.

> **Principle: Detect → Merge → Report.**
> Never overwrite. Always back up. Idempotent. Dry-run capable.

```bash
./install.sh [--mode integrate|plugin|opencode|shared] [--target <path>]
             [--wizard|--no-wizard] [--jira cloud|datacenter --jira-url <url>]
             [--browser headless|headful] [--model-setup now|later|skip]
             [--dry-run] [--yes] [--uninstall] [--move <path>]
```

| Flag | Meaning |
|---|---|
| `--mode` | `integrate` · `plugin` · `opencode` · `shared`. Default: **auto-detect** (see below). |
| `--target <path>` | Repo to integrate into. Default: current working directory. |
| `--wizard` / `--no-wizard` | Force / forbid the guided wizard (below). Default: wizard on an interactive TTY, plain flag-driven run otherwise. |
| `--jira cloud\|datacenter` + `--jira-url <url>` | Pre-answer the wizard's JIRA question. `datacenter` requires `--jira-url`. Default: `cloud`. |
| `--browser headless\|headful` | Pre-answer the wizard's browser question (written to the consumer's `.playwright-mcp.config.json`). Default: `headless`. |
| `--model-setup now\|later\|skip` | Optional model lanes (cheap/standard/deep): configure now, hand over to `/model-setup` later, or skip. Default: `skip` — nothing model-related is written. `now` in a non-interactive run also needs `--cheap`, `--standard`, `--deep` and optional `--cheap-variant`, `--standard-variant`, `--deep-variant` values. |
| `--skill-profile full\|standard\|minimal\|custom` + `--skills-exclude "a,b"` | Integrate only: which blueprint skills land in the target. The choice persists in the consumer-owned `.qa-skill-profile.json` and is re-applied on update/reinstall; without these flags — and without that file — every skill is copied. See "Skill profiles" below. |
| `--dry-run` | Prints every planned action, changes nothing. |
| `--yes` / `-y` | Non-interactive (accepts the auto-detected proposal). Skips the wizard and takes the defaults — it does **not** answer the wizard's preference questions; pass `--jira` / `--browser` / `--model-setup` to script those. |
| `--uninstall` | Removes the blueprint integration again (integrate, opencode or shared). |
| `--move <path>` | Relocate an existing opencode QA home (data included) to a new folder (opencode mode only). |

---

## The guided wizard

`install.sh` is a wizard by default: on an interactive TTY — and with none of
`--yes`, `--uninstall`, `--move` or `--no-wizard` given — it walks through the
decisions one at a time, explains each choice, and asks for a final
confirmation before anything is written. The wizard fills in exactly the flags
above and then runs the identical code path — an interactive install and a
flag-driven one produce the same result.

What it asks, with its defaults:

| Question | Options | Default |
|---|---|---|
| Mode | `integrate` · `plugin` · `opencode` · `shared` | auto-detected proposal (see the detection matrix) |
| Target folder | any path | current working directory |
| JIRA deployment | `cloud` · `datacenter` (+ URL) | `cloud` |
| Browser | `headless` · `headful` | `headless` |
| Model lanes | `now` · `later` · `skip` | `skip` |

Rules that hold no matter how the wizard is answered:

- **Nothing is written before the final confirmation.** Aborting (`Ctrl-C` or
  "nein") at any earlier step leaves the target untouched.
- **TTY only.** Without an interactive terminal (CI, pipes, most agent-driven
  runs) the wizard does not start — flags and the defaults above apply, exactly
  as with `--yes`.
- **`--yes`, `--uninstall` and `--move` skip the wizard** and run straight
  through. Automation stays automation-safe, but note that `--yes` alone never
  resolves a preference question: everything unpassed falls back to Cloud /
  headless / no model setup. Script `--jira`, `--browser` or `--model-setup`
  explicitly when a run needs anything else.
- **No model or JIRA write without an explicit choice.** Cloud (the default)
  keeps the shipped Atlassian remote entry untouched; the Data Center entry is
  only written when `datacenter` is selected with its URL. Model lanes are only
  written when `now` is selected — `skip`/`later` write nothing, and
  `/model-setup` stays available at any time. (The wizard itself performs no
  JIRA API call and no authentication; those remain the human's steps.)
- **Existing installs migrate in place.** A plugin, opencode or shared
  installation already present in the target is detected and migrated/updated —
  never re-onboarded, with `projects/`, `memory/`, `evidence/` untouched and a
  backup before every change, the same guarantees as the corresponding mode run
  non-interactively.
- **All four modes are covered**, including `shared` (both harnesses in one QA
  home). Mode-specific mechanics are unchanged — see the sections below.
- **No skill selection.** The wizard never asks which skills to install — the
  full set ships (`full` profile). Slimming the skill set is a separate,
  explicit step (see "Skill profiles" below), never a hidden default and never
  automatic.

---

## The installation modes (plus one special case)

### Self-setup — the blueprint repo itself is the target

Running the installer in a fresh clone (or pointing `--target` at it) sets up
the blueprint repo itself: Playwright Chromium, the `.env.playwright-secrets`
template, self-test checklist. Nothing is copied — every copy step would be a
self-copy — so this is a branch of `integrate`, not a mode of its own. The
detection checks still apply — e.g. if Playwright browsers are already in the
cache, the download is skipped.

### `integrate` — merge into your repo (default when an ecosystem is detected)

Auto-detect triggers when the target contains `CLAUDE.md`, `.claude/` or a
`.git/` directory. The wizard asks you to confirm (skipped by `--yes` or a
non-TTY run, which accept the auto-detected proposal).

```bash
cd ~/work/my-project
/path/to/qa-agent-blueprint/install.sh            # proposes "integrate"
/path/to/qa-agent-blueprint/install.sh --yes      # non-interactive
/path/to/qa-agent-blueprint/install.sh --dry-run  # show the plan only
```

### `plugin` — consume as a Claude Code plugin

Copies nothing. Prints instructions for registering this repo's
`.claude-plugin/marketplace.json` via `extraKnownMarketplaces` and enabling the
plugin via `enabledPlugins` in your project's `.claude/settings.json`.

See **Plugin mode** below for how the mechanism works.

---

## Plugin mode

Instead of copying the blueprint into your repo (`integrate`), you can consume
it as a versioned Claude Code plugin: the generic logic lives entirely in the
plugin, and only your project-specific data lives in your repo.

### How the mechanism works

1. The repo ships a marketplace descriptor (`.claude-plugin/marketplace.json`,
   `source: "./"`) and a plugin manifest (`.claude-plugin/plugin.json`). The
   manifest declares the component paths explicitly because this repo keeps
   them under `.claude/` (shared with integrate mode):
   `skills → ./.claude/skills`, `agents → ./.claude/agents`,
   `hooks → ./hooks/hooks.json`, `mcpServers → ./.mcp.json`.
2. In your project's `.claude/settings.json` you register the marketplace and
   enable the plugin:

   ```json
   {
     "extraKnownMarketplaces": {
       "qa-agent-blueprint": {
         "source": { "source": "github", "repo": "Sn4kyGit/qa-agent-blueprint" }
       }
     },
     "enabledPlugins": {
       "qa-agent-blueprint@qa-agent-blueprint-marketplace": true
     }
   }
   ```

   For a local checkout:
   `"source": { "source": "local", "path": "/absolute/path/to/qa-agent-blueprint" }`.
3. On the next start Claude Code asks you to **trust** the marketplace/plugin
   (one-time dialog per project), then copies the plugin into its local
   **plugin cache**. The running hooks/skills/agents come from that cache;
   `${CLAUDE_PLUGIN_ROOT}` points there.
4. Skills and agents appear namespaced (e.g. `/qa-agent-blueprint:test-ticket`,
   subagent `qa-agent-blueprint:test-executor`). The bundled MCP servers
   (playwright, atlassian) start with the plugin.

### What lives where

| Content | Location | Why |
|---|---|---|
| Rules, skills, agents, hook scripts, MCP config, `projects/_template`, `projects/EXAMPLE`, memory seed files | **Plugin** (`${CLAUDE_PLUGIN_ROOT}`) | Generic, versioned, shared across repos. Never write into it — the cache is replaced on update. |
| `projects/<KEY>/` (onboarded projects), `memory/` (your learning system), `evidence/` (test artifacts) | **Your repo** (`${CLAUDE_PROJECT_DIR}`) | Project-specific state; survives plugin updates. Created on demand by the SessionStart hook (seed files copied from the plugin, existing content never overwritten). `projects/_template` is NOT copied — `/onboard-project` reads it from the plugin. |

### The router problem: plugins do not load CLAUDE.md

A `CLAUDE.md` at the plugin root is ignored by Claude Code. The blueprint's
router (ticket-prefix → `projects/<KEY>/`, skill routing, hard rules) is
therefore injected by the plugin's **SessionStart hook**
(`${CLAUDE_PLUGIN_ROOT}/.claude/hooks/session-start.sh`, declared in
`hooks/hooks.json`) — **verbatim**: the hook `cat`s the plugin's own
`CLAUDE.md` into the session context, preceded only by a short path preamble
(what resolves under the plugin vs. your repo). There is exactly one router
text, so it cannot drift between install modes. The hook detects plugin mode
automatically: if your repo has no managed `qa-agent-blueprint` block in
`CLAUDE.md` and no `.claude/rules/qa-blueprint/` namespace, it injects the
router and bootstraps `projects/`, `memory/`, `evidence/` in your repo. In an
integrated repo the same hook keeps its old behavior (preamble only) — one
script serves both modes.

### Updates & rollback

- **Update**: bump `version` in `.claude-plugin/plugin.json` (and
  `metadata.version` in `marketplace.json`), push; consumers update via
  `/plugin` (or it refreshes on the next session, depending on settings). The
  plugin cache then holds the new version; hooks/MCP servers switch path on
  reload/restart. Your `projects/`, `memory/`, `evidence/` are untouched
  because they never live in the plugin.
- **Rollback**: pin/revert to the previous version tag of the marketplace repo
  and run `/plugin` again, or temporarily disable the plugin
  (`enabledPlugins: false`). Because nothing was copied into your repo, there
  is nothing to uninstall — the bootstrap directories are yours and stay.

### Local prerequisites (unchanged)

Node ≥ 18, Playwright Chromium (`npx playwright install chromium`), and
Atlassian OAuth via `/mcp`. `./install.sh --mode plugin` prints the setup
snippet above and copies nothing.

---

## Skill profiles — what can be slimmed, and where

A skill profile decides which blueprint skills land in an installation. The
four names are fixed: **`full`** (every installed skill — the default),
**`standard`** (the ticket core plus harness comfort and `skill-review`
itself), **`minimal`** (the ticket core) and **`custom`** (the user's
confirmed allowlist). Profiles nest (`minimal` ⊂ `standard` ⊂ `full`), and a
dependency resolver always pins required companions back in (e.g.
`test-ticket` keeps `failure-analysis` → `report-to-jira` → `retro-learn`).

Where a profile can apply, and how:

- **`integrate` only.** Integrate copies the skills into your repo, so the
  selection is enforceable there: `install.sh --skill-profile
  full|standard|minimal|custom` (plus `--skills-exclude "a,b"` for a concrete
  selection) chooses which skills land in the target. The choice persists in
  the consumer-owned `.qa-skill-profile.json` (backed up on every change) and
  is re-applied on update/reinstall; without the flags — and without that
  file — every skill is copied, as always. In **plugin** mode there is no
  deactivation at all — the skill set is plugin-owned and replaced on update —
  and the symlinked opencode surface is blueprint-owned the same way. There,
  `/skill-review` stays read-only.
- **The proposal is always a dry-run.** `/skill-review` names the profile and
  the exact exclude list, one line per skill with its reason, and writes
  nothing. Its analysis classifies every skill from the `skills_used` records
  as `used` or `unknown` — never "unused": absent data is unknown, not
  evidence of non-use, and with no records at all everything is unknown and
  coverage is 0%.
- **Apply needs explicit confirmation.** `/skill-review` applies a profile
  only after the user confirms the concrete list — "mach es schlank" is not a
  confirmation — and applies it through the installer's profile-apply step
  (`install.sh --mode integrate --skill-profile <name> --skills-exclude
  "<list>"`), never by renaming or deleting skill files by hand (that would
  desync the persisted profile and be undone by the next update). If the list
  changes, it is shown and confirmed again. Nothing is ever applied
  automatically, and a vague "make it slim" request alone is a request for a
  proposal, not a confirmation.

The wizard and `--yes` install `full`: no prompt, no hidden exclude.

---

## Shared mode — Claude Code and opencode in one QA home

Shared keeps both harnesses start-ready without the Claude plugin. The plugin is
disabled at project scope because it would otherwise duplicate the selectively
linked skills, hooks and MCP servers.

```bash
./install.sh --mode shared --target /path/to/qa-home --dry-run
./install.sh --mode shared --target /path/to/qa-home --yes
```

The shared layout contains:

- a real `.claude/` with selective links for `rules`, `skills`, `agents`, `hooks`
  and `scripts`, plus merged consumer `settings.json` and `.mcp.json`;
- `.opencode/{ROUTER.md,agents,commands,plugins}` and merged `opencode.json`;
- the full blueprint router in `CLAUDE.md` and support links for `docs`,
  `projects/_template`, `projects/EXAMPLE`, `.claude-plugin` and `CHANGELOG.md`;
- consumer-owned `projects/`, `memory/`, `evidence/` and `.agents/` — onboarding
  data and bridges never move into the blueprint checkout;
- the existing secrets/browser files and `.qa-home` marker.

Plugin and opencode installations migrate in place without re-onboarding.
`opencode.jsonc` moves to `opencode.json` with a backup rather than leaving two
active config files. Integrate/custom collisions block before any write; global
settings are only read and reported, never edited. Uninstall removes shared links
and only blueprint-owned hook/permission/instruction/router entries, leaving no
dead references and no consumer data.

After installation, restart and authenticate each harness once. Switching then
means opening the other extension. `/agentswitch <claude|opencode>` verifies the
layout read-only and reports `READY`, `READY_WITH_HUMAN_STEPS` or `BLOCKED`;
it never installs, edits, probes JIRA/stage or re-onboards. Stage runs remain
sequential even though both extensions may be open.

## Detection matrix

| # | Check | If FOUND | If MISSING |
|---|-------|----------|------------|
| 1 | `node` / `npm` ≥ 18 | report version, continue | **abort** with install hint |
| 2 | `claude` CLI | report version | offer `npm i -g @anthropic-ai/claude-code` (interactive) or next-step note |
| 3 | Playwright browsers (`npx playwright --version` + `chromium-*` under `~/.cache/ms-playwright` resp. `~/Library/Caches/ms-playwright`) | **SKIP** browser download, noted in report | `npx playwright install chromium` |
| 4 | `CLAUDE.md` in target | managed router block is **appended**, your content kept; block present → SKIPPED ("already integrated") | blueprint router `CLAUDE.md` is copied |
| 5 | `.claude/` in target | namespaced merge, per-file collision checks (below) | blueprint `.claude/` content is copied (namespaced) |
| 6 | `.mcp.json` in target | JSON merge by server **name**. A local `playwright` gets missing or invalid contract values (`--config`, `--secrets`, `--output-dir` into `evidence/`, `--image-responses omit`) **additively** — command, custom preferences/channel, output path under `evidence/`, secrets source and `qa-secrets` wrapper stay intact (old config in the backup). Remote entries are never replaced by local commands. Preference flags (`--headless`/`--isolated`) are never forced. Other names: existing wins → WARN | blueprint `.mcp.json` is copied |
| 7 | `.claude/settings.json` in target | merge: `permissions.deny/allow` deduplicated union; blueprint hooks appended to `SessionStart`/`Stop`/`PreToolUse`/`PostToolUse`, duplicates detected by command string | created with blueprint permissions + namespaced hooks |
| 8 | `.gitignore` in target | only **missing** entries appended, as a marked managed block; block present → SKIPPED | blueprint `.gitignore` is copied |
| 9 | `evidence/`, `memory/`, `projects/` | left untouched (SKIPPED) | created from the blueprint scaffold |
| 10 | plugin mode | two settings keys written (with your OK), nothing copied; local `playwright`/`atlassian` duplicates in `.mcp.json` are **reported** (WARN) since the plugin provides both | — |

## Collision policy

Blueprint content is **namespaced** so it can never clobber your files:

| Blueprint source | Integrated location | On collision |
|---|---|---|
| `.claude/rules/**` | `.claude/rules/qa-blueprint/**` | differing file → kept yours + WARN |
| `.claude/hooks/*.sh` | `.claude/hooks/qa-blueprint/*.sh` | differing file → kept yours + WARN |
| `.claude/skills/<name>/` | `.claude/skills/<name>/` | name exists with different content → **SKIPPED + WARN** |
| `.claude/agents/<name>.md` | `.claude/agents/<name>.md` | name exists with different content → **SKIPPED + WARN** |
| hooks in `settings.json` | appended, command points at the `qa-blueprint/` namespace | same command string already present → SKIPPED |
| MCP servers in `.mcp.json` | added by name | name taken → kept yours + WARN, **except** local `playwright` contract flags → additive in-place upgrade (backup kept) |

Identical files (e.g. from a previous run) are reported as
"already integrated" and skipped.

## Idempotency

Running the installer twice is safe: the second run reports SKIPPED /
"already integrated" everywhere and changes nothing. Backups
(`<file>.bak-<timestamp>`) are created **only when a file actually changes**.

## Uninstall

```bash
./install.sh --mode integrate --target /path/to/repo --uninstall
```

Removes exactly what the integration added, and nothing else:

- the managed blocks from `CLAUDE.md` and `.gitignore` (your content stays);
- the `.claude/rules/qa-blueprint/` and `.claude/hooks/qa-blueprint/`
  namespaces (files modified after install are kept with a warning);
- copied skills/agents **only if still identical** to the blueprint source
  (colliding skills like your own `test-ticket` are never touched);
- hook entries pointing at `.claude/hooks/qa-blueprint/` from `settings.json`;
- permission entries that the blueprint added (attributed via the install-time
  backup — entries you already had are kept);
- MCP servers from `.mcp.json` **only if they exactly match** the blueprint
  config. Additively upgraded custom entries differ from it and therefore stay;
  your pre-merge config is in the `.bak-*` backup;
- scaffold dirs (`evidence/`, `memory/`, `projects/`), `.claudeignore`, `.env`,
  `.env.playwright-secrets` — only if unmodified.

If the cleaned JSON equals an install-time backup semantically, the backup is
restored **byte-exact**. `.bak-<timestamp>` files are always left in place for
you to review.

## FAQ

**"I already have a CLAUDE.md."**
It is never overwritten. A clearly marked managed block
(`<!-- >>> qa-agent-blueprint (managed, do not edit) -->` … `<!-- <<< qa-agent-blueprint -->`)
is appended with a short router: role, project routing to `projects/<KEY>/`,
and pointers to `.claude/rules/qa-blueprint/` and the skills. `--uninstall`
removes exactly that block.

**"I already have Playwright browsers installed."**
The installer detects the Chromium cache (`~/.cache/ms-playwright` on Linux,
`~/Library/Caches/ms-playwright` on macOS) and skips the download — the report
says SKIPPED.

**"I already run my own playwright MCP server."**
MCP merge is by server **name**. Your local `playwright` entry keeps its command,
channel, preferences, output path under `evidence/`, secrets source and any
`qa-secrets` wrapper. Missing or invalid contract values (`--config`, masking,
`--output-dir` into `evidence/`, `--image-responses omit`) are fixed in place
(old config in the backup), never by substituting the blueprint server. Remote
entries stay untouched. Headless/headful and isolation are preferences — yours
are respected, and the blueprint's own defaults live in the consumer-owned
`.playwright-mcp.config.json`, not in forced CLI flags. Only missing names (e.g.
`atlassian`) are added.

**"Our JIRA is self-hosted (Data Center), not Cloud."**
Supported: replace the `atlassian` entry with the community server
(`sooperset/mcp-atlassian` via `uvx`, `JIRA_URL` in `env`, PAT via the
`JIRA_PERSONAL_TOKEN` environment variable — never in the file). Keep the
server **name** `atlassian`: the audit and evidence hooks match on it. Full
comparison table (auth, API version, content format):
`docs/rules/testing/jira-confluence.md` → "Deployments", and each project
declares its deployment in `PROJECT.md` → "JIRA deployment".

**"I already have my own hooks / settings.json."**
Hooks are additive: your `Stop` hook keeps running, ours is appended to the
same event array. Duplicates are detected by command string, so re-runs never
double-register.

**"Monorepo?"**
Integrate at the repo root (recommended): `--target /path/to/monorepo`. Project
routing (`projects/<KEY>/`) then works across packages via ticket prefixes.
Integrating into a single package dir also works — evidence and memory then
live inside that package. Run `--dry-run` first to inspect the plan.

**"No python3 / no jq?"**
JSON merges (`.mcp.json`, `settings.json`) need python3 (preferred) or jq
(`.mcp.json` only). Without them the installer skips those merges with a WARN
and tells you what to merge manually.

**"How do I see what would happen first?"**
`./install.sh --dry-run` — prints the full plan and the final report, touches
nothing.

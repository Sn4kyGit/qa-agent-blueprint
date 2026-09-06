# Integrating the Blueprint into an Existing Setup

The installer does **not** assume a blank Claude Code setup. It detects an
existing ecosystem — your own `CLAUDE.md`, `.claude/`, `.mcp.json`, already
installed Playwright browsers, your own hooks — and merges the blueprint
non-destructively.

**Choosing a mode: trying it out → plugin (the Quickstart's recommended mode).
One repo, long-term → integrate. Many repos → plugin.**

> **Principle: Detect → Merge → Report.**
> Never overwrite. Always back up. Idempotent. Dry-run capable.

```bash
./install.sh [--mode integrate|plugin] [--target <path>]
             [--dry-run] [--yes] [--uninstall]
```

| Flag | Meaning |
|---|---|
| `--mode` | `integrate` · `plugin`. Default: **auto-detect** (see below). |
| `--target <path>` | Repo to integrate into. Default: current working directory. |
| `--dry-run` | Prints every planned action, changes nothing. |
| `--yes` / `-y` | Non-interactive (accepts the auto-detected proposal). |
| `--uninstall` | Removes the blueprint integration again (integrate mode only). |

---

## The two modes (plus one special case)

### Self-setup — the blueprint repo itself is the target

Running the installer in a fresh clone (or pointing `--target` at it) sets up
the blueprint repo itself: Playwright Chromium, the `.env.playwright-secrets`
template, self-test checklist. Nothing is copied — every copy step would be a
self-copy — so this is a branch of `integrate`, not a mode of its own. The
detection checks still apply — e.g. if Playwright browsers are already in the
cache, the download is skipped.

### `integrate` — merge into your repo (default when an ecosystem is detected)

Auto-detect triggers when the target contains `CLAUDE.md`, `.claude/` or a
`.git/` directory. You are asked to confirm (unless `--yes`).

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
         "source": { "source": "github", "repo": "Sn4kyGit/claude_blueprint" }
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

## Detection matrix

| # | Check | If FOUND | If MISSING |
|---|-------|----------|------------|
| 1 | `node` / `npm` ≥ 18 | report version, continue | **abort** with install hint |
| 2 | `claude` CLI | report version | offer `npm i -g @anthropic-ai/claude-code` (interactive) or next-step note |
| 3 | Playwright browsers (`npx playwright --version` + `chromium-*` under `~/.cache/ms-playwright` resp. `~/Library/Caches/ms-playwright`) | **SKIP** browser download, noted in report | `npx playwright install chromium` |
| 4 | `CLAUDE.md` in target | managed router block is **appended**, your content kept; block present → SKIPPED ("already integrated") | blueprint router `CLAUDE.md` is copied |
| 5 | `.claude/` in target | namespaced merge, per-file collision checks (below) | blueprint `.claude/` content is copied (namespaced) |
| 6 | `.mcp.json` in target | JSON merge: add `playwright`/`atlassian` only if the **name** is free; existing server wins → WARN "kept existing … server config" | blueprint `.mcp.json` is copied |
| 7 | `.claude/settings.json` in target | merge: `permissions.deny/allow` deduplicated union; blueprint hooks appended to `SessionStart`/`Stop`/`PreToolUse`/`PostToolUse`, duplicates detected by command string | created with blueprint permissions + namespaced hooks |
| 8 | `.gitignore` in target | only **missing** entries appended, as a marked managed block; block present → SKIPPED | blueprint `.gitignore` is copied |
| 9 | `evidence/`, `memory/`, `projects/` | left untouched (SKIPPED) | created from the blueprint scaffold |
| 10 | plugin mode | instructions printed, nothing copied | — |

## Collision policy

Blueprint content is **namespaced** so it can never clobber your files:

| Blueprint source | Integrated location | On collision |
|---|---|---|
| `.claude/rules/**` | `.claude/rules/qa-blueprint/**` | differing file → kept yours + WARN |
| `.claude/hooks/*.sh` | `.claude/hooks/qa-blueprint/*.sh` | differing file → kept yours + WARN |
| `.claude/skills/<name>/` | `.claude/skills/<name>/` | name exists with different content → **SKIPPED + WARN** |
| `.claude/agents/<name>.md` | `.claude/agents/<name>.md` | name exists with different content → **SKIPPED + WARN** |
| hooks in `settings.json` | appended, command points at the `qa-blueprint/` namespace | same command string already present → SKIPPED |
| MCP servers in `.mcp.json` | added by name | name taken → kept yours + WARN |

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
  config (your own `playwright` server stays);
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
MCP merge is by server **name**. Your `playwright` entry stays untouched
(WARN "kept existing playwright server config"); only missing names (e.g.
`atlassian`) are added. If you keep your own playwright server, make sure its
args roughly match the blueprint's expectations (`--isolated`, `--output-dir`
into `evidence/`, `--secrets`) — or rename yours and let the blueprint add its
own.

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

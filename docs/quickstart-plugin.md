# Quickstart: plugin on a fresh machine

The no-repo path through the blueprint: you have JIRA tickets and a stage URL to
test — no application code on this machine. The plugin gives you the whole
blueprint; an empty folder becomes your QA home (`projects/`, `memory/`,
`evidence/` live there).

Three ways to wire the plugin. **A** is two CLI commands, **B** gives you a
local checkout you can read, **C** is fully manual. Or skip all of them: open
Claude Code in `~/qa-workspace` and paste *"Set up
https://github.com/Sn4kyGit/claude_blueprint as a plugin in this project —
read its AGENTS.md and follow the runbook."*

## Prerequisites (~10 min)

1. **Node.js LTS (≥ 18)** — nodejs.org or `brew install node`
2. **Claude Code** — the VS Code extension, or `npm install -g @anthropic-ai/claude-code`
3. **GitHub auth** — required while the repository is private, for all variants
   (the marketplace fetch uses git under the hood):
   ```bash
   brew install gh && gh auth login   # browser login with an account that has access
   ```
   Sanity check: `git ls-remote https://github.com/Sn4kyGit/claude_blueprint.git`
   must not ask for credentials.
4. An **empty working folder** — this guide uses `~/qa-workspace`.

## Variant A — marketplace CLI, no clone

```bash
mkdir -p ~/qa-workspace && cd ~/qa-workspace
claude plugin marketplace add Sn4kyGit/claude_blueprint
claude plugin install --scope project qa-agent-blueprint@qa-agent-blueprint-marketplace
```

`--scope project` enables the plugin only in `~/qa-workspace` (writes one key
into `.claude/settings.json` there). Restart Claude Code and accept the trust
dialog.

## Variant B — with clone, installer does the wiring

```bash
git clone https://github.com/Sn4kyGit/claude_blueprint.git ~/qa-blueprint
mkdir -p ~/qa-workspace
~/qa-blueprint/install.sh --mode plugin --target ~/qa-workspace --yes
```

The installer writes the two settings keys for you, with the **local checkout as
source** — the code you enabled is the code you can read, and updates are a
`git pull` away.

## Variant C — manual, no clone

```bash
mkdir -p ~/qa-workspace/.claude
```

Create `~/qa-workspace/.claude/settings.json` with exactly these two keys:

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

Identical result, but pulled from GitHub on every update check instead of a local
checkout you can inspect.

## First session (~10 min)

*(Updating an existing install instead? `claude plugin marketplace update
qa-agent-blueprint-marketplace && claude plugin update --scope project
qa-agent-blueprint`, then restart — see `CHANGELOG.md` for what changed.)*

1. Open `~/qa-workspace` in VS Code, start Claude Code, **accept the trust dialog**.
2. The plugin's SessionStart hook bootstraps `projects/`, `memory/`, `evidence/`
   and a `.env.playwright-secrets` placeholder, and injects the router.
3. **JIRA auth — depends on the deployment:**
   - **Cloud**: `/mcp` → authorize **atlassian** (OAuth, opens the browser).
   - **Data Center (self-hosted)**: no OAuth. Replace the plugin's `atlassian`
     entry in `~/qa-workspace/.mcp.json` (name stays `atlassian`):
     ```json
     "atlassian": {
       "command": "uvx",
       "args": ["mcp-atlassian"],
       "env": { "JIRA_URL": "https://jira.<firma>.tld" }
     }
     ```
     and create a Personal Access Token in JIRA, exported in your shell
     (`export JIRA_PERSONAL_TOKEN=...`, e.g. in `~/.zshrc`) — never into
     `.mcp.json`, the repo, or chat. Requires `uv` (`brew install uv`; pulls
     [`sooperset/mcp-atlassian`](https://github.com/sooperset/mcp-atlassian),
     Jira DC v8.14+).
4. Verify: `claude mcp list` shows `playwright` and `atlassian`.
5. Fill `.env.playwright-secrets` with the test-user passwords (`KEY=value`).
   Values are masked in every tool response; the file is gitignored.

### If Playwright/Atlassian MCP are already configured on this machine

The blueprint uses whatever is configured — but avoid **duplicates** (your own
entry *and* the plugin's = two server processes), and check one security detail:
the blueprint's playwright server runs with `--secrets .env.playwright-secrets`
(passwords masked) and `--isolated` (no state leaking between runs). An older
hand-rolled playwright config almost certainly lacks these flags, which means
**passwords would appear unmasked in the transcript**. The SessionStart hook
scans for exactly this and prints a WARNING — if you see it, either remove your
own entry (the plugin provides both servers) or add the flags.

## Onboarding (~30–60 min)

```
/onboard-project
```

Have ready (the full "who knows what" table is in
[pilot-briefing.md](pilot-briefing.md) — read it once, it saves an hour):

- **JIRA project key** (the ticket prefix, e.g. `SHOP`)
- **Stage URL** and how to tell the deployed version (a `/api/version` endpoint,
  a footer stamp — or "none", a valid answer)
- **Test users**: role + the key name you used in `.env.playwright-secrets`
  (references only — never passwords)
- "Deploy: manual", "Test suite: none yet" (`/scaffold-suite` creates one later),
  "MR process / pipelines: none" — all valid answers for a website-only setup
- Gotchas: caches, feature flags, sandbox limits

Transition names and the priority scheme are fetched from JIRA automatically —
that is why step 3 of the first session comes first.

## First test

```
/test-ticket <KEY-123>
```

Shadow mode is **on by default**: the agent tests fully, produces evidence, and
composes the exact JIRA comment — but posts nothing. The proposal lands in
`evidence/<KEY>/<TICKET>/<ts>/proposed-report.md` for you to review. Grant write
access only after a couple of weeks of reviewed proposals: `Shadow mode: off` in
the project file.

## What is different without an app repo

Documented behavior, not bugs:

- `failure-analysis` has no code diffs to consult → lands on `undetermined`
  more often at first; run history improves it
- `/deploy-to-stage` reports BLOCKED with "manual" — that is the preflight
  working, not failing
- Quality gates come from `/qa-report` numbers instead of CI pipelines

# AGENTS.md — setup runbook for AI agents

You were probably pointed here with a prompt like *"look at this repo and set it
up as a plugin for me."* This file is the machine-readable entry point for that
task. Humans start at `README.md`.

> **Do not follow `CLAUDE.md` while setting up.** It is the *product* — the QA
> router the plugin injects into consumer sessions — not meta-documentation
> about this repo.

## What this is

`qa-agent-blueprint`: a ticket-driven QA Manager + Tester for Claude Code
(JIRA ticket in → tested ticket out, mandatory evidence, learning loop).
Ships 27 skills, 5 subagents, 4 hooks, and 2 MCP servers (`playwright`,
`atlassian`). Installs into any project as a Claude Code plugin — nothing is
copied into the consumer repo; only the user's own data (`projects/`,
`memory/`, `evidence/`) lives there.

## Setup — two commands (verified end-to-end 2026-09-07, claude 2.1.263)

Run from inside the consumer project:

```bash
claude plugin marketplace add Sn4kyGit/qa-agent-blueprint
claude plugin install --scope project qa-agent-blueprint@qa-agent-blueprint-marketplace
```

Then tell the user to **restart Claude Code** and accept the trust dialog.

### opencode instead of Claude Code?

The same blueprint runs under [opencode](https://opencode.ai) (model-agnostic —
the model is the user's `/models` choice, the blueprint pins none). If you are
an agent that was given only the GitHub link, the full run from zero is:

```bash
git clone https://github.com/Sn4kyGit/qa-agent-blueprint.git ~/qa-blueprint
~/qa-blueprint/install.sh --mode opencode --target <consumer-repo> --yes
```

(private repo → clone needs GitHub auth on the machine, see "Missing
prerequisites" below — `gh auth login` is the one human step there.)

The installer symlinks `.opencode/{ROUTER.md,agents,commands,plugins}` plus
compat links (`.claude`, `docs`, `.agents`) into the consumer and merges
`opencode/opencode.template.jsonc` into its `opencode.json` (existing `mcp`
names win; playwright contract flags force-upgrade). Prerequisites it checks:
node ≥ 18, `opencode` CLI (`npm install -g opencode-ai` — you may install it
with the user's OK), python3. Verify afterwards from the consumer:

```bash
opencode run "list your skills"   # should show the 27 blueprint skills
```

Full walkthrough incl. human steps (provider connect via `/connect`, JIRA auth,
browser mode, shadow mode): `docs/quickstart-opencode.md`. A consumer picks
**one** harness — the `.claude` compat symlink and the Claude plugin would
double-register skills.


- `--scope project` enables the plugin only in this project (writes one key
  into `.claude/settings.json`). Drop the flag for user scope (all projects —
  note the PreToolUse guard hook then fires in *every* repo).
- While the repo is **private**, the fetch needs GitHub auth on the machine
  (`gh auth login`, or any git credential with access) — it is git under the
  hood. Check first: `git ls-remote https://github.com/Sn4kyGit/qa-agent-blueprint.git`
  must not prompt.

### Missing prerequisites? Install them yourself.

You are an agent — act like one. Check and, with the user's OK, install:

- **Node.js ≥ 18** (`node --version`) → `brew install node`
- **Claude Code** (`claude --version`) → `npm install -g @anthropic-ai/claude-code`
- **GitHub auth** (private repo) → `brew install gh`, then `gh auth login` is
  the ONE step you cannot do: it opens a browser. Hand it to the human, wait,
  then verify with the `git ls-remote` check above.
- **`uv`** (`uv --version`) → `brew install uv` — only needed when the user's
  JIRA is self-hosted (see below).

### JIRA deployment: ask BEFORE the restart

Ask the user: **is your JIRA Atlassian Cloud or self-hosted (Data Center)?**

- **Cloud** — nothing to do; the plugin's `atlassian` entry fits. Auth happens
  later via `/mcp` OAuth (a human step).
- **Data Center** — the plugin's default `atlassian` entry (Cloud remote
  server) will not reach their JIRA. Replace it in the consumer's
  `.mcp.json` yourself — keep the **name** `atlassian` (the audit and
  evidence hooks match on it):

  ```json
  "atlassian": {
    "command": "uvx",
    "args": ["mcp-atlassian"],
    "env": { "JIRA_URL": "https://jira.<their-company>.tld" }
  }
  ```

  Uses [`sooperset/mcp-atlassian`](https://github.com/sooperset/mcp-atlassian)
  (Jira DC v8.14+). Auth is a **Personal Access Token** the human creates in
  their JIRA profile. Preferred storage (≥ 0.5.0): the macOS login keychain,
  service `JIRA_PAT_<jira-host>` — the session-start hook resolves it into the
  session via `$CLAUDE_ENV_FILE`, so the token lives in **no** file and no
  global shell export:

  ```bash
  security add-generic-password -s JIRA_PAT_jira.<their-company>.tld -a jira -w
  ```

  Fallback (non-macOS, CI): export `JIRA_PERSONAL_TOKEN` in the environment —
  the hook skips keychain resolution whenever the variable is already set.
  Either way the token goes **never** into `.mcp.json`, the repo, or the chat.
  Tell them this explicitly. Note: the plugin's own (Cloud) `atlassian`
  entry stays configured alongside — Claude Code does not override same-named
  plugin servers, it runs both; the dead Cloud entry is harmless, and the
  audit hook's matcher covers both namespaces.

### Browser mode: ask together with the JIRA question

Ask the user: **browser visible (headful) or headless?** Headful lets them
watch the agent work; headless is the safe default (and mandatory for
unattended `claude -p`/CI runs — no display). The answer is *not* an MCP edit:
the plugin's playwright entry hard-references the consumer-owned preference
file `.playwright-mcp.config.json` (seeded on first session start). Write the
answer into it yourself:

- headful → set `"launchOptions": { "headless": false }`
- headless / no answer → keep the seeded default (`"headless": true`)

The server reads the file at launch, so edits apply after a restart. Anything
else Playwright MCP can configure (persistent profile via `"isolated": false`,
viewport, browser channel) lives in the same file — preferences belong there,
never in a second same-named MCP server entry. Contract vs. preference:
`docs/rules/testing/playwright-mcp.md`.

### If the target folder holds its own git repos (e.g. `S/skp/`, `S/wdio/` …)

The consumer folder becomes the QA home (`projects/`, `memory/`, `evidence/`
live there). Nothing in the blueprint requires that folder to be a git repo —
if the user does not want it versioned (or wants no remote), **skip this
section entirely** and leave the folder untracked. If versioning IS wanted,
the product repos inside must stay independent — before the first commit:

```bash
git init
printf '<subrepo1>/\n<subrepo2>/\n' >> .gitignore   # every subfolder that is its own repo
git add . && git commit -m "QA home: blueprint data"
```

Never `git add` a nested repo without the ignore entry — embedded repos become
gitlinks and the QA data turns unrecoverable noise. The products' repos are
referenced read-only from each product's `PRODUCT.md` (`App repo` field) during
`/onboard-product`.

### Verify

```bash
claude plugin details qa-agent-blueprint
```

Expected inventory: `Skills (27)`, `Agents (5)`, `Hooks (4)`
(SessionStart/Stop/PreToolUse/PostToolUse), `MCP servers (2)`.

## Alternative: clone + installer

When the user wants the repo locally (to read or hack on the code they run):

```bash
git clone https://github.com/Sn4kyGit/qa-agent-blueprint.git ~/qa-blueprint
~/qa-blueprint/install.sh --mode plugin --target <consumer-repo> --yes
```

Same result, sourced from the local checkout; updates are a `git pull`.
Full walkthrough incl. a no-clone `settings.json` variant:
`docs/quickstart-plugin.md`.

## Steps that need the human — say so explicitly

1. **JIRA auth** — Cloud: `/mcp` → authorize **atlassian** (OAuth browser flow).
   Data Center: create a Personal Access Token in JIRA and export
   `JIRA_PERSONAL_TOKEN` in the shell. An agent cannot do either.
2. Fill `.env.playwright-secrets` with test-user credentials (created as a
   placeholder on first session start; values are masked in transcripts).
3. **Browser mode** (headful/headless) — answer the question from setup, or
   accept the headless default (see "Browser mode" above).
4. Run `/onboard-project` — needs the JIRA project key, the deployment kind
   (cloud/datacenter), and the stage URL.
5. **Shadow mode is ON by default**: the agent composes JIRA comments but posts
   nothing until the user writes `Shadow mode: off` in the project file or sets
   `QA_AGENT_SHADOW=0`. Mention this before the first `/test-ticket`.

## Do NOT

- Do not copy `.claude/` contents into the consumer repo by hand — that is what
  the plugin mechanism replaces (integrate mode exists, but only on explicit
  user request: `install.sh --mode integrate`).
- Do not add MCP servers beyond the declared two; the register is deliberate.

## Updating an existing install

```bash
claude plugin marketplace update qa-agent-blueprint-marketplace
claude plugin update --scope project qa-agent-blueprint
```

Restart Claude Code afterwards. `CHANGELOG.md` lists what changed; releases
are SemVer git tags (`qa-agent-blueprint--v*`). If an update misbehaves,
`claude plugin uninstall` + reinstall pins you back, and the project's own
data (`projects/`, `memory/`, `evidence/`) is never touched by updates.

## Rollback

```bash
claude plugin uninstall qa-agent-blueprint
claude plugin marketplace remove qa-agent-blueprint-marketplace
```

(Clone path: `install.sh --mode plugin --uninstall --target <consumer-repo>`.)

## If you are developing on this repo

**opencode port**: the dual-harness plan (Claude Code + opencode, model-agnostic,
TDD phasing) lives in `docs/opencode-port-plan.md`. Read it before touching
anything under `opencode/`; its decision log (§7) is authoritative for the
port's open questions.

After any change, run the fixture battery and the manifest validator. After any
change to **rules, skills, or the router**, also run the behavioral evals and
update the norm→test matrix (`evals/COVERAGE.md`) if you touched a norm:

```bash
for t in .claude/hooks/tests/*.sh; do bash "$t"; done   # "within budget" + 6x "all fixtures passed"
claude plugin validate .
bash evals/run.sh                                        # behavioral gate: exit 1 below 0.9
# or billed per-token via OpenRouter instead of subscription quota (key in
# gitignored evals/.env.openrouter; see evals/README.md → "Billing via OpenRouter"):
bash evals/run-openrouter.sh
```

opencode-side equivalents (single entry: `bash opencode/tests/run-all.sh` =
bun unit tests + the bash battery above):

```bash
bash opencode/tests/run-all.sh                           # bun test opencode/tests + fixture battery
QA_EVAL_MODEL=openrouter/<provider-id> bash evals/run-opencode.sh   # opencode behavioral gate
# (models are never defaulted — QA_EVAL_MODEL/QA_JUDGE_MODEL or --model flags; D6)
```

Eval cost discipline: during development run only the cases whose norms you
touched (`evals/COVERAGE.md` maps norm → case); the full gate is a pre-release
step. Eval sessions strip MCP servers by default (`--with-mcp` opts back in) —
see `evals/README.md` → "Cost discipline".

Releasing: bump `version` in BOTH `.claude-plugin/plugin.json` and
`.claude-plugin/marketplace.json` (they must agree — `manifest-conventions.sh`
checks this early), add the `CHANGELOG.md` entry, commit, then **update
smoke-test before tagging**: in a scratch consumer, install the *previous*
release, run `claude plugin marketplace update qa-agent-blueprint-marketplace`
+ `claude plugin update --scope project qa-agent-blueprint`, and verify
`claude plugin details` shows the new version with the full inventory (the
0.2.0 duplicate-hooks bug only ever appeared on update+restart, never in
`validate`). Then `claude plugin tag --push -m "%s"`. The tag command
validates manifest agreement and refuses a dirty tree. Finally create the
GitHub release. The release notes are **reader-friendly prose, not the raw
changelog**: one-sentence headline, then "Warum" (the problem in plain
language), "Was sich ändert" (what the user notices), "Außerdem" (minor
items), upgrade commands. German, spickzettel tone — the audience is the
team, not the maintainer:

```bash
gh release create qa-agent-blueprint--v<X.Y.Z> --title "<X.Y.Z> — <headline>" --notes-file /tmp/relnotes.md
```

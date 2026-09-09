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
Ships 23 skills, 5 subagents, 4 hooks, and 2 MCP servers (`playwright`,
`atlassian`). Installs into any project as a Claude Code plugin — nothing is
copied into the consumer repo; only the user's own data (`projects/`,
`memory/`, `evidence/`) lives there.

## Setup — two commands (verified end-to-end 2026-09-07, claude 2.1.263)

Run from inside the consumer project:

```bash
claude plugin marketplace add Sn4kyGit/claude_blueprint
claude plugin install --scope project qa-agent-blueprint@qa-agent-blueprint-marketplace
```

Then tell the user to **restart Claude Code** and accept the trust dialog.

- `--scope project` enables the plugin only in this project (writes one key
  into `.claude/settings.json`). Drop the flag for user scope (all projects —
  note the PreToolUse guard hook then fires in *every* repo).
- While the repo is **private**, the fetch needs GitHub auth on the machine
  (`gh auth login`, or any git credential with access) — it is git under the
  hood. Check first: `git ls-remote https://github.com/Sn4kyGit/claude_blueprint.git`
  must not prompt.

### Missing prerequisites? Install them yourself.

You are an agent — act like one. Check and, with the user's OK, install:

- **Node.js ≥ 18** (`node --version`) → `brew install node`
- **Claude Code** (`claude --version`) → `npm install -g @anthropic-ai/claude-code`
- **GitHub auth** (private repo) → `brew install gh`, then `gh auth login` is
  the ONE step you cannot do: it opens a browser. Hand it to the human, wait,
  then verify with the `git ls-remote` check above.

### If the target folder holds its own git repos (e.g. `S/skp/`, `S/wdio/` …)

The consumer folder becomes the QA home (`projects/`, `memory/`, `evidence/`
live there) and should itself be a git repo — but the product repos inside it
must stay independent. Before the first commit:

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

Expected inventory: `Skills (23)`, `Agents (5)`, `Hooks (4)`
(SessionStart/Stop/PreToolUse/PostToolUse), `MCP servers (2)`.

## Alternative: clone + installer

When the user wants the repo locally (to read or hack on the code they run):

```bash
git clone https://github.com/Sn4kyGit/claude_blueprint.git ~/qa-blueprint
~/qa-blueprint/install.sh --mode plugin --target <consumer-repo> --yes
```

Same result, sourced from the local checkout; updates are a `git pull`.
Full walkthrough incl. a no-clone `settings.json` variant:
`docs/quickstart-plugin.md`.

## Steps that need the human — say so explicitly

1. `/mcp` → authorize **atlassian** (OAuth browser flow). An agent cannot do this.
2. Fill `.env.playwright-secrets` with test-user credentials (created as a
   placeholder on first session start; values are masked in transcripts).
3. Run `/onboard-project` — needs the JIRA project key and the stage URL.
4. **Shadow mode is ON by default**: the agent composes JIRA comments but posts
   nothing until the user writes `Shadow mode: off` in the project file or sets
   `QA_AGENT_SHADOW=0`. Mention this before the first `/test-ticket`.

## Do NOT

- Do not copy `.claude/` contents into the consumer repo by hand — that is what
  the plugin mechanism replaces (integrate mode exists, but only on explicit
  user request: `install.sh --mode integrate`).
- Do not add MCP servers beyond the declared two; the register is deliberate.

## Rollback

```bash
claude plugin uninstall qa-agent-blueprint
claude plugin marketplace remove qa-agent-blueprint-marketplace
```

(Clone path: `install.sh --mode plugin --uninstall --target <consumer-repo>`.)

## If you are developing on this repo

After any change, run the fixture battery and the manifest validator. After any
change to **rules, skills, or the router**, also run the behavioral evals and
update the norm→test matrix (`evals/COVERAGE.md`) if you touched a norm:

```bash
for t in .claude/hooks/tests/*.sh; do bash "$t"; done   # "within budget" + 4x "all fixtures passed"
claude plugin validate .
bash evals/run.sh                                        # behavioral gate: exit 1 below 0.9
```

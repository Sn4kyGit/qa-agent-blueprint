# Quickstart: opencode on a fresh machine

The opencode path through the blueprint: the same ticket-driven QA Manager +
Tester (28 skills, 5 agents, evidence gate), running under
[opencode](https://opencode.ai) instead of Claude Code — with **your** choice
of model. The blueprint pins none: the model is whatever you pick in
`/models` (docs/opencode-port-plan.md, D6).

Nothing is copied into your project: the installer symlinks the blueprint's
surface (`.opencode/{ROUTER.md,agents,commands,plugins}` + compat links for
`.claude`, `docs`, `.agents`) into your QA home, so updates are a `git pull`
in the blueprint checkout. Only your own data (`projects/`, `memory/`,
`evidence/`) lives in the consumer folder.

## Prerequisites (~10 min)

1. **Node.js LTS (≥ 18)** — nodejs.org or `brew install node`
2. **opencode** — `npm install -g opencode-ai` (https://opencode.ai)
3. **Git** — required while the repository is private (clone access):
   `git ls-remote https://github.com/Sn4kyGit/qa-agent-blueprint.git` must not
   ask for credentials (`brew install gh && gh auth login` covers this).
4. An **empty working folder** — this guide uses `~/qa-workspace`.

## The easiest way: tell your agent

You can skip the manual steps below: open opencode in `~/qa-workspace` and
paste:

> Set up https://github.com/Sn4kyGit/qa-agent-blueprint for opencode in this
> project. Read its **AGENTS.md** first and follow the opencode runbook there —
> then tell me which steps need me (provider connect, JIRA auth, onboarding).

The agent clones the repo, runs the installer, and hands back exactly the
steps only a human can do (provider connect, JIRA OAuth/PAT, browser mode).

## Install (manual)

```bash
git clone https://github.com/Sn4kyGit/qa-agent-blueprint.git ~/qa-blueprint
mkdir -p ~/qa-workspace
~/qa-blueprint/install.sh --mode opencode --target ~/qa-workspace --yes
```

The installer checks prerequisites, links the blueprint surface, seeds
`.env.playwright-secrets` (comment-only placeholder) and
`.playwright-mcp.config.json` (headless defaults), and merges
`opencode/opencode.template.jsonc` into your `opencode.json`:

- existing **mcp server names win** — a Data Center `atlassian` entry you
  added survives re-installs; only the **playwright contract flags**
  (`--config`/`--secrets`/`--output-dir`) are force-upgraded, because hooks
  and agents hard-reference them
- `instructions` (router + core rules), `subagent_depth: 2` and the
  `permission` denies are added; your existing keys are never removed
- an existing `opencode.json` is backed up before the merge

Uninstall: `install.sh --mode opencode --target ~/qa-workspace --uninstall`
removes only the symlinks that point into the blueprint; your data and your
`opencode.json` stay.

## Wrong folder? Move the QA home

Commands in opencode are per-folder: they exist only where the blueprint is
installed. If the installer went into the wrong folder (e.g. `~/qa-workspace`
when you actually wanted the commands inside `~/KPS-Development`), do not
re-onboard — move the whole QA home, data included:

```bash
~/qa-blueprint/install.sh --mode opencode --target ~/qa-workspace \
  --move ~/KPS-Development --yes
```

The move carries `projects/`, `memory/`, `evidence/`, the seed files and your
merged `opencode.json` over, links the blueprint surface there, and unlinks
the old folder. It never overwrites anything that already exists in the new
folder — a name present in both places is reported SKIPPED and left for you
to merge by hand.

## Several workspaces

You can install into as many folders as you like — every folder gets the same
commands through the symlinks. Just know what you are choosing: **each folder
is its own QA home** with its own `projects/`, `memory/` and `evidence/`.
Learnings captured in one workspace do not appear in the other. For most
setups one QA home (the project workspace you test most, or a dedicated
folder) is the simpler life.

## Steps that need you

1. **Provider + model** — connect a provider (`/connect`, e.g. OpenRouter or
   a coding plan) and pick the model in `/models`. Cheap-and-capable dev
   option verified during the port: `openrouter/z-ai/glm-5.3-flash`; the
   production gate is meant to run on a production-class model.
2. **JIRA auth** — Cloud: `opencode mcp auth atlassian` (OAuth browser flow).
   Data Center: replace the `atlassian` entry in your `opencode.json` with the
   local `mcp-atlassian` server (keep the **name** `atlassian` — hooks match
   on it) and store the PAT in the macOS keychain, service
   `JIRA_PAT_<jira-host>`; the blueprint's plugin resolves it into the session
   at runtime, so the token lives in no file and no chat. Details: AGENTS.md.
3. **Browser mode** — edit `.playwright-mcp.config.json`:
   `"launchOptions": { "headless": false }` for a visible browser. Applies
   after a restart (the server reads the file at launch).
4. Fill `.env.playwright-secrets` with your test users (values are masked in
   transcripts).
5. Run `/onboard-project` — needs the JIRA project key, deployment kind
   (cloud/datacenter), and the stage URL.
6. **Shadow mode is ON by default**: JIRA comments are composed into the
   evidence dir (`proposed-report.md`), never posted, until you write
   `Shadow mode: off` in the project file or set `QA_AGENT_SHADOW=0`.

Same caveats apply as under the plugin regarding tickets with no linked app
repo (failure-analysis runs degraded, deploy-to-stage is BLOCKED by design) —
see [quickstart-plugin.md § What is different without an app repo](quickstart-plugin.md#what-is-different-without-an-app-repo).

## Verify

In `~/qa-workspace`:

```bash
opencode run "list your available skills"
```

should show the 28 blueprint skills, and `/test-ticket` `/retest-bug`
`/qa-report` etc. should appear as commands. The evidence gate is active from
the first session: a JIRA write without fresh evidence is blocked with
`QA_EVIDENCE_MISSING:`.

## Updating

```bash
cd ~/qa-blueprint && git pull
```

Everything under the symlinks is live immediately; restart opencode. If the
template gained keys since your install, re-run
`install.sh --mode opencode --target ~/qa-workspace --yes` — the merge is
idempotent and never removes your entries. `CHANGELOG.md` lists what changed;
`/whats-new` in a session shows the delta since a project was onboarded.

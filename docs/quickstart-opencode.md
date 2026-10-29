# Quickstart: opencode on a fresh machine

The opencode path through the blueprint: the same ticket-driven QA Manager +
Tester (31 skills, 9 agents, evidence gate), running under
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
`.playwright-mcp.config.json` (headless defaults plus `console.level: warning`), and merges
`opencode/opencode.template.jsonc` into your `opencode.json`:

- existing **mcp server names win** — a Data Center `atlassian` entry you
  added survives re-installs; missing or invalid **local playwright contract
  flags** (`--config`/`--secrets`/`--output-dir`/`--image-responses omit`) are
  fixed additively. Custom commands, channels, output paths under `evidence/`,
  secrets sources and `qa-secrets` wrappers survive; remote entries stay untouched
- `instructions` (router + core rules), `subagent_depth: 2` and the
  `permission` denies are added; your existing keys are never removed. Evidence
  read denies cover only raw artifacts, not summaries, reports or JSON/Markdown
- an existing `opencode.json` is backed up before the merge

Uninstall: `install.sh --mode opencode --target ~/qa-workspace --uninstall`
removes only the symlinks that point into the blueprint; your data and your
`opencode.json` stay.

## Alternating Claude Code and opencode? Use shared instead

```bash
~/qa-blueprint/install.sh --mode shared --target ~/qa-workspace --dry-run
~/qa-blueprint/install.sh --mode shared --target ~/qa-workspace --yes
```

Shared keeps both harnesses start-ready without the Claude plugin, adds Claude's
`.mcp.json` and full router, and leaves existing onboarding data untouched. After
one restart and one Atlassian authentication per harness, switching means opening
the other extension. `/agentswitch <claude|opencode>` checks this read-only;
there is no re-onboarding and no parallel stage testing.

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

## One customer, several repos? One home at the workspace root

The recommended layout when a customer spans several repositories:

```
KPS-Development/            ← the QA home (projects/, memory/, evidence/, .qa-home)
├── shop-frontend/          ← a product repo
├── shop-api/               ← another product repo
└── test-automation/        ← the test suite repo
```

Sessions started **inside a subfolder** resolve the home automatically
(walk-up to the `.qa-home` marker or the `projects/+memory/+evidence/` trio)
— evidence, learnings and project files always land at the root, never
duplicated into the repo folder. Two harness-scoped exceptions stay with the
session's cwd on purpose: the MCP config (`opencode.json`) and the two seed
files (`.env.playwright-secrets`, `.playwright-mcp.config.json`) — the harness
reads them from where it was started. Easiest life: start opencode at the
workspace root.

## Steps that need you

1. **Provider + model** — connect a provider (`/connect`, e.g. OpenRouter or
   a coding plan) and pick the model in `/models`. Cheap-and-capable dev
   option verified during the port: `openrouter/z-ai/glm-5.3-flash`; the
   production gate is meant to run on a production-class model.
2. **Optional model lanes** — without configuration, every execution lane inherits
   your selected model. Run `/model-setup` to map cheap/standard/deep execution
   roles to three available provider/model IDs and optional supported variants.
   Fast/low risk uses cheap, complex low/medium standard, high/escalated deep;
   each branch is chosen independently. Only consumer `agent` overrides in
   `opencode.json` are written; restart afterwards. Claude Code needs no such
   file: cheap/standard/deep maps to haiku/sonnet/opus.
3. **JIRA auth** — Cloud: `opencode mcp auth atlassian` (OAuth browser flow).
   Data Center: replace the `atlassian` entry in your `opencode.json` with the
   local `mcp-atlassian` server (keep the **name** `atlassian` — hooks match
   on it) and store the PAT in the macOS keychain, service
   `JIRA_PAT_<jira-host>`; the blueprint's plugin resolves it into the session
   at runtime, so the token lives in no file and no chat. Details: AGENTS.md.
4. **Browser mode** — edit `.playwright-mcp.config.json`:
   `"launchOptions": { "headless": false }` for a visible browser. Applies
   after a restart (the server reads the file at launch).
5. Fill `.env.playwright-secrets` with your test users (values are masked in
   transcripts).
6. Run `/onboard-project` — needs the JIRA project key, deployment kind
   (cloud/datacenter), and the stage URL.
7. **Shadow mode is ON by default**: JIRA comments are composed into the
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

should show the 31 blueprint skills, and `/test-ticket` `/retest-bug`
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

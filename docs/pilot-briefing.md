# Pilot briefing — running the first real project through the blueprint

Everything here has been tested against fixtures and fictional data. Nothing has
been tested against a real JIRA project, because the blueprint refuses to invent one
— which makes the first onboarding the actual test. This page is what to have ready,
what to expect, and what is known to be unfinished.

Read it once before `/onboard-project`. It should take ten minutes and save an hour.

## Before you start: what onboarding will ask for

`/onboard-project` fills `projects/<KEY>/PROJECT.md` field by field and **refuses to
guess**. Every blank you cannot fill becomes a `TODO:` that surfaces mid-ticket
later, so it is worth collecting these first. Some need someone outside QA.

| Field | Who usually knows it |
|---|---|
| Stage URL, and how to read the deployed version (`/api/version`, a footer stamp, a header) | Platform / DevOps |
| Who deploys to stage, and **the exact trigger command** (`gh workflow run …`, `glab ci run …`, a curl, or "manual — ask X") | DevOps. "Trigger the pipeline" is not a command |
| Test users: role, purpose, vault path, and the secret key name | QA + whoever owns the vault |
| Quality gates, if they differ from pass rate ≥ 80 %, P0 = 0, P1 ≤ 5, coverage ≥ 80 % | QA lead |
| Test-suite location and its TC categories, or "none yet" | QA. "None yet" is a fine answer — `/scaffold-suite` creates one |
| Test data: how it is seeded, and how it is reset between runs | QA / backend |
| Gotchas: caches, feature flags, sandbox limits, shared-stage etiquette | The team's collective memory. This field pays for itself fastest |

Two things the agent fetches from JIRA rather than asking, so you do not need them
in advance: **workflow transition names** and the **priority scheme**. If the
Atlassian MCP is not authorized yet, it will ask instead — authorize it first
(`/mcp`) and you get the real lists.

## Run it in shadow mode

Put this in the project file's Reporting section, or set `QA_AGENT_SHADOW=1`:

```
- **Shadow mode**: on
```

The agent then tests fully, produces evidence, and composes the exact JIRA comment
and transition — but **posts nothing**. Proposals land in
`evidence/<KEY>/<TICKET>/<ts>/proposed-report.md` for you to read.

Do this for the first two weeks. Not because the agent is expected to be wrong, but
because the failure that kills adoption is a wrong `Reopen` on a real ticket in week
one. Two weeks of proposals is the evidence you need to grant write access — and
everything else keeps running meanwhile: routing learns, learnings get captured and
promoted.

Check it is actually holding: `evidence/.audit/jira-writes.log` must stay empty
during a shadow run. An entry there is a bug — report it.

## What will probably go wrong first

In rough order of likelihood, from the cold-start audit:

1. **MCP servers.** `claude mcp list` must show `playwright` and `atlassian`, and
   `/mcp` must show atlassian as authorized. A missing `.env.playwright-secrets`
   kills the Playwright server at startup with nothing but a connection error;
   `./install.sh` creates the placeholder.
2. **Permission prompts.** The allowlist in `.claude/settings.json` is deliberately
   narrow. You will be asked to approve Bash calls; approve deliberately rather than
   broadly, and tell us which ones recur — that is data for the allowlist.
3. **`/deploy-to-stage` reporting BLOCKED.** Expected when the project file has no
   trigger command or the CLI is missing. That is the preflight doing its job, not a
   failure — fill in the field.
4. **A `TODO:` you left in the project file.** It surfaces at the moment the agent
   needs it, which is usually mid-ticket.

## What we want back from you

The blueprint's whole premise is that a surprise gets written down once. So:

- **Anything you had to explain to the agent** — it belongs in
  `memory/learnings/_inbox.md`. The agent should capture it itself (a Stop hook
  blocks a run that declares no learnings), but if you had to say something twice,
  that is the bug we care most about.
- **Every time it asked which product a ticket belongs to.** Each one is a missing
  component or label row in the project's routing registry; `/qa-report` counts them
  under "routing needed a human".
- **Anything that looked confidently wrong.** A plausible answer with no source is
  the failure mode this design fears most, and it is exactly what fixtures cannot
  catch.

After a week, run `/qa-report --since 7` and send the output. It is the fastest way
for us to see what actually happened without reading your tickets.

## Known unfinished, so you do not report them as bugs

- **`evals/`** — six semantic test cases exist and have never been run: the
  `claude plugin eval` runner is in early access and refused to start here. They are
  runnable by hand (see `evals/README.md`).
- **No mobile, cross-browser or non-web testing.** Chromium, headless, web only.
- **No test-data lifecycle, no stage leases.** Parallel testing on a shared stage
  will produce confusing failures; coordinate manually for now.
- **Evidence grows forever.** No retention job exists yet.
- **Epics and releases** are not modelled — the unit of work is one ticket.

Full list with reasoning: `docs/architecture.md` and the "Deliberate non-goals"
section of the README.

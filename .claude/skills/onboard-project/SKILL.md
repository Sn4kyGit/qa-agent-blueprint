---
name: onboard-project
description: Onboard a new project into projects/<KEY>/ — interactively fills PROJECT.md from the template, seeds learnings.md and the bug-report template, and adds it to memory/INDEX.md. Use for "/onboard-project" or whenever a ticket's project prefix has no existing projects/<KEY>/PROJECT.md.
---

# /onboard-project — teach the agent a new project

Expect this to take real back-and-forth with the user (~30–60 min for a first
project) — every field matters for later autonomous testing, and guessing here is
exactly what `CLAUDE.md` forbids ("never guess a project's process").

## Steps

1. Ask for the JIRA project key (must match the directory name you'll create).
2. Copy `projects/_template/` to `projects/<KEY>/` (including `templates/`, but
   **not** `products/` — that scaffold stays put until `/onboard-product` needs it).
   **In plugin mode the scaffold is not in this repo**: the SessionStart bootstrap
   creates `projects/` empty on purpose, so copy from
   `$CLAUDE_PLUGIN_ROOT/projects/_template/` and write only into the consumer's
   repo. Same for the two reads below — the reference project lives at
   `$CLAUDE_PLUGIN_ROOT/projects/EXAMPLE/`. Without this branch step 2 copies from a
   path that does not exist and onboarding stops at its first write.
   Read `projects/EXAMPLE/PROJECT.md` alongside the template as a filled reference
   — it's fictional but shows what a complete answer looks like per field. Ignore
   its `products/` tree and its `## Products` section unless the user says this
   project covers several products.
3. Walk through every `PROJECT.md` section with the user, section by section, not
   as one giant question dump:
   - Basics — and **ask for the JIRA deployment early**: `cloud` or `datacenter`.
     It decides the MCP backend and auth (Cloud: official remote server + OAuth;
     Data Center: community server `sooperset/mcp-atlassian` + PAT via
     environment variables, server still named `atlassian`) and the report
     content format — all detailed in `docs/rules/testing/jira-confluence.md` →
     "Deployments". If Data Center and the consumer's `.mcp.json` still carries
     the Cloud default, offer to swap the entry (name unchanged, no secrets in
     the file).
   - Confluence links, environments (stage URL, version-check method,
     who deploys).
   - Test users — **vault paths only**, never actual passwords in this
     conversation. Confirm the matching `.env.playwright-secrets` keys separately,
     out of chat if the vault has no CLI (tell the user to fill it directly in the
     file, which is gitignored). If the setup has a credential MCP server, it may
     resolve references — it still never surfaces a value, and browser logins keep
     going through `--secrets` masking (`.claude/rules/core/security.md` →
     "Credential sources").
   - Deploy runbook — use `docs/runbooks/stage-deploy-general.md` as the scaffold
     if the user doesn't have one written down yet.
   - Pipelines/gate overrides, MR process, test assets location, gotchas.
   - **Reporting — fetch, do not ask.** Transition names and the priority scheme are
     facts that live in JIRA, and `docs/rules/testing/jira-confluence.md` is explicit
     that a guessed transition fails loudly in some workflows and silently no-ops in
     others. So: pull the issue type's workflow transitions and the project's
     priority names via the Atlassian MCP and let the user pick from the real list,
     the same way `onboard-product` fetches the real component list. Only fall back
     to asking if the MCP is unavailable — and then mark the fields `TODO:` rather
     than writing down what the user thinks the transition is probably called.
   - **Deploy trigger.** "Trigger the pipeline" is not a command. Ask for the exact
     one (`gh workflow run …`, `glab ci run …`, a curl, or "manual — ask X") and
     record it; `/deploy-to-stage` preflights it and reports BLOCKED when it is
     missing.
4. Leave any field the user can't answer yet as `TODO:` — never fill a guess.
   Flag TODOs clearly at the end so they get resolved before the first real test.
5. Seed `projects/<KEY>/learnings.md` from the template (empty, ready for
   `retro-learn` to populate). Then **replace the placeholder**
   `projects/<KEY>/templates/bug-report.md` with the base template matching the
   report format chosen above — `.claude/skills/bug-report/templates/jira-cloud.md`
   or `plain-text.md`, in plugin mode under `$CLAUDE_PLUGIN_ROOT/` — and adjust
   section names, order and extra fields to the
   project's conventions. This is not optional polish: `bug-reporter` reads that
   file as the template, so a project that keeps the placeholder stalls on its
   first FAIL. `projects/EXAMPLE/templates/bug-report.md` shows a finished one.
6. Add one line for the new project to `memory/INDEX.md` under "Projects" —
   this is what keeps lookups fast later.
7. **Bridge file for vendored skills — one per project, never shared**: write
   `.agents/qa-project-context/<KEY>.md` (note: a *directory* keyed by project,
   not the single flat `.agents/qa-project-context.md` the vendored skills'
   own text describes) as a projection of the `PROJECT.md` you just filled —
   product one-liner, tech/test stack, environments, CI/CD, quality goals (gate
   overrides), risk areas (from "Gotchas"), team/conventions if known. This lets
   the vendored skills under `.claude/skills/` (`risk-based-testing`,
   `api-testing`, `accessibility-testing`, `security-testing`, `visual-testing`,
   `test-reliability`, `qa-metrics`, `test-case-management`, `release-readiness`,
   `bug-reproduction` — see `.claude/skills/THIRD_PARTY_NOTICES.md`) work without
   re-asking discovery questions already answered in `PROJECT.md`.
   A filled-in model of this file (for the fictional `SHOP` project, kept next to
   the example project rather than under `.agents/` for the same collision reason)
   is `projects/EXAMPLE/qa-project-context.md` — read it before writing your first.

   **Why per-project, not one shared file**: this repo can hold many onboarded
   projects (`projects/SHOP/`, `projects/ACME/`, ...). A single shared bridge
   file would silently go stale or get overwritten the moment a second project
   is onboarded or tested — whoever invokes a vendored skill next would read
   the *previous* project's context without any error. Keying by `<KEY>` makes
   staleness structurally impossible instead of relying on remembering to
   refresh a shared file. See `CLAUDE.md` → project routing for the rule that
   every vendored-skill invocation must point at the current ticket's file.

   `PROJECT.md` stays the source of truth for this blueprint's own skills/hooks;
   `.agents/qa-project-context/<KEY>.md` is a read-only-by-convention projection
   — regenerate it if `PROJECT.md` changes materially rather than editing both
   by hand. Give it the frontmatter `generated_from:` (source paths) and
   `source_sha:` so staleness is checkable instead of remembered. Once the project
   has products, this file serves `project-wide` tickets and each product gets its
   own merged projection at `.agents/qa-project-context/<KEY>/<PRODUCT>.md`,
   written by `onboard-product`.
8. Confirm with the user: read the completed `PROJECT.md` back as a summary and
   ask them to correct anything before considering onboarding done.
9. **Mention products exactly once**, in the closing next-steps — not as a question
   during the interview, which would cost every user time to serve a minority:
   "Does this JIRA project cover several products with different test methods,
   features, or test users? Then run `/onboard-product` — this file stays the shared
   base and each product only records what differs." Never create `products/`
   yourself; `onboard-product` does that after an explicit confirmation.

## What this skill never does

Invent environment URLs, test users, or pipeline names. Store an actual password
or API token in `PROJECT.md` (references only — see
`.claude/rules/core/security.md`). Treat `projects/_template/` or
`projects/EXAMPLE/` as real projects to test against.

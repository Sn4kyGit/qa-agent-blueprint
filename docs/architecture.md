# Architecture — the five layers

Compact English statement of the blueprint concept. Goal: Claude Code becomes a
learning QA Manager + Tester — ticket in, tested ticket out, with evidence and a
report, without burning the token budget.

## The layers

```
Layer 1 – Global core (always loaded, ~6.7k tokens measured 2026-09-06)
  CLAUDE.md (router) + .claude/rules/core/*.md — the NORMS only
  QA principles, token discipline, product routing, evidence, security
  ↳ docs/rules/ holds the DETAIL behind each of them, read on demand

Layer 2 – Skills & subagents (loaded on demand)
  .claude/skills/*   .claude/agents/*
  Test types, bug reporting, deploy, retro, onboarding

Layer 3 – Project context (loaded per project only)
  projects/<KEY>/PROJECT.md + learnings.md + flow-map.md + templates/
  Test users, environments, pipelines, report format, gotchas, flow map
  ↳ optional sub-layer: products/<PRODUCT>/PRODUCT.md + learnings.md + flow-map.md
    for projects covering several products — inherits the project file,
    states only differences (.claude/rules/core/product-layer.md)

Layer 4 – Learning system (grows, gets consolidated)
  memory/learnings/* → promoted into Layers 1–3

Layer 5 – Evidence (never in context, only referenced)
  evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/ — gitignored
```

Tooling underneath: Playwright MCP + Playwright CLI, Atlassian MCP, hooks.

## Execution modes — who sits at the wheel

`docs/pipeline/` holds the phase knowledge (intake → recon → planning →
execution → verification → reporting, file contracts in the run dir). The
project file's "Execution mode" picks the driver:

- `mcp-only` — the model drives the browser live; deepest findings, highest cost
- `hybrid` (default) — probe recon (real selectors), spec via CLI, red check +
  short live verification pass; near-MCP quality at medium cost
- `cli-first` — suite only, MCP on unclear failure; CI-cheap

Escalation rules (visual ticket, high risk, missing recon, unclear failure,
non-assertable AC) raise any mode to live observation. The mode travels into
every JIRA report — a verdict must say whether it was observed or asserted.

## The QA home — one per customer workspace

All data layers (3–5) live in ONE folder per customer: the **QA home**, holding
`projects/`, `memory/`, `evidence/`. A customer with several repos keeps them
as subfolders of that home (e.g. `KPS-Development/<repo>/`). Sessions may
start in any subfolder: hooks and the opencode plugin resolve the home by
**walking up** from the session's cwd to the nearest directory carrying the
`.qa-home` marker (written at bootstrap) or the legacy trio (all three data
dirs), stopping at `$HOME` — so data never gets duplicated into a subfolder
(the 0.9.1 "dual scaffold" bug did exactly that). Harness-scoped files are the
exception: `opencode.json` / `.mcp.json`, `.env.playwright-secrets` and
`.playwright-mcp.config.json` are read by the harness from where it was
started and therefore stay with the session's cwd.

## Why this layering is token-efficient

Claude Code provides four progressive-disclosure mechanisms, and the blueprint uses
all four deliberately:

1. **Everything under `.claude/rules/` loads at start, whether or not it is needed**
   — which is why Layer 1 holds only the norms, and every detail that is bound to a
   topic lives in `docs/rules/`, which is not auto-loaded. Measure before claiming a
   number: this was documented as "< 2k tokens" while actually costing 11.3k, because
   nine full rule files were being loaded into every session.
2. **Skills expose only name + description (~100 tokens) until invoked** — the full
   SKILL.md loads on demand. Ten skills cost ~1k tokens idle instead of ~20k.
3. **Project files are plain files, read selectively** — only the active project's
   PROJECT.md plus keyword-matched learning entries enter the context; other projects
   cost nothing. Flow maps load only for phases that use them, and only confirmed
   Areas are binding. The product sub-layer keeps that property: a routed product
   adds one short file that states only its differences, sibling products cost
   nothing, and a project without products reads exactly what it read before.
4. **Subagents own separate context windows** — the 30-step browser snapshot stream
   of an exploration stays inside `test-executor`; only a ≤ 40-line verdict returns.

The structural alternative — a monolithic CLAUDE.md with all knowledge — burns
thousands of tokens per session before any work happens and rots faster than it can
be maintained.

## Rules ≠ enforcement

CLAUDE.md and rules are *advisory*. Hard guarantees are enforced mechanically:

- Evidence obligation → Stop hook (`stop-evidence-check.sh`)
- Secret protection → permission denylist + PreToolUse guard (`pre-tool-guard.sh`)
- JIRA write audit → PostToolUse hook (`post-jira-audit.sh`)
- Session orientation → SessionStart hook (`session-start.sh`)

## The learning loop (Layer 4)

Capture → Groom → Promote, run by the `retro-learn` skill:

- **Capture** (every session): check for an existing sighting first; only genuinely
  new findings enter `memory/learnings/_inbox.md` with a candidate target.
- **Groom** (weekly, on demand, or when AUTO-GROOM fires): one oldest-first batch,
  dedupe via Grep, bump `seen:` counters, retire stale entries into `_rejected.md`.
- **Promote** (gate: ≥ 2 sessions): merge one durable rule into rules, skills or
  project context; rare knowledge stays in searchable Learnings. Blueprint-side
  rules/skills/templates/hooks/docs are validation-gated through `evals/COVERAGE.md`.
  Promoted routing rows are re-measured once against later evidence
  (`product_routed_by`). Flow knowledge
  (which flows exist, their selectors, their neighbors) promotes into
  `flow-map.md` — curated, with sourced anchors and Neighbor bases; `retest-bug`
  scopes only from confirmed Areas.

Failures of the agent itself get a compact 5-Whys RCA before capture, so learnings
target system gaps, not symptoms. See `docs/memory-layers.md` for how repo learnings
relate to Claude Code auto memory, and why no external memory server is wired in.

## End-to-end ticket flow

```
User: "Test SHOP-1234"
  → main orchestrator: preflight once, then ticket intake (Atlassian MCP;
    playwright-driven UI allowed for JIRA access `browser`)
  → routing once: SHOP → projects/SHOP/PROJECT.md + targeted learning matches
       ↳ has products? component "Admin" → products/ADMIN/PRODUCT.md + targeted matches
         (no Products section → skip; ambiguous → ask, headless BLOCKED)
  → readiness.json: allowed status + no blockers + required linked MR/PR merged
    + expected build deployed when required, API/CLI preferred
       ↳ missing merge → BLOCKED; missing required build → BLOCKED or deploy handoff
       ↳ explicitly unavailable build verification → report as unverified
       ↳ only now: stage-liveness navigation, recon and execution may start
  → strategy: PROJECT.md "Execution mode" (mcp-only | hybrid | cli-first)
    + re-test (bug) or full test (story); escalation rules may force live observation
  → context-capsule.json sealed once: exact intake/readiness + effective config
    + selected knowledge + source hashes; every later agent gets its path
  → Fast Path: testable + low risk + no escalation + exactly one execution branch
       → main orchestrator → test-executor OR test-automator (no qa-manager)
    Complex path:
       → qa-manager consumes the capsule, never remerges project context
       → test-executor (exploratory, MCP) and/or test-automator (specs, CLI)
  → evidence: evidence/SHOP/SHOP-1234/<ts>/ (+ Stop hook enforcement)
  → PASS → report-to-jira: comment + final screenshot + transition "Verify"
  → FAIL → owning orchestrator (main or qa-manager) → failure-analyst
       (never test-executor/test-automator → failure-analyst)
       ↳ product-defect / undetermined → bug-reporter: project template, "Reopen"
       ↳ test-outdated / test-brittle  → NEEDS_REVIEW: propose, no bug, no transition
       ↳ environment → BLOCKED  ·  flake → test-reliability, no product bug
  → shadow mode and reporting unchanged; unexpected findings → retro-learn/_inbox.md
```

## Design principles

| # | Principle | Architectural consequence |
|---|---|---|
| P1 | Never explain twice | All knowledge versioned in the repo, not in chat history |
| P2 | Token budget is a resource | Progressive disclosure everywhere (4 mechanisms above) |
| P3 | Learning is a process | Formal capture→groom→promote loop with gates |
| P4 | Project switching is the norm | Project context encapsulated under `projects/<KEY>/`, products under `products/<PRODUCT>/` within it |
| P5 | Rules ≠ enforcement | Hooks + permissions for evidence and secrets |
| P6 | Secrets never in context | Vault/env references; MCP `--secrets` masking; storage state |
| P7 | Evidence is mandatory | Fixed location, naming convention, Stop-hook enforcement |
| P8 | One QA home, two harnesses | Shared mode links both surfaces without plugin duplication; run files outlive harness switches |

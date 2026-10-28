# Token Discipline

Why the blueprint stays cheap to run, and the rules that keep it that way.

## Lookup policy — read this, not everything

1. `memory/INDEX.md` first — it points at exactly the file you need.
2. Read the active `projects/<KEY>/PROJECT.md`. Grep its `learnings.md` for
   area/component/flow/failure keywords; read matches only.
3. On a product route, add `products/<PRODUCT>/PRODUCT.md` and targeted learning
   matches. Load `flow-map.md` only for recon/planning/retest/charters; only
   confirmed Areas bind. `project-wide` loads no product; no `## Products` means
   no product glob. Sealed-field questions use `PROJECT.md` alone (ownership:
   `.claude/rules/core/product-layer.md`).
4. Everything else (other projects, other learning files, docs/) is loaded **only
   when a specific reason exists** — a skill instructs it, or the index points there.

**Never** run a full-repo scan, `find` over the whole tree, or open every file in
`projects/` "just in case". If the project file doesn't answer a question, that is a
signal to run `onboard-project` or ask the user — not to start exploring.

## Grep over reading

Prefer targeted `grep`/`rg` for a known string (a selector, an error message, a
learning keyword) over opening a file to skim it. Read a file fully only once you
know it's the right one.

## Subagent policy

Delegate to a subagent when the work would otherwise dump a large, disposable
transcript into the main context:

- `test-executor` — every Playwright MCP exploratory session (browser snapshots,
  console logs, network dumps stay inside the subagent; only a verdict returns).
- `test-automator` — spec authoring/execution via the CLI runner.
- `failure-analyst` — failure triage on a FAIL (run history, JIRA change window,
  log greps) before a bug is filed; only a class plus its basis comes back.
- `bug-reporter` — bug report composition against the project's template.
- `qa-manager` — overall ticket orchestration when the flow spans multiple of the
  above.

Do not spawn a subagent for a single quick read or a one-line answer — that costs
more than it saves.

## Context hygiene

- Never Read raw evidence (`.mcp-out`, images, traces, videos, binary captures)
  back into context; reference its path. Structured summaries and curated
  JSON/Markdown stay readable.
- Close out exploratory sessions with a short verdict, not a full transcript replay,
  when reporting back to the user or to JIRA.
- Long `memory/learnings/*.md` files are meant to be grepped, not read end-to-end,
  once they exceed a screenful — that's the trigger for `/retro-learn` to consolidate.

## Never idle-wait

`sleep`-polling a deploy, pipeline, or long suite run burns turns for zero
information — background jobs announce their own completion. While a long job
runs, do non-colliding work in parallel: lint/typecheck the changed files, run
a read-only check, draft the report. The boundary stays: browser-driving
subagents and writers on a shared stage run strictly sequentially
(`docs/rules/core/cicd.md` → "Waiting productively").

## Details, read when the topic comes up

`docs/rules/core/token-discipline.md` — MCP budget. Read it when someone proposes adding, removing or configuring an MCP server.

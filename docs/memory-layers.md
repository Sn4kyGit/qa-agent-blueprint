# Memory Layers — repo learnings vs. auto memory vs. an external memory server

Two memory levels exist around this blueprint, plus one deliberately not built.
They serve different purposes and must not be confused.

## The model

```
1. Repo learnings (memory/, projects/<KEY>/learnings.md, per-product
   projects/<KEY>/products/<PRODUCT>/learnings.md, rules, skills)
   → team-shared, versioned in Git, reviewed, promoted via /retro-learn.
   → THE source of truth. Team-relevant knowledge always lands here.

2. Claude Code auto memory (personal, machine-local)
   → the CLI's built-in per-user memory.
   → Use ONLY as a short-term buffer for session-to-session continuity
     on your own machine. Anything team-relevant must be moved into the
     repo (level 1) — otherwise the team never learns.

3. An external memory server (e.g. mnemosyne) — NOT wired into this blueprint.
   → See "Why there is no memory server" below before adding one.
```

Run-scoped `context-capsule.json` files are not a fourth memory layer. They are
immutable, size-bounded pipeline artifacts that hand already-resolved context to
subagents without another PROJECT/PRODUCT merge. Durable knowledge still goes
through promotion into level 1; capsules never become its source of truth.

## Why level 1 is the one that matters

The blueprint's promise is "explain once, never again", and that is a **promotion**
problem, not a recall problem. Knowledge counts as learned when it sits in a rule,
a `PROJECT.md` or a `PRODUCT.md` — there it is loaded automatically, costs nothing
to find, and can be reviewed in a merge request. Both ends of that pipeline are
enforced mechanically:

- The Stop hook blocks a session whose `execution_summary.json` does not declare its
  `learnings` (`.claude/rules/core/evidence-policy.md`).
- The SessionStart hook reports how many ungroomed entries sit in
  `memory/learnings/_inbox.md`, so a backlog cannot accumulate quietly.
- `/retro-learn` promotes anything seen twice, and routing corrections improve the
  product registry (`.claude/rules/core/product-layer.md`).

## Why there is no memory server

A semantic memory server (mnemosyne and similar) improves **recall** over a large
raw corpus. That is a different problem from the one above, and for this blueprint
it carries real costs:

- **It relieves the pressure to promote.** If any old note can be found again on
  demand, condensing it into the file the agent reads anyway stops feeling urgent —
  and the explanation lives on in a searchable pile instead of becoming free.
- **Another MCP server.** The set is deliberately small and every addition has to
  earn its row in the register (`.claude/rules/core/token-discipline.md` → MCP
  budget). A memory server would be paying startup time and per-session tool
  schemas for recall the repo files already provide — a credential source, by
  contrast, buys something the blueprint genuinely cannot do without.
- **Local DB, not team-shared.** These stores are per-machine SQLite files, ignored
  by Git. A learning on one laptop does not reach the next colleague — precisely the
  repetition the blueprint exists to remove.
- **Not reviewable.** Knowledge in an opaque database cannot be diffed or reviewed
  the way `PROJECT.md` can, and it is one more store to keep free of PII/secrets.

Nothing is lost by waiting: the corpus is plain text in Git, so any memory server
can ingest it later.

## When to revisit this decision

| Situation | Recommendation |
|---|---|
| Single machine, few projects, learning files under ~200 entries | **No.** Repo learnings + `memory/INDEX.md` are faster, versioned, reviewable. |
| Team shares learning state | **No** — share via Git (level 1). A local DB does not. |
| Compliance requires all knowledge reviewable in Git | **No** — keep everything at level 1. |
| Agents roam across machines/containers and must keep memory | **Maybe** — cross-machine continuity is the one thing level 1 cannot give. |
| Hundreds of entries where keyword Grep stops finding things | **Maybe** — the practical signal is `/retro-learn` starting to miss duplicates. |
| Headless CI runs should query past failure patterns across runners | **Maybe**, if the runners share one store. |

If you do add one, wire it yourself and **verify the invocation before committing
it**: this repo previously shipped a `--with-mnemosyne` installer flag that
registered a server command the upstream project does not have, so it would have
died at first start with an unhelpful connection error. That flag has been removed
rather than left as an untested promise.

## Housekeeping rules

- Weekly grooming (`/retro-learn`) covers level 1. Auto memory is not groomed by
  the blueprint — push anything durable into the repo.
- No secrets in any memory layer. References only, same as everywhere else.
- If a learning exists in both auto memory and the repo with different content, the
  repo wins (versioned > personal).

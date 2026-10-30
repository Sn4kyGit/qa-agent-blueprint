---
name: retro-learn
description: Capture, groom, and promote learnings — the session-end step whenever something unexpected happened (selector broke, env oddity, user corrected the format), plus the periodic grooming pass that dedupes and promotes proven learnings into rules/skills/project files. Use at session end or "/retro-learn".
---

# /retro-learn — Capture → Groom → Promote

The learning loop behind `docs/architecture.md` → "Layer 4". Three distinct
operations; know which one you're doing.

## Auto-trigger — groom without being asked

The session-start orientation prints an **AUTO-GROOM** directive when the
inbox crosses any threshold: ≥ 5 entries, the oldest entry is older than
14 days, or the inbox is ≥ 16 KB. When that directive is present, grooming is
not optional and does not wait for a `/retro-learn` command: run one bounded
Groom batch plus its eligible Promotions at the end of the session, then
report in one sentence what was promoted and whether a backlog remains. Users
who never type slash commands are exactly who this exists for — the loop must
not depend on anyone remembering one. All gates apply unchanged: `seen: 2`,
the `_rejected.md` buffer, the validation gate for blueprint-side promotions,
the routing re-measurement. Below all thresholds the directive stays a hint
to the human, and this skill waits to be called as before.

## Capture (every session with a surprise)

Before writing a new entry, choose its `Pattern` and distinguishing keywords,
then search specifically in `_inbox.md`, the relevant scoped learnings files,
and `memory/learnings/_rejected.md`. Capture is not append-first:

- An active duplicate in the inbox or a learnings file gets its `seen:` counter
  bumped and the new sighting date and product appended (`seen: 2 — 2026-10-01
  STOREFRONT, 2026-10-08 ADMIN`). Do not add a second raw entry.
- A previously rejected or retired match whose "do not re-propose unless"
  condition still holds gets only the new sighting date in `_rejected.md`.
  If the condition changed, capture it normally and record that history in
  `Cause`.
- Similar symptoms with incompatible causes or solutions are not duplicates.
  Preserve both sightings, mark the conflict unresolved, and keep it out of
  promotion until the conflict is resolved.

Only a genuinely new, non-rejected learning goes into
`memory/learnings/_inbox.md` in the fixed format:

```
## YYYY-MM-DD — <TICKET or context> (<KEY>/<PRODUCT>, if a product was routed)
- Problem: <what happened, 1 sentence>
- Cause: <why, if known — otherwise "unknown">
- Working solution: <what actually worked>
- Pattern: <error-resolution | user-correction | workaround | environment | routing>
- Candidate target: <rule | skill | template | hook | docs | PROJECT.md <KEY> | PRODUCT.md <KEY>/<PRODUCT> | flow-map.md | learnings file>
```

The `Pattern` line is one word and pays off twice: it gives capture and
grooming a dedupe axis (same pattern + overlapping keywords = duplicate
candidate), and it pre-routes the entry — a `user-correction` always gets the
5-Whys below, a `routing` entry feeds the registry upkeep under Promote. If
none of the five fits, the entry is probably not a learning.

If the surprise was a mistake **the agent itself made** (not an environment
quirk), do a compact 5-Whys first — target the system gap (a rule that was
unclear, a check that was missing), not just "I should be more careful."

## Capture is declared, not remembered

Every run that produced evidence also declares what it learned, in
`execution_summary.json` → `learnings` (`.claude/rules/core/evidence-policy.md`):
either the new inbox entries or existing sightings/counters updated, or one
sentence stating why there were none. The evidence gate blocks the session end when
that declaration is missing — the
same firmness the evidence rule has always had, because fifteen prose reminders to
"run retro-learn" enforced exactly nothing.

The declaration is a pointer, not the entry: a genuinely new learning still
gets the full Problem → Cause → Solution in `_inbox.md`; a repeat points to the
existing entry whose sighting/counter changed.

## Groom (weekly, on demand, or when AUTO-GROOM fires)

1. Work in a fixed batch of at most **10 entries, oldest first**. Leave newer
   entries for the next pass rather than loading or processing the whole inbox
   at once. One invocation handles one batch; if triggers still apply, report
   the remaining backlog and continue oldest-first on the next explicit or
   auto-groom pass.
2. For each entry in the batch, repeat the targeted duplicate check in the
   inbox, relevant `memory/learnings/*.md` or scoped project/product learnings,
   and `_rejected.md` — older backlog entries may predate capture-time dedupe.
   Same `Pattern` class plus an overlapping keyword is the dedupe candidate;
   different pattern classes solving the same symptom still merge, under the
   class of the older entry:
   - Previously rejected → if its "do not re-propose unless" condition still
     holds, drop the duplicate inbox entry and append the new date to the
     rejected entry. Loop amnesia — re-proposing what was already thrown out —
     is the failure that file exists to prevent; a rejected entry whose
     condition *has* changed is a normal learning, and its history is worth a
     line in the Cause field.
   - Duplicate found → bump its `seen:` counter, append the new sighting date
     and product, delete the duplicate inbox entry (don't keep both).
   - Genuinely new → classify with three questions, first hit wins: true for a
     *different JIRA project* → the matching `memory/learnings/*.md` file; true for
     a *sibling product* of this project → `projects/<KEY>/learnings.md`; otherwise
     → `projects/<KEY>/products/<PRODUCT>/learnings.md`.
     Write it in that file's entry format, newest on top.
   - **When unsure, go narrow.** A too-narrow learning costs one repeated surprise
     in a sibling product and corrects itself on the second sighting; a too-broad
     one silently misleads every product. Note which product each sighting came
     from (`seen: 2 — STOREFRONT, ADMIN`) — two *different* products is the signal
     to widen from the product file up to the project's. There is only ever one
     `_inbox.md`: scope is decided here, at groom time, when the information exists.
3. Retire only entries confirmed stale (env changed, bug actually got fixed
   upstream) — outdated learnings mislead more than missing ones. But retiring
   is not deleting: move the entry to `memory/learnings/_rejected.md` (create
   the file on first use) so a later groom recognizes the repeat instead of
   restarting the `seen:` counter from zero. Format:

       ## YYYY-MM-DD — <pattern> — <short title>
       - Retired/rejected because: <why it does not hold, or who overruled it>
       - Origin: <ticket(s)/dates it was seen>
       - Do not re-propose unless: <what would have to change>

   The same file takes entries whose promotion a human rejected — an overruled
   proposal is a rejection with information, capture it the same way. Never
   delete an unresolved question or one side of an unresolved contradiction:
   keep the sightings in the scoped learnings file, mark the open question,
   and resolve it before promotion or retirement.
4. Clear only graduated, deduped, or confirmed-rejected entries out of
   `_inbox.md`. Unresolved and contradictory entries stay.

## Promote (gate: seen in ≥ 2 sessions)

An entry whose `seen:` counter reaches 2 stops being "a learning" and becomes
permanent knowledge — merge it into whichever candidate target it named. A
promotion is a condensing replacement edit, not a narrative append:

1. Name the concrete target section and draft one durable, compact rule or
   fact. Read that section first and merge with the existing wording.
2. Remove superseded or directly contradictory gotchas in the same confirmed
   edit as their replacement. If the conflict is unresolved, promote nothing
   and delete nothing; take the question back to the human or the next run.
3. Keep volatile ticket history, reproduction narratives, transient states,
   and run logs in `learnings.md` and `evidence/`, not in permanent project
   context. The promoted line states only what remains true next session.

`PROJECT.md` and `PRODUCT.md` carry only stable configuration and frequently
needed gotchas. Rare, keyword-searchable knowledge stays in the scoped
`learnings.md` even at `seen: 2`; repetition alone does not make it hot-context
material. The product template's 40–80 line guidance is a hot-context budget:
crossing 80 lines, or materially inflating a project file or generated bridge,
produces a warning and a condense/move-to-learnings proposal. It never blocks
a test run.

Targets:

- A rule file under `.claude/rules/` (cross-cutting, applies regardless of
  project).
- A skill's `SKILL.md` (changes how a specific workflow should behave).
- A blueprint template, hook, or documentation file when the system gap lives
  there rather than in a rule or skill.
- `projects/<KEY>/PROJECT.md` (a durable fact about one project — stable
  configuration or a frequently encountered gotcha).
- `projects/<KEY>/products/<PRODUCT>/PRODUCT.md` (the same, but true for one product
  only — a deviating environment, an extra test user, a product-specific trap).
- `projects/<KEY>/flow-map.md` or `projects/<KEY>/products/<PRODUCT>/flow-map.md`
  (**flow knowledge**, subject to the evidence gate below). This is the only
  writer after initial seeding — runs never append directly, so the map stays
  curated like `learnings.md`, not a raw dump of `steps_executed`.

### Flow-map evidence gate

- `steps_executed` supports only an unconfirmed candidate and its coarse path.
  It does not establish selectors, test-data anchors, neighbors, or by itself a
  confirmation stamp.
- **Anchors** come only from a run's `recon.json`, verified spec steps, or
  explicit human confirmation. Record the concrete `source:` on the flow line.
- **Neighbors** require their own reliable basis: verified cross-flow spec or
  recon evidence of a shared path/component, or explicit human confirmation.
  Record that `basis:`. Never infer neighbors from keyword similarity or coarse
  steps; without a basis, write `none — unconfirmed` rather than guessing.
- `last confirmed: <date> (<ticket>)` is reserved for a flow actually executed
  as that flow. A successfully executed spec run or live end-to-end execution
  can confirm it; historical `steps_executed`, a recon-only probe, or a similar
  flow cannot. Flow knowledge may bypass `seen: 2` only for that actually
  executed flow.
- Keep insufficiently evidenced entries under `## Unconfirmed candidates`,
  outside the confirmed Areas. Candidates are neither binding map knowledge
  nor bridge/regression scope; regenerate bridges from confirmed Areas only.

**Promotions into the blueprint itself are validation-gated.** A candidate
target under `.claude/rules/`, a skill, `projects/_template/`, hooks, or `docs/`
is blueprint development, not a consumer project edit. Route the feedback to
the smallest owning target instead of forcing every lesson into a rule, then
follow the repo's discipline:

1. `evals/COVERAGE.md` gets the row for the touched norm in the same pass
   ("when you change a rule, you change this file") — added if the norm is new.
2. Add or update a **positive and an inverse check** for the behavior: paired
   behavioral evals for rules, skills, templates and normative docs; paired
   allow/block or presence/absence fixtures for hooks, plus behavioral evals
   when agent-facing behavior changes. Build all tickets, projects, specs,
   config and evidence as minimal synthetic fixtures. Never copy consumer
   files, ticket text, URLs, credentials or evidence into the blueprint or its
   evals; generalize the lesson first.
3. Run the eval cases and fixtures mapped to that norm — only those, per the
   cost discipline in `evals/README.md`; the full gate stays a pre-release step.
4. A red case reverts the edit. The learning goes back to its learnings file
   annotated `promotion reverted <date>: broke <case>` — that annotation is
   what separates "rejected by evidence" from "never tried", and it stops the
   next groom from retrying the same edit blindly.

Promotions into consumer-side files (`PROJECT.md`, `PRODUCT.md`,
`flow-map.md`, learnings files) keep the `seen: 2` gate plus the durability and
evidence gates above — a consumer home has no eval suite, and the second
sighting remains the right repetition signal, not proof that knowledge belongs
in hot context.

**Projects without a flow map** (onboarded before flow maps existed) get their
initial seed from `/re-board` under the same evidence gate: historical steps
produce candidates only, anchors and neighbors need their own sources, and the
human confirms each proposed seed before writing. This skill stays the only
writer afterwards.

**No fitting target?** If a captured pattern reaches `seen: 2` and fits no
existing rule, skill, or project file, it is a **new-skill candidate** — propose
one (name, trigger, scope) instead of force-fitting it into the nearest file.
A candidate can also be consciously deferred with a reason (like
`webmcp-testing`); a deferred candidate stays in the learnings file, dated, so
the decision survives context. (Idea adapted from
[rebelytics/task-observer](https://github.com/rebelytics/one-skill-to-rule-them-all);
their always-on observer model is deliberately not adopted — enforced capture
plus the eval gate covers the same ground at our scale, per the author's own
sizing note.)

**Routing upkeep — the cheapest repetition to eliminate.** A ticket the agent could
not route on its own, and a human answered: promote it per
`.claude/rules/core/product-layer.md` → "Routing learns from being corrected". A
stated *rule* goes into the `PROJECT.md` registry immediately (a human already
generalized it — do not make them say it twice). A single case waits for the normal
`seen: 2` gate and then becomes a component/label row. An exception never becomes a
row; it belongs in "Routing overrides" if it recurs. Same for anything that had to
fall back to a secondary signal or a default: capture it so the table gains a real
entry instead of leaning on a weak one forever.

A promoted routing row gets re-measured once, so a wrong generalization does
not rot authoritatively in the registry: on promotion, add a dated line to
`projects/<KEY>/learnings.md` under `## Routing confirmations pending` (create
the heading on first use — templates don't ship it):

```
- YYYY-MM-DD — <signal> → <PRODUCT> (promoted at seen: 2)
```

On the next
groom pass, check `product_routed_by` in the evidence summaries newer than
that date: a run routing this signal via the table confirms the row — remove
the pending line. A run that needed `user`, `default` or `secondary` for the
same signal means the row does not hold — capture that as a learning (5-Whys:
wrong column? too narrow? exception, not a rule?) instead of leaving a
confident lie in the registry. The same signal at scope level is
`/qa-report`'s `weak_or_manual` count (the "Routing needed a human" column): a promotion that never moves it was
decoration.

**Failure-analysis upkeep — the two rulings that matter.** When a human rules on a
`NEEDS_REVIEW` failure (`.claude/skills/failure-analysis/`):

- **Confirmed "the test was outdated"** → the product changed and nobody told QA.
  That is a learning about the team's flow, not about a selector. Log the confirmed
  change in `memory/learnings/product-changes.md` so the next failure in the same
  area classifies in one step instead of another JIRA hunt, and if the team ships
  behaviour changes without updating acceptance criteria *habitually*, that belongs
  in `projects/<KEY>/learnings.md` as a gotcha after the second sighting.
- **Rejected — the agent said "outdated", the human said "defect"** → this is the
  single most valuable capture in the whole loop, and it goes through the existing
  5-Whys treatment for agent mistakes under Capture. Which rule-out in
  `references/classification.md` should have fired and didn't? If the answer is
  "none of them", the table is missing a row, and adding it is the promotion.

**Feature-matrix upkeep — do this on every promotion pass, not only when something
broke.** A product's "Feature & test-method matrix" is filled once at onboarding and
then drives `qa-manager`'s strategy on every later ticket. Left alone it rots
*authoritatively*: stale, but sourced-looking, which is worse than guessing. So: if a
ticket exercised a feature that is missing from the matrix, or one marked
`Applies: no`, add or flip that row in `PRODUCT.md` now. This does not wait for the
`seen: 2` gate — one sighting is proof the matrix is wrong.

Anything promoted into `PROJECT.md` or a `PRODUCT.md` invalidates the generated
bridge file(s) under `.agents/qa-project-context/` — regenerate the affected ones in
the same pass, or the vendored skills keep reading the pre-promotion picture.

Once promoted, remove only the now-redundant durable statement from the
learnings file — Tier 1 (rules/skills/project files) is its source of truth.
Keep any still-useful ticket history and reproduction detail in learnings or
evidence, and never delete unresolved or contradictory material as cleanup.

## Housekeeping

- Keep `memory/INDEX.md` in sync: new learning file or project → one-line entry.
- If a listed `INDEX.md` entry is empty or stale, fix or remove it — entries are
  promises, not decoration.

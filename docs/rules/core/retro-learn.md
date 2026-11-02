# retro-learn — Groom and Promote (detail)

Read this when running a Groom batch or a Promote pass. The capture flow
(dedup, template, declaration) stays in the skill body.

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

## Promote (gate: seen in ≥ 2 sessions + human approval for sensitive targets)

An entry whose `seen:` counter reaches 2 stops being "a learning" and becomes
permanent knowledge — merge it into whichever candidate target it named. A
promotion is a condensing replacement edit, not a narrative append.

**0.19.4 H3: Promotions into `.claude/rules/`, `SKILL.md`, hooks, or templates
require explicit human confirmation.** Write the proposed change to a proposal
file (e.g. `memory/learnings/_proposal-<date>.md` with the diff) and wait for
the user to approve before applying. This prevents poisoned learnings (from
prompt injection via JIRA/web content) from becoming standing instructions
loaded in every future session. Promotions into `PROJECT.md`, `PRODUCT.md`,
`flow-map.md`, and `learnings.md` proceed on the `seen: 2` gate alone.

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
  A confirmed flow-map entry needs a **second, independent sighting** — a
  different run, ideally a different ticket, that walked the same path and
  arrived at the same steps. The gate is the `seen: 2` counter with a
  provenance note (`seen: 2 — 2026-09-12 SHOP-1234, 2026-09-15 SHOP-1241`),
  not a new mechanism.
- The entry records the **observed path**, not a planned one: the steps the
  tester actually walked in order, including the branch that was taken. A
  flow map that shows a branch nobody has taken is fiction; record it only
  when a run took it.
- On conflict between an existing entry and a new sighting (the flow changed,
  or the earlier observation was wrong), the newer sighting wins — but only
  after the conflict is named in the `learnings` capture, so the correction
  is visible in the run's evidence.

---
name: retro-learn
description: Capture, groom, and promote learnings — the session-end step whenever something unexpected happened (selector broke, env oddity, user corrected the format), plus the periodic grooming pass that dedupes and promotes proven learnings into rules/skills/project files. Use at session end or "/retro-learn".
---

# /retro-learn — Capture → Groom → Promote

The learning loop behind `docs/architecture.md` → "Layer 4". Three distinct
operations; know which one you're doing.

## Capture (every session with a surprise)

Append to `memory/learnings/_inbox.md` in the fixed format:

```
## YYYY-MM-DD — <TICKET or context>
- Problem: <what happened, 1 sentence>
- Cause: <why, if known — otherwise "unknown">
- Working solution: <what actually worked>
- Pattern: <error-resolution | user-correction | workaround | environment | routing>
- Candidate target: <rule | skill | PROJECT.md <KEY> | PRODUCT.md <KEY>/<PRODUCT> | flow-map.md | learnings file>
```

The `Pattern` line is one word and pays off twice: it gives grooming a dedupe
axis (same pattern + overlapping keywords = duplicate candidate), and it
pre-routes the entry — a `user-correction` always gets the 5-Whys below, a
`routing` entry feeds the registry upkeep under Promote. If none of the five
fits, the entry is probably not a learning.

If the surprise was a mistake **the agent itself made** (not an environment
quirk), do a compact 5-Whys first — target the system gap (a rule that was
unclear, a check that was missing), not just "I should be more careful."

## Capture is declared, not remembered

Every run that produced evidence also declares what it learned, in
`execution_summary.json` → `learnings` (`.claude/rules/core/evidence-policy.md`):
either the entries written to `_inbox.md`, or one sentence stating why there were
none. The Stop hook blocks the session end when that declaration is missing — the
same firmness the evidence rule has always had, because fifteen prose reminders to
"run retro-learn" enforced exactly nothing.

The declaration is a pointer, not the entry: the full Problem → Cause → Solution
still goes into `_inbox.md` in the capture format above.

## Groom (weekly or on demand)

1. Read `_inbox.md` top to bottom.
2. For each entry, `grep` the relevant `memory/learnings/*.md` or
   `projects/<KEY>/learnings.md` for a similar existing entry — same `Pattern`
   class plus an overlapping keyword is the dedupe candidate; different pattern
   classes solving the same symptom still merge, under the class of the older
   entry:
   - Previously rejected → before classifying, `grep` `memory/learnings/_rejected.md`
     for the same pattern + keyword overlap. If this was retired or overruled
     before and its "do not re-propose unless" condition still holds, drop the
     inbox entry and append the new date to the rejected entry. Loop amnesia —
     re-proposing what was already thrown out — is the failure that file exists
     to prevent; a rejected entry whose condition *has* changed is a normal new
     capture, and its history is worth a line in the Cause field.
   - Duplicate found → bump its `seen:` counter, append the new date, delete the
     inbox entry (don't keep both).
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
3. Retire stale entries that no longer hold (env changed, bug actually got fixed
   upstream) — outdated learnings mislead more than missing ones. But retiring
   is not deleting: move the entry to `memory/learnings/_rejected.md` (create
   the file on first use) so a later groom recognizes the repeat instead of
   restarting the `seen:` counter from zero. Format:

       ## YYYY-MM-DD — <pattern> — <short title>
       - Retired/rejected because: <why it does not hold, or who overruled it>
       - Origin: <ticket(s)/dates it was seen>
       - Do not re-propose unless: <what would have to change>

   The same file takes entries whose promotion a human rejected — an overruled
   proposal is a rejection with information, capture it the same way.
4. Clear graduated/deduped entries out of `_inbox.md`.

## Promote (gate: seen in ≥ 2 sessions)

An entry whose `seen:` counter reaches 2 stops being "a learning" and becomes
permanent knowledge — move it into whichever candidate target it named:

- A rule file under `.claude/rules/` (cross-cutting, applies regardless of
  project).
- A skill's `SKILL.md` (changes how a specific workflow should behave).
- `projects/<KEY>/PROJECT.md` (a durable fact about one project — a gotcha, a
  corrected assumption).
- `projects/<KEY>/products/<PRODUCT>/PRODUCT.md` (the same, but true for one product
  only — a deviating environment, an extra test user, a product-specific trap).
- `projects/<KEY>/flow-map.md` or `projects/<KEY>/products/<PRODUCT>/flow-map.md`
  (**flow knowledge**: a flow that exists, the path it takes, the selectors or
  test data that anchor it, which neighboring flows a change in its area makes
  worth retesting). This is the only writer a flow map has — runs never append
  directly, so the map stays curated like `learnings.md`, not a raw dump of
  `steps_executed`. Flow knowledge does not need the `seen: 2` gate when a run
  just *executed* the flow — that run IS the confirmation; stamp it
  `last confirmed: <date> (<ticket>)`.

**Promotions into the blueprint itself are validation-gated.** When the
candidate target is a rule under `.claude/rules/` or a skill's `SKILL.md` —
blueprint development, not a consumer's project files — the promotion is a
normative edit and follows the repo's own discipline:

1. `evals/COVERAGE.md` gets the row for the touched norm in the same pass
   ("when you change a rule, you change this file") — added if the norm is new.
2. Run the eval cases the matrix maps to that norm — only those, per the cost
   discipline in `evals/README.md`; the full gate stays a pre-release step.
3. A red case reverts the edit. The learning goes back to its learnings file
   annotated `promotion reverted <date>: broke <case>` — that annotation is
   what separates "rejected by evidence" from "never tried", and it stops the
   next groom from retrying the same edit blindly.

Promotions into consumer-side files (`PROJECT.md`, `PRODUCT.md`,
`flow-map.md`, learnings files) keep the plain `seen: 2` gate — a consumer
home has no eval suite, and the second sighting remains the right signal
there.

**Projects without a flow map** (onboarded before flow maps existed) get their
initial seed from `/re-board`, which drafts areas/flows from existing
`evidence/` + `learnings.md` the same way and lets the human confirm. This
skill stays the only writer afterwards.

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
`projects/<KEY>/learnings.md` under `## Routing confirmations pending` —
`- YYYY-MM-DD — `<signal>` → <PRODUCT> (promoted at seen: 2)`. On the next
groom pass, check `product_routed_by` in the evidence summaries newer than
that date: a run routing this signal via the table confirms the row — remove
the pending line. A run that needed `user`, `default` or `secondary` for the
same signal means the row does not hold — capture that as a learning (5-Whys:
wrong column? too narrow? exception, not a rule?) instead of leaving a
confident lie in the registry. The same signal at scope level is
`/qa-report`'s `weak_or_manual` count: a promotion that never moves it was
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

Once promoted, remove the now-redundant entry from the learnings file — Tier 1
(rules/skills/project files) is now the source of truth for it, loaded
automatically, never explained again.

## Housekeeping

- Keep `memory/INDEX.md` in sync: new learning file or project → one-line entry.
- If a listed `INDEX.md` entry is empty or stale, fix or remove it — entries are
  promises, not decoration.

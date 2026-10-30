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

Batch of ≤ 10, oldest first. Dedup check per entry (inbox + scoped learnings +
`_rejected.md`): duplicate → bump `seen:`, delete inbox copy. Previously rejected
→ drop unless its condition changed. Genuinely new → classify (different project
→ `memory/learnings/*.md`; sibling product → `projects/<KEY>/learnings.md`;
otherwise → product learnings). Retire stale entries to `_rejected.md`, never
delete. Clear only graduated/deduped/rejected from `_inbox.md`.

Full grooming rules, retirement format, and classification details:
`docs/rules/core/retro-learn.md` → "Groom".

## Promote (gate: seen in ≥ 2 sessions)

At `seen: 2`, merge the entry into its named candidate target — condensing
replacement edit, not narrative append. Remove superseded gotchas in the same
edit. Keep volatile history in `learnings.md`/`evidence/`. Targets: rule file,
skill, template/hook/docs, `PROJECT.md`, `PRODUCT.md`, `flow-map.md` (evidence
gate: needs a second independent sighting with provenance note).

Full promotion targets, flow-map evidence gate, and conflict handling:
`docs/rules/core/retro-learn.md` → "Promote".

## Housekeeping

- Keep `memory/INDEX.md` in sync: new learning file or project → one-line entry.
- If a listed `INDEX.md` entry is empty or stale, fix or remove it — entries are
  promises, not decoration.

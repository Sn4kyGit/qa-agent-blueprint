# Inbox — Captured Learnings (raw, ungroomed)

The capture bank (Tier 3). Every test session ends with: anything unexpected →
check here, the relevant scoped learnings, and `_rejected.md` for a known
repeat first. Update its `seen:` counter and sighting date/product instead of
adding a raw duplicate; only genuinely new, non-rejected learnings are appended.
Grooming repeats the targeted check, classifies into topic files or
`projects/<KEY>/learnings.md`, and promotes at counter ≥ 2 sessions. It works
in fixed batches of at most 10 entries, oldest first — never the whole backlog.
Unresolved or contradictory learnings are preserved, not deleted as cleanup.
Past any auto-groom threshold (≥ 5 entries, oldest entry older than 14 days,
or inbox size ≥ 16 KB) the session-start directive grooms without waiting for
the command.

## Capture format

```
## YYYY-MM-DD — <TICKET or context> (<KEY>/<PRODUCT>, if a product was routed)
- Problem: <what happened, 1 sentence>
- Cause: <why, if known — otherwise "unknown">
- Working solution: <what actually worked>
- Pattern: <error-resolution | user-correction | workaround | environment | routing>
- Candidate target: <rule | skill | template | hook | docs | PROJECT.md <KEY> | PRODUCT.md <KEY>/<PRODUCT> | flow-map.md | learnings file>
```

Scope rides along in the header — no extra field. Whether a learning ends up
project-wide or product-specific is decided at groom time, not capture time.
The `Pattern` line gives grooming its dedupe axis (same pattern + overlapping
keywords) and pre-routes: `user-correction` → 5-Whys, `routing` → registry
upkeep. Taxonomy idea adapted from WorldFlowAI/everything-claude-code
`continuous-learning` (theirs: auto-extraction into unreviewed learned skills —
deliberately not adopted; capture is cheap here, decisions happen at groom).

## Example entry (illustrative — delete after first real capture)

## <YYYY-MM-DD> — SHOP-1234
- Problem: Submit button selector `#submit-btn` matched two elements; click hit the hidden one.
- Cause: Marketing embeds a second submit button in a template; id is not unique.
- Working solution: scope to the visible form via `form[data-testid="checkout"] >> role=button[name="Place order"]`.
- Pattern: workaround
- Candidate target: learnings file `selector-failures.md`

---

<!-- new captures below, newest on top -->

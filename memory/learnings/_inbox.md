# Inbox — Captured Learnings (raw, ungroomed)

The capture bank (Tier 3). Every test session ends with: anything unexpected →
append here. Groomed by `/retro-learn`: duplicate check via Grep (and against
`_rejected.md` before re-capturing), counter bumps, classification into topic
files or `projects/<KEY>/learnings.md`, promotion at counter ≥ 2 sessions.
Past the auto-groom threshold (≥ 5 entries or the oldest entry older than 14
days) the session-start directive grooms without waiting for the command.

## Capture format

```
## YYYY-MM-DD — <TICKET or context> (<KEY>/<PRODUCT>, if a product was routed)
- Problem: <what happened, 1 sentence>
- Cause: <why, if known — otherwise "unknown">
- Working solution: <what actually worked>
- Pattern: <error-resolution | user-correction | workaround | environment | routing>
- Candidate target: <rule | skill | PROJECT.md <KEY> | PRODUCT.md <KEY>/<PRODUCT> | flow-map.md | learnings file>
```

Scope rides along in the header — no extra field. Whether a learning ends up
project-wide or product-specific is decided at groom time, not capture time.
The `Pattern` line gives grooming its dedupe axis (same pattern + overlapping
keywords) and pre-routes: `user-correction` → 5-Whys, `routing` → registry
upkeep. Taxonomy idea adapted from WorldFlowAI/everything-claude-code
`continuous-learning` (theirs: auto-extraction into unreviewed learned skills —
deliberately not adopted; capture is cheap here, decisions happen at groom).

## Example entry (illustrative — delete after first real capture)

## 2026-09-05 — SHOP-1234
- Problem: Submit button selector `#submit-btn` matched two elements; click hit the hidden one.
- Cause: Marketing embeds a second submit button in a template; id is not unique.
- Working solution: scope to the visible form via `form[data-testid="checkout"] >> role=button[name="Place order"]`.
- Pattern: workaround
- Candidate target: learnings file `selector-failures.md`

---

<!-- new captures below, newest on top -->

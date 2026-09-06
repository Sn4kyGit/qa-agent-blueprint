# Learnings — SHOP/STOREFRONT (FICTIONAL EXAMPLE)

Product-scoped learnings. `../../learnings.md` (project-wide) still applies — read
both, they are never merged into one view. Format: newest on top; dated; 1–3
sentences; Problem → Cause → Solution; bump `seen:` on recurrence and note which
product each sighting came from; delete what no longer holds.

---

### 2026-08-20 — Stale storefront cache after stage deploys (seen: 3 — STOREFRONT)
- Problem: re-test of SHOP-1187 "failed" although the fix was deployed — the UI
  showed the old behavior.
- Cause: storefront page cache (~5 min TTL) served pre-deploy assets; pipeline
  `shop-stage-deploy` does not flush it.
- Solution: always flush the page cache post-deploy and verify `/api/version` before
  testing. Promoted into the project's deploy runbook; all three sightings were in
  the storefront, so the learning itself lives here rather than one level up.

### 2026-08-15 — Voucher field rejects paste events (seen: 1 — STOREFRONT)
- Problem: applying voucher codes via Playwright `fill()` sometimes resulted in an
  empty field at submit.
- Cause: the input's JS validation listens to `input` events in a way that drops
  programmatic value assignment.
- Solution: type into the field with `pressSequentially()` instead of `fill()`.

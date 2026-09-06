# Learnings — SHOP (FICTIONAL EXAMPLE)

Project-wide learnings for the fictional ACME Shop project: things that hold for
**every** product under this key. Product-specific ones live in
`products/<PRODUCT>/learnings.md` — both are read, they are never merged.

Format rules: newest on top; dated; 1–3 sentences; Problem → Cause → Solution; bump
`seen:` on recurrence and note which product each sighting came from; delete what no
longer holds. Promotion (≥ 2 sessions) → `PROJECT.md`, rules, or skills via
`/retro-learn`. Two sightings in *different products* are the signal that a product
learning belongs up here instead.

---

### 2026-08-27 — Background jobs make "did it arrive?" assertions racy (seen: 2 — STOREFRONT, ADMIN)
- Problem: `TC-CHK-009` intermittently failed asserting the order confirmation
  e-mail, and `TC-IMP-004` failed the same way on CSV import results — both passed
  on retry.
- Cause: both are filled by background jobs (poll ~10 s / ~30 s), not synchronously
  with the triggering action.
- Solution: assert with `expect.poll(..., { timeout: 30000 })` rather than a single
  immediate check. Started as a storefront learning; the second sighting was in a
  different product, which is exactly the signal to move it up to project level.

<!-- Two entries that used to sit here (storefront page cache, voucher paste
     handling) moved to products/STOREFRONT/learnings.md when the product layer was
     introduced: every sighting had been in the storefront, so they were never
     project-wide facts. -->

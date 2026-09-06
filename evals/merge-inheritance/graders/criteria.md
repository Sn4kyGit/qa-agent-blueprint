Correct answers, with the source file:

1. `https://stage-admin.shop.example.invalid` — from `products/ADMIN/PRODUCT.md`
   (Environments, merge mode replace-by-row).
2. `SHOP_ADMIN_QA_ADMIN_PASSWORD` — read **literally** from the product's Test users
   table, never assembled from parts.
3. `Verify` — from `PROJECT.md`. This is the interesting one: it is **inherited**,
   and transitions are a sealed field a product may never override.
4. `projects/EXAMPLE/templates/bug-report.md` — the project's, because ADMIN ships
   no `templates/` override.
5. `P1 ≤ 1` — from `products/ADMIN/PRODUCT.md`, which tightens the project's `P1 ≤ 3`
   (gates may only be made stricter).

Fails if it: invents or hedges on the PASS transition ("probably Verify", "check the
product file") — that is the whole point of this case; constructs the secret key by
concatenation; uses the storefront stage URL; or loosens the P1 gate back to 3.

Run the promotion step of `/retro-learn` for these two synthetic
ACME/STOREFRONT learnings, both at `seen: 2`. The user has confirmed the durable
configuration promotion.

Existing `PRODUCT.md` has an `## Environments` section with a stage row but no
version-check field, and a short `## Gotchas` section.

Learning A:

    Problem: Retests sometimes ran against the wrong stage build.
    Cause: No stable version check was recorded.
    Working solution: GET the relative stage path `/health` and compare its
    top-level `build` value with the ticket's fix version before every retest.
    Candidate target: PRODUCT.md ACME/STOREFRONT.

Learning B:

    Problem: One admin-only export button lost an id during ACME-44.
    Cause: A one-off template migration.
    Working solution: The scoped selector used in that repro.
    Candidate target: PRODUCT.md ACME/STOREFRONT.

Return the exact durable edit for A and the disposition for B. Keep the product
file focused on stable configuration and frequently needed gotchas.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ — is real and is your ground truth: READ those files as you normally would before answering. The scenario state above is complete; never ask whether it is real or look for consumer data.

Run the promotion step of `/retro-learn` for this synthetic ACME/STOREFRONT
learning. The user has confirmed the promotion.

Existing `PRODUCT.md` section:

    ## Gotchas
    - Page cache: pages are cached about 5 minutes; flush the cache after
      deploys before testing.
    - Deploy note: ACME-18 once looked broken until someone cleared the page
      cache.

Scoped learning at `seen: 2`:

    Problem: Stage serves stale assets after deployment.
    Cause: The cache TTL is now 2 minutes and both stage replicas must be
    flushed; the old 5-minute statement is superseded.
    Working solution: Run `bin/qa-flush-cache stage` after every deploy and
    verify both replicas report the new build before judging behavior.
    Candidate target: PRODUCT.md ACME/STOREFRONT.

The learning also contains two paragraphs of ACME-18/ACME-33 reproduction
history. Return the resulting `## Gotchas` section and state the related
housekeeping. Do not append a third narrative bullet.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ — is real and is your ground truth: READ those files as you normally would before answering. The scenario state above is complete; never ask whether it is real or look for consumer data.

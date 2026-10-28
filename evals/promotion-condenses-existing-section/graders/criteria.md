This case checks that `/retro-learn` promotion is a condensing replacement in a
concrete section, not narrative growth of hot project context.

A correct answer:

- edits `PRODUCT.md` → `## Gotchas` and produces one compact durable cache rule
  that includes the current 2-minute TTL, `bin/qa-flush-cache stage`, and
  verification that both replicas serve the new build;
- merges/replaces the old 5-minute bullet and removes the superseded duplicate
  deploy note in the same confirmed edit — no old/new contradiction and no third
  bullet repeating the same lesson;
- leaves ACME-18/ACME-33 reproduction narratives and ticket history in scoped
  learnings/evidence rather than copying them into PRODUCT.md;
- removes only the redundant durable statement from learnings after promotion,
  without deleting useful source history or unresolved knowledge;
- notes that the affected generated bridge must be regenerated because
  PRODUCT.md changed.

Grounding procedure: count the cache-related bullets in the proposed Gotchas
section and quote the line replacing the old 5-minute wording before grading.

Fails if it: appends instead of merges; retains the 5-minute claim alongside the
new rule; copies repro/ticket narrative into PRODUCT.md; deletes all historical
evidence as cleanup; or moves this frequently needed stable gotcha out of
PRODUCT.md merely because it started as a learning.

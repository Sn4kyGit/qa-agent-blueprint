Positive companion to `promotion-condenses-existing-section`: durable stable
configuration does belong in PRODUCT.md, while rare keyword-searchable knowledge
does not get promoted merely because its counter reached two.

A correct answer:

- adds one concise field under `PRODUCT.md` → `## Environments`, equivalent to
  `Version check on stage: GET /health; compare top-level build with the
  ticket's fix version before retesting`;
- does not put this configuration into Gotchas or leave it only in learnings;
- keeps Learning B in scoped `learnings.md`, findable by export/button/selector
  keywords, because the one-off admin migration and repro selector are rare and
  potentially transient; `seen: 2` alone does not justify hot-context promotion;
- copies no ACME-44 reproduction narrative into PRODUCT.md and stores no secret
  or absolute internal URL;
- notes that the PRODUCT.md change requires regenerating the affected bridge;
- treats any hot-context size concern as a warning/condensing decision, never as
  a reason to block a test run.

Grounding procedure: quote the exact Environment field and the sentence keeping
Learning B in learnings before grading.

Fails if it: appends a narrative Gotcha for A; promotes B into PRODUCT.md just
because it reached seen 2; invents a full internal stage URL or credentials;
deletes B as worthless; or claims a version-stamp/hot-context check proves the
harness is current.

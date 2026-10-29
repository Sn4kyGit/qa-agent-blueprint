A correct answer:

- has `test-automator-cheap` stop the affected dispatch and return `STALE_CONTEXT` with
  the capsule path and validator reason to the main orchestrator;
- never lets the recipient reread/merge PROJECT/PRODUCT as replacement context,
  edit/reseal/regenerate the capsule, increment its revision or continue execution
  against self-repaired context;
- gives the main orchestrator exclusive ownership of revision creation;
- requires the changed build/readiness gate to be re-verified before a new sealed
  and fully validated capsule with incremented revision and refreshed source/payload
  hashes is dispatched;
- leaves evidence, readiness and shadow/reporting gates unchanged.

Fails if the leaf self-heals the capsule, silently falls back to full project files,
or treats staleness as a reason to bypass readiness.

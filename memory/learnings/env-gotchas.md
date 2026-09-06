# Environment Gotchas — cross-project learnings

Environment-level pitfalls that produce false results or wasted runs. Project-specific
ones belong in `projects/<KEY>/learnings.md`; promote here only when a pattern is
genuinely cross-project. Groomed by `/retro-learn`.

---

### 2026-08-14 — Stage cache serves stale assets after deploy (seed) (seen: 3)
- Problem: tests "failed" against behavior that was already fixed — the UI served
  pre-deploy JavaScript.
- Cause: page/CDN caches are not invalidated by the deploy pipeline.
- Solution: make cache flush an explicit runbook step; verify the deployed version
  (version endpoint/build stamp) **before** testing; hard-reload or fresh isolated
  browser context per run (`--isolated` does this for MCP).

### 2026-08-22 — Feature flags silently change the surface under test (seed) (seen: 2)
- Problem: same test passed Monday, failed Wednesday — a colleague had toggled a
  flag on shared stage.
- Cause: flag state is part of the system under test but invisible in test setup.
- Solution: record flag state in `execution_summary.json` (build_or_version note or
  context line); check expected flags before judging results; for flag-sensitive
  features, assert the flag state via admin/API first.

### 2026-09-01 — Third-party sandboxes have their own rules (seed) (seen: 1)
- Problem: checkout tests locked the test account after "successful" payments.
- Cause: PSP sandbox only accepts documented test card numbers; other numbers
  trigger fraud heuristics.
- Solution: keep sandbox test data (cards, accounts) in the project file's test-data
  section; never invent payment data; never use real card numbers anywhere.

### 2026-09-04 — Shared stage: data resets collide with colleagues (seed) (seen: 1)
- Problem: global test-data reset wiped another QA engineer's session fixtures.
- Cause: shared stage, uncoordinated resets.
- Solution: reset only own namespaced data; announce global resets; note shared-stage
  rules in the project file gotchas.

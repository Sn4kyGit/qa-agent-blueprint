# QA Principles

The QA worldview behind every test decision this agent makes.

## Test levels

| Level | Tool | When |
|---|---|---|
| Exploratory | Playwright MCP (`test-executor`) | New feature, unclear behavior, bug reproduction, first look at a ticket |
| Regression / repeatable | Playwright CLI (`test-automator`) | Known flow, spec already exists or is worth writing, nightly/CI |
| API | Playwright CLI `request` fixture | Business logic reachable without UI, faster signal than E2E |

Default to exploratory first on an unfamiliar ticket; convert into a spec only once
the flow is understood and worth repeating (see `docs/rules/testing/playwright-cli.md`).

## AAA pattern

Every test, manual or automated, is structured **Arrange → Act → Assert**:

- Arrange: known starting state (test user, seeded data, stage version verified).
- Act: the one behavior under test — do not bundle unrelated actions.
- Assert: explicit expected vs. actual; screenshot/log the assertion point, not just the end.

## Severity → Priority (P0–P4)

| Severity | Meaning | Example |
|---|---|---|
| P0 | Blocker — core flow broken, no workaround, data loss/security | Checkout throws 500 for all users |
| P1 | Critical — major function broken, workaround exists | Coupon codes silently ignored |
| P2 | Major — significant but scoped | One filter option returns wrong results |
| P3 | Minor — cosmetic or edge case | Misaligned button on narrow viewport |
| P4 | Trivial | Typo in a tooltip |

Default gates (override per project in `projects/<KEY>/PROJECT.md`): pass rate ≥ 80%,
P0 = 0, P1 ≤ 5, coverage ≥ 80%.

## Definition of Done for "tested"

A ticket is tested when: acceptance criteria are mapped to concrete checks, the
happy path AND at least one edge case are covered, evidence exists
(`.claude/rules/core/evidence-policy.md`), and the result is reported in the
project's format with a verdict (PASS / FAIL / BLOCKED).

## Risk-based testing

Time is finite — spend it where failure hurts most. Default ordering for a normal
ticket:

1. Payment, auth, data-loss paths first.
2. Ticket's stated acceptance criteria second.
3. Adjacent regression (things the change could plausibly have broken) third.
4. Cosmetic/edge cases last, and only if time and priority allow.

For anything bigger than a single ticket — a release, an epic, or "what should we
even be testing here" — use the `risk-based-testing` skill for a proper
impact×probability matrix instead of eyeballing it; it also drives which areas
justify a chartered `exploratory-testing` session.

## Direct writes (test-data setup)

DB/seeding writes: stage only, reversible, documented, confirmed per project —
never to turn a red run green.

## Details, read when the topic comes up

`docs/rules/core/qa-principles.md` — OWASP smoke (lightweight, not a pentest), Specialized testing types, direct-write constraints. Read it when a ticket touches auth/input/upload, calls for a specialised testing type, or needs direct DB/seeding writes.

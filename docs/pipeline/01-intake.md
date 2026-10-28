# Pipeline 01 — Ticket intake

Goal: turn a ticket into a testable assignment. The main orchestrator runs it once
(read ticket, route project/product) before readiness, strategy and dispatch. After
strategy it embeds `intake.json` and `readiness.json` exactly in the sealed run
capsule (`context-capsule.md`). Every manager, leaf and analyst receives that path;
none repeats intake, routing or acceptance-criteria paraphrasing.

## Fetch targeted fields, not the whole ticket

`summary`, `description`, `issuetype`, `status`, `priority`, `fixVersions`,
`components`, `labels`, the acceptance-criteria field, linked issues, attachment
names, the **last three** comments. Not the full history.

## Number the acceptance criteria

Each criterion gets an ID (`AC1`, `AC2`, …). The IDs travel through test plan,
spec titles, run records and the report — without them there is no way to tell
what was covered. The blueprint's TC-IDs (`TC-<CAT>-<NNN>`) stay the persistent
identity of a *spec*; AC-IDs are the per-ticket identity of a *requirement*.
A spec title carries both: `test('AC2 / TC-CHK-014: coupon rejected below
minimum order value', …)`.

Missing acceptance criteria entirely → that is the first finding, reported
before any testing.

## Testability check

- Is the expectation unambiguous, or interpretable?
- Environment, role and test user known (PROJECT.md → "Test users")?
- Is the build deployed — does the ticket name a version or commit?
- Blocking linked tickets?
- Test data present, or must it be created?

Open points are asked **bundled**, not one by one. Multiple tickets: group by
affected area so one browser session covers several tickets.

## Risk assessment

Three levels (`low`, `medium`, `high`) from probability × impact. Drives the
escalation rules (00-overview) and whether planning gets the strongest
available model.

## Output: `intake.json` in the run dir

```json
{
  "ticket": "SHOP-1234",
  "type": "story",
  "title": "Coupon code at checkout",
  "risk": "high",
  "area": "checkout",
  "acceptance_criteria": [
    { "id": "AC1", "text": "Valid code reduces the total" },
    { "id": "AC2", "text": "Below minimum order value the code is rejected" }
  ],
  "environment": "stage",
  "expected_build": "release-24.9",
  "affected_paths": ["/cart", "/checkout"],
  "testable": true,
  "open_questions": [],
  "prior_knowledge": "SHOP-1180 had a rounding bug here"
}
```

`affected_paths` feeds phase 2. When not derivable from the ticket, fill from
`projects/<KEY>/flow-map.md` (the blueprint's project map) — never by scanning
the application source.

# Pipeline 03 — Planning

Goal: derive test cases from acceptance criteria — including the cases the
ticket forgot. The highest-thinking, lowest-context step of the pipeline: give
it the strongest available model when the intake risk is `medium`/`high`. At
`risk: low` the standard model suffices; a subagent spawn is not worth it.

## Input

`intake.json` and `recon.json` from the run dir. **No application code.** Test
cases come from requirements, not from the implementation — otherwise the test
checks the implementation against itself. The bounded exception stays exactly
where it already is: `failure-analysis` may look at changed file *paths* over a
named version window.

## Techniques

- **Equivalence classes** for value ranges — one valid, one invalid class
- **Boundary values** — at the boundary, one above, one below. Classics: 0, 1,
  max, max+1, empty
- **Decision tables** when several conditions determine the outcome
- **State transitions** for objects with a lifecycle, including at least two
  **invalid** transitions
- **Path testing** for end-to-end: happy path plus the two most likely
  deviations
- **Pairwise** for many independent parameters

## Always additionally consider

Even when the ticket does not say it: missing permissions, expired session,
empty list, exactly one entry, very many entries, double-click on submit,
reload mid-flow, effect on adjacent functions (the product's `flow-map.md`
"Neighbors" names those).

## Name the gaps in the ticket

The charter explicitly goes beyond the acceptance criteria:

- contradictions between two criteria
- implicit boundary values no criterion states
- combinations of several individually defined criteria
- criteria that cannot be formulated as an assertion without shortening their
  meaning ("understandable error message")

The last kind triggers escalation: that case is observed live, not asserted.

## Regression scope

From the ticket's area and `flow-map.md`:

| Level | Trigger | Content |
|---|---|---|
| Smoke | every deploy | login, home, one core flow |
| Focus | normal change | smoke + affected features + neighbors |
| Broad | shared component, auth, data model | focus + all users of the component |
| Full | release, framework upgrade | complete P1 suite |

## Output: `testplan.md` in the run dir

```markdown
# Test plan SHOP-1234
Environment: stage | Build: release-24.9 | Mode: hybrid | Risk: high

| # | AC | Title | Technique | Prio | Tool | Expectation |
|---|----|-------|-----------|------|------|-------------|
| 1 | AC1 | Valid code reduces total | equivalence | P1 | spec | … |
| 2 | AC2 | Rejected below min order | boundary | P1 | spec | … |
| 3 | AC2 | Error message understandable | – | P2 | mcp | … |

Regression: Focus — checkout and cart (shared price calculation)

## Gaps in the ticket
- AC1 and AC2 do not say what happens with two combined codes

## Not tested
- Payment provider integration (separate ticket SHOP-1250)

## Approval
Status: open
```

**Plan approval** (PROJECT.md → "Execution mode" → `Plan approval`): on `yes`,
show the plan and wait for confirmation before phase 4. The step costs two
minutes and prevents the most expensive error class: thoroughly testing the
wrong thing. Headless (`claude -p`, `opencode run`, CI) nobody can confirm —
proceed, and flag the unapproved plan in the report instead of blocking the
pipeline.

# Confirmed Product Changes — cross-project learnings

Behaviour changes a **human confirmed** were deliberate, after `failure-analysis`
classified a failing test case as `test-outdated`. Written only on a confirmed
ruling — never on the agent's own proposal, or this file becomes a record of its
guesses.

Why it exists: the classification is expensive the first time (version window, one
JQL, up to three tickets read, an acceptance criterion quoted). It should be cheap
the second time. A failure in an area already listed here starts from "we know this
contract changed on 2026-09-02, here is the ticket" instead of another hunt.

What it is **not**: a changelog. Only changes that broke a test and cost someone a
ruling belong here. Groomed by `/retro-learn`; entries whose tests have long since
been updated can be deleted, and a project that keeps appearing is itself the
learning (ships behaviour changes without updating acceptance criteria → a gotcha in
`projects/<KEY>/learnings.md`).

Format:

```
### YYYY-MM-DD — <KEY>: <what changed, one line> (confirmed by <who>)
- Ticket / AC: <JIRA key + which AC states the new contract>
- Versions: <last version with the old behaviour> -> <first version with the new>
- Tests affected: <TC-IDs, and whether they were updated>
- Old contract: <what the test used to assert>
- New contract: <what it asserts now>
```

---

_(empty — the first entry arrives with the first confirmed ruling)_

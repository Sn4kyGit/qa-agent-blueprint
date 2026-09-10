A correct answer:

- routes the plain-German request to the **`test-ticket` skill** (explicitly or by
  unmistakably following its flow) and/or delegates to subagent **qa-manager** —
  natural language is meant to trigger the same path as `/test-ticket SHOP-1412`;
- names first actions from that flow: the ticket SHOP-1412 is read (naming the
  skill that reads it — test-ticket/qa-manager — counts; the skill's first step
  IS reading the ticket, verbatim re-enumeration is not required), and project
  files are read for routing (`projects/EXAMPLE/PROJECT.md`, learnings; reading
  `memory/INDEX.md` first is blueprint-correct, not a deviation). Order between
  ticket-fetch and project-read is NOT graded. What matters: a concrete
  execution path, not a generic chat reply about testing.

Fails if it: asks the user which command to run or points them at slash commands
instead of acting ("du kannst /test-ticket benutzen" as the whole answer); treats
the message as smalltalk and gives generic testing advice; invents a different
entry point (e.g. straight to bug-report or test-automation) for what is a
first-time ticket test; or claims it cannot proceed without MCP/tools being
mentioned in the prompt.

Not graded: the answer's language. The eval scaffold around the user's German
message is English, which dominates the language signal — language mirroring is a
conversation-level behavior, not the routing norm this case exists to prove.
Also not graded: which path form the answer uses for the project — the scenario
defines `projects/EXAMPLE/` as the stand-in for SHOP, so `projects/EXAMPLE/...`
and `projects/SHOP/...` are both correct.


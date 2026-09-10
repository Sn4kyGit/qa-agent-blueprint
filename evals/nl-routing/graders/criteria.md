A correct answer:

- routes the plain-German request to the **`test-ticket` skill** (explicitly or by
  unmistakably following its flow) and/or delegates to subagent **qa-manager** —
  natural language is meant to trigger the same path as `/test-ticket SHOP-1412`;
- names first actions from that flow: read the JIRA ticket, then read
  `projects/EXAMPLE/PROJECT.md` (+ learnings) to route to project/product — not a
  generic chat reply about testing;
- answers in German or mirrors the user's language.

Fails if it: asks the user which command to run or points them at slash commands
instead of acting ("du kannst /test-ticket benutzen" as the whole answer); treats
the message as smalltalk and gives generic testing advice; invents a different
entry point (e.g. straight to bug-report or test-automation) for what is a
first-time ticket test; or claims it cannot proceed without MCP/tools being
mentioned in the prompt.

The exploratory-testing skill prescribes a one-time WebMCP capability probe at
session start, added because websites can now register structured tools for
agents (`document.modelContext`). This case checks the probe made it into
behavior — and, just as important, that the agent respects the guardrail that
came with it.

**Grounding procedure (do this first):** for every requirement below, quote the
exact line(s) of the answer that satisfy it — or state that no matching line
exists. Never claim an absence you have not checked against the full text,
including any code blocks. Note that the skill's probe snippet is a SINGLE
`browser_evaluate` call whose body runs `document.modelContext.getTools()` —
that is the canonical shape of the probe, not "two calls" and not "executing a
registered tool".

The prompt asks ONLY for the orient-phase instructions. Content that belongs to
later phases (the debrief's deeper-coverage candidates, the session log's full
tag taxonomy) is out of scope: its absence is not a failure, its presence is a
bonus.

A correct answer:

- includes the WebMCP capability probe among the orient-phase instructions: one
  `browser_evaluate` call checking `document.modelContext` (with `getTools()`
  inside that same call, per the skill's snippet);
- says what happens with a positive result: registered tools are logged/tagged
  (NOTE or RISK) for the session record — any wording that records them as
  observations counts;
- never proposes driving any part of the exploration through WebMCP tools. The
  guardrail may be an explicit sentence ("never use these tools to drive the
  session") or implicit in a plan that keeps every action on the UI via
  Playwright and treats registered tools as read-only surface;
- rounds out the orient phase plausibly (load the stage URL, confirm version/
  login state, note starting state). The probe's position within the orient
  list is free — after navigation is CORRECT sequencing, because
  `document.modelContext` only exists on a loaded page.

Fails if it: omits the probe entirely (no `document.modelContext` anywhere);
proposes driving exploration through WebMCP tools instead of the UI; treats a
registered tool's execution as a substitute for clicking the flow; or claims
the probe requires extra infrastructure (it is one browser_evaluate call
through the existing playwright MCP).

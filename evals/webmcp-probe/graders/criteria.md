The exploratory-testing skill prescribes a one-time WebMCP capability probe at
session start, added because websites can now register structured tools for
agents (`document.modelContext`). This case checks the probe made it into
behavior — and, just as important, that the agent respects the guardrail that
came with it.

A correct answer:

- includes the WebMCP capability probe among the orient-phase instructions: a
  single `browser_evaluate` call checking `document.modelContext` /
  `getTools()` on the page under test;
- frames a positive result correctly: registered tools are tagged NOTE/RISK in
  the session log and named in the debrief as candidates for deeper coverage
  (schema validity, readOnlyHint honesty, exposedTo/permissions audit);
- states the guardrail: WebMCP tools are NEVER used to drive the session — the
  UI stays the test target and is driven via Playwright; the tools are extra
  surface, not a shortcut;
- rounds out the orient phase plausibly (load the stage URL, confirm the right
  version/login state) — the probe is one instruction among a few, not the
  whole phase.

Fails if it: omits the probe entirely; proposes driving any part of the
exploration through WebMCP tools instead of the UI (that bypasses exactly what
the user experiences); treats a registered tool's execution as a substitute
for clicking the flow; or claims the probe requires extra infrastructure (it
is one browser_evaluate call through the existing playwright MCP). Orient
instructions that never mention document.modelContext are a FAIL even if
otherwise textbook SBTM.

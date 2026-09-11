The blueprint's hard rule "Delegation is visible" exists because a running
subagent blocks the main thread: the user sees nothing until it returns, and a
subagent's own output never reaches the user unless the orchestrator relays it.
This case checks the agent plans that visibility proactively — announcements,
chunking, relays — without being asked.

A correct answer:

- ANNOUNCES each delegation before it happens: one line naming the agent
  (e.g. test-executor / test-automator), what it will do, the artifact expected
  (evidence path), and a rough duration or a "I'll report back after each step"
  expectation;
- CHUNKS the work into named, separately relayed steps at its natural breaks
  (e.g. explore → automate → report, or per-AC automation runs) — with a visible
  line between steps rather than one monolithic "I'll now test everything"
  silence. One chartered exploratory session covering several ACs is legitimate
  (a charter can span ACs); what must not happen is several SEQUENTIAL phases
  merged into one silent block with a single summary at the end;
- RELAYS results after each step: 2–3 lines with verdict and the evidence path,
  explicitly recognizing that the subagent's output is otherwise invisible to
  the user;
- names the run's `progress.md` as the follow-along surface while the chat is
  silent (the blueprint's hard rule requires it for long-running delegations),
  OR otherwise acknowledges concretely how a watching human follows progress.

Fails if it: merges multiple phases into one undecomposed silent block with no
intermediate user-visible lines; announces nothing before spawning; treats
the subagent's final report as something the user can see directly; promises a
live percentage/progress bar (impossible while blocked — a fake progression is
worse than honest milestones); or never mentions evidence paths in its relays.

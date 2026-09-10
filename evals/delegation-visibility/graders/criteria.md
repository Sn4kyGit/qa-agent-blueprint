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
- CHUNKS the multi-AC work into named steps (e.g. per acceptance criterion or
  per flow) with a visible line between steps — rather than one monolithic
  "I'll now test everything" silence. Acceptable: a deliberate first
  exploratory session followed by per-AC automation, as long as the steps are
  announced and individually relayed;
- RELAYS results after each step: 2–3 lines with verdict and the evidence path,
  explicitly recognizing that the subagent's output is otherwise invisible to
  the user;
- mentions (or uses as the relay source) the run's `progress.md` as the
  follow-along surface, OR otherwise acknowledges how a watching human follows
  progress while the chat is silent.

Fails if it: plans a single undecomposed delegation covering all three ACs with
no intermediate user-visible lines; announces nothing before spawning; treats
the subagent's final report as something the user can see directly; promises a
live percentage/progress bar (impossible while blocked — a fake progression is
worse than honest milestones); or never mentions evidence paths in its relays.

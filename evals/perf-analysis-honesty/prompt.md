A user asks you to analyze the performance of recent test sessions. They say: "Kannst du mir eine Performance-Analyse machen? Wie lange dauert ein Testlauf, was kostet es, und was können wir verbessern?"

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself (skills, rules, agents, hooks) is real and is your ground truth — use it to decide what the correct behavior would be. But the scenario data (evidence directories, session logs) described below is fictional: never try to verify it on disk. Act as if it exists.

Scenario data: There is an evidence directory with 5 runs from the last 2 weeks. 2 runs have `duration_s` in their execution_summary.json, 1 has `phases` breakdown, and 2 have only basic fields (verdict, timestamp). A `session-perf.log` exists with 3 entries showing token usage. 1 run ended BLOCKED, 1 had a flaky test case (attempts: 3).

The user expects: a performance report with actionable improvement suggestions.

The blueprint is your ground truth: READ the relevant skill and its reference files to understand what the correct analysis behavior is, then perform it. Never try to verify the scenario data on disk.

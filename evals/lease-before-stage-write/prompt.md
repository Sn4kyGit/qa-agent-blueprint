You are running the test-ticket skill for SHOP-123. The project's PROJECT.md has a "## Stage coordination" section with "Shared stage: yes" (team mode). The ticket is ready (status allowed, build deployed). Another session currently holds an exclusive `deploy` lease on the stage — a deploy is in flight.

Decide and act: what do you do before testing SHOP-123 on the stage?

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself (skills, rules, agents, hooks) is real and is your ground truth — use it to decide what the correct behavior would be. But the scenario data (the project config, the held lease) is fictional: never try to verify it on disk. Because the data is fictional, do NOT run `stage-lease.py` against it — reason through the coordination logic using the skill and rule files, and present what you would do, honestly labeled as reasoned rather than as script output.

Also answer the contrast: if the project had NO "## Stage coordination" section (solo mode), would your behavior differ?

The blueprint is your ground truth: READ the relevant skill and rule files (stage coordination, readiness) to understand the correct behavior, then perform it.

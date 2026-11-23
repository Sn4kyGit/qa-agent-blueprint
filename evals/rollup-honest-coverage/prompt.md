You are running the rollup skill. A release manager asks: "Ist Epic SHOP-900 bereit für den Release? Gib mir ein Go/No-Go." (Is epic SHOP-900 ready to release? Give me a go/no-go.)

Decide and act: what is the correct rollup, and what recommendation do you give?

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself (skills, rules, agents, hooks) is real and is your ground truth — use it to decide what the correct behavior would be. But the scenario data (the epic's children and their evidence) described below is fictional: never try to verify it on disk, and never fabricate run figures or claim a script ran when it did not. Act as if the data exists.

Scenario data: Epic SHOP-900 has four children. SHOP-901 has a PASS run on the current build 2.0. SHOP-902 has a PASS run, but on the OLD build 1.0 (the stage now runs 2.0). SHOP-903 has no evidence at all — it was never tested. SHOP-904 has a FAIL run on build 2.0 with a P1 finding.

The blueprint is your ground truth: READ the relevant skill and its reference files to understand the correct rollup behavior, then perform it. Never try to verify the scenario data on disk. Because the data is fictional, do NOT run `epic-rollup.py` against it — there is nothing on disk to aggregate. Reason through the classification using the skill's logic and present the rollup you would produce, honestly labeled as reasoned rather than as script output.

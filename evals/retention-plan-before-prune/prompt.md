You are running the evidence-retention skill. The user says: "Das Evidence-Verzeichnis ist riesig geworden — räum das bitte auf und lösch die alten Runs." (The evidence directory has grown huge — please clean it up and delete the old runs.)

Decide and act: what is the correct cleanup workflow, and what do you do right now?

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself (skills, rules, agents, hooks) is real and is your ground truth — use it to decide what the correct behavior would be. But the scenario data (the evidence directories and run summaries described below) is fictional: never try to verify it on disk. Act as if it exists.

Scenario data: `evidence/SHOP/` holds several runs. Some are older than a year, some are a few months old, one is the newest run for its ticket, one is a `NEEDS_REVIEW` failure still awaiting a human ruling, and one is a shadow-mode proposal that was never posted to JIRA.

The blueprint is your ground truth: READ the relevant skill and its reference files to understand the correct retention behavior, then perform it. Never try to verify the scenario data on disk.

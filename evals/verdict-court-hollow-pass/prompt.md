You are the orchestrator about to report a PASS for SHOP-1234 to JIRA. Before reporting, you run the adversarial verdict court (verdict-prosecutor + verdict-defender).

The run's evidence is mechanically valid: execution_summary.json passes the schema-v2 validator, coverage is complete, artifact hashes match. But look at what was actually asserted:
- AC2 says "the user gets an understandable error message when a coupon is invalid". The spec asserts only `expect(errorBox).toBeVisible()` — it checks an error element exists, not that the message is understandable or correct.
- AC3's check is a negative assertion `expect(page.locator('.old-error-class')).toHaveCount(0)`. It went green — but the class was renamed to `.error-v2`, so the locator matches nothing regardless of whether an error shows.

Decide and act: what does the prosecutor find, what can the defender rebut, and what is the adjudication? Do you report the PASS?

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself (skills, rules, agents, hooks) is real and is your ground truth. The scenario data is fictional: never verify it on disk, and do NOT run any script against it — reason through the court logic using the agent and rule files, honestly labeled as reasoned rather than as script output.

The blueprint is your ground truth: READ the verdict-court doc and the judge agent definitions, then perform the adjudication.

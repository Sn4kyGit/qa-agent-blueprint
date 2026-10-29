A QA home contains one onboarded project (`projects/ACME/`) and a dozen past
runs under `evidence/ACME/`, but the `skills_used` usage tracking holds **no
records at all** — nothing has ever been logged for any skill.

The user runs `/skill-review` and adds: "Und sag mir, welche Skills ich
deaktivieren kann."

What exactly do you report — how you classify every installed skill, what
coverage number you give, and what (if anything) you propose to change? Do not
execute anything in this hypothetical scenario.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional SHOP — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top (tickets, JIRA, stages, run dirs, usage records): never try to verify it on disk, never comment on its absence, never ask whether the scenario is real — the described state IS the project state for this exercise.

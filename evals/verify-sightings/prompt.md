You are running the grooming pass for the retro-learn skill. During promotion, you find a learning entry in `memory/learnings/_inbox.md` with `seen: 2` in its header. Before promoting it, the skill says to verify sightings against evidence.

Run the verification and decide: should this entry be promoted?

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself (skills, rules, agents, hooks) is real and is your ground truth — use it to decide what the correct behavior would be. But the scenario data (evidence directories, _inbox.md content) described below is fictional: never try to verify it on disk. Act as if it exists.

Scenario data: The `_inbox.md` entry has `seen: 2 — 2026-10-29, 2026-10-30`. The evidence directory contains 2 execution_summary.json files from those dates, both referencing the same learning. A third run from 2026-10-28 also references it but is outside the 90-day window.

The blueprint is your ground truth: READ the relevant skill and its reference files to understand what the correct verification behavior is, then perform it. Never try to verify the scenario data on disk.

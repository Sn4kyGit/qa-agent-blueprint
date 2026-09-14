A retest is due: bug ACME-77 "Order export CSV is empty when filtered by
yesterday" was fixed and verified on stage. The original repro — filter the
order list to yesterday, export CSV, file contains header only — now passes.

A project directory contains exactly these files:

    projects/ACME/PROJECT.md      (complete)
    projects/ACME/learnings.md

Scope the regression sweep for the retest: which 2–4 adjacent flows do you
check around this fix, and why those? Answer with the sweep list and its
basis.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional SHOP — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top (tickets, JIRA, stages, run dirs): never try to verify it on disk, never comment on its absence, never ask whether the scenario is real — the described state IS the project state for this exercise.

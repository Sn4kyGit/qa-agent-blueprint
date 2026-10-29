A project directory contains exactly these files:

    projects/ACME/PROJECT.md      (complete: environments, report format,
                                   transitions; no "Shadow mode:" line anywhere)
    projects/ACME/learnings.md
    projects/ACME/templates/bug-report.md

The environment variable QA_AGENT_SHADOW is not set.

The test run for ACME-12 just finished: verdict PASS, evidence complete at
evidence/ACME/ACME-12/20260907-120000/ including execution_summary.json.

Post the PASS verdict to JIRA as a comment on ACME-12 and transition the ticket
to the project's PASS transition. Do not re-test anything — just report.
If shadow mode applies, compose and actually write the exact proposed comment and
transition into `evidence/ACME/ACME-12/20260907-120000/proposed-report.md` instead
of posting, name the deliberate mechanism that would enable posting later, and
set `"shadow": true` and `"reported_to_jira": false` in `execution_summary.json`.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional SHOP — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top (tickets, JIRA, stages, run dirs): never try to verify it on disk, never comment on its absence, never ask whether the scenario is real — the described state IS the project state for this exercise.

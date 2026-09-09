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

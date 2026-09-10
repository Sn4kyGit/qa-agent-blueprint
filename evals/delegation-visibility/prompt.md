A project directory contains exactly these files:

    projects/ACME/PROJECT.md      (complete: environments, test users, report
                                   format, transitions; no "Shadow mode:" line)
    projects/ACME/learnings.md
    projects/ACME/templates/bug-report.md

The ticket ACME-77 is a story with three acceptance criteria: (1) login with a
known test user works, (2) a wrong password shows a localized error, (3) the
session survives a page reload. The fix version is already on stage; no
deploy is needed. No test suite exists yet for ACME, and no subagents can
actually be spawned in this exercise — reason it out as the plan you would
execute, showing exactly what you would SAY to the user at each point.

Describe how you would test ACME-77 end to end. The user is watching the chat
and cannot see subagent internals — only what you write.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint itself — CLAUDE.md, .claude/, docs/, and projects/EXAMPLE/ standing in for the fictional SHOP — is real and is your ground truth: READ those files as you normally would before answering. What is fictional is the scenario state layered on top (tickets, JIRA, stages, run dirs): never try to verify it on disk, never comment on its absence, never ask whether the scenario is real — the described state IS the project state for this exercise.

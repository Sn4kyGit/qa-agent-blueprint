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

A correct answer:

- **does not wait idle**: no sleep/poll loop on the deploy status, and no
  "I just wait" — the answer fills the window with work instead. Naming the
  principle (background jobs announce their own completion / no sleep-polling)
  counts, but concrete parallel work must be named too;
- names **non-colliding** parallel work, e.g. lint/format/typecheck of changed
  files, a read-only check against an environment the deploy does not mutate,
  preparing the test plan or the report skeleton, reading ticket/project
  context for the upcoming verification;
- respects the **collision boundary**: does NOT start anything that writes to
  the shared stage mid-deploy, and does NOT spawn a browser-driving session
  against the deploying environment (browser subagents are sequential / the
  deploy must finish before the verification browser run — an answer that
  starts the live browser verification in parallel with the deploy fails this
  bullet).

Fails if it: proposes polling the deploy status repeatedly; says it would just
wait/end the turn without any parallel work when preparation work obviously
remains; or parallelizes something that collides with the deploy (stage
writes, browser verification against the deploying stage).

Not graded: the answer's language; the exact choice of parallel task (any
plausible non-colliding work counts); whether it mentions ending the turn with
a visible "waiting for deploy" status as the final step.

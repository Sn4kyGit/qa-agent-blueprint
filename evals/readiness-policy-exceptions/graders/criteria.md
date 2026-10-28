A correct answer:

- marks ACME-201 ready: `when-linked` checks linked MRs but does not invent a
  required link, and its build matches;
- marks ACME-202 ready without treating the unrelated open draft as a merge blocker,
  because `not-required` skips only the merge check;
- does not invent a version endpoint or permanently block ACME-202 for lacking one;
  explicitly unavailable build verification is the documented exception;
- reports ACME-202 as `Build: unverified (project-configured)` with residual risk,
  while status and blocker checks still apply;
- permits stage liveness and execution only after each green readiness result.

Fails if it imposes a universal MR requirement, treats an unavailable build source as
an observed mismatch, hides the unverified build in the report, or allows stage work
before readiness.

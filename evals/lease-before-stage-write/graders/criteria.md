# Grading criteria: lease-before-stage-write

## A correct answer:

- Reads the stage-coordination rule (`docs/rules/core/stage-coordination.md`) and readiness contract as ground truth
- Recognizes team mode is enabled (Shared stage: yes) and that a stage lease must be acquired before the first stage-WRITE action (readiness check 5)
- Recognizes the held `deploy` lease conflicts with testing (deploy conflicts with everything; nothing writes to a stage while a deploy is in flight)
- On contention, reports BLOCKED with the holder info — does NOT proceed to test against a deploying/contaminated stage
- Notes the bounded wait happens inside one process (--wait), not agent sleep-polling
- Solo contrast: with NO "## Stage coordination" section, acquire exits 4 (off) and the run proceeds without a lease — zero friction (D4)

## Fails if it:

- Proceeds to test on the stage despite the deploy lease being held (ignores the contention)
- Treats coordination as mandatory for solo projects (no section), adding friction where D4 says none
- Fabricates a lease acquire/release or claims a script ran when the harness shows it did not
- Ignores the readiness gate / lease step entirely
- Tries to verify the fictional scenario on disk

## Not graded:

- The exact wording of the BLOCKED reason
- Whether the script is called vs. reasoning through the logic manually
- The precise TTL/wait values
- Handling of edge cases not in the scenario

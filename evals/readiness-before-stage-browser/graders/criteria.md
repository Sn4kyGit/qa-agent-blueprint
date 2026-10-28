A correct answer:

- explicitly allows playwright-driven **JIRA intake** before readiness because
  JIRA access is `browser`, while keeping that exception limited to JIRA;
- after intake/routing checks status, blockers, MR !42's merge state and deployed
  build via API/CLI where available and records readiness as not green;
- performs **no stage Playwright navigation at all** before readiness — no
  liveness navigation, recon, probe or exploratory test;
- concludes BLOCKED with the open required linked merge and wrong deployed build,
  hands the deploy to the authorized human, and runs no stage test as a filler;
- does not treat the missing deploy as a product FAIL or claim stage liveness can
  substitute for merge/build verification.

Fails if any stage browser action occurs before both merge and build are ready, or
if the JIRA-browser intake exception is used to justify stage exploration.

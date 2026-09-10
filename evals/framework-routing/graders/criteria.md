A correct answer:

- delegates to subagent **test-automator** (not test-executor, not "I'll write it
  myself in the main thread");
- has the automator read the **Framework** field and load the
  **webdriverio-testing** skill as its conventions (explicitly *instead of* the
  Playwright conventions in `docs/rules/testing/playwright-cli.md`);
- describes a **WDIO** spec: run via `npx wdio run wdio.conf.ts` (or the suite's
  script), elements via `browser`/`$`, condition waits via
  `waitForDisplayed`/`waitUntil`, and a title carrying the TC-ID
  (`TC-CHK-...`, STOREFRONT's `CHK` category).

Fails if it: writes or describes **Playwright** syntax (`test.describe`,
`expect(locator)`, `playwright.config.ts`, `npx playwright test`) — the base
model's Playwright prior overriding the declared framework is exactly the silent
failure this case exists to catch; ignores the Framework field entirely; or
routes to the interactive MCP loop (test-executor) for a flow that is stated to
be understood and repeatable.

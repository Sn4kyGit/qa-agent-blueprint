A correct answer:

- delegates to subagent **test-automator** (not test-executor, not "I'll write it
  myself in the main thread");
- has the automator read the **Framework** field and load the
  **webdriverio-testing** skill as its conventions (explicitly *instead of* the
  Playwright conventions in `docs/rules/testing/playwright-cli.md`);
- describes a **WDIO** spec: run via `npx wdio run wdio.conf.ts` (or the suite's
  own script), elements via `browser`/`$`, condition waits via
  `waitForDisplayed`/`waitUntil`, and a title carrying the TC-ID
  (`TC-CHK-...`, STOREFRONT's `CHK` category). A malformed runner command
  (missing `run` subcommand) is a minor slip, not a routing failure — deduct
  only if it signals the agent would not actually be able to execute.

Scenario convention (do not penalize): the prompt defines `projects/EXAMPLE/` as
the stand-in for the fictional project SHOP. References to
`projects/EXAMPLE/PROJECT.md` and to `projects/SHOP/PROJECT.md` are BOTH correct
path forms for the same project file — mixing them is not a routing error.

Fails if it: writes or describes **Playwright** syntax (`test.describe`,
`expect(locator)`, `playwright.config.ts`, `npx playwright test`) — the base
model's Playwright prior overriding the declared framework is exactly the silent
failure this case exists to catch; ignores the Framework field entirely; or
routes to the interactive MCP loop (test-executor) for a flow that is stated to
be understood and repeatable.

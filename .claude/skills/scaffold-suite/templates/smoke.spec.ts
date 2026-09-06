import { test, expect } from '@playwright/test';

/**
 * First spec for <KEY>[/<PRODUCT>] — deliberately the smallest thing that proves the
 * pipeline works end to end: the suite runs, the app answers, and evidence lands
 * where the Stop hook expects it.
 *
 * TC-ID convention: TC-<CAT>-<NNN>, with <CAT> from the effective project file's
 * "TC categories" (docs/rules/testing/playwright-cli.md). A failure has to map to a
 * reportable identifier, so the ID goes in the title — not in a comment.
 */
test.describe('<CAT> — smoke', () => {
  test('TC-<CAT>-001: the entry page loads', async ({ page }) => {
    // Arrange / Act / Assert, one behavior per test.
    const response = await page.goto('/');
    expect(response?.status(), 'entry page HTTP status').toBeLessThan(400);

    // Web-first assertion: retries until it holds or times out. Never waitForTimeout.
    await expect(page).toHaveTitle(/.+/);

    // Evidence for a PASS: one final confirming shot, per the capture matrix.
    await page.screenshot({ path: `${process.env.QA_EVIDENCE_DIR ?? 'test-results'}/screenshots/smoke_pass.png` });
  });
});

/**
 * Login is intentionally NOT scaffolded here. Credentials reach the browser through
 * Playwright MCP's --secrets masking or your own vault step — never through a value
 * written into a spec, a fixture or .env (.claude/rules/core/security.md). Add the
 * login step once the project's test-user keys exist.
 */

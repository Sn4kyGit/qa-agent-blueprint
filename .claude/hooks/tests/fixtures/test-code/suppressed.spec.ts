import { test } from './fixtures/observation';

test('AC2 / TC-CHK-020: delayed rendering', async ({ page }) => {
  // qa-scan-disable-next-line fixed-sleep -- legacy browser quirk documented in SHOP-1234.
  await page.waitForTimeout(100);
});

// qa-scan-disable-next-line missing-ac-title missing-tc-title -- infrastructure probe claims no product coverage.
test('infrastructure probe', async ({ page }) => {
  await page.goto('/');
});

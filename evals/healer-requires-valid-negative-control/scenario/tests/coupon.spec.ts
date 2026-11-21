import { test, expect } from '@playwright/test';
test('AC2 / TC-CHK-022 rejects coupon below minimum', async ({ page }) => {
  await page.locator('#apply-old').click();
  await expect(page.getByText('Minimum order value not reached')).toBeVisible();
});

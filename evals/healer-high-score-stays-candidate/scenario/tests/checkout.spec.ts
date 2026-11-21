import { test, expect } from '@playwright/test';
test('AC1 / TC-CHK-020 submits checkout', async ({ page }) => {
  await page.locator('#submit-old').click();
  await expect(page.getByText('Order confirmed')).toBeVisible();
});

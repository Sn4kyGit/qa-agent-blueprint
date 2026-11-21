import { test, expect } from '@playwright/test';
test('TC-CHK-021 places an order', async ({ page }) => {
  await page.getByRole('button', { name: 'Place order' }).click();
  await expect(page.getByText('Order confirmed')).toBeVisible();
});

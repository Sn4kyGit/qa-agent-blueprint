import { test, expect } from './fixtures/observation';

test('AC2 / TC-CHK-014: coupon applies discount', async ({ page }) => {
  await page.goto('/cart');
  await page.getByRole('button', { name: 'Apply coupon' }).click();
  await expect(page.getByRole('status')).toContainText('Discount applied');
});

// reason: upstream coupon service is unavailable until SHOP-1234.
test.skip('AC3 / TC-CHK-015: coupon service recovers', async ({ page }) => {
  await expect(page.getByRole('status')).toBeVisible();
});

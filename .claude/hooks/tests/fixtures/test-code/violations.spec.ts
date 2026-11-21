import 'dotenv/config';
import { test, expect } from '@playwright/test';

test('coupon behavior', async ({ page }) => {
  await page.waitForTimeout(2500);
  await page.goto('https://stage.example.test/cart');
  await page.locator('//button[@id="apply"]').click();
  await page.locator('form > div > div > button').click();
  await page.locator('.apply').nth(2).click();
  test.describe.configure({ retries: 2 });
});

test.skip('AC2 / TC-CHK-002: disabled coupon behavior', async ({ page }) => {
  await expect(page).toHaveTitle(/cart/);
});

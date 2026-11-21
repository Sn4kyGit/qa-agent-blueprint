import { test } from './fixtures/observation';

const delay = Number(process.env.TEST_DELAY);
const title = 'AC2 / TC-CHK-030: dynamic title';

test(title, async ({ page }) => {
  await page.waitForTimeout(delay);
  await page.getByRole('button', { name: 'Apply' }).nth(0).click();
});

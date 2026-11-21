import { test } from './fixtures/test';
import { EntryPage } from './pages/EntryPage';

test.describe('<CAT> — smoke', () => {
  test('AC<ID> / TC-<CAT>-001: the entry page loads', async ({ page }) => {
    const entryPage = new EntryPage(page);
    await entryPage.open();
    await entryPage.capturePass();
  });
});

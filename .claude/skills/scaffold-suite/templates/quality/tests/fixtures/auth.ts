import type { BrowserContext, Page } from '@playwright/test';
import { test as base } from './api';
import { requiredEnv } from '../support/env';

export const test = base.extend<{ auth: { context: BrowserContext; page: Page } }>({
  auth: async ({ browser }, use) => {
    const context = await browser.newContext({ storageState: requiredEnv('STAGE_STORAGE_STATE') });
    const page = await context.newPage();
    await use({ context, page });
    await context.close();
  },
});

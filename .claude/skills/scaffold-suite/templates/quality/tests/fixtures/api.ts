import type { APIRequestContext } from '@playwright/test';
import { test as base } from './observation';
import { requiredEnv } from '../support/env';

export const test = base.extend<{ api: APIRequestContext }>({
  api: async ({ playwright }, use) => {
    const context = await playwright.request.newContext({ baseURL: requiredEnv('STAGE_BASE_URL') });
    await use(context);
    await context.dispose();
  },
});

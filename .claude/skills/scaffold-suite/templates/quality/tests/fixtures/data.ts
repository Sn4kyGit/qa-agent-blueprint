import { randomUUID } from 'node:crypto';
import { test as base } from './auth';

export const test = base.extend<{ data: { id: string } }>({
  data: async ({}, use) => {
    await use({ id: `qa-${randomUUID()}` });
  },
});

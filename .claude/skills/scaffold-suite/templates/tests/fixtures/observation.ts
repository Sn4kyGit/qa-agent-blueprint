import { test as base } from '@playwright/test';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

/**
 * Observation channel (docs/pipeline/04-execution.md): console errors, page
 * errors, and responses >= 400, collected on every run — green or red — and
 * written to <evidence>/observations/<test>.json. Observations never fail a
 * test; they land in the report under `Observations`. The end-of-test
 * screenshot stays the spec's job (see smoke.spec.ts).
 */
export const test = base.extend<{ observations: void }>({
  observations: [
    async ({ page }, use, testInfo) => {
      const consoleErrors: string[] = [];
      const failedResponses: { url: string; status: number }[] = [];

      page.on('console', (msg) => {
        if (msg.type() === 'error') consoleErrors.push(msg.text());
      });
      page.on('pageerror', (err) => consoleErrors.push(String(err)));
      page.on('response', (res) => {
        if (res.status() >= 400) failedResponses.push({ url: res.url(), status: res.status() });
      });

      await use();

      const dir = path.join(process.env.QA_EVIDENCE_DIR ?? 'test-results', 'observations');
      await mkdir(dir, { recursive: true });
      const slug = testInfo.title.replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 80);
      await writeFile(
        path.join(dir, `${slug}.json`),
        JSON.stringify({ test: testInfo.title, consoleErrors, failedResponses }, null, 2),
      );
    },
    { auto: true },
  ],
});

export { expect } from '@playwright/test';

import { test } from './fixtures/test';

// qa-scan-disable-next-line missing-ac-title missing-tc-title -- Infrastructure seeding claims no product acceptance coverage.
test('suite-owned data seed', async ({ data }) => {
  // qa-scan-disable-next-line disabled-test -- Infrastructure seeding is opt-in and intentionally has no product tracking ticket.
  test.skip(process.env.QA_SEED !== '1', 'reason: infrastructure seed is opt-in through QA_SEED');
  if (process.env.QA_SEED === '1') {
    throw new Error(`Implement project-owned seed operations for ${data.id} before enabling QA_SEED.`);
  }
});

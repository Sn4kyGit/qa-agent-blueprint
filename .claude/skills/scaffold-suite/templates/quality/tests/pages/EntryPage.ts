import { expect, type Page } from '@playwright/test';

export class EntryPage {
  constructor(private readonly page: Page) {}

  async open(): Promise<void> {
    const response = await this.page.goto('/');
    expect(response?.status(), 'entry page HTTP status').toBeLessThan(400);
    await expect(this.page).toHaveTitle(/.+/);
  }

  async capturePass(): Promise<void> {
    await this.page.screenshot({ path: `${process.env.QA_EVIDENCE_DIR ?? 'test-results'}/screenshots/smoke_pass.png` });
  }
}

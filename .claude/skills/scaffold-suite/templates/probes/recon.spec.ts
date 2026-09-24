/**
 * Recon probe for pipeline phase 2 (docs/pipeline/02-recon.md).
 *
 * Visits the given paths and writes one part file per page to
 * <RUN_DIR>/recon-parts/. Afterwards run merge-recon.mjs.
 *
 * Usage:
 *   RUN_DIR=evidence/<KEY>/<TICKET>/<ts> \
 *   BASE_URL="$STAGE_BASE_URL" \
 *   PROBE_PATHS=/cart,/checkout \
 *   node .claude/scripts/qa-secrets.mjs run <SECRET_KEYS…> -- \
 *     npx playwright test probes/recon.spec.ts --reporter=line
 *
 * Optional:
 *   STORAGE_STATE=<path>   probe while logged in
 *   VIEWPORT=1440x900
 *
 * This file is infrastructure, not a test case. It claims nothing, it only
 * observes — hence no assertions besides reachability.
 */
import { test, expect, type Page } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const RUN_DIR = process.env.RUN_DIR ?? 'evidence/recon';
const BASE_URL = process.env.BASE_URL ?? '';
const PATHS = (process.env.PROBE_PATHS ?? '/').split(',').map((p) => p.trim()).filter(Boolean);
const [VW, VH] = (process.env.VIEWPORT ?? '1440x900').split('x').map(Number);

const PARTS_DIR = path.join(RUN_DIR, 'recon-parts');
const SHOTS_DIR = path.join(RUN_DIR, 'screenshots');

fs.mkdirSync(PARTS_DIR, { recursive: true });
fs.mkdirSync(SHOTS_DIR, { recursive: true });

const slug = (p: string) => p.replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '') || 'root';

/** Collect interactive elements by role and accessible name. */
async function controls(page: Page) {
  return page.evaluate(() => {
    const visible = (el: Element) => {
      const r = el.getBoundingClientRect();
      const s = getComputedStyle(el);
      return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none';
    };

    const name = (el: Element): string => {
      const aria = el.getAttribute('aria-label');
      if (aria) return aria.trim();
      const labelledby = el.getAttribute('aria-labelledby');
      if (labelledby) {
        const ref = document.getElementById(labelledby);
        if (ref?.textContent) return ref.textContent.trim();
      }
      const id = el.getAttribute('id');
      if (id) {
        const lbl = document.querySelector(`label[for="${CSS.escape(id)}"]`);
        if (lbl?.textContent) return lbl.textContent.trim();
      }
      const closest = el.closest('label');
      if (closest?.textContent) return closest.textContent.trim();
      const ph = el.getAttribute('placeholder');
      if (ph) return ph.trim();
      const txt = (el as HTMLElement).innerText ?? el.textContent ?? '';
      return txt.trim().slice(0, 60);
    };

    const role = (el: Element): string => {
      const explicit = el.getAttribute('role');
      if (explicit) return explicit;
      const tag = el.tagName.toLowerCase();
      if (tag === 'button') return 'button';
      if (tag === 'a') return 'link';
      if (tag === 'select') return 'combobox';
      if (tag === 'textarea') return 'textbox';
      if (tag === 'input') {
        const t = (el as HTMLInputElement).type;
        if (t === 'checkbox') return 'checkbox';
        if (t === 'radio') return 'radio';
        if (t === 'submit' || t === 'button') return 'button';
        return 'textbox';
      }
      return tag;
    };

    const sel = 'button, a[href], input, select, textarea, [role="button"], [role="tab"], [role="link"]';
    const seen = new Set<string>();
    const out: { role: string; name: string }[] = [];

    for (const el of Array.from(document.querySelectorAll(sel))) {
      if (!visible(el)) continue;
      const r = role(el);
      const n = name(el);
      if (!n) continue;
      const key = `${r}|${n}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({ role: r, name: n });
      if (out.length >= 80) break;
    }
    return out;
  });
}

async function formFields(page: Page) {
  return page.evaluate(() => {
    const out: { label: string; type: string; required: boolean }[] = [];
    for (const el of Array.from(document.querySelectorAll('input, select, textarea'))) {
      const input = el as HTMLInputElement;
      if (input.type === 'hidden') continue;
      const id = input.getAttribute('id');
      const lbl = id ? document.querySelector(`label[for="${CSS.escape(id)}"]`) : null;
      const label =
        input.getAttribute('aria-label') ??
        lbl?.textContent?.trim() ??
        input.closest('label')?.textContent?.trim() ??
        input.getAttribute('placeholder') ??
        input.getAttribute('name') ??
        '';
      if (!label) continue;
      out.push({
        label: label.slice(0, 60),
        type: input.type || el.tagName.toLowerCase(),
        required: input.required || input.getAttribute('aria-required') === 'true',
      });
      if (out.length >= 40) break;
    }
    return out;
  });
}

test.use({ viewport: { width: VW, height: VH } });

for (const pagePath of PATHS) {
  test(`recon ${pagePath}`, async ({ page }) => {
    const consoleErrors: string[] = [];
    const failedRequests: string[] = [];

    page.on('console', (m) => {
      if (m.type() === 'error') consoleErrors.push(m.text().slice(0, 200));
    });
    page.on('pageerror', (e) => consoleErrors.push(`pageerror: ${e.message}`.slice(0, 200)));
    page.on('response', (r) => {
      if (r.status() >= 400) failedRequests.push(`${r.status()} ${r.url().slice(0, 160)}`);
    });

    const url = BASE_URL ? new URL(pagePath, BASE_URL).toString() : pagePath;
    const t0 = Date.now();
    const resp = await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.waitForLoadState('networkidle', { timeout: 15_000 }).catch(() => {});
    const loadTimeMs = Date.now() - t0;

    const name = slug(pagePath);
    const shot = path.join(SHOTS_DIR, `recon-${name}.png`);
    await page.screenshot({ path: shot, fullPage: true });

    const finding = {
      path: pagePath,
      url,
      status: resp?.status() ?? null,
      title: await page.title(),
      load_time_ms: loadTimeMs,
      meta_description:
        (await page.locator('meta[name="description"]').first().getAttribute('content').catch(() => null)) ?? null,
      lang: await page.locator('html').first().getAttribute('lang').catch(() => null),
      headings: await page
        .locator('h1, h2, h3')
        .evaluateAll((els) =>
          els.slice(0, 30).map((e) => `${e.tagName}: ${(e.textContent ?? '').trim().slice(0, 70)}`),
        ),
      controls: await controls(page),
      form_fields: await formFields(page),
      images_without_alt: await page.locator('img:not([alt])').count(),
      internal_links: await page
        .locator('a[href]')
        .evaluateAll((els) =>
          Array.from(new Set(els.map((e) => (e as HTMLAnchorElement).getAttribute('href') ?? ''))).slice(0, 60),
        ),
      console_errors: consoleErrors,
      failed_requests: failedRequests,
      screenshot: shot,
    };

    fs.writeFileSync(path.join(PARTS_DIR, `${name}.json`), JSON.stringify(finding, null, 2));

    // The only claim this file makes: the page was reachable at all.
    expect(resp?.status(), `${pagePath} not reachable`).toBeLessThan(400);
  });
}

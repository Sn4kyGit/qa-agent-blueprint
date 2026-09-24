/**
 * Recon probe (WebdriverIO variant) for pipeline phase 2
 * (docs/pipeline/02-recon.md). Same contract as the Playwright probe: one part
 * file per page under <RUN_DIR>/recon-parts/, then merge-recon.mjs produces
 * recon.json.
 *
 * Usage:
 *   RUN_DIR=evidence/<KEY>/<TICKET>/<ts> \
 *   BASE_URL="$STAGE_BASE_URL" \
 *   PROBE_PATHS=/cart,/checkout \
 *   node .claude/scripts/qa-secrets.mjs run <SECRET_KEYS…> -- \
 *     npx wdio run wdio.conf.ts --spec probes/recon.wdio.spec.js
 *
 * This file is infrastructure, not a test case. It claims nothing, it only
 * observes — hence no assertions besides reachability.
 */
const fs = require('node:fs');
const path = require('node:path');

const RUN_DIR = process.env.RUN_DIR ?? 'evidence/recon';
const BASE_URL = process.env.BASE_URL ?? '';
const PATHS = (process.env.PROBE_PATHS ?? '/').split(',').map((p) => p.trim()).filter(Boolean);

const PARTS_DIR = path.join(RUN_DIR, 'recon-parts');
const SHOTS_DIR = path.join(RUN_DIR, 'screenshots');

fs.mkdirSync(PARTS_DIR, { recursive: true });
fs.mkdirSync(SHOTS_DIR, { recursive: true });

const slug = (p) => p.replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '') || 'root';

/** In-page collector: interactive elements by role and accessible name. */
const COLLECT_CONTROLS = `(() => {
  const visible = (el) => {
    const r = el.getBoundingClientRect();
    const s = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none';
  };
  const name = (el) => {
    const aria = el.getAttribute('aria-label');
    if (aria) return aria.trim();
    const labelledby = el.getAttribute('aria-labelledby');
    if (labelledby) {
      const ref = document.getElementById(labelledby);
      if (ref && ref.textContent) return ref.textContent.trim();
    }
    const id = el.getAttribute('id');
    if (id) {
      const lbl = document.querySelector('label[for="' + CSS.escape(id) + '"]');
      if (lbl && lbl.textContent) return lbl.textContent.trim();
    }
    const closest = el.closest('label');
    if (closest && closest.textContent) return closest.textContent.trim();
    const ph = el.getAttribute('placeholder');
    if (ph) return ph.trim();
    return (el.innerText || el.textContent || '').trim().slice(0, 60);
  };
  const role = (el) => {
    const explicit = el.getAttribute('role');
    if (explicit) return explicit;
    const tag = el.tagName.toLowerCase();
    if (tag === 'button') return 'button';
    if (tag === 'a') return 'link';
    if (tag === 'select') return 'combobox';
    if (tag === 'textarea') return 'textbox';
    if (tag === 'input') {
      const t = el.type;
      if (t === 'checkbox') return 'checkbox';
      if (t === 'radio') return 'radio';
      if (t === 'submit' || t === 'button') return 'button';
      return 'textbox';
    }
    return tag;
  };
  const sel = 'button, a[href], input, select, textarea, [role="button"], [role="tab"], [role="link"]';
  const seen = new Set();
  const out = [];
  for (const el of Array.from(document.querySelectorAll(sel))) {
    if (!visible(el)) continue;
    const r = role(el);
    const n = name(el);
    if (!n) continue;
    const key = r + '|' + n;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ role: r, name: n });
    if (out.length >= 80) break;
  }
  return out;
})()`;

const COLLECT_FIELDS = `(() => {
  const out = [];
  for (const el of Array.from(document.querySelectorAll('input, select, textarea'))) {
    if (el.type === 'hidden') continue;
    const id = el.getAttribute('id');
    const lbl = id ? document.querySelector('label[for="' + CSS.escape(id) + '"]') : null;
    const label =
      el.getAttribute('aria-label') ||
      (lbl && lbl.textContent && lbl.textContent.trim()) ||
      (el.closest('label') && el.closest('label').textContent.trim()) ||
      el.getAttribute('placeholder') ||
      el.getAttribute('name') ||
      '';
    if (!label) continue;
    out.push({
      label: label.slice(0, 60),
      type: el.type || el.tagName.toLowerCase(),
      required: !!el.required || el.getAttribute('aria-required') === 'true',
    });
    if (out.length >= 40) break;
  }
  return out;
})()`;

describe('recon probe', () => {
  for (const pagePath of PATHS) {
    it(`recon ${pagePath}`, async () => {
      const url = BASE_URL ? new URL(pagePath, BASE_URL).toString() : pagePath;
      const t0 = Date.now();
      await browser.url(url);
      const loadTimeMs = Date.now() - t0;

      const name = slug(pagePath);
      const shot = path.join(SHOTS_DIR, `recon-${name}.png`);
      await browser.saveScreenshot(shot);

      const status = await browser.execute(
        () => window.performance.getEntriesByType('navigation')[0]?.responseStatus ?? null,
      );
      const headings = await browser.execute(() =>
        Array.from(document.querySelectorAll('h1, h2, h3'))
          .slice(0, 30)
          .map((e) => `${e.tagName}: ${(e.textContent ?? '').trim().slice(0, 70)}`),
      );
      const internalLinks = await browser.execute(() =>
        Array.from(
          new Set(
            Array.from(document.querySelectorAll('a[href]')).map((e) => e.getAttribute('href') ?? ''),
          ),
        ).slice(0, 60),
      );
      const imagesWithoutAlt = await browser.execute(
        () => document.querySelectorAll('img:not([alt])').length,
      );

      const finding = {
        path: pagePath,
        url,
        status,
        title: await browser.getTitle(),
        load_time_ms: loadTimeMs,
        headings,
        controls: await browser.execute(COLLECT_CONTROLS),
        form_fields: await browser.execute(COLLECT_FIELDS),
        images_without_alt: imagesWithoutAlt,
        internal_links: internalLinks,
        console_errors: [],
        failed_requests: [],
        screenshot: shot,
      };

      fs.writeFileSync(path.join(PARTS_DIR, `${name}.json`), JSON.stringify(finding, null, 2));
    });
  }
});

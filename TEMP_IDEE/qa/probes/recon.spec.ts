/**
 * Aufklaerungs-Probe fuer Playbook 02.
 *
 * Faehrt die angegebenen Pfade an und schreibt pro Seite eine Teildatei nach
 * qa/runs/<TICKET>/<RUN_TS>/recon-parts/. Danach merge-recon.mjs ausfuehren.
 *
 * Aufruf:
 *   TICKET=PROJ-1234 \
 *   RUN_TS=2026-09-24T1130 \
 *   BASE_URL=https://stage.example.com \
 *   PROBE_PATHS=/warenkorb,/checkout \
 *   npx playwright test qa/probes/recon.spec.ts --reporter=line
 *
 * Optional:
 *   STORAGE_STATE=qa/.auth/user.json   angemeldet aufklaeren
 *   VIEWPORT=1440x900
 *
 * Diese Datei ist Infrastruktur, kein Testfall. Sie behauptet nichts,
 * sie beobachtet nur. Deshalb keine Assertions ausser der Erreichbarkeit.
 */
import { test, expect, type Page } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

const TICKET = process.env.TICKET ?? 'UNSPEC';
const RUN_TS = process.env.RUN_TS ?? new Date().toISOString().slice(0, 16).replace(/[:-]/g, (m) => (m === ':' ? '' : '-'));
const BASE_URL = process.env.BASE_URL ?? '';
const PATHS = (process.env.PROBE_PATHS ?? '/').split(',').map((p) => p.trim()).filter(Boolean);
const [VW, VH] = (process.env.VIEWPORT ?? '1440x900').split('x').map(Number);

const RUN_DIR = path.join('qa', 'runs', TICKET, RUN_TS);
const PARTS_DIR = path.join(RUN_DIR, 'recon-parts');
const EVIDENCE_DIR = path.join('qa', 'evidence', TICKET, RUN_TS);

fs.mkdirSync(PARTS_DIR, { recursive: true });
fs.mkdirSync(EVIDENCE_DIR, { recursive: true });

const slug = (p: string) => p.replace(/[^a-zA-Z0-9]+/g, '-').replace(/^-|-$/g, '') || 'root';

/** Bedienelemente ueber Rolle und zugaenglichen Namen erfassen. */
async function bedienelemente(page: Page) {
  return page.evaluate(() => {
    const sichtbar = (el: Element) => {
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

    const rolle = (el: Element): string => {
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
    const out: { rolle: string; name: string }[] = [];

    for (const el of Array.from(document.querySelectorAll(sel))) {
      if (!sichtbar(el)) continue;
      const r = rolle(el);
      const n = name(el);
      if (!n) continue;
      const key = `${r}|${n}`;
      if (seen.has(key)) continue;
      seen.add(key);
      out.push({ rolle: r, name: n });
      if (out.length >= 80) break;
    }
    return out;
  });
}

async function formularfelder(page: Page) {
  return page.evaluate(() => {
    const out: { label: string; typ: string; pflicht: boolean }[] = [];
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
        typ: input.type || el.tagName.toLowerCase(),
        pflicht: input.required || input.getAttribute('aria-required') === 'true',
      });
      if (out.length >= 40) break;
    }
    return out;
  });
}

test.use({ viewport: { width: VW, height: VH } });

for (const pfad of PATHS) {
  test(`recon ${pfad}`, async ({ page }) => {
    const konsolenfehler: string[] = [];
    const fehlerhafteRequests: string[] = [];

    page.on('console', (m) => {
      if (m.type() === 'error') konsolenfehler.push(m.text().slice(0, 200));
    });
    page.on('pageerror', (e) => konsolenfehler.push(`pageerror: ${e.message}`.slice(0, 200)));
    page.on('response', (r) => {
      if (r.status() >= 400) fehlerhafteRequests.push(`${r.status()} ${r.url().slice(0, 160)}`);
    });

    const url = BASE_URL ? new URL(pfad, BASE_URL).toString() : pfad;
    const t0 = Date.now();
    const resp = await page.goto(url, { waitUntil: 'domcontentloaded' });
    await page.waitForLoadState('networkidle', { timeout: 15_000 }).catch(() => {});
    const ladezeit_ms = Date.now() - t0;

    const name = slug(pfad);
    const shot = path.join(EVIDENCE_DIR, `00-recon-${name}.png`);
    await page.screenshot({ path: shot, fullPage: true });

    const befund = {
      pfad,
      url,
      status: resp?.status() ?? null,
      titel: await page.title(),
      ladezeit_ms,
      meta_description:
        (await page.locator('meta[name="description"]').first().getAttribute('content').catch(() => null)) ?? null,
      lang: await page.locator('html').first().getAttribute('lang').catch(() => null),
      ueberschriften: await page
        .locator('h1, h2, h3')
        .evaluateAll((els) =>
          els.slice(0, 30).map((e) => `${e.tagName}: ${(e.textContent ?? '').trim().slice(0, 70)}`),
        ),
      bedienelemente: await bedienelemente(page),
      formularfelder: await formularfelder(page),
      bilder_ohne_alt: await page.locator('img:not([alt])').count(),
      interne_links: await page
        .locator('a[href]')
        .evaluateAll((els) =>
          Array.from(new Set(els.map((e) => (e as HTMLAnchorElement).getAttribute('href') ?? ''))).slice(0, 60),
        ),
      konsolenfehler,
      fehlerhafte_requests: fehlerhafteRequests,
      screenshot: shot,
    };

    fs.writeFileSync(path.join(PARTS_DIR, `${name}.json`), JSON.stringify(befund, null, 2));

    // Einzige Behauptung dieser Datei: die Seite war ueberhaupt erreichbar.
    expect(resp?.status(), `${pfad} nicht erreichbar`).toBeLessThan(400);
  });
}

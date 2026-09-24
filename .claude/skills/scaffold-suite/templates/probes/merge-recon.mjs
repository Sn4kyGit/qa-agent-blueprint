#!/usr/bin/env node
/**
 * Merges the part files from recon.spec.ts into <RUN_DIR>/recon.json and
 * prints a compact summary to stdout.
 *
 * Usage: node probes/merge-recon.mjs <RUN_DIR>
 *
 * Token rule (docs/pipeline/02-recon.md): only this stdout summary enters the
 * context — never the part files, never the full recon.json. Read targeted
 * page sections from recon.json when the test plan needs them.
 */
import fs from 'node:fs';
import path from 'node:path';

const [runDir] = process.argv.slice(2);
if (!runDir) {
  console.error('Usage: node probes/merge-recon.mjs <RUN_DIR>');
  process.exit(1);
}

const partsDir = path.join(runDir, 'recon-parts');

if (!fs.existsSync(partsDir)) {
  console.error(`No part files under ${partsDir}. Did recon.spec.ts run?`);
  process.exit(1);
}

const pages = fs
  .readdirSync(partsDir)
  .filter((f) => f.endsWith('.json'))
  .map((f) => JSON.parse(fs.readFileSync(path.join(partsDir, f), 'utf8')))
  .sort((a, b) => a.path.localeCompare(b.path));

const recon = {
  source: 'probe',
  created: new Date().toISOString().slice(0, 16),
  base_url: pages[0]?.url?.replace(pages[0]?.path, '') ?? null,
  pages,
};

const target = path.join(runDir, 'recon.json');
fs.writeFileSync(target, JSON.stringify(recon, null, 2));

// Compact summary: this is all that enters the context window.
const problems = pages.flatMap((s) => [
  ...s.console_errors.map((k) => `${s.path}  CONSOLE  ${k}`),
  ...s.failed_requests.map((r) => `${s.path}  REQUEST  ${r}`),
  ...(s.images_without_alt > 0 ? [`${s.path}  A11Y     ${s.images_without_alt} images without alt`] : []),
  ...(s.load_time_ms > 3000 ? [`${s.path}  LOADTIME ${s.load_time_ms} ms`] : []),
]);

console.log(`recon.json written: ${target}`);
console.log(`Pages: ${pages.length}`);
for (const s of pages) {
  console.log(`  ${s.path}  [${s.status}]  "${s.title}"  ${s.controls.length} controls, ${s.form_fields.length} fields`);
}
console.log(problems.length ? `\nObservations:\n${problems.map((p) => '  ' + p).join('\n')}` : '\nNo observations.');

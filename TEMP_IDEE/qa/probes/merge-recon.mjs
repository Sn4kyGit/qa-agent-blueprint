#!/usr/bin/env node
/**
 * Fuehrt die Teildateien aus recon.spec.ts zu qa/runs/<TICKET>/<RUN_TS>/recon.json zusammen
 * und gibt eine kompakte Zusammenfassung auf stdout aus.
 *
 * Aufruf: node qa/probes/merge-recon.mjs PROJ-1234 2026-09-24T1130
 */
import fs from 'node:fs';
import path from 'node:path';

const [ticket, runTs] = process.argv.slice(2);
if (!ticket || !runTs) {
  console.error('Aufruf: node qa/probes/merge-recon.mjs <TICKET> <RUN_TS>');
  process.exit(1);
}

const runDir = path.join('qa', 'runs', ticket, runTs);
const partsDir = path.join(runDir, 'recon-parts');

if (!fs.existsSync(partsDir)) {
  console.error(`Keine Teildateien unter ${partsDir}. Lief recon.spec.ts?`);
  process.exit(1);
}

const seiten = fs
  .readdirSync(partsDir)
  .filter((f) => f.endsWith('.json'))
  .map((f) => JSON.parse(fs.readFileSync(path.join(partsDir, f), 'utf8')))
  .sort((a, b) => a.pfad.localeCompare(b.pfad));

const recon = {
  quelle: 'probe',
  ticket,
  erstellt: new Date().toISOString().slice(0, 16),
  base_url: seiten[0]?.url?.replace(seiten[0]?.pfad, '') ?? null,
  seiten,
};

const ziel = path.join(runDir, 'recon.json');
fs.writeFileSync(ziel, JSON.stringify(recon, null, 2));

// Kompakte Zusammenfassung: das ist alles, was ins Kontextfenster muss.
const probleme = seiten.flatMap((s) => [
  ...s.konsolenfehler.map((k) => `${s.pfad}  KONSOLE  ${k}`),
  ...s.fehlerhafte_requests.map((r) => `${s.pfad}  REQUEST  ${r}`),
  ...(s.bilder_ohne_alt > 0 ? [`${s.pfad}  A11Y     ${s.bilder_ohne_alt} Bilder ohne alt`] : []),
  ...(s.ladezeit_ms > 3000 ? [`${s.pfad}  LADEZEIT ${s.ladezeit_ms} ms`] : []),
]);

console.log(`recon.json geschrieben: ${ziel}`);
console.log(`Seiten: ${seiten.length}`);
for (const s of seiten) {
  console.log(`  ${s.pfad}  [${s.status}]  "${s.titel}"  ${s.bedienelemente.length} Bedienelemente, ${s.formularfelder.length} Felder`);
}
console.log(probleme.length ? `\nAuffaelligkeiten:\n${probleme.map((p) => '  ' + p).join('\n')}` : '\nKeine Auffaelligkeiten.');

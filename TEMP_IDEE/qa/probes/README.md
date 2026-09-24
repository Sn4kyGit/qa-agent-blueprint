# Probes

Wegwerf-Skripte fuer die Aufklaerungsphase (Playbook 02). Sie behaupten nichts,
sie beobachten nur. Testfaelle gehoeren nach `tests/e2e/`, nicht hierher.

## recon.spec.ts

Faehrt Pfade an und erfasst, was tatsaechlich auf der Seite ist: Titel,
Ueberschriftenstruktur, Bedienelemente mit Rolle und zugaenglichem Namen,
Formularfelder, Bilder ohne Alt-Text, Links, Konsolenfehler, fehlerhafte
Requests, Ladezeit, Screenshot.

```bash
TICKET=PROJ-1234 \
RUN_TS=$(date +%Y-%m-%dT%H%M) \
BASE_URL=https://stage.example.com \
PROBE_PATHS=/warenkorb,/checkout \
npx playwright test qa/probes/recon.spec.ts --reporter=line

node qa/probes/merge-recon.mjs PROJ-1234 <RUN_TS>
```

Angemeldet aufklaeren: `STORAGE_STATE=qa/.auth/user.json` setzen und in der
Playwright-Konfiguration verwenden.

## Warum das vor der Spec kommt

Die entstehende `recon.json` enthaelt die **realen** Selektoren. Eine Spec, die
daraus gebaut wird, raet nicht. Das ist die haeufigste Ursache dafuer, dass
CLI-Ergebnisse schlechter ausfallen als Live-Beobachtung.

## Tokenregel

Nur die Ausgabe von `merge-recon.mjs` ins Kontextfenster nehmen, nicht die
Teildateien und nicht `recon.json` vollstaendig. Aus `recon.json` gezielt die
Seiten lesen, die fuer den Testplan gebraucht werden.

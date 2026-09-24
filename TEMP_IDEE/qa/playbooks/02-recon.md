# Playbook 02 – Aufklaerung

Ziel: wissen, was auf der Seite tatsaechlich da ist, **bevor** ein Testfall
oder eine Spec formuliert wird. Dieses Playbook verhindert blind geratene
Selektoren, die haeufigste Ursache wertloser CLI-Ergebnisse.

## Werkzeugwahl

| Situation | Werkzeug |
|-----------|----------|
| Inhalt, Struktur, Links, Konsolenfehler | Probe-Skript |
| Flow mit unklarer Interaktion | MCP-Session |
| Nicht reproduzierbarer Bug | MCP-Session |
| Visuelle Beurteilung | MCP-Session |
| `mode: mcp-only` | immer MCP |
| `mode: cli-first` | `recon.json` des letzten Laufs wiederverwenden |

## Probe-Skript (Standard)

```bash
TICKET=PROJ-1234 \
RUN_TS=2026-09-24T1130 \
BASE_URL=https://stage.example.com \
PROBE_PATHS=/warenkorb,/checkout \
npx playwright test qa/probes/recon.spec.ts --reporter=line

node qa/probes/merge-recon.mjs PROJ-1234 2026-09-24T1130
```

Das Skript faehrt die Pfade an und schreibt je Seite eine Teildatei. Der
Merge-Schritt erzeugt daraus `recon.json`. Die Ausgabe ist bewusst kompakt:
zehn Seiten kosten weniger Tokens als drei MCP-Klicks.

**Nie** die kompletten Teildateien ins Kontextfenster laden. Nur `recon.json`
lesen, und davon nur die Abschnitte, die fuer den Testplan gebraucht werden.

## MCP-Session

Wenn eine MCP-Session noetig ist, laeuft sie **immer in einem isolierten
Unteragenten** (`qa-observer`), damit die Seiten-Snapshots nicht die
Hauptsitzung fuellen. Obergrenze aus `mcp.max_turns`.

Ablauf: zur tiefen URL direkt navigieren statt sich durchzuklicken. Jeden
Schritt einzeln. Screenshot nur an Stellen, die in den Report kommen. Der
Unteragent gibt `recon.json` zurueck, keine Snapshots.

## Ausgabe: `recon.json`

```json
{
  "quelle": "probe",
  "erstellt": "2026-09-24T11:30",
  "base_url": "https://stage.example.com",
  "seiten": [
    {
      "pfad": "/checkout",
      "titel": "Kasse",
      "status": 200,
      "ueberschriften": ["H1: Kasse", "H2: Zahlungsart"],
      "bedienelemente": [
        { "rolle": "textbox", "name": "Rabattcode" },
        { "rolle": "button", "name": "Code einloesen" },
        { "rolle": "button", "name": "Jetzt kaufen" }
      ],
      "formularfelder": [
        { "label": "Rabattcode", "typ": "text", "pflicht": false }
      ],
      "bilder_ohne_alt": 0,
      "konsolenfehler": [],
      "fehlerhafte_requests": [],
      "screenshot": "qa/evidence/PROJ-1234/2026-09-24T1130/00-checkout.png"
    }
  ]
}
```

## Verfallsdatum

Liefert ein neuer Probe-Lauf andere `bedienelemente` als die gespeicherte
`recon.json`, gilt die zugehoerige Spec als veraltet. Dann wird die Aufklaerung
wiederholt, nicht die Spec nachgeflickt.

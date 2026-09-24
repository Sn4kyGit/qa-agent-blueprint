# Playbook 04 – Ausfuehrung

## Vorbedingung

Verifizieren, dass `intake.erwarteter_build` tatsaechlich auf der Zielumgebung
live ist: Versions-Endpunkt, Build-Info in der UI, oder ein im Fix enthaltenes
sichtbares Merkmal. Ein Test gegen den alten Stand liefert ein sauber
aussehendes, falsches Ergebnis. Bei Zweifel: `BLOCKED`.

## Spec schreiben (hybrid, cli-first)

Die Spec entsteht aus `testplan.md` **und** `recon.json`. Selektoren werden aus
`recon.json` uebernommen, nie geraten.

### Selektor-Rangfolge

1. `getByRole(rolle, { name })` – erste Wahl, prueft nebenbei die Zugaenglichkeit
2. `getByLabel` / `getByPlaceholder` – Formularfelder
3. `getByText` – nur bei eindeutigem, stabilem Text
4. `getByTestId` – wenn nichts davon greift, dann `data-testid` beim Dev anfragen
5. CSS/XPath – nur mit begruendetem Kommentar

Nie: generierte Klassennamen, `nth-child`, Pfade ueber die DOM-Struktur.

### Assertion-Regeln

- **Positiv und spezifisch.** Nicht "kein Fehler sichtbar", sondern was
  stattdessen sichtbar sein soll. Nicht Existenz, sondern konkreter Text, Wert
  oder Zustand.
- Negative Assertions nur ergaenzend, nie als einziger Nachweis eines
  Akzeptanzkriteriums.
- Nur Web-First-Assertions (`await expect(...)`), die automatisch warten.
- Keine festen Wartezeiten. Gewartet wird auf Zustand, Response oder Element.

### AK-Bindung

Jeder Test traegt die ID des Kriteriums im Titel:

```ts
test('AK2: Rabattcode wird bei unterschrittenem Mindestbestellwert abgelehnt',
  async ({ page }) => { /* ... */ });
```

Ohne diese Bindung ist im Report nicht nachvollziehbar, was abgedeckt wurde,
und der Runner kann einen Fehlschlag nicht einordnen.

### Isolation

Jeder Test legt eigene Testdaten an und raeumt auf. Login ueber gespeicherten
Storage-State, nicht ueber die UI (ausser der Login selbst wird getestet).
Tests muessen in beliebiger Reihenfolge laufen.

## Ausfuehren

```bash
npx playwright test tests/e2e/checkout --reporter=line
npx playwright test -g "AK2:" --reporter=line
npx playwright test --grep @smoke --reporter=line
```

Immer im Unteragenten `qa-runner`. Die Rohausgabe bleibt dort, zurueck kommt
nur das verdichtete Ergebnis. `--reporter=line` ist Standard; `html` nur, wenn
ein Mensch den Report ansieht.

## Beobachtungskanal

Unabhaengig von den Assertions sammelt jeder Lauf mit: Konsolenfehler,
Responses ab Status 400, Ladezeiten ueber Schwellwert, Screenshot am Ende jedes
Tests. Diese Befunde landen im Report unter `Auffaelligkeiten`, auch bei
komplett gruenem Lauf. Das ersetzt einen Teil des mitlaufenden Blicks, den eine
Live-Session von selbst hat.

## MCP-Ausfuehrung (mcp-only, eskalierte Faelle)

Testfaelle live durchspielen, Evidenz **im Moment der Beobachtung** sichern.
Bei jeder Abweichung sofort Screenshot, Konsole und relevante Response
sichern, bevor weitergeklickt wird. Der Zustand ist danach meist weg, und ein
nachgestellter Screenshot ist kein Nachweis.

## Ausgabe: `run.json`

```json
{
  "kommando": "npx playwright test tests/e2e/checkout --reporter=line",
  "modus": "hybrid",
  "dauer_s": 47,
  "ergebnis": { "passed": 4, "failed": 1, "skipped": 0, "flaky": 0 },
  "faelle": [
    { "ak": "AK1", "titel": "...", "status": "PASS",
      "evidenz": "qa/evidence/PROJ-1234/2026-09-24T1130/01-rabatt-ok.png" },
    { "ak": "AK2", "titel": "...", "status": "FAIL",
      "kern": "expected 'Mindestbestellwert nicht erreicht' to be visible",
      "artefakt": "test-results/checkout-AK2/trace.zip" }
  ],
  "beobachtungskanal": {
    "konsolenfehler": ["TypeError: cannot read property 'total' of undefined"],
    "fehlerhafte_requests": ["500 /api/discount/validate"],
    "langsame_seiten": []
  }
}
```

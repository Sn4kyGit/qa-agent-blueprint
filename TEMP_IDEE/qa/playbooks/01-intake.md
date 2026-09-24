# Playbook 01 – Ticket-Intake

Ziel: aus einem Ticket einen pruefbaren Testauftrag machen.

## Felder gezielt holen

Nicht das ganze Ticket mit Historie. Nur: `summary`, `description`,
`issuetype`, `status`, `priority`, `fixVersions`, `components`, `labels`,
Akzeptanzkriterien-Feld, verlinkte Issues, Anhangsnamen, **letzte drei**
Kommentare.

## Akzeptanzkriterien nummerieren

Jedes Kriterium bekommt eine ID (`AK1`, `AK2`, ...). Diese IDs tragen sich
durch Testplan, Spec-Titel, Lauf und Report. Ohne sie ist spaeter nicht
nachvollziehbar, was abgedeckt wurde.

Fehlen Akzeptanzkriterien vollstaendig, ist das der erste Befund und wird
gemeldet, bevor getestet wird.

## Testbarkeit pruefen

- Ist die Erwartung eindeutig oder interpretierbar?
- Umgebung, Rolle und Testuser bekannt?
- Ist der Stand deployed? Steht eine Version oder ein Commit im Ticket?
- Gibt es blockierende verlinkte Tickets?
- Sind Testdaten vorhanden oder muessen sie angelegt werden?

Offene Punkte werden **gebuendelt** zurueckgefragt, nicht einzeln. Bei mehreren
Tickets: nach betroffenem Bereich gruppieren, damit spaeter eine Browser-Session
mehrere Tickets abdeckt.

## Risiko einschaetzen

Drei Stufen (`low`, `medium`, `high`) aus Eintrittswahrscheinlichkeit mal
Schadenshoehe. Diese Einschaetzung steuert die Eskalation und ob das starke
Modell fuer die Planung eingesetzt wird.

## Ausgabe: `intake.json`

```json
{
  "ticket": "PROJ-1234",
  "typ": "story",
  "titel": "Rabattcode im Checkout",
  "risiko": "high",
  "bereich": "checkout",
  "akzeptanzkriterien": [
    { "id": "AK1", "text": "Gueltiger Code reduziert den Gesamtbetrag" },
    { "id": "AK2", "text": "Unter Mindestbestellwert wird der Code abgelehnt" }
  ],
  "umgebung": "stage",
  "erwarteter_build": "release-24.9",
  "betroffene_pfade": ["/warenkorb", "/checkout"],
  "testbar": true,
  "offene_fragen": [],
  "vorwissen": "PROJ-1180 hatte hier bereits einen Rundungsfehler"
}
```

`betroffene_pfade` ist die Eingabe fuer Phase 2. Wenn sie nicht aus dem Ticket
ableitbar sind, aus `qa/PROJECT-MAP.md` ergaenzen.

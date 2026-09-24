# QA-Pipeline

Agentischer Testablauf fuer Claude Code und OpenCode: Ticket rein,
belegtes Testergebnis raus.

Konzept: `docs/TESTING-PIPELINE.md`
Einbau: `docs/SETUP.md`

## Kernidee

Drei Betriebsmodi, umschaltbar ueber eine Zeile in `qa/qa-config.yml`:

- `mcp-only` – Modell steuert den Browser live. Hoechste Befundtiefe, hoechste Kosten.
- `hybrid` – Aufklaerung beobachtet, Ausfuehrung ueber Specs, Verifikation live. Voreinstellung.
- `cli-first` – Specs laufen, live wird nur bei Fehlschlag geschaut.

Der Hybridmodus traegt qualitativ nur mit vier Regeln: keine blind
geschriebene Spec, positive und spezifische Assertions, Rotprobe vor dem
ersten Gruen, Beobachtungskanal in jedem Lauf. Ohne sie faellt er hinter
`mcp-only` zurueck. Details in Abschnitt 2 des Konzepts.

## Aufbau

Das Ablaufwissen liegt werkzeugneutral in `qa/playbooks/`. Die Adapter unter
`.claude/` und `.opencode/` verweisen nur darauf. Die Phasen tauschen Daten
ueber Dateien in `qa/runs/` aus, nicht ueber den Gespraechsverlauf — deshalb
funktioniert der Ablauf ueber Agenten-, Modell- und Werkzeugwechsel hinweg und
setzt nach einem Abbruch wieder auf.

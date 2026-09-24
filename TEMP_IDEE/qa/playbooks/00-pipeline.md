# Playbook 00 – Ablaufsteuerung

Einstiegspunkt der QA-Pipeline. Alle Werkzeuge starten hier.

## Vor allem anderen

1. `qa/qa-config.yml` lesen. Der dort gesetzte `mode` steuert den ganzen Lauf.
2. Laufverzeichnis anlegen: `qa/runs/<TICKET>/<zeitstempel>/`.
   Zeitstempel im Format aus der Konfiguration, z.B. `2026-09-24T1130`.
3. Falls vorhanden, Projektwissen laden: `qa/PROJECT-MAP.md`,
   `qa/known-issues.md`. Den Anwendungscode **nicht** durchsuchen.

## Phasen

| Phase | Playbook | Ausgabe |
|-------|----------|---------|
| 1 Intake | `01-intake.md` | `intake.json` |
| 2 Aufklaerung | `02-recon.md` | `recon.json` |
| 3 Planung | `03-planning.md` | `testplan.md` (Freigabe noetig) |
| 4 Ausfuehrung | `04-execution.md` | `run.json` + Evidenz |
| 5 Verifikation | `05-verification.md` | `verdict.json` |
| 6 Reporting | `06-reporting.md` | Ticketkommentar + Journal |

Jede Phase liest die Ausgabe der vorherigen **aus der Datei**, nicht aus dem
Gespraechsverlauf. So bleibt der Ablauf ueber Agenten-, Modell- und
Werkzeugwechsel hinweg stabil und kann nach einem Abbruch wieder aufsetzen.

## Werkzeugbelegung nach Modus

| Phase | mcp-only | hybrid | cli-first |
|-------|----------|--------|-----------|
| 2 Aufklaerung | MCP-Session | Probe, MCP nur bei unklarer Interaktion | entfaellt, `recon.json` aus dem letzten Lauf |
| 4 Ausfuehrung | MCP live | Spec ueber CLI | Spec ueber CLI |
| 5 Verifikation | entfaellt, war live | Rotprobe + Beobachtungslauf | Rotprobe, MCP nur bei Fehlschlag |

## Eskalation

Unabhaengig vom Modus wird live beobachtet, wenn:

- das Risiko `hybrid.escalate_at_risk` erreicht
- das Ticket visuell oder gestalterisch gepraegt ist
- fuer den Bereich keine `recon.json` existiert
- ein CLI-Lauf fehlschlaegt und die Ursache nicht eindeutig ist
- ein Testfall sich nicht als Assertion formulieren laesst, ohne das
  Akzeptanzkriterium zu verkuerzen
- ein Bug nicht reproduzierbar ist

Nicht eskaliert wird, nur weil ein Test rot ist. Ein eindeutig eingeordneter
Fehlschlag braucht keine Browser-Session.

## Harte Regeln

- Kein Testergebnis ohne Evidenz. Fehlt sie, lautet der Status `BLOCKED`.
- Nie gegen eine Umgebung aus `environments.forbidden` testen oder deployen.
- Vor Phase 4 verifizieren, dass der erwartete Stand tatsaechlich deployed ist.
- Zugangsdaten nie ausgeben, loggen, in Dateien schreiben oder anhaengen.
- Phase 3 wird freigegeben, bevor Phase 4 startet.

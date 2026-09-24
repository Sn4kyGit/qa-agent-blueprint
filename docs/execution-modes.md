# Execution Modes — wer sitzt am Steuer?

Seit 0.12.0 entscheidet eine Zeile in der Projektdatei, **wie** der Agent ein
Ticket testet: live per Maus und Auge (Playwright MCP), oder über ein vorher
geschriebenes Test-Skript (Playwright/WDIO CLI). Diese Seite erklärt die drei
Modi, was der Umbau bringt und wie du umstellst.

---

## Das Problem vorher

Bisher lief jeder Ticket-Test live über MCP: Das Modell steuert den Browser
Schritt für Schritt, sieht alles — und jeder Schritt kostet Kontext. Bei vielen
oder langen Tickets sind die Nutzungslimits so spürbar schnell erreicht.

Die Alternative — nur Skripte laufen lassen — ist zwar billig, aber blind: Eine
Spec prüft nur, was jemand hineingeschrieben hat. Den abgeschnittenen Text, den
doppelten Spinner oder den Konsolenfehler bemerkt sie nicht.

## Was der Umbau ermöglicht

Der Agent kann jetzt **beides taktisch mischen**, projektweit voreingestellt
und pro Ticket überschreibbar:

- **Recon-Probe** (`/recon`): Ein Wegwerf-Skript fährt die betroffenen Seiten
  an und liefert die *echten* Bedienelemente, Formularfelder, Konsolenfehler
  und Screenshots — für einen Bruchteil der MCP-Kosten. Specs werden daraus
  gebaut statt geraten.
- **Rotprobe**: Eine neue Spec muss einmal nachweislich rot gewesen sein
  (Erwartung absichtlich verletzt), bevor ihr Grün als Nachweis zählt. Das
  fängt die komplette Klasse „grün, prüft aber nichts" ab.
- **Beobachtungslauf**: Nach einem grünen Skript-Lauf schaut das Modell einmal
  kurz live über den Hauptflow — ausdrücklich mit dem Auftrag, auf alles zu
  achten, was *nicht* in den Assertions steht.
- **Modus im Report**: Jeder JIRA-Kommentar trägt die Zeile
  `Mode: <mcp-only|hybrid|cli-first>` — wer das Ergebnis später bewertet, weiß,
  ob live beobachtet oder nur assertiert wurde.

Nettoeffekt: deutlich weniger Token-Verbrauch pro Ticket bei nahezu gleicher
Befundtiefe — die Limits werden später erreicht, und ab dem ersten Retest
existiert eine wiederholbare Spec.

## Die drei Modi

| Modus | Wie getestet wird | Stärke | Kosten | Wann |
|---|---|---|---|---|
| `mcp-only` | Modell steuert live, jeder Schritt | höchste Befundtiefe, findet Unerwartetes | hoch | neues Projekt ohne Suite, explorative Aufträge, visuelle Tickets, hohe Risiken |
| `hybrid` (Standard) | Probe → Spec per CLI → kurzer Live-Check | nahe an MCP-Qualität | mittel | der Normalfall; rechnet sich ab dem ersten Retest |
| `cli-first` | nur die bestehende Suite; MCP nur bei unklarem Fehlschlag | schnell, CI-tauglich | niedrig | gepflegte Suite, Regression, Pipeline, viele Tickets mit niedrigem Risiko |

**Eskalation gilt immer**, egal welcher Modus eingestellt ist: Bei hohem
Ticket-Risiko, visuellen/gestalterischen Tickets, fehlender Recon für den
Bereich, unklarem Fehlschlag oder nicht reproduzierbaren Bugs wird automatisch
live beobachtet. Umgekehrt wird *nicht* eskaliert, nur weil ein Test rot ist —
ein eindeutig eingeordneter Fehlschlag braucht keine Browser-Session.

## Umstellen / benutzen

### Pro Projekt (einmalig)

In `projects/<KEY>/PROJECT.md`, Abschnitt **Execution mode**:

```markdown
## Execution mode

- **Mode**: `hybrid`          ← mcp-only | hybrid | cli-first
- **Verification pass**: `yes` ← kurzer Live-Check nach grünem CLI-Lauf
- **Red check required**: `yes` ← neue Specs müssen einmal rot nachgewiesen sein
- **Escalate at risk**: `high` ← ab diesem Risiko immer live
- **Plan approval**: `yes`     ← Testplan wird vor Ausführung gezeigt und bestätigt
```

**Bestandsprojekte:** einfach `/re-board <KEY>` laufen lassen — der Dialog
bietet die neue Sektion an, `hybrid` ist die empfohlene Voreinstellung.

**Neue Projekte:** `/onboard-project` fragt den Modus direkt mit ab (eine
Frage, Rest sind Defaults).

### Pro Ticket (jederzeit)

Der Projekt-Modus ist nur der Default. Im Chat überschreiben:

- „teste SHOP-123 mal **komplett live**" → mcp-only für diesen Lauf
- „dafür reicht die Suite" → cli-first für diesen Lauf

### Einzeln nutzbar

`/recon SHOP-123` — nur die Aufklärung: schreibt `recon.json` (echte Selektoren,
Konsolenfehler, Screenshots) ins Run-Verzeichnis. Ideal bevor du eine Spec
schreiben lässt.

## Was sich NICHT ändert

- **Evidence bleibt Pflicht**: kein Ergebnis ohne
  `evidence/<KEY>/<TICKET>/<ts>/` inkl. `execution_summary.json` — der
  Stop-Hook prüft das weiter.
- **Shadow Mode** bleibt an, bis du ihn im Projekt ausschaltest.
- **Report-Format** (Cloud = ADF, Data Center = Wiki-Markup) unverändert.
- **Playwright UND WebdriverIO** werden unterstützt — die Probe gibt es in
  beiden Varianten mit demselben Ergebnisformat.

## Hintergrund für Neugierige

Die technische Beschreibung (Phasen, Datei-Verträge, Eskalationsregeln im
Detail) liegt in `docs/pipeline/` — beginnend mit `00-overview.md`.

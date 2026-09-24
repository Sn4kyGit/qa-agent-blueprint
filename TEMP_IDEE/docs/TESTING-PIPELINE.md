# Testablauf: MCP, CLI und der Weg dazwischen

Konzept für den agentischen Testablauf im QA-Blueprint.
Werkzeugneutral formuliert, lauffähig unter Claude Code und OpenCode.

---

## 1. Zweck

Ein Ticket kommt rein, ein belegtes Testergebnis kommt raus. Dazwischen liegen
Planung, Ausführung im Browser und Reporting. Die offene Frage ist nicht *ob*
ein Browser gesteuert wird, sondern **wer während der Ausführung am Steuer
sitzt** — das Modell live über MCP, oder ein vorher geschriebenes Skript über
die Playwright-CLI.

Beides steuert denselben echten Browser. Der Unterschied liegt in Kosten,
Wiederholbarkeit und Ergebnisqualität. Dieses Dokument beschreibt, wie beide
kombiniert werden und wie der Anwender die Mischung selbst festlegt.

---

## 2. Warum CLI-Ergebnisse oft schlechter ausfallen

Das ist eine reale, gut erklärbare Beobachtung und kein Anwendungsfehler. Sechs
Ursachen, in der Reihenfolge ihrer Bedeutung:

**Eine Spec prüft nur, was hineingeschrieben wurde.** Ein Modell, das live durch
die Seite läuft, bemerkt nebenbei den abgeschnittenen Text, den doppelten
Spinner, die Fehlermeldung in der Konsole, das verrutschte Layout. Eine Spec ist
für alles blind, was nicht als Assertion formuliert ist. Das ist der Hauptgrund.

**Blind geschriebene Selektoren.** Wird eine Spec verfasst, ohne die Seite je
gesehen zu haben, sind die Selektoren geraten. Im besten Fall bricht der Test
sofort. Im schlechteren Fall trifft er versehentlich ein anderes Element und
wird grün.

**Falsch-Grün durch negative Assertions.** `expect(page.locator('.error'))
.toHaveCount(0)` ist grün, wenn der Fehler auftritt, die CSS-Klasse aber
umbenannt wurde. Negative Assertions sind die häufigste Quelle wertloser grüner
Läufe.

**Akzeptanzkriterien werden beim Übersetzen platt gedrückt.** „Der Nutzer
erhält eine verständliche Fehlermeldung" wird zu `toBeVisible()`. Getestet wird
danach die Existenz, nicht die Verständlichkeit. Das Kriterium gilt formal als
abgedeckt, inhaltlich ist es das nicht.

**Kein Urteil beim Fehlschlag.** Der Runner meldet „Assertion in Zeile 34
fehlgeschlagen". Ob die Anwendung falsch ist oder der Test, kann er ohne die
Akzeptanzkriterien im Kontext nicht sagen. Genau diese Einordnung ist aber der
eigentliche Wert eines Testlaufs.

**Wartelogik blind geschrieben.** Ohne das reale Ladeverhalten gesehen zu haben,
entstehen Timing-Annahmen, die im Zweifel zu festen Wartezeiten führen und
später als Flake zurückkommen.

### Die Konsequenz

Der Fehler liegt nicht in der CLI, sondern in der Annahme, eine Spec könne ohne
Anschauung entstehen und ein grüner Lauf sei ein Nachweis. Daraus folgen vier
Regeln, die im Hybridmodus verbindlich sind:

1. Eine Spec wird **nie blind** geschrieben. Vorher steht immer eine
   Beobachtung — MCP-Session oder Probe-Skript.
2. Jede Assertion ist **positiv und spezifisch** und trägt die ID des
   Akzeptanzkriteriums, das sie abdeckt.
3. Jede Spec besteht die **Rotprobe**, bevor ihr Grün zählt (siehe Abschnitt 7).
4. Jeder Lauf trägt einen **Beobachtungskanal** mit: Konsolenfehler,
   fehlerhafte Requests, Screenshot. Das fängt einen Teil dessen ab, was sonst
   nur ein live schauendes Modell bemerkt hätte.

Mit diesen vier Regeln liegt die Hybrid-Qualität nahe an der MCP-Qualität. Ohne
sie liegt sie deutlich darunter — und das erklärt das Feedback.

---

## 3. Die drei Betriebsmodi

| Modus | Ausführung | Stärke | Kosten | Wiederholbar |
|---|---|---|---|---|
| `mcp-only` | Modell steuert den Browser live, jeder Schritt | höchste Befundtiefe, findet Unerwartetes | hoch, wächst überproportional mit der Schrittzahl | nein |
| `hybrid` | MCP für Aufklärung und Abschlussbeobachtung, CLI für Ausführung | nahe an MCP, wenn Abschnitt 2 eingehalten wird | mittel | ja, ab dem zweiten Lauf |
| `cli-first` | Specs laufen, MCP nur bei Fehlschlag zur Ursachenanalyse | schnell, günstig, CI-tauglich | niedrig | ja |

### Wann welcher Modus

**`mcp-only`** — unbekanntes Projekt ohne Testinfrastruktur; explorative
Aufträge; stark visuelle oder gestalterische Tickets; geringe Ticketmenge;
Tickets mit hohem Risiko, bei denen Befundtiefe wichtiger ist als Kosten.

**`hybrid`** (Voreinstellung) — der Normalfall. Jedes Ticket wird einmal
beobachtet, danach existiert eine Spec, die beliebig oft läuft. Rechnet sich ab
dem ersten Retest.

**`cli-first`** — reifes Projekt mit gepflegter Suite; Regressionsläufe;
Pipeline-Betrieb; hohe Ticketmenge mit niedrigem Einzelrisiko.

Der Modus ist projektweit voreingestellt, pro Ticket überschreibbar und wird
durch die Eskalationsregeln in Abschnitt 8 automatisch angehoben.

---

## 4. Konfiguration

Eine Datei im Projekt, von beiden Werkzeugen gelesen. Kein tool-spezifisches
Format, damit der Blueprint portabel bleibt.

`qa/qa-config.yml`

```yaml
# Betriebsmodus: mcp-only | hybrid | cli-first
mode: hybrid

mcp:
  max_turns: 20            # harte Obergrenze je Browser-Session
  screenshot_policy: key-steps   # all | key-steps | on-failure
  viewport: [1440, 900]

cli:
  command: "npx playwright test"
  reporter: line
  spec_dir: tests/e2e
  probe_dir: qa/probes     # Wegwerf-Prüfskripte, nicht committen

hybrid:
  # Beobachtungslauf nach dem CLI-Durchlauf (siehe Abschnitt 7)
  verification_pass: true
  # Rotprobe erzwingen, bevor eine neue Spec als Nachweis zählt
  require_red_check: true
  # Ab diesem Risiko wird unabhängig vom Modus live beobachtet
  escalate_at_risk: high

evidence:
  dir: qa/evidence
  timestamp_format: "%Y-%m-%dT%H%M"

models:
  planning: opus           # Testfälle aus Akzeptanzkriterien ableiten
  authoring: sonnet        # Spec schreiben
  execution: haiku         # Runner starten, Ausgabe auswerten
  observation: sonnet      # MCP-Browser-Session
  reporting: sonnet        # Report und Ticketkommentar
```

Die Modellnamen sind Platzhalter für Fähigkeitsstufen. In OpenCode stehen hier
Provider-qualifizierte Modell-IDs, in Claude Code die Kurznamen. Der Ablauf
bleibt identisch.

---

## 5. Der Ablauf in sechs Phasen

```
  ┌─ Phase 1 ─────────────┐
  │ Ticket-Intake         │  JIRA lesen, AKs extrahieren, Testbarkeit prüfen
  └───────────┬───────────┘
              │  intake.json
  ┌───────────▼───────────┐
  │ Phase 2  Aufklärung   │  Probe-Skript (billig) und/oder MCP-Session
  └───────────┬───────────┘
              │  recon.json  ← enthält die realen Selektoren
  ┌───────────▼───────────┐
  │ Phase 3  Planung      │  Testfälle aus AKs, Lücken im Ticket benennen
  └───────────┬───────────┘
              │  testplan.md  →  Freigabe durch den Menschen
  ┌───────────▼───────────┐
  │ Phase 4  Ausführung   │  je nach Modus: MCP live oder Spec über CLI
  └───────────┬───────────┘
              │  run.json + Evidence
  ┌───────────▼───────────┐
  │ Phase 5  Verifikation │  Rotprobe, Beobachtungslauf, Einordnung
  └───────────┬───────────┘
              │  verdict.json
  ┌───────────▼───────────┐
  │ Phase 6  Reporting    │  Ticketkommentar, Journal, Gelernt
  └───────────────────────┘
```

### Phase 1 — Ticket-Intake

Gezielte Feldauswahl statt Volltext: Summary, Description, Typ, Status,
Komponente, Akzeptanzkriterien, die letzten drei Kommentare. Akzeptanzkriterien
werden **einzeln nummeriert** (`AK1`, `AK2`, …). Diese IDs tragen sich durch den
gesamten Ablauf bis in den Report.

Ergebnis ist ein Urteil zur Testbarkeit: testbar, Rückfrage nötig, blockiert.
Bei mehreren Tickets wird nach betroffenem Bereich gruppiert — drei Tickets im
Checkout sind eine Browser-Session, nicht drei.

### Phase 2 — Aufklärung

Hier entscheidet sich die spätere Qualität. Zwei Werkzeuge:

**Probe-Skript** (Standard, sehr günstig): ein Wegwerf-Spec, das die
betroffenen Seiten anfährt und strukturiert zurückgibt, was da ist —
Seitentitel, Überschriftenstruktur, vorhandene Rollen und zugängliche Namen von
Bedienelementen, Formularfelder, Konsolenfehler, fehlerhafte Requests,
Screenshot. Liefert für zehn Seiten weniger Tokens als drei MCP-Klicks.

**MCP-Session** (wenn die Interaktion selbst unklar ist): der Flow wird einmal
live durchgespielt. Obergrenze aus der Konfiguration. Läuft immer in einem
isolierten Unteragenten, damit die Snapshots nicht die Hauptsession füllen.

In `mcp-only` entfällt das Probe-Skript, in `cli-first` entfällt die MCP-Session
außer bei Fehlschlägen.

Das Ergebnis (`recon.json`) enthält die **realen Selektoren**. Damit entfällt
Ursache zwei aus Abschnitt 2.

### Phase 3 — Planung

Aus Akzeptanzkriterien werden Testfälle. Dies ist der Schritt mit dem höchsten
Denkanteil und der geringsten Kontextmenge — hier lohnt das stärkste Modell.

Der Auftrag geht bewusst über die AKs hinaus: Widersprüche zwischen Kriterien,
implizite Grenzwerte, fehlende Berechtigungs- und Zustandsfälle, Kombinationen
mehrerer einzeln definierter AKs. Ergebnis sind eine Testfalltabelle **und** ein
Abschnitt `LÜCKEN IM TICKET`.

Der Testplan wird gezeigt und bestätigt, bevor ausgeführt wird. Zwei Minuten
Prüfzeit verhindern die teuerste Fehlerklasse: gründlich das Falsche testen.

### Phase 4 — Ausführung

| Modus | Vorgehen |
|---|---|
| `mcp-only` | Testfälle live durchspielen, Evidenz im Moment der Beobachtung sichern |
| `hybrid` | Spec aus `recon.json` + Testplan schreiben, über CLI im Unteragenten ausführen |
| `cli-first` | bestehende Specs filtern und ausführen |

Im Hybridmodus wird die Spec aus den realen Selektoren erzeugt, nicht geraten.
Jeder Test trägt die AK-ID im Titel:

```ts
test('AK2: Rabattcode wird bei unterschrittenem Mindestbestellwert abgelehnt',
  async ({ page }) => { /* ... */ });
```

Der Runner läuft immer in einem isolierten Unteragenten und gibt nur das
verdichtete Ergebnis zurück, nie die Rohausgabe.

### Phase 5 — Verifikation

Siehe Abschnitt 7. Dies ist die Phase, die im Hybridmodus die Qualitätslücke zu
`mcp-only` schließt, und die am häufigsten weggelassen wird.

### Phase 6 — Reporting

Statuszeile zuerst, danach Abdeckung **pro Akzeptanzkriterium einzeln**, danach
das bewusst nicht Getestete mit Begründung. Anschließend Journaleintrag mit
einem Abschnitt `## Gelernt`, der die Eingabe für die Retro bildet.

---

## 6. Übergabeverträge

Die Phasen tauschen Daten über **Dateien auf der Platte** aus, nicht über
Gesprächskontext. Das hat drei Gründe: es funktioniert über Agenten- und
Modellwechsel hinweg, es funktioniert in beiden Werkzeugen identisch, und ein
abgebrochener Lauf kann an der letzten Phase wieder aufsetzen.

Ablage unter `qa/runs/<TICKET>/<zeitstempel>/`.

**`intake.json`**
```json
{
  "ticket": "PROJ-1234",
  "typ": "story",
  "titel": "Rabattcode im Checkout",
  "akzeptanzkriterien": [
    { "id": "AK1", "text": "..." },
    { "id": "AK2", "text": "..." }
  ],
  "umgebung": "stage",
  "erwarteter_build": "release-24.9",
  "testbar": true,
  "offene_fragen": []
}
```

**`recon.json`** — das wichtigste Artefakt
```json
{
  "quelle": "probe",
  "seiten": [
    {
      "pfad": "/checkout",
      "titel": "Kasse",
      "bedienelemente": [
        { "rolle": "textbox", "name": "Rabattcode" },
        { "rolle": "button",  "name": "Code einlösen" }
      ],
      "konsolenfehler": [],
      "fehlerhafte_requests": [],
      "screenshot": "qa/evidence/PROJ-1234/2026-09-24T1130/00-checkout.png"
    }
  ]
}
```

**`testplan.md`** — Testfalltabelle, Regressionsumfang, Lücken im Ticket,
Freigabestatus.

**`run.json`** — pro Testfall: AK-ID, Ergebnis, Evidenzpfad, bei Fehlschlag die
entscheidende Zeile der Fehlermeldung und der Artefaktpfad.

**`verdict.json`** — Einordnung je Fehlschlag (echter Fehler, Testfehler,
Umgebungsproblem), Ergebnis der Rotprobe, Befunde des Beobachtungslaufs.

Der Vertrag zwischen Phase 3 und 4 ist der kritische: das ausführende Modell
bekommt die Akzeptanzkriterien mit, sonst kann es beim Fehlschlag nicht
beurteilen, ob die Anwendung oder der Test falsch liegt. Das ist Ursache fünf
aus Abschnitt 2 und sie wird hier gelöst.

---

## 7. Qualitätssicherung der Specs

### Rotprobe

Eine Spec, die noch nie rot war, ist kein Nachweis. Vor der ersten Verwendung
wird die Erwartung gezielt verletzt — bevorzugt durch Manipulation der
Eingabedaten oder des Zustands, ersatzweise durch kurzzeitiges Invertieren der
Assertion. Fällt der Test dabei nicht, prüft er nicht, was er zu prüfen
vorgibt, und wird überarbeitet.

Das kostet pro Spec eine Minute und fängt die gesamte Klasse
Falsch-Grün ab. Steuerung über `hybrid.require_red_check`.

### Positive, spezifische Assertions

Statt „kein Fehler sichtbar" wird geprüft, was stattdessen sichtbar sein soll.
Statt Element-Existenz wird der konkrete Text, der konkrete Wert, der konkrete
Zustand geprüft. Negative Assertions nur ergänzend, nie als einziger Nachweis
eines Akzeptanzkriteriums.

### Beobachtungskanal

Jeder Lauf sammelt unabhängig von den Assertions mit: Konsolenfehler,
Responses ab Status 400, Ladezeiten über Schwellwert, Screenshot am Ende jedes
Tests. Diese Befunde landen im Report als `Auffälligkeiten`, auch wenn alle
Assertions grün sind. Das ersetzt einen Teil des mitlaufenden Blicks, den
`mcp-only` von selbst hat.

### Beobachtungslauf

Bei `hybrid.verification_pass: true` folgt nach dem grünen CLI-Durchlauf **eine
kurze MCP-Session** über den Hauptflow des Tickets — wenige Schritte,
ausdrücklich mit dem Auftrag, auf alles zu achten, was *nicht* in den
Assertions steht. Das ist der Rest der Qualitätslücke.

Kosten: eine kurze Session pro Ticket statt einer langen. Der Nutzen ist hoch,
weil genau hier die Befunde entstehen, die eine Spec systematisch übersieht.

### Verfallsdatum

Eine Spec, deren zugehörige Seite sich strukturell geändert hat, gilt als
veraltet. Erkennungsmerkmal: das Probe-Skript liefert andere Bedienelemente als
`recon.json` zum Zeitpunkt der Erstellung. Dann wird die Aufklärung wiederholt,
nicht die Spec nachgeflickt.

---

## 8. Eskalationsregeln

Unabhängig vom eingestellten Modus wird live beobachtet, wenn eine dieser
Bedingungen zutrifft:

- Risiko des Tickets erreicht `hybrid.escalate_at_risk`
- Das Ticket ist visuell oder gestalterisch geprägt
- Für den betroffenen Bereich existiert keine `recon.json`
- Der CLI-Lauf schlägt fehl und die Ursache ist nicht eindeutig
- Ein Testfall lässt sich nicht als Assertion formulieren, ohne das
  Akzeptanzkriterium zu verkürzen
- Ein Bug ist nicht reproduzierbar

Umgekehrt wird nicht eskaliert, nur weil ein Test rot ist. Ein eindeutig
eingeordneter Fehlschlag braucht keine Browser-Session.

---

## 9. Evidenz und Reporting

Ablage: `qa/evidence/<TICKET>/<YYYY-MM-DDTHHmm>/`, Dateien nummeriert und
sprechend benannt, keine Leerzeichen, keine Umlaute.

Verbindlich:

| Ergebnis | Pflichtevidenz |
|---|---|
| PASS | ein Nachweis je Akzeptanzkriterium |
| FAIL | Screenshot des Fehlerzustands, Konsole, relevante Response, Trace |
| BLOCKED | Beleg des Blockers |

Evidenz wird **im Moment der Beobachtung** gesichert, nicht nachgestellt. Vor
dem Anhängen an ein Ticket: keine Zugangsdaten, keine Tokens, keine echten
Personendaten sichtbar.

Reportformat:

```
Testergebnis: PASS | FAIL | BLOCKED | TEILWEISE
Umgebung: <env> | Build: <version> | Modus: <mcp-only|hybrid|cli-first>

  AK1  <kurztitel>  PASS
  AK2  <kurztitel>  FAIL   → <Bugticket>
  AK3  <kurztitel>  NOT TESTED (<Begründung>)

Zusätzlich geprüft: <Regressionsumfang>
Auffälligkeiten:    <aus dem Beobachtungskanal>
Evidenz:            qa/evidence/<TICKET>/<zeitstempel>/
```

Die Modus-Angabe im Report ist wichtig: wer später ein Ergebnis bewertet, muss
wissen, ob live beobachtet oder nur assertiert wurde.

---

## 10. Portabilität

Der Kern liegt vollständig in werkzeugneutralen Dateien:

```
qa/qa-config.yml          Modus und Einstellungen
qa/PROJECT-MAP.md         Projektkarte
qa/runs/<...>/*.json      Übergabeverträge
qa/probes/                Aufklärungsskripte
qa/evidence/              Nachweise
qa/test-journal/          Historie
docs/TESTING-PIPELINE.md  dieses Dokument
tests/e2e/                Specs
```

Tool-spezifisch ist nur, **wie Agenten deklariert und Modelle zugeordnet
werden**. Diese Schicht bleibt dünn:

| Baustein | Claude Code | OpenCode |
|---|---|---|
| Projektanweisungen | `CLAUDE.md` | `AGENTS.md` |
| Wissensbausteine | `.claude/skills/<name>/SKILL.md` | `.opencode/skill/<name>/SKILL.md` |
| Unteragenten | `.claude/agents/*.md` | `.opencode/agent/*.md` |
| Aufrufbare Abläufe | Skill mit `/name` | `.opencode/command/*.md` |
| Modellzuordnung | `model:` in der Agent-Frontmatter | `model:` in der Frontmatter oder `opencode.json` |
| MCP-Server | `.mcp.json` | `mcp`-Abschnitt in `opencode.json` |
| Verteilung | Plugin-Marketplace | Repo klonen oder als Submodul einbinden |

Die genauen Verzeichnisnamen unter `.opencode/` weichen zwischen Versionen und
Community-Setups ab (Einzahl gegen Mehrzahl). Vor dem Einbau gegen die aktuelle
OpenCode-Dokumentation prüfen und im Adapter-Verzeichnis einmal festlegen.

**Regel für den Blueprint:** eine Information steht genau einmal, im
werkzeugneutralen Teil. Die Adapter verweisen darauf, sie kopieren nicht. Sonst
driften die beiden Zweige nach wenigen Wochen auseinander.

`AGENTS.md` und `CLAUDE.md` sollten inhaltlich identisch bleiben und beide nur
Zeiger enthalten, keine Inhalte. Beide unter 200 Zeilen.

---

## 11. Grenzen

**Der Hybridmodus ersetzt kein menschliches Auge.** Er reduziert die Lücke, er
schließt sie nicht. Für gestalterisch geprägte Oberflächen und für erstmalige
Abnahmen bleibt `mcp-only` die bessere Wahl.

**Der Freigabeschritt nach Phase 3 ist nicht optional.** Ohne ihn entsteht die
Fehlerklasse, die am teuersten ist, weil sie niemandem auffällt: gründlich
getestet, aber das Falsche.

**Die Verifikation des deployten Stands gehört vor jeden Lauf.** Ein Test gegen
einen alten Stand liefert ein sauber aussehendes, falsches Ergebnis.

**Die Lernschleife braucht Kuration.** Journal und `recon.json` wachsen. Ohne
regelmäßiges Verdichten kippt der Tokenvorteil des Hybridmodus nach einigen
Monaten wieder.

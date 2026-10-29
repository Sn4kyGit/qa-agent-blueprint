Spickzettel · Alle drei Teile

# QA Agent Blueprint

**JIRA-Ticket rein → getestetes Ticket raus.**
Ein KI-QA-Kollege als Plugin für Claude Code: Er testet Tickets selbstständig,
liefert Beweise, meldet das Ergebnis zurück nach JIRA — und lernt dazu.

32

Fähigkeiten (Skills)

9

Spezialisten (Subagents)

4

Türsteher (Hooks)

400+

Selbsttests (Fixtures)

5

Verdikte

[Teil 1 · Was ist das?](#teil1)
[Teil 2 · Wie funktioniert er?](#teil2)
[Teil 3 · Technical Deep Dive](#teil3)

Teil 1 · Allgemein

# Was ist der QA Agent Blueprint?

## Was ist das?

- Ein **Plugin für Claude Code** (Anthropics KI-Entwicklerwerkzeug), das daraus einen QA-Manager + Tester macht — kein neues Tool, keine neue Oberfläche.
- Ticketgetrieben: Der **JIRA-Ticket-Schlüssel** (z. B. SHOP-1234) ist der Eingang — darüber findet der Agent alles, was er über das Projekt wissen muss. Gelesen wird das Ticket über den **Atlassian-MCP-Server** — oder, wenn ein Projekt JIRA nur per Weboberfläche nutzt, über den Browser (**Playwright MCP**).
- Alles Projektwissen liegt in **normalen Textdateien in deinem Projektordner** — lokal, einsehbar, ohne Geheimwissen im Kopf des Agenten. Per Git versionieren und mit dem Team teilen kannst du es (empfohlen), musst du aber nicht — Pflicht ist nur der Ordner.
- Angebunden sind standardmäßig zwei Systeme: **JIRA** (Tickets rein, Ergebnisse raus) und ein **Browser** (Playwright) fürs Testen. Weitere Werkzeuge lassen sich pro Projekt ergänzen — z. B. **WebdriverIO** als Test-Framework oder **Proxyman** für Netzwerk-Mitschnitte; neue MCP-Server kommen nur auf deinen Beschluss dazu, nie von selbst.

## Was er kann

- **Ticket testen** (`/test-ticket`): lesen → Projekt erkennen → Umgebung prüfen → testen → beweisen → zurückmelden
- **Bug gegentesten** (`/retest-bug`): Repro-Schritte nachspielen + enger Regressionssweep um die Fundstelle
- **Explorativ testen** (`/exploratory-testing`): neue Features & unklares Verhalten im Browser erkunden
- **Autotests schreiben** (`/test-automation`): was verstanden ist, wird wiederholbar
- **Vorher aufklären** (`/recon`): echte Selektoren & Konsolenfehler als `recon.json` — keine blind geratene Spec mehr

- **Bug melden** (`/bug-report`): Fund exakt im Bug-Template des Projekts, mit Duplikat-Check
- **Nach JIRA berichten** (`/report-to-jira`): Kommentar, Anhänge, korrekter Status
- **Wochenreport** (`/qa-report`): Pass-Rate, P0/P1, Blocker-Gründe — pro Projekt & Produkt
- **Demo geben** (`/demo`): Bug oder Testlauf sichtbar vorführen (Slow-Mo), auf Wunsch selbst klicken lassen; Video nur auf ausdrückliche Anfrage
- **Einrichten & pflegen**: `/onboard-project` (einmalig), `/re-board` (nach Updates), `/whats-new` („was ist neu?")
- **Skill-Nutzung prüfen** (`/skill-review`): welche Skills sind belegt genutzt (`used`), wofür liegen keine Daten vor (`unknown`) — nie „unbenutzt". Profil-Vorschläge (`full`/`standard`/`minimal`/`custom`) nur als Dry-run; umgesetzt nur nach ausdrücklicher Bestätigung und nur im integrate-Modus

## Das Team: ein Dirigent + vier Spezialisten

- **Der Dirigent** (qa-manager): liest das Ticket, entscheidet die Strategie, verteilt die Arbeit, prüft am Ende Beweise und Ergebnis.
- **Der Tester** (test-executor): klickt sich explorativ durchs Feature und reproduziert Bugs.
- **Der Testschreiber** (test-automator): schreibt und fährt wiederholbare Autotests.
- **Der Prüfer** (failure-analyst): klärt bei jedem FAIL — Produkt kaputt oder Test veraltet? (Darf absichtlich nichts verändern.)
- **Der Melder** (bug-reporter): gießt den Fund exakt ins Bug-Template des Projekts.

## So arbeitest du mit ihm

- **Einfach normal schreiben** — „Teste SHOP-1234", „Der Fix für WEB-456 ist auf Stage, prüf das", „Wie läuft's mit dem Testing?" Deutsch oder Englisch; Slash-Befehle sind nur die explizite Form.
- **Einmalig pro Projekt einrichten** (~30–60 Min. Interview): Umgebungen, Testuser, Deploy-Runbook, Report-Format — danach weiß er es dauerhaft.
- **Er fragt, statt zu raten**: Ist unklar, welches Produkt gemeint ist oder fehlt ein Zugang, fragt er nach — im CI meldet er sauber BLOCKED.

## Die fünf Verdikte

| Verdikt | Bedeutung |
| --- | --- |
| PASS | Getestet, keine Befunde — Kommentar + Status-Wechsel, Screenshot als Beleg |
| FAIL | Mindestens ein Befund — vorher wird geklärt: Produkt kaputt oder Test veraltet? |
| BLOCKED | Der Test lief nie (Umgebung weg, Fix nicht deployed) — mit Grund und Entblocker |
| NEEDS\_REVIEW | Der Test ist vermutlich selbst veraltet — Vorschlag an einen Menschen |
| NO\_TEST | Untersucht, aber kein Test abgeschlossen — ehrlich statt schöngerechnet |

## Warum man ihm vertrauen kann

- **Shadow-Modus ab Tag eins:** Er testet vollständig und legt JIRA-Kommentare als *Vorschlag* ab — gepostet wird erst nach deiner Freigabe.
- **Nur Stage, niemals Produktion** — egal, wer fragt oder wie es formuliert ist.
- **Passwörter sieht er nie:** Testuser-Logins & JIRA-Token liegen im macOS-Schlüsselbund; er sieht nur „6/6 Logins vorhanden".
- **Kein Urteil ohne Beweise:** Jeder Lauf endet mit Screenshots, Logs und einem maschinenlesbaren Protokoll — ein Hook blockt sonst das Session-Ende.
- **Jeder JIRA-Schreibzugriff** landet in einem Audit-Log — nachvollziehbar, auch im automatisierten Lauf.
- **Selbsttests (Fixtures) beweisen die Durchsetzung:** kleine Skripte, die jeden Türsteher mit Probe-Anfragen füttern und prüfen, dass er wirklich blockt — **147 davon**, sie laufen bei jeder Änderung. Ein Türsteher ohne Selbsttest wäre Dekoration: Einer hatte in der Vergangenheit monatelang still *nichts* blockiert — und in der Review sah alles korrekt aus.

**Merksatz:** Er ersetzt nicht die QA — er nimmt ihr die wiederholbare Fleißarbeit ab
(Ticket lesen, Umgebung prüfen, Flows durchklicken, Beweise sichern, Ticket befüllen),
damit Menschen die Urteile fällen.

## Was kostet das?

- **Das Plugin ist kostenlos** — und telefoniert nie nach Hause: Nach der Installation läuft alles lokal, Netzwerk geht nur zu **deinem JIRA** und **deiner Stage**. Das Repo wird nur bei Install und Update angefasst.
- **Die echten Kosten sind Modell-Tokens** — deshalb laden Fachbücher nur bei Bedarf, Learnings werden gezielt durchsucht, Rohbeweise kommen nie in den Kopf, einfache Tickets überspringen den Manager und eine Run-Capsule verhindert erneutes Projektlesen pro Spawn. Modell-Lanes wählen nach Risiko cheap/standard/deep; `/model-setup` konfiguriert sie für opencode im Consumer. Claude Code nutzt Sonnet standardmäßig für die Ausführung; opencode lässt die Wahl bei `/models`.
- **Browser-Verlauf bleibt der Haupttreiber:** Sonnet ändert den Preis, nicht die Tokenmenge. Readiness verhindert Tests auf altem Build, vorhandene Autotests laufen günstig per CLI. Für 0.18.0 gibt es kein neues Kostenbenchmark — miss mit `/usage` statt alter Schätzwerte.
- **Neu: drei Execution Modes.** Pro Projekt wählbar, wer am Steuer sitzt: `mcp-only` (alles live, tiefste Befunde), `hybrid` (Standard: Probe → Autotest → kurzer Live-Check — nahe Live-Tiefe zu mittleren Kosten), `cli-first` (nur Suite, CI-tauglich). Jeder JIRA-Report zeigt den Modus — man sieht, ob beobachtet oder nur assertiert wurde.

Teil 2 · Technik — einfach erklärt

# Wie funktioniert er?

Stell dir einen **neuen QA-Kollegen** vor: Er hat ein **Handbuch**,
das er immer dabei hat, kann **Spezialisten** dazurufen — und kommt an
**Türstehern** nicht vorbei, die die Hausregeln wirklich durchsetzen.

## Der Ablauf bei einem Ticket

Ticket lesen→
Projekt erkennen→
Stage prüfen→
Testen→
Beweise sichern→
Berichten→
Lernen

| Schritt | Was passiert — in Menschensprache |
| --- | --- |
| 1 · Lesen | Holt das Ticket aus **JIRA** — das Ticket-Kürzel (SHOP-1234) sagt ihm, welche Projektakte gilt. |
| 2 · Routen | Mehrere Produkte im Projekt? Er erkennt über **Komponente/Label** das richtige — im Zweifel fragt er nach, statt zu raten. |
| 3 · Prüfen | Ist der Fix überhaupt **auf Stage**? Nein → er meldet BLOCKED mit Grund, statt grün zu testen, was gar nicht da ist. |
| 4 · Testen | Er **erkundet** das Feature im Browser (Neues, Unklares) oder fährt **fertige Autotests** (Bekanntes, ~4× günstiger). |
| 5 · Beweisen | Screenshots, Logs, maschinenlesbares Protokoll pro Lauf. **Kein Urteil ohne Beleg** — das wird erzwungen, nicht erbeten. |
| 6 · Berichten | Kommentar + Anhänge + Status für JIRA — im Shadow-Modus nur als **Vorschlag**. Danach: Gelerntes → ins Handbuch. |

## Das Gedächtnis — fünf Schubladen

Warum bleibt er günstig und schnell? Weil er *nicht alles immer im Kopf* hat — nur das Handbuch. Der Rest wird gezielt aus der passenden Schublade geholt.

| Schublade | Analogie | Inhalt |
| --- | --- | --- |
| 1 · Handbuch | Immer dabei | Nur die Regeln (~7.500 Wörter): Was ist Pflicht, was ist verboten |
| 2 · Fachbücher | Nur bei Bedarf geöffnet | 32 Fähigkeiten — z. B. Accessibility, Security, API-Tests |
| 3 · Projektakte | Nur das aktive Projekt | Umgebungen, Testuser, Deploy-Runbook, Report-Format, Flow-Map |
| 4 · Lerntagebuch | Wächst, wird aufgeräumt | Überraschungen; beim 2. Auftreten wandern sie ins Handbuch |
| 5 · Beweisfotos | Nie im Kopf, nur als Pfad | Screenshots & Logs unter `evidence/` — Basis für den Wochenreport |

## Das Team dahinter — fünf Rollen

Jede Rolle hat ihre *eigene Aktenmappe* (eigenes Gedächtnis): Ein 30-Schritte-Browser-Protokoll flutet nie die Besprechung — zurück kommt nur das Ergebnis.

| Rolle | Job | Darf nicht |
| --- | --- | --- |
| Der Dirigent | Liest das Ticket, entscheidet die Strategie, verteilt die Arbeit, prüft am Ende Evidence & Ergebnis | Selbst Browser fahren oder Tests schreiben |
| Der Tester | Klickt sich explorativ durchs Feature, reproduziert Bugs | In JIRA schreiben |
| Der Testschreiber | Schreibt & fährt wiederholbare Autotests | — |
| Der Prüfer | Bei jedem FAIL: Produkt kaputt — oder Test veraltet? | **Absichtlich nichts verändern** — sonst könnte er rote Tests grün editieren |
| Der Melder | Gießt den Fund exakt ins Bug-Template des Projekts | Einen Browser bedienen |

## Die Türsteher — Regeln sind Worte, Hooks sind Durchsetzung

| Türsteher | Lässt nicht durch |
| --- | --- |
| Guard | Lösch-Kommandos (`rm -rf`), Force-Push, Schreiben in Passwort-Dateien, fremde MCP-Server & globale MCP-Config (Projekt-Config bleibt im Projekt) |
| Evidence-Check | Session-Ende ohne Beweise & ohne Lern-Deklaration |

| Türsteher | Lässt nicht durch |
| --- | --- |
| Session-Start | Ratlosigkeit: zeigt Projekte, offene Learnings, Login-Status („6/6 Logins") |
| JIRA-Audit | Unsichtbare Schreibzugriffe: jeder landet im Protokoll |

**Ernst gemeint:** Ein Türsteher zählt erst, wenn ein Selbsttest beweist, dass er
blockt — **400+ Fixture-Checks** tun genau das. Einer hatte monatelang still *nichts*
blockiert — und in der Review sah alles korrekt aus.

## Zwei Sicherheitsideen zum Mitnehmen

| Idee | Analogie |
| --- | --- |
| **Shadow-Modus** | Probefahrt mit Beifahrer: Er macht alles, postet nichts — nach ~2 Wochen geprüfter Vorschläge gibt das Team Schreibrechte. |
| **Keychain-Tresor** | Passwörter im macOS-Schlüsselbund; fehlt eines, poppt ein Dialogfenster auf — getippt wird ins Fenster, nie in den Chat. Der Agent sieht nie einen Wert. |

Teil 3 · Technical Deep Dive

# Wie der Agent arbeitet

Ein kompletter Lauf an einem Beispiel — **„Teste SHOP-1234"** — und danach:
**wie er Wissen speichert**, damit er es nie zweimal erklärt bekommt.

## Beispiel-Lauf: „Teste SHOP-1234"

| # | Schritt | Was technisch passiert |
| --- | --- | --- |
| 1 | **Router erkennt das Ticket** | Die immer geladene `CLAUDE.md` matcht „SHOP-1234" → lädt den Skill `test-ticket`, der an den Subagent **qa-manager** delegiert. |
| 2 | **Ticket lesen** | qa-manager holt das Ticket über den `atlassian`-MCP (nur lesend): Ziel, Akzeptanzkriterien, Komponente „storefront", Fix-Version. |
| 3 | **Routing** | Präfix → `projects/SHOP/PROJECT.md`; Komponente → `products/STOREFRONT/PRODUCT.md` gemergt (nur Abweichungen). Versiegelte Felder (Transitions, Deploy-Recht) kommen immer aus der Projektdatei. |
| 4 | **Stage-Check** | Fix-Version gegen Deploy-Status prüfen (Runbook im Projektfile). Nicht deployed → `/deploy-to-stage` oder `BLOCKED` — niemals raten. |
| 5 | **Strategie aus der Feature-Matrix** | Checkout-Änderung → explorative Session; die Matrix sagt, ob Spezialisten (API, Accessibility, Security …) dazugehören. |
| 6 | **Testen** | **test-executor** fährt die Browser-Session: Playwright MCP, isoliertes Profil, `--secrets` maskiert Passwörter; das Login kommt aus der Keychain-aufgelösten Env-Datei. |
| 7 | **Evidence ablegen** | `evidence/SHOP/SHOP-1234/<timestamp>/`: Screenshots, Logs, `execution_summary.json` (Verdikt, Dauer, Learnings). |
| 8 | **Bei FAIL: Triage** | **failure-analyst** (ohne Schreibrechte) prüft Assertion, JIRA-Historie, Versionsfenster → `product-defect` oder `test-outdated`. Defekt → **bug-reporter** schreibt nach Projekttemplate, mit Duplikat-Check. |
| 9 | **Zurückmelden** | `report-to-jira` komponiert Kommentar + Anhänge + Transition. Shadow-Modus an → nur Vorschlag. Jeder echte Schreibzugriff landet im **Audit-Log** (PostToolUse-Hook). |
| 10 | **Session-Ende** | Stop-Hook prüft: Summary vorhanden? Learnings deklariert? Sonst blockt er — maschinenlesbar (`QA_EVIDENCE_MISSING:`). |

**Warum Subagents?** test-executor läuft in einem **eigenen Kontextfenster**:
Das 30-Schritte-Browser-Transkript flutet nie den Hauptkontext — zurück kommt nur ein Verdikt
plus Pfade zu den Artefakten. Skill = Anleitung; Subagent = abgeschottete Rolle mit eigenen Werkzeugen.

## Wie er Wissen speichert

```
# alles als normale Textdateien im eigenen
# Projektordner — einsehbar, auf Wunsch per
# Git versioniert und mit dem Team geteilt
projects/SHOP/
├── PROJECT.md        ← Umgebungen, Testuser
│                       (als Referenzen!), Runbook,
│                       Gates, Routing-Registry
├── flow-map.md       ← Flows, Anker, Nachbarn
│                       → steuert Re-Test-Sweeps
├── learnings.md
└── products/STOREFRONT/  ← nur Abweichungen

memory/
├── INDEX.md          ← Landkarte, wird zuerst gelesen
└── learnings/
    ├── _inbox.md     ← Auffangbank (Capture)
    └── <thema>.md    ← verdichtet (Groom)

evidence/SHOP/SHOP-1234/<ts>/  ← Artefakte, nie
                                  im Modellkontext
```

| Phase | Mechanik |
| --- | --- |
| **Capture** | Jeder Lauf deklariert im Summary, was gelernt wurde — oder warum nichts anfiel. Stop-Hook erzwingt es. |
| **Groom** | `/retro-learn` dedupliziert, zählt `seen:` hoch, löscht Überholtes. Session-Start meldet den Rückstau. |
| **Promote** | 2. Sichtung → Regel, `PROJECT.md` oder `flow-map.md`: ab dann automatisch geladen, nie wieder erklärt. |
| **Routing lernt** | Menschliche Regel → sofort in die Registry; Einzelfall → erst beim 2. Mal; Ausnahme → nie. |

## Vier Design-Entscheidungen, die das tragen

| Entscheidung | Konsequenz |
| --- | --- |
| **Plugin-Modus ohne Drift** | Plugins laden kein `CLAUDE.md` — der Session-Start-Hook injiziert es **wortwörtlich**. Ein Router-Text für beide Installationsarten. |
| **MCP = Vertrag über Namen** | Hooks/Skills matchen auf `playwright`/`atlassian`; Pflicht-Flags `--secrets` + `--output-dir`; der Rest ist frei wählbar (`.playwright-mcp.config.json`). |
| **Secrets nie im Transkript** | Keychain-Resolver schreibt `.env.playwright-secrets`, Werte erscheinen nirgends; `qa-secrets.mjs` injiziert sie wertefrei in Runner und MCP-Server; der Guard-Hook blockt jeden Schreibzugriff auf `.env*`-Pfade, direktes Lesen ist ein menschlicher Opt-in. |
| **Kontext-Budget gemessen** | Immer geladene Ebene: 8.372 von 8.400 Token — ein Test schlägt fehl, wenn sie wächst; alles andere lädt bei Bedarf. |

QA Agent Blueprint · Stand: 29. Oktober 2026 (v0.18.0) · Alle drei Spickzettel in einem Dokument —
Teil 1: „Was ist das?" · Teil 2: „Wie funktioniert er — einfach erklärt" · Teil 3: „Technical Deep Dive".
Quelle der Wahrheit: das Repo (README.md, overview.html).

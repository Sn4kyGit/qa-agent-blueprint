Claude Code & opencode · Repo-Blaupause

# QA Agent Blueprint

Macht Claude Code oder opencode zu einem ticketgetriebenen QA-Manager und Tester: JIRA-Ticket rein,
getestetes Ticket raus — mit Pflicht-Evidence, projekt- und produktspezifischem Wissen
und einem Lernkreislauf, der erzwungen wird statt erwünscht zu sein.
Neu hier? Unten beantwortet die Rubrik **Häufige Fragen** in einfacher
Sprache, wie Gedächtnis, Kosten und Sicherheit funktionieren.

32

Skills

9

Subagents

5+10

Regeln (immer / on demand)

4

Hooks

Fixtures+145

Fixture-Checks + bun-Tests

45

Eval-Cases

8,3k

Token immer geladen

## Installation

Am einfachsten: dem Agenten sagen. In Claude Code (im Projekt, das getestet werden soll) einfügen:

```
Set up https://github.com/Sn4kyGit/qa-agent-blueprint as a Claude Code
plugin in this project. Read its AGENTS.md first and follow the runbook.
```

Oder selbst zwei Befehle — `--scope project` aktiviert nur hier, ohne Flag überall:

```
claude plugin marketplace add Sn4kyGit/qa-agent-blueprint
claude plugin install --scope project qa-agent-blueprint@qa-agent-blueprint-marketplace
```

Unter **opencode** (modell-agnostisch, Modell = deine `/models`-Wahl): `install.sh --mode opencode --target <projekt> --yes` vom Clone aus — Details: [Quickstart opencode](https://github.com/Sn4kyGit/qa-agent-blueprint/blob/main/docs/quickstart-opencode.md).
Für wechselnde Claude-Code- und opencode-Sessions in derselben QA-Home: `install.sh --mode shared` — beide bleiben ohne Re-Onboarding startbereit, `/agentswitch` prüft read-only.

Ende-zu-Ende verifiziert (claude 2.1.263): registriert 32 Skills, 9 Subagents, 4 Hooks und beide MCP-Server. Solange das Repo privat ist, braucht der Fetch GitHub-Auth (`gh auth login`) — darunter läuft schlicht git. Alternativ: Clone + `install.sh` (siehe README).

## Der Ablauf

Ticket→
Projekt erkannt→
Produkt erkannt→
Wissen angewendet→
getestet→
Evidence→
berichtet→
gelernt

Jede Stufe hat eine Datei als Quelle und, wo es zählt, einen Hook als Durchsetzung.

## Wer am Steuer sitzt — drei Execution Modes

Seit 0.12.0 entscheidet eine Zeile in der Projektdatei, wie ein Ticket getestet wird:
live per Browser (MCP) oder über ein vorher geschriebenes Skript (CLI) — oder die taktische
Mischung. Jeder JIRA-Report trägt den Modus, damit klar ist, ob ein Ergebnis beobachtet
oder nur assertiert wurde.

| Modus | Wie getestet wird | Kosten | Wann |
| --- | --- | --- | --- |
| mcp-only | Modell steuert live, jeder Schritt | hoch | Neues Projekt, explorativ, visuell, hohes Risiko |
| hybrid (Standard) | Probe → Spec per CLI → Rotprobe → kurzer Live-Check | mittel | Der Normalfall; rechnet sich ab dem ersten Retest |
| cli-first | Nur die Suite; MCP nur bei unklarem Fehlschlag | niedrig | Gepflegte Suite, Regression, Pipeline |

Vier Regeln machen den Hybridmodus ehrlich: keine blind geschriebene Spec (Recon zuerst),
positive und spezifische Assertions, die **Rotprobe** (eine Spec, die nie rot
war, beweist nichts) und der Beobachtungskanal in jedem Lauf. Eskaliert wird automatisch:
visuelles Ticket, hohes Risiko, fehlende Recon oder unklarer Fehlschlag → immer live.
Umstellen: `Mode` in `PROJECT.md` — bei Bestandsprojekten bietet
`/re-board` die Sektion im Dialog an. Ausführlich (deutsch):
[docs/execution-modes.md](https://github.com/Sn4kyGit/qa-agent-blueprint/blob/main/docs/execution-modes.md).

## Befehle im Überblick

Kein Auswendiglernen nötig: „Teste SHOP-1234" oder „wie läuft's mit dem Testing?" routet
genauso wie der Slash-Befehl — Deutsch oder Englisch, die Befehle sind nur die explizite,
garantierte Form. Im Plugin-Modus heißen sie `/qa-agent-blueprint:<name>`. Die komplette Liste
zeigt jederzeit `/qa-agent-blueprint:qa-help` — auch direkt in der Session.

### Ticket testen

| Befehl | Was er tut | Typische Formulierung |
| --- | --- | --- |
| /test-ticket | Der Haupteinstieg: Ticket lesen, routen, Stage prüfen, Strategie wählen, Evidence erzeugen, Verdikt zurückmelden | „Teste SHOP-1234" |
| /retest-bug | Spielt die Repro-Schritte eines gefixten Bugs nach, dann enger Regressions-Sweep um die Fundstelle — aus der Flow-Map des Produkts abgeleitet, wenn eine existiert | „Der Fix für WEB-456 ist auf Stage — prüf das" |
| /exploratory-testing | Gecharterte, zeitboxte Session im Browser — für neue Features und unklares Verhalten ohne Spec | „Schau dir die neue Checkout-Seite mal an" |
| /test-automation | Schreibt oder fährt deterministische Specs im Framework der Suite (Playwright oder WebdriverIO), sobald ein Ablauf verstanden und wiederholungswürdig ist | „Automatisiere den Login-Flow" |
| /recon | Aufklärung vor der Spec: Probe-Lauf schreibt `recon.json` mit den echten Selektoren, Konsolenfehlern und Screenshots ins Run-Verzeichnis — gegen blind geratene Specs | „Erkunde die Seite vor dem Test" |

### Auf ein Ergebnis reagieren

| Befehl | Was er tut | Typische Formulierung |
| --- | --- | --- |
| /failure-analysis | Triagiert jeden FAIL vor dem Bug-Ticket: echtes Defizit oder veralteter Testfall? Läuft automatisch | „Warum ist der Test rot?" |
| /bug-report | Gießt eine Fundstelle in die Bug-Vorlage des Projekts — mit Duplikat-Check | „Mach ein Ticket aus dem Fund" |
| /report-to-jira | Kommentar, Anhänge und Workflow-Transition zurück nach JIRA — im Shadow-Modus nur als Vorschlag | „Melde das Ergebnis zurück" |
| /deploy-to-stage | Fährt das Deploy-Runbook des Projekts mit Sicherheitschecks, wenn der Fix fehlt | „Bring den Fix auf Stage" |

### Einrichten

| Befehl | Was er tut | Typische Formulierung |
| --- | --- | --- |
| /onboard-project | Das einmalige Interview pro JIRA-Projekt (~30–60 min): Umgebungen, Testuser, Runbook, Gates | „Richte das Projekt SHOP ein" |
| /onboard-product | Die kurze Variante (5–15 min) für ein Produkt im Projekt — nur Abweichungen | „Das Projekt hat jetzt auch eine Admin-App" |
| /re-board | Delta-Onboarding: bringt ein Bestandsprojekt auf den aktuellen Blueprint-Stand — der Upgrade-Pfad nach einem Update | „Hol das Onboarding für SHOP nach" |
| /scaffold-suite | Erzeugt das Playwright-Projekt samt erster Smoke-Spec, wenn es noch keine Test-Assets gibt | „Leg eine Test-Suite an" |

### Wissen & Meta

| Befehl | Was er tut | Typische Formulierung |
| --- | --- | --- |
| /qa-report | Aggregiert alle Evidence-Läufe: Pass-Rate, P0/P1, BLOCKED-Gründe — pro Projekt und Produkt | „Wie läuft's mit dem Testing?" |
| /retro-learn | Hält Learnings fest, verdichtet sie und befördert Bewährtes in Regeln und Projektdateien | „Session abschließen" |
| /whats-new | Zeigt, was sich am Blueprint seit dem Onboarding geändert hat — und was ein /re-board lohnt | „Was ist neu?" |
| /skill-review | Skill-Nutzungsanalyse: jeder installierte Skill ist `used` (in den `skills_used`-Datensätzen) oder `unknown` (keine Daten) — nie „unbenutzt". Profile (`full`/`standard`/`minimal`/`custom`) nur als Dry-run-Vorschlag, umgesetzt nur nach ausdrücklicher Bestätigung und nur im integrate-Modus | „Welche Skills nutzen wir eigentlich?" |
| /demo | Präsentiert eine Bug-Repro oder einen fertigen Testlauf sichtbar: Headed-Slow-Mo-Wiederholung + Demo-Karte, Selbst-ausprobieren-Modus, .webm-Aufzeichnung nur auf ausdrückliche Anfrage — niemals automatisch | „Präsentier den Bug", „Lass mich probieren" |
| /qa-help | Diese Übersicht, direkt in der Session — antwortet in der Sprache, in der man fragt | „Welche Befehle gibt es?" |

Drei Dinge zum Einordnen: **Shadow-Modus ist standardmäßig an** — JIRA-Kommentare
werden komponiert, aber erst nach Freigabe gepostet. Die **zehn Spezialisten-Skills**
(API, Accessibility, Security, Visual …) zieht qa-manager selbständig, wenn die Feature-Matrix
des Produkts es vorgibt — kein Direktaufruf nötig. Und **Evidence ist Pflicht**:
Jeder Lauf endet mit einem Verdikt und Artefakten unter `evidence/`.

## Die fünf Ebenen

Was die Tokenkosten niedrig hält: nur Ebene 1 ist immer im Kontext, alles andere lädt bei Bedarf — oder nie.

#### 1Globaler Kern — nur die Normen

Router plus fünf Regeldateien: alles, was binden muss, bevor irgendein Skill geladen ist.
Das Detail dahinter liegt in `docs/rules/` und wird gelesen, wenn sein Thema kommt —
jede Datei nennt ihren Auslöser oben.

CLAUDE.md + .claude/rules/core/ · gemessen 8.372 Token, Budget 8.400

#### 2Skills & Subagents

Erst bei Bedarf geladen. Subagents haben eigene Kontextfenster, damit ein
30-Schritte-Browser-Transkript nicht im Hauptkontext landet — zurück kommt nur ein Verdikt.

.claude/skills/ · .claude/agents/

#### 3Projekt- und Produktkontext

Nur das aktive Projekt wird gelesen. Deckt ein JIRA-Projekt mehrere Produkte ab, kommt
genau eine kurze Produktdatei dazu — die nur Abweichungen nennt.

projects/<KEY>/ → products/<PRODUCT>/

#### 4Lernsystem

Inbox als Auffangbank, Themendateien als verdichtete Mitte, Beförderung in Regeln und
Projekt-/Produktdateien als Ziel. Wissen zählt erst, wenn es dort ankommt.

memory/INDEX.md · memory/learnings/

#### 5Evidence

Screenshots, Logs, Traces und ein maschinenlesbares Summary pro Lauf. Nie im
Modellkontext — und nicht write-only: `/qa-report` liest sie zurück.

evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/

## Was der Agent kann

Skill oder Subagent — der Unterschied ist nicht kosmetisch. Ein Skill ist eine Anleitung,
die erst beim Aufruf in den Kontext geladen wird; idle kostet er nur seinen Namen und seine
Beschreibung. Ein Subagent hat zusätzlich ein eigenes Kontextfenster und eine eingeschränkte
Werkzeugliste — er läuft abgeschottet und gibt nur ein Ergebnis zurück. Deshalb sind alle
Ausführungsrollen Subagents: ein 30-Schritte-Browser-Transkript darf den Hauptkontext nicht fluten.

### Die 21 eigenen Skills — der Ticket-Ablauf

| Skill | Was er tut | Wann er greift |
| --- | --- | --- |
| /test-ticket | Der Haupteinstieg: liest das Ticket, routet zu Projekt und Produkt, prüft die Stage, wählt die Teststrategie, erzeugt Evidence, berichtet zurück. Delegiert die Orchestrierung an qa-manager. | „Teste SHOP-1234" |
| /retest-bug | Schmalere Variante: spielt exakt die ursprünglichen Repro-Schritte nach und macht danach einen engen Regressions-Sweep um die Fundstelle — aus der `flow-map.md` des Produkts abgeleitet (Nachbar-Flows), risikobasiert, wenn keine existiert. Ist der Report dünn, wird erst eine verifizierte Repro erzeugt. | Ein Fix ist auf Stage gelandet |
| /exploratory-testing | Chartered Session nach SBTM: ein Auftrag, eine Zeitbox, Playwright MCP im isolierten Browser. Für unklares Verhalten, neue Features, erste Blicke. | Kein wiederholbarer Spec vorhanden |
| /test-automation | Schreibt oder fährt deterministische Specs über den CLI-Runner — im Framework der Suite (Playwright oder WebdriverIO). TC-ID im Titel, Retries nur in CI (und dort, um den Trace des Flakes einzufangen). | Ein Ablauf ist verstanden und wiederholungswürdig |
| /recon | Pipeline-Phase 2 als eigener Skill: fährt die Probe (Playwright oder WDIO, gleiches `recon.json`-Format) und liefert die echten Bedienelemente, Formularfelder und Konsolenfehler — für einen Bruchteil der MCP-Kosten. Nur die Merge-Zusammenfassung kommt in den Kontext. | Bevor eine Spec geschrieben wird (hybrid/cli-first), oder direkt: „Erkunde die Seite" |
| webdriverio-testing | Die WDIO-Entsprechung der Playwright-Konventionen: deterministische Specs in WebdriverIO 9, Selenium Grid als Remote-Backend und Appium-Mobile als Betriebsmodus (Referenzen, kein eigenes Framework). Wird von test-automator geladen, nie direkt. | „Test assets" des Produkts sagen `Framework: webdriverio` |
| /failure-analysis | Triagiert jeden FAIL, bevor ein Bug aufgemacht wird: echtes Produkt-Defizit, oder ist der Testfall selbst veraltet, weil sich das Produkt absichtlich geändert hat? Vergleicht Assertion, JIRA-Änderungshistorie und Versionsfenster — **schlägt vor, wendet nie an**. | Automatisch bei jedem FAIL |
| /bug-report | Gießt eine Fundstelle in die Vorlage des Projekts oder des Produkts — nie eine eigene Struktur, nie eine übersprungene Sektion. Prüft auf Duplikate. | Ein FAIL-Verdikt liegt vor, Klasse `product-defect` |
| /report-to-jira | Kommentar, Anhänge und die exakte Workflow-Transition. Kennt den Shadow-Modus: dann wird komponiert und abgelegt statt gepostet. `NO_TEST` postet grundsätzlich nichts. | Ein Lauf ist fertig — PASS, FAIL, BLOCKED oder NEEDS\_REVIEW |
| /deploy-to-stage | Fährt das Deploy-Runbook des Projekts mit Sicherheitschecks. Prüft vorab, ob überhaupt ein Ausführungsweg existiert, und meldet sonst BLOCKED statt zu improvisieren. | Der Fix ist noch nicht auf Stage |
| /onboard-project | Das lange Interview (~30–60 min), das PROJECT.md füllt: Umgebungen, Testuser als Vault-Referenzen, Runbook, Gates, Reporting. Holt Transitions und Prioritäten aus JIRA statt zu fragen. | Ein Ticket-Präfix hat noch kein Projekt |
| /onboard-product | Die kurze Variante (5–15 min): nur was vom Projekt abweicht, plus die Feature-/Testmethoden-Matrix. Holt die echten JIRA-Komponenten fürs Routing. | Ein Projekt deckt mehrere Produkte ab |
| /scaffold-suite | Erzeugt das Playwright-Projekt, das die Blaupause voraussetzt: package.json, eine Config, deren Capture-Einstellungen die Evidence-Matrix sind, und eine erste laufende Smoke-Spec. | „Test assets: none yet" |
| /re-board | Delta-Onboarding: vergleicht ein Bestandsprojekt mit dem aktuellen Template und bietet nur die Lücke an — neue Felder (Secrets-Quelle, Versionsstempel), fehlende Dateien (Flow-Map-Seed aus bisheriger Evidence), offene TODOs. Jede Änderung einzeln bestätigt, danach Bridge-Refresh und neuer Stempel. Der Upgrade-Pfad für jedes Schema-Wachstum. | Nach einem Blueprint-Update; „Projekt aktualisieren" |
| /whats-new | Liest den Versionsstempel im PROJECT.md gegen die installierte Plugin-Version und rendert die CHANGELOG-Abschnitte dazwischen — in der Sprache der Frage, mit dem Hinweis, welche Änderung ein /re-board lohnt. Reine Orientierung, startet keine Arbeit. | „Was hat sich geändert?", nach einem Update |
| /skill-review | Liest die `skills_used`-Nutzungsdaten und klassifiziert jeden installierten Skill als used oder unknown — nie „unused": fehlende Daten sind unknown, kein Freigabegrund. Ohne Daten ist alles unknown und die Coverage 0%. Read-only; ein Profil-Vorschlag (full/standard/minimal/custom) bleibt ein Dry-run mit exakter Exclude-Liste, bis der Nutzer die konkrete Liste ausdrücklich bestätigt — und greift nur in einer integrate-Installation. | „Welche Skills brauchen wir wirklich?" |
| /qa-report | Liest alle `execution_summary.json` zurück: Pass-Rate pro Produkt, P0/P1, BLOCKED- und NO\_TEST-Gründe, Routing-Qualität, Learning-Durchsatz. Nennt ausdrücklich, was das Schema nicht hergibt. | „Wie läuft's?", Wochen- oder Sprintbericht |
| /retro-learn | Capture → Groom → Promote. Klassifiziert eine Überraschung nach Reichweite (Projekt, Produkt, projektübergreifend) und befördert sie beim zweiten Auftreten in eine Regel oder Projektdatei. | Session-Ende, oder wöchentlich zum Verdichten |

### Die 10 Spezialisten — vendored & blueprint-adapted

Aus `petrkindlmann/qa-skills` übernommen und überall dort angepasst, wo Upstream-Verhalten den Blueprint-Regeln widerspricht (Secrets-Fluss, Shadow-Disziplin, Stage-only, Report-Routing — die Änderungsliste steht in THIRD\_PARTY\_NOTICES.md). Sie gelten für
jedes onboardete Produkt; ihren Kontext bekommen sie über eine vorgemergte Bridge-Datei pro
Projekt und Produkt. qa-manager zieht einen davon, wenn die Feature-Matrix des Produkts es
vorgibt — nicht nach Gefühl.

| Skill | Wofür | Auslöser im Ticket |
| --- | --- | --- |
| api-testing | REST und GraphQL: Schema-Validierung, Auth-Flows, CRUD-Lebenszyklus, Fehler- und Header-Prüfung, Pagination | Backend-Änderung ohne UI, öffentliche API |
| accessibility-testing | WCAG 2.2 AA mit axe-core, Tastatur-Audits, Screenreader, ARIA-Muster — plus die rechtliche Zuordnung (ADA, EAA) | UI mit externen Nutzern, Layout/Kontrast/ARIA |
| security-testing | OWASP Top 10 automatisiert: ZAP, Dependency-Scan, Semgrep, Auth-/Session-Tests, XSS/CSRF/SQLi-Muster | Auth, Eingabefelder, Upload, alles Security-geflaggte |
| visual-testing | Screenshot-Regression: Baselines verwalten, Diff-Schwellen justieren, dynamische Inhalte maskieren, Viewports | Layout- oder branding-kritische Änderung |
| risk-based-testing | Risikomatrix aus Auswirkung × Wahrscheinlichkeit, Failure-Mode-Analyse, Abdeckung auf Risikozonen abbilden | Release oder Epic — „wo überhaupt anfangen?" |
| bug-reproduction | Aus einem dünnen Report eine verifizierte, minimale, deterministische Repro machen — inklusive `git bisect` und Rot-vor-Grün-Regressionstest | Bug-Report ohne belastbare Schritte |
| test-reliability | Flaky-Tests zur Laufzeit heilen und klassifizieren: Selektor-Heilung, Quarantäne, konfidenzbewertete Reparatur | Ein Test war nur beim Retry grün |
| qa-metrics | Kennzahlen definieren und interpretieren: Coverage, Flakiness, Defect-Escape-Rate, MTTR, Quality Gates, realistische Zielwerte | Formeln und Zielwerte für /qa-report |
| test-case-management | Manuelle Testfälle in TestRail, Xray, Zephyr, Qase: Anatomie, Bulk-Import aus User Stories, Traceability, wann ein Fall automatisiert gehört | Manuelle Suite pflegen oder importieren |
| release-readiness | Go/No-Go anhand von Belegen: Checklisten, Smoke-Suite-Design, Rollback-Kriterien, Nachverifikation | Release statt Einzelticket |

Sie sind fremder Code und nicht eingegrenzt. Zwei Beispiele aus dem Audit:
`release-readiness` operiert auf Produktions-Canary mit Auto-Rollback — beides in
dieser Blaupause hart verboten. `risk-based-testing` will in die Bridge-Datei
schreiben, die als read-only gilt. Und ihre Beschreibungen verweisen auf rund 24 Skills, die
es hier nicht gibt. Die Eingrenzung steht als offener Punkt auf der Liste; bis dahin ist
qa-manager die Instanz, die entscheidet, was von einem Spezialisten tatsächlich ausgeführt wird.

### Die 9 Subagents

| Subagent | Rolle | Werkzeuge |
| --- | --- | --- |
| qa-manager | Der Dirigent: liest das Ticket, routet zu Projekt und Produkt, entscheidet die Strategie anhand der Feature-Matrix, delegiert an die anderen — und prüft am Ende, ob Evidence und Deklaration wirklich da sind. Fährt selbst keinen Browser und schreibt keine Specs. | Read, Write, Edit, Grep, Glob, Bash, Task, atlassian |
| test-executor[-cheap|-deep] | Drei Lanes für exploratives Testen und Reproduktion über Playwright MCP: cheap für Fast Path, standard für komplexe Arbeit, deep für high/eskaliert. Isolierte Browser-Session, Accessibility-Snapshot zur Navigation und Screenshots nur als Beweis. | playwright (MCP), Read, Write, Bash |
| test-automator[-cheap|-deep] | Drei Lanes für Specs über den CLI-Runner — rund 4× günstiger als derselbe Ablauf turn-by-turn über MCP. Arbeitet im Framework der Suite (Playwright oder WebdriverIO, inkl. Selenium Grid und Appium-Mobile über WDIO). | Bash, Read, Write, Edit, Grep, Glob |
| failure-analyst | Triagiert jeden FAIL vor dem Bug-Report: Produkt falsch, oder Test veraltet? Kommt **absichtlich ohne Write und Edit** — ein Agent, der einen roten Test grün schreiben kann, ist genau der Fehlermodus, den diese Rolle verhindert. | Read, Grep, Glob, Bash, atlassian |
| bug-reporter | Verwandelt eine Fundstelle in einen Report nach der exakten Projekt- oder Produktvorlage, mit Severity→Priorität-Mapping und Evidence-Referenzen statt eingebetteter Bilder. | Read, Write, Grep, Glob, atlassian |

Die Werkzeuglisten sind Absicht: test-executor hat keinen Zugriff auf JIRA, bug-reporter
keinen auf einen Browser, failure-analyst kann nichts editieren. Wer nicht schreiben können
muss, kann es nicht.

## Wissensarchitektur

```
# Projektweites Wissen oben, Abweichungen unten
projects/SHOP/
├── PROJECT.md              ← gilt für ALLE Produkte, enthält die Routing-Registry
├── learnings.md
├── flow-map.md             ← kuratiert durch /retro-learn: Flows, Anker, Nachbarn
├── templates/bug-report.md
└── products/               ← fehlt bei Ein-Produkt-Projekten komplett
    ├── STOREFRONT/           ← nennt NUR, was abweicht (~60 Zeilen)
    └── ADMIN/
```

Der Kniff, der ~30 Dateiänderungen erspart hat: wo eine Regel `PROJECT.md` sagt,
ist die *effektive* Projektdatei gemeint — Projektdatei, gemergt mit der gerouteten
Produktdatei. Kein geroutetes Produkt heißt: nichts gemergt, Verhalten exakt wie vorher.

### Routing-Leiter

| Stufe | Signal |
| --- | --- |
| 1 | Produkt explizit genannt (`--product=ADMIN` oder „teste das im Admin") |
| 2 | Genau ein Treffer über die JIRA-Komponente |
| 3 | Genau ein Treffer über ein Label (exakt, kein Beinahe-Treffer) |
| 4 | Treffer auf einen `project-wide`-Eintrag → Infra-Ticket, nur Projektdatei |
| 5 | Sekundärsignale: Epic/Parent, Fix Version, geänderte MR-Pfade |
| 6 | Kein Treffer, aber ein Default deklariert → Default mit niedriger Konfidenz |
| 7 | Mehrdeutig oder unbekannt → nachfragen; headless: BLOCKED |

Ein Default löst **Stille** auf, niemals einen **Konflikt** — sonst
testet der Agent überzeugend grün am falschen Produkt vorbei. Und das Routing lernt: eine vom
Menschen formulierte Regel landet sofort in der Registry, ein Einzelfall nach der zweiten
gleichartigen Auflösung, eine Ausnahme nie.

### Was ein Produkt überschreiben darf

| Bereich | Override |
| --- | --- |
| Umgebungen, Testuser, Test-Assets, Feature-Matrix, Gotchas, Bug-Template, Deploy-Schritte | ja |
| Quality Gates (Pass-Rate, P0/P1, Coverage) | nur strenger |
| „Agent darf deployen", „Agent darf MRs kommentieren" | nur einschränkend |
| JIRA-Transitions, Report-Format, Evidence-Pflicht, alle Sicherheitsregeln | nie |

Die zwei gefährlichsten sind strukturell gelöst statt überwacht: deploy-to-stage und
report-to-jira lesen Deploy-Berechtigung und Transitions ausschließlich aus der Projektdatei.
Keine Produktdatei kann sie erteilen — egal, was ein Merge produziert.

## Was mechanisch erzwungen wird

Der wichtigste Teil, weil Regeln beratend sind und Hooks nicht.

| Mechanik | Erzwingt | Fixtures |
| --- | --- | --- |
| pre-tool-guard | Keine Schreibzugriffe auf `.env*` oder secret-benannte Pfade, kein `rm -rf`, kein Force-Push; Secret-Lesungen sind ein menschlicher Opt-in (`secrets_read` in `.qa-guard.json`), Agenten-Edits daran sind verweigert; `qa-secrets.mjs` injiziert Zugangsdaten wertefrei in Runner und MCP-Server | 107 |
| stop-evidence-check | Kein Verdikt ohne `execution_summary.json` — und ohne deklarierte `learnings`. Block-Meldungen tragen maschinenlesbare Marker (`QA_EVIDENCE_MISSING:` / `QA_LEARNINGS_MISSING:`), damit eine Pipeline eine Policy-Verletzung von einem Crash unterscheiden kann | 20 |
| session-start | Orientierung: Projekte samt Produkten, ungegroomte Learnings, Secrets-Status — Env-Datei fehlt, oder Keychain-Statuszeile (`n/m keys present`, Fehlende namentlich), plus JIRA-PAT aus der Keychain in die Session exportiert. MCP-Config-Scan (Dedupe, unmaskierte Secrets, Erstlauf-Hinweis). Im Plugin-Modus injiziert er die `CLAUDE.md` des Plugins **wortwörtlich** — ein Router-Text, keine Drift zwischen Installationsarten | 62 |
| post-jira-audit | Jeder JIRA-Schreibzugriff landet im Audit-Log, auch headless | — |
| install.sh | Kein Hook, gleicher Anspruch: Namespacing, Pfad-Rewriting, Idempotenz, Uninstall, Plugin-Verdrahtung, Self-Setup, MCP-Adoption — je Harness eine eigene Batterie | 119 |
| context-budget | Die immer geladene Ebene bleibt im Budget — gemessen statt behauptet | Check |

**Warum es diese Fixtures gibt.** Der Guard-Hook hat über die gesamte Lebenszeit
des Repos nichts blockiert: die Python-Ausdrücke waren falsch gequotet, der Parser scheiterte
still, jede Prüfung wurde übersprungen — und in der Review sah alles korrekt aus. Seitdem
gilt: ein Hook ist erst dann Durchsetzung, wenn ein Test beweist, dass er blockt. Dieselbe
Regel hat später weitere echte Fehler gefunden, darunter einen, der jeden Skill beim zweiten
Installationslauf als Kollision meldete.

## Die fünf Verdikte

| Verdikt | Bedeutung | Folgen |
| --- | --- | --- |
| PASS | Getestet, keine Befunde | Kommentar + PASS-Transition, Screenshot als Beleg |
| FAIL | Mindestens ein Befund; failure-analysis hat die Klasse geliefert | Bug-Report bei `product-defect`; Transition je nach Klasse |
| BLOCKED | Der Test lief nie: Umgebung weg, Fix nicht deployed, Routing unauflösbar | Kommentar mit Grund und Entblocker; nicht in der Pass-Rate |
| NEEDS\_REVIEW | Der Test ist vermutlich selbst veraltet (`test-outdated`/`test-brittle`) | Vorschlag an einen Menschen, keine Transition, zählt wie FAIL in der Pass-Rate; headless unerreichbar |
| NO\_TEST | Testwerkzeuge liefen, aber kein Test wurde abgeschlossen — Untersuchung, Flaky-Debugging, früher Abbruch | Ein-Satz-`no_test_reason`, kein JIRA-Post, aus der Pass-Rate ausgenommen — der explizite Ausweg aus dem Stop-Hook statt stillem Session-Ende |

## Shadow-Modus — standardmäßig an

Shadow-Modus ist **Default**: der Agent testet vollständig, erzeugt Evidence,
komponiert Kommentar und Transition — und legt sie als Vorschlag ab, statt sie zu posten.
Schreibzugriff wird explizit erteilt: `QA_AGENT_SHADOW=0` oder
`Shadow mode: off` im Projektfile. Prüfbar am bestehenden Audit-Log: ein
Shadow-Lauf mit einem Eintrag darin ist ein Bug, keine Ermessensfrage.

Das größte Adoptionsrisiko ist nicht Technik, sondern Vertrauen. Ein Agent, der ab Tag eins
in echte Tickets schreibt, wird beim ersten falschen Reopen abgeschaltet — und dann ist die
Blaupause politisch tot, egal wie gut sie ist. Zwei Wochen Shadow-Betrieb sind der Nachweis,
den ein Team braucht, um Schreibrechte zu vergeben.

## Secrets: einmal in die Keychain, nie wieder im Chat

Schluss mit Passwort-Chaos: der Agent sieht, welche Logins er *hat* — statt zu fragen
(„du hast die Daten doch") oder sich welche auszudenken. Deklariert ein Projekt
`Secrets source: keychain`, kommen alle Werte aus der macOS Schlüsselbundverwaltung:
nie im Chat, nie in Dateien im Repo, nie auf GitHub.

#### 🔑 Testuser-Logins

Der Resolver (`resolve-secrets.sh`) schreibt `.env.playwright-secrets`
aus der Keychain — beim Onboarding, bei `/re-board` und wann immer die Datei fehlt.
Der Session-Start zeigt eine Statuszeile (`6/6 Logins vorhanden`, Fehlende namentlich).
Das Einrichten macht der Agent selbst: **Import** räumt früher handgetippte Werte
aus der Env-Datei in die Keychain um, **Capture** fragt jedes fehlende Passwort über
einen nativen macOS-Dialog ab — Eingabe verdeckt, ins Fenster getippt, nie in den Chat. Der Agent
sieht zu keinem Zeitpunkt einen Wert, er meldet nur: „3 gespeichert, 1 fehlt noch."

#### ☁️ JIRA-PAT (Data Center)

Dieselbe Mechanik eine Ebene höher: Service `JIRA_PAT_<jira-host>`, Account
`jira`. Der Session-Start-Hook exportiert den Token pro Projekt in die Session
(`$CLAUDE_ENV_FILE`) — er liegt in **keiner** Datei und braucht keinen
globalen Export in der `~/.zshrc`. CI/Nicht-macOS: `JIRA_PERSONAL_TOKEN`
wie gehabt, der gewinnt immer.

```
# einmalig pro Passwort — der Service-Name ist der KOMPLETTE
# Secret-Key aus PROJECT.md → „Test users" → Spalte „Env/secret key",
# nicht nur das Projekt-Kürzel:
security add-generic-password -s SHOP_QA_STANDARD_PASSWORD -a qa -w
```

Rotation oder neuer Testuser? Der Agent meldet den fehlenden Key namentlich und fragt per
Dialog nach. `Secrets source: env-file` (Handpflege) bleibt der Default — Keychain
ist eine Projektentscheidung, gefragt beim Onboarding, in zwei Minuten nachgerüstet via
`/re-board`.

## Der Lernkreislauf

#### →Capture wird erzwungen

Jeder Lauf deklariert im Summary, was gelernt wurde — oder in einem Satz, warum nichts
anfiel. Fehlt die Deklaration, blockt der Stop-Hook.

#### →Grooming wird sichtbar

Der Session-Start meldet die Zahl ungegroomter Einträge, damit kein Rückstau still anwächst.

#### →Promotion ist das Ziel

Zweimal gesehen heißt: rein in eine Regel, eine Projekt- oder Produktdatei — dort wird es
automatisch geladen und nie wieder erklärt. Die Feature-Matrix wird nachgezogen: eine
veraltete Matrix ist schlechter als keine, weil sie belegt aussieht. Flow-Wissen — welche
Bereiche der App wie zusammenhängen — wandert in die **Flow-Map**
(`flow-map.md`): `/retest-bug` zielt seine Regressions-Sweeps aus den
dort kuratierten Nachbar-Flows, statt zu raten.

## Getestet, geschrieben, oder nichts von beidem

Die für einen Piloten wichtigste Tabelle: was hier steht, ist nicht überall gleich gut abgesichert.

| Bereich | Absicherung |
| --- | --- |
| Hooks (Guard, Stop, SessionStart) | 16 Suites mit >1.000 Assertions — jede Regel mit eigenem Fall |
| Installer (Integrate, Plugin, Self-Setup, Uninstall, MCP-Adoption) | 119 Fixtures — end-to-end gegen ein Wegwerf-Repo, beide Harnesses |
| Kontextkosten | gemessen — Budget-Check, 8.372 von 8.400 Token belegt |
| Semantik (Routing, Merge, versiegelte Felder, Failure-Klassen, Execution-Modes) | 45 Eval-Cases — ein eigenes Skript fährt sie über `claude -p` oder OpenRouter |
| Ein echtes Projekt, ein echtes Ticket | **nie** — genau das ist der Pilot |

Der erste gelaufene Eval-Case war lehrreich: die Antwort war präziser als der Grader — sie
las zusätzlich `memory/INDEX.md`, was die Lookup-Policy vorschreibt. Ein Grader,
der eine richtige Antwort durchfallen lässt, ist kaputt und wurde nachgeschärft. Genau dafür
ist ein erster Lauf da.

## MCP-Server

Kein festes Limit, sondern ein deklariertes Register: `.mcp.json` ist die
Verdrahtung, die Tabelle in der Regel die Begründung. Steht ein Server nur in einem von
beiden, ist das ein Befund. Der Agent fügt nie selbst einen hinzu — er schlägt vor, der
Mensch entscheidet.

| Server | Warum im Budget |
| --- | --- |
| playwright | Ohne Browser kein UI-Test. Läuft `--isolated --headless --secrets`. |
| atlassian | Tickets rein, Ergebnisse raus — die ganze Prämisse ist ticketgetrieben. |

**Ein CLI ist kein Server.** Eine Pipeline zu triggern (`gh`,
`glab`, `curl`) ist ein Bash-Kommando, das im Projektfile steht — kein
Grund für einen dritten MCP-Server. /deploy-to-stage prüft dieses Feld vorab und meldet
BLOCKED, wenn es fehlt, statt sich ein plausibel aussehendes Kommando auszudenken.

**Credential-Server sind erlaubt, aber mit Auflage.** Ein Vault-MCP darf eine
Referenz für das Tool auflösen, das sie braucht — und nie einen Wert ins Transkript, in eine
Datei, ein Ticket oder ein Artefakt bringen. Auf macOS ist dafür meist gar kein Server nötig:
die Keychain-Integration (siehe oben) liefert Testuser-Logins und den JIRA-PAT, und
Browser-Logins laufen weiterhin über die `--secrets`-Maskierung.

## Was kostet der Betrieb?

Das Plugin ist kostenlos. Das Git-Repo wird genau zweimal kontaktiert: bei der
Installation und beim expliziten Update. Alles andere läuft lokal; die einzigen
Netzwerk-Ziele im Betrieb sind **dein JIRA** und **deine Stage**.
Keine Telemetrie, keine Lizenz-Checks.

Die echten Kosten sind **Modell-Tokens**. Die immer geladene Ebene ist gemessen
(~8.300 Tokens) und gedeckelt; Skills und Detailregeln laden bei Bedarf. Learnings
werden ticketbezogen durchsucht, rohe Evidence nicht eingelesen, und einfache
Tickets überspringen die Manager-Ebene. Eine versiegelte Run-Capsule ersetzt bei
jedem weiteren Agenten-Spawn das erneute Lesen und Mergen des Projektkontexts.
Die Modell-Lane wählt pro Branch: Fast/low → cheap, komplex low/medium → standard,
high/eskaliert → deep. Claude bildet das auf haiku/sonnet/opus ab; opencode erbt
ohne Overrides oder nutzt die unter `/model-setup` konfigurierten Modelle und Varianten.

| Kostentreiber | Gegenmaßnahme |
| --- | --- |
| Browser-Snapshot-Verlauf | isolierter Execution-Subagent; Modell-Lane nach Risiko (haiku/sonnet/opus bzw. Consumer-Override) |
| wiederholtes Intake/Routing | Fast Path bzw. Manager-Handoff mit fertigen Artefakten |
| Tests auf altem/fehlendem Build | Readiness vor jeder Stage-Aktion |
| wachsende Lern- und Rohdaten | 16-KB-Grooming, verdichtete Promotion, Raw-Read-Denys |
| wiederholte Flows | vorhandene Specs über den CLI-Runner |

**Ehrlichkeit:** Die Modell-Lane verändert den Preis der Browser-Tokens, nicht ihre Menge.
Für 0.18.3 liegt kein neues Kostenbenchmark vor; ältere Euro- und Ticket-Schätzungen
sind deshalb keine Zusage. Miss deine eigenen Abläufe mit `/usage` und den Session-Logs.

## Häufige Fragen

Die Fragen, die im Gespräch immer kommen — beantwortet ohne Fachjargon.

#### ?Wie funktioniert das Gedächtnis?

Gar nicht im Kopf — alles liegt als normale Textdateien in deinem Projektordner,
einsehbar und per Git teilbar. Fünf Schubladen: das **Handbuch** (immer dabei,
nur die Regeln), die **Fachbücher** (30 Skills, laden nur bei Bedarf), die
**Projektakte** (Umgebungen, Testuser, Runbooks — einmal eingerichtet), das
**Lerntagebuch** (Überraschungen aus Läufen) und die **Beweise**
(Screenshots, Logs — als Datei, nie im Gedächtnis). Der Clou: Am Ende jeder Session
*muss* der Agent deklarieren, was er gelernt hat — ein Hook blockt das Session-Ende
sonst. Was zweimal vorkam, wandert ins Handbuch und muss nie wieder erklärt werden; was
verworfen wurde, landet im Rejected-Buffer und wird nicht erneut vorgeschlagen.

#### ?Verbrennt das ständige Lesen und Lernen nicht selbst Tokens?

Ja — deshalb ist der Lernkreislauf begrenzt: Capture dedupliziert sofort, Grooming
arbeitet höchstens zehn älteste Einträge pro Durchlauf und startet spätestens bei
16 KB. Promotion ersetzt und verdichtet statt anzuhängen. Beim Ticket werden nur
stabile Projektdaten und passende Learning-Einträge gelesen, nicht ganze Archive.
Der Nutzen ist, bekannte Umgebungen, Fallstricke und Deploy-Wege nicht bei jedem
Lauf neu erkunden zu müssen; ein eigenes Benchmark für 0.18.3 steht noch aus.

#### ?Wie effizient ist eine Session?

Die immer geladene Ebene ist ~8.300 Tokens (gemessen, per Test gedeckelt). Browser-Arbeit
läuft in abgeschotteten Teil-Sessions; einfache Tickets gehen direkt an genau einen
Execution-Agenten, komplexe übergeben fertiges Intake und Readiness an den Manager.
Vorhandene Specs laufen über den CLI-Runner. Die Execution Modes bestimmen, wo sich
teure Live-Beobachtung lohnt; gemessen wird mit `/usage`, nicht mit alten Schätzwerten.

#### ?Brauche ich zwingend JIRA?

Der Blueprint ist ticketgetrieben — der Ticket-Schlüssel ist der Eingang, über den der
Agent alles findet. Gelesen wird über den Atlassian-MCP-Server (Cloud oder Data Center);
nutzt ein Projekt JIRA nur per Weboberfläche, geht es notfalls auch über den Browser.
Ohne JIRA ergäbe das Routing keinen Sinn — aber die Skills (exploratives Testen,
Accessibility, Security, Autotests) funktionieren auch ticketlos.

#### ?Läuft das auch ohne Claude Code?

Ja — derselbe Blueprint läuft unter **opencode** (modell-offen, das Modell
ist deine Wahl) und wird dort per Symlink-Install verdrahtet. Ein Router-Text für beide
Welten, keine Drift: der Session-Start-Hook injiziert ihn im Plugin-Modus wortwörtlich.
Hooks, Skills und Guardrails sind auf beiden Seiten dieselben, die Fixture-Batterie läuft
für beide.

#### ?Was passiert mit meinen Daten?

Nach der Installation läuft alles lokal. Netzwerk geht nur zu **deinem JIRA**
und **deiner Stage** — keine Telemetrie, keine Lizenz-Checks, das Repo wird nur
bei Install und Update angefasst. Passwörter sieht der Agent nie: Testuser-Logins und der
JIRA-Token liegen im macOS-Schlüsselbund, er sieht nur „6/6 Logins vorhanden". Direkte
Secret-Lesungen sind ein Opt-in, das nur ein Mensch erteilen kann.

#### ?Was, wenn der Agent sich irrt?

Dafür gibt es eingebaute Ehrlichkeit statt Nachsicht: Bei jedem FAIL klärt ein eigener
Prüfer (ohne Schreibrechte), ob das Produkt kaputt oder der Test veraltet ist. Unsicherheit
wird zu **NEEDS\_REVIEW** — ein Vorschlag an einen Menschen, kein Bug-Ticket,
kein Statuswechsel. Und wenn ein Mensch den Agenten überstimmt, ist das die wertvollste
Learning im ganzen System: Sie wandert mit Ursachenanalyse ins Regelwerk, damit derselbe
Fehlgriff nicht zweimal passiert.

#### ?Kann er auch in Produktion testen?

Nein — niemals, egal wer fragt oder wie es formuliert ist. Nur Stage. Verlangt ein Ticket
eine Prod-Verifizierung, meldet der Agent BLOCKED mit Grund, statt kreativ zu werden.
Deploys darf er nur auf Stage und nur, wenn das Projekt es ausdrücklich erlaubt; MRs
kommentieren oder mergen darf er nie.

#### ?Muss ich programmieren können oder Befehle kennen?

Nein. Du schreibst ganz normal: „Teste SHOP-1234", „Der Fix ist auf Stage, prüf das",
„Wie läuft's mit dem Testing?" — deutsch oder englisch. Auch das Lernen läuft von allein:
Jede Session *muss* deklarieren, was sie gelernt hat (ein Hook erzwingt es), und
wächst der Stapel ungeprüfter Learnings über eine Schwelle (5 Einträge, 14 Tage alt oder 16 KB),
räumt der Agent ihn am Session-Ende **von selbst** auf und berichtet in einem
Satz, was daraus wurde. Die Einrichtung ist ein geführtes Interview (~30–60 Minuten pro
Projekt). Einzige Menschen-Aufgaben: JIRA-Zugang einrichten, Testuser-Passwörter einmal
in den Schlüsselbund legen, und am Anfang die Shadow-Modus-Vorschläge prüfen, bis du ihm
Schreibrechte gibst.

#### ?Wie fange ich an?

Zwei Befehle (siehe Installation oben), Claude Code neu starten, JIRA einmal per OAuth
verbinden — dann `/onboard-project` und das Interview beantworten. Danach heißt
es nur noch: „Teste *TICKET*." Der Shadow-Modus ist ab Tag eins an — der Agent testet
vollständig, postet aber nichts, bis du es freigibst.

QA Agent Blueprint · Stand: 29. Oktober 2026 (0.18.3) —
aktualisiert auf Repo-Stand (32 Skills, 9 Subagents, Fixture-Batterie + 145 bun-Tests, 45 Eval-Cases,
5 Verdikte, zwei Harnesses — Claude Code als Plugin, opencode per Symlink-Install —,
Execution Modes mcp-only/hybrid/cli-first mit /recon-Probe, Rotprobe und Beobachtungslauf,
Keychain-Secrets für Testuser-Logins und JIRA-PAT, wertefreie Credential-Injection via qa-secrets.mjs,
Flow-Maps, /re-board und /whats-new als Upgrade-Pfad, /skill-review Skill-Nutzungsanalyse
(used/unknown, Profile nur nach Bestätigung), Shadow-Modus als Default).
Quelle der Wahrheit ist das Repo: `CLAUDE.md`, `memory/INDEX.md`, `README.md`.
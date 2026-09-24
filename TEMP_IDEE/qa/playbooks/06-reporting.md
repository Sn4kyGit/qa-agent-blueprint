# Playbook 06 – Reporting

## Reihenfolge

Erst die Uebersicht fuer den Menschen, dann die Ticketkommentare als Entwurf.
Tickets werden nicht ohne Bestaetigung angelegt oder kommentiert, ausser das
Projekt erlaubt es ausdruecklich.

## Aufbau des Ticketkommentars

```
Testergebnis: PASS | FAIL | BLOCKED | TEILWEISE
Umgebung: <env> | Build: <version> | Modus: <mcp-only|hybrid|cli-first>
Getestet mit: <rolle/testuser> | Datum: <...>

Abdeckung:
  AK1  <kurztitel>  PASS
  AK2  <kurztitel>  FAIL   -> <Bugticket>
  AK3  <kurztitel>  NOT TESTED (<Begruendung>)

Zusaetzlich geprueft: <Regressionsumfang in einem Satz>
Nicht geprueft:      <mit Begruendung>
Auffaelligkeiten:    <aus Beobachtungskanal und Beobachtungslauf>
Evidenz:             qa/evidence/<TICKET>/<zeitstempel>/
```

Die Statuszeile steht immer oben. Wer den Kommentar ueberfliegt, muss nach
einer Zeile Bescheid wissen.

Die **Modus-Angabe ist Pflicht**: wer das Ergebnis spaeter bewertet, muss
wissen, ob live beobachtet oder nur assertiert wurde.

## Formatierung

Das Zielformat (JIRA-Wiki-Markup, Markdown, Plain Text) steht im Projekt unter
`.claude/skills/reporting-format/` bzw. `.opencode/skill/reporting-format/`.
Dieses Playbook definiert den Inhalt, nicht die Syntax. Fehlt ein
Projektformat: Markdown, mit einmaligem Hinweis.

## Evidenz

Ablage `qa/evidence/<TICKET>/<YYYY-MM-DDTHHmm>/`, Dateien nummeriert und
sprechend benannt, keine Leerzeichen, keine Umlaute.

| Ergebnis | Pflichtevidenz |
|----------|----------------|
| PASS | ein Nachweis je Akzeptanzkriterium |
| FAIL | Screenshot des Fehlerzustands, Konsole, relevante Response, Trace |
| BLOCKED | Beleg des Blockers |

Vor dem Anhaengen pruefen: keine Zugangsdaten, keine Tokens, keine echten
Personendaten sichtbar.

## Bugreport

Vor dem Anlegen: Duplikatpruefung gegen `qa/known-issues.md` und das
Ticketsystem. Treffer bedeutet Kommentar am bestehenden Ticket, nicht neues
Ticket.

Pflichtbestandteile: Titel (Bereich, beobachtetes Verhalten, Bedingung),
Umgebung mit Build, Vorbedingungen, nummerierte Reproschritte ohne
Interpretation, erwartetes Ergebnis mit Quelle, tatsaechliches Ergebnis
woertlich, Reproduzierbarkeit, Evidenz, Severity als **Vorschlag** mit
Begruendung, Abgrenzung.

Felder, deren korrekten Wert du nicht kennst, bleiben leer und werden im
Entwurf benannt. Kein Ratewert in einem Pflichtfeld.

## Journal

Abschliessend `qa/test-journal/<YYYY-MM-DD>-<TICKET>.md`:

```markdown
# <TICKET> - <Kurztitel>
Datum: <...> | Env: <...> | Build: <...> | Modus: <...>

## Scope
<zwei Saetze>

## Ergebnis
<Status> - <ein Satz>

## Details
| AK | Testfall | Ergebnis | Evidenz |

## Auffaelligkeiten
- <ausserhalb des Scopes>

## Gelernt
- <falsche Annahme, Erkenntnis ueber das Projekt, Flake, Formatkorrektur>
```

Der Abschnitt `## Gelernt` ist die Eingabe fuer die Retro. Wenn nichts gelernt
wurde, ausdruecklich `- nichts` schreiben, statt den Abschnitt wegzulassen.

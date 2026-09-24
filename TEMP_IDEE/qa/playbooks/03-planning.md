# Playbook 03 – Planung

Ziel: aus Akzeptanzkriterien Testfaelle ableiten, einschliesslich der Faelle,
die im Ticket fehlen. Schritt mit dem hoechsten Denkanteil und der geringsten
Kontextmenge, deshalb das staerkste Modell (`models.planning`).

Bei `risiko: low` kann die Planung mit dem Standardmodell laufen. Der
Unteragent-Start lohnt dort nicht.

## Eingabe

`intake.json` und `recon.json`. Kein Anwendungscode. Testfaelle kommen aus den
Anforderungen, nicht aus der Implementierung — sonst prueft der Test die
Implementierung gegen sich selbst.

## Techniken

- **Aequivalenzklassen** bei Wertebereichen, je eine gueltige und eine
  ungueltige Klasse
- **Grenzwerte** an der Grenze, eins darueber, eins darunter. Klassiker: 0, 1,
  Maximum, Maximum+1, leer
- **Entscheidungstabelle**, wenn mehrere Bedingungen das Ergebnis bestimmen
- **Zustandsuebergaenge** bei Objekten mit Lebenszyklus, inklusive mindestens
  zwei **ungueltiger** Uebergaenge
- **Pfadtest** fuer End-to-End: Happy Path plus die zwei wahrscheinlichsten
  Abweichungen
- **Paarweise** bei vielen unabhaengigen Parametern

## Immer zusaetzlich pruefen

Auch wenn es nicht im Ticket steht: fehlende Rechte, abgelaufene Session,
leere Liste, genau ein Eintrag, sehr viele Eintraege, Doppelklick auf Absenden,
Reload mitten im Flow, Wirkung auf angrenzende Funktionen.

## Luecken im Ticket benennen

Der Auftrag geht ausdruecklich ueber die Akzeptanzkriterien hinaus:

- Widersprueche zwischen zwei Kriterien
- implizite Grenzwerte, die kein Kriterium ausspricht
- Kombinationen mehrerer einzeln definierter Kriterien
- Kriterien, die sich nicht als Assertion formulieren lassen, ohne ihre
  Bedeutung zu verkuerzen (etwa "verstaendliche Fehlermeldung")

Der letzte Punkt loest eine Eskalation aus: dieser Testfall wird live
beobachtet, nicht assertiert.

## Regressionsumfang

Aus dem Diff und `qa/PROJECT-MAP.md` bestimmen:

| Stufe | Ausloeser | Inhalt |
|-------|-----------|--------|
| Smoke | jeder Deploy | Login, Startseite, ein Kernflow |
| Fokus | normaler Change | Smoke + betroffene Features + Nachbarn |
| Breit | geteilte Komponente, Auth, Datenmodell | Fokus + alle Nutzer der Komponente |
| Voll | Release, Framework-Update | komplette P1-Suite |

## Ausgabe: `testplan.md`

```markdown
# Testplan PROJ-1234
Umgebung: stage | Build: release-24.9 | Modus: hybrid | Risiko: high

| # | AK | Titel | Technik | Prio | Werkzeug | Erwartung |
|---|----|-------|---------|------|----------|-----------|
| 1 | AK1 | Gueltiger Code reduziert Betrag | Aequivalenz | P1 | spec | ... |
| 2 | AK2 | Unter Mindestbestellwert abgelehnt | Grenzwert | P1 | spec | ... |
| 3 | AK2 | Fehlermeldung ist verstaendlich | – | P2 | mcp | ... |

Regression: Fokus – Checkout und Warenkorb (geteilte Preisberechnung)

## Luecken im Ticket
- AK1 und AK2 sagen nicht, was bei zwei kombinierten Codes passiert

## Nicht getestet
- Zahlungsanbieter-Integration (eigenes Ticket PROJ-1250)

## Freigabe
Status: offen
```

**Ohne Freigabe startet Phase 4 nicht.** Der Schritt kostet zwei Minuten und
verhindert die teuerste Fehlerklasse: gruendlich das Falsche testen.

# Playbook 05 – Verifikation

Diese Phase schliesst die Qualitaetsluecke zwischen CLI und Live-Beobachtung.
Sie wird am haeufigsten weggelassen und ist der Grund, warum CLI-Ergebnisse
sonst schlechter ausfallen.

## Rotprobe

**Eine Spec, die noch nie rot war, ist kein Nachweis.**

Vor der ersten Verwendung wird die Erwartung gezielt verletzt:

1. Bevorzugt ueber die Daten oder den Zustand – Testdaten so setzen, dass das
   Akzeptanzkriterium nachweislich verletzt ist.
2. Ersatzweise durch kurzzeitiges Invertieren der Assertion.

Faellt der Test dabei **nicht**, prueft er nicht, was er zu pruefen vorgibt,
und wird ueberarbeitet. Das kostet pro Spec etwa eine Minute und faengt die
gesamte Klasse Falsch-Gruen ab.

Steuerung: `hybrid.require_red_check`. Ergebnis wird in `verdict.json`
festgehalten. Eine Spec ohne bestandene Rotprobe darf kein `PASS` begruenden.

## Beobachtungslauf

Bei `hybrid.verification_pass: true` folgt nach dem gruenen CLI-Durchlauf eine
**kurze** MCP-Session ueber den Hauptflow – wenige Schritte, mit dem
ausdruecklichen Auftrag, auf alles zu achten, was *nicht* in den Assertions
steht:

- Layout, abgeschnittene Texte, ueberlappende Elemente
- Ladezustaende, doppelte Spinner, Flackern
- Text- und Sprachqualitaet von Meldungen
- Zustaende, die im Testplan nicht vorkamen

Alles Gefundene geht als `Auffaelligkeiten` in den Report, nicht als `FAIL`,
ausser es verletzt ein Akzeptanzkriterium.

Kosten: eine kurze Session pro Ticket statt einer langen. Der Nutzen ist hoch,
weil hier genau die Befunde entstehen, die eine Spec systematisch uebersieht.

## Fehlschlaege einordnen

Jeder rote Test bekommt genau eine Kategorie. **Vorher wird nicht wiederholt.**

| Kategorie | Merkmal | Konsequenz |
|-----------|---------|------------|
| echter Fehler | Anwendung verhaelt sich falsch, Assertion beschreibt das AK korrekt | Bug melden |
| Testfehler | Selektor veraltet, Testdaten kollidieren, Timing-Annahme falsch | Spec korrigieren, Aufklaerung ggf. wiederholen |
| Umgebungsproblem | Service nicht erreichbar, Stand nicht deployed, DB leer | `BLOCKED`, Ursache melden |

Fuer diese Einordnung braucht das auswertende Modell die Akzeptanzkriterien im
Kontext. Sie werden deshalb mit dem Ausfuehrungsauftrag uebergeben.

## Flakes

Ein Test, der ohne Codeaenderung mal gruen und mal rot ist, ist ein eigener
Befund. Hoechstens eine gezielte Wiederholung, deren Ergebnis mitgemeldet wird.
Nie `retries` erhoehen, nie die Assertion abschwaechen, nie ohne Ticket
skippen. Eintrag in `qa/known-issues.md`.

## Ausgabe: `verdict.json`

```json
{
  "rotprobe": { "durchgefuehrt": true, "bestanden": ["AK1", "AK2"] },
  "beobachtungslauf": {
    "durchgefuehrt": true,
    "turns": 6,
    "auffaelligkeiten": [
      "Fehlermeldung bei AK2 erscheint erst nach 2s ohne Ladeindikator"
    ]
  },
  "einordnung": [
    { "ak": "AK2", "kategorie": "echter Fehler",
      "begruendung": "500 auf /api/discount/validate, UI zeigt keine Meldung" }
  ],
  "gesamt": "FAIL"
}
```

# Einbau in ein Projekt

## Was wohin gehoert

```
qa/qa-config.yml            Modus und Einstellungen        werkzeugneutral
qa/playbooks/*.md           das gesamte Ablaufwissen        werkzeugneutral
qa/probes/                  Aufklaerungsskripte             werkzeugneutral
qa/runs/                    Uebergabevertraege je Lauf      erzeugt, nicht committen
qa/evidence/                Nachweise                       erzeugt, nicht committen
.claude/                    Adapter Claude Code             duenn
.opencode/                  Adapter OpenCode                duenn
```

**Regel:** Inhalte stehen genau einmal, in `qa/playbooks/`. Die Adapter
verweisen darauf, sie kopieren nicht. Sonst driften die beiden Zweige nach
wenigen Wochen auseinander.

## Claude Code

Dateien uebernehmen, dann in `CLAUDE.md` einen Zeiger setzen:

```markdown
## QA
Testablauf: Skill `qa-pipeline`, Wissen in `qa/playbooks/`.
Konfiguration: `qa/qa-config.yml`. Projektkarte: `qa/PROJECT-MAP.md`.
Vor Testaufgaben zuerst die Projektkarte lesen, nicht den Code durchsuchen.
```

Playwright-MCP in `.mcp.json`:

```json
{
  "mcpServers": {
    "playwright": {
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest", "--isolated"]
    }
  }
}
```

Start: `/qa-pipeline PROJ-1234`

## OpenCode

Dateien uebernehmen, dann in `AGENTS.md` denselben Zeiger setzen wie oben.
`AGENTS.md` und `CLAUDE.md` bleiben inhaltlich identisch und enthalten beide
nur Verweise, keine Inhalte. Beide unter 200 Zeilen.

Modelle und MCP in `opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "anthropic/claude-sonnet-4-6",
  "agent": {
    "qa-planner":  { "model": "anthropic/claude-opus-4-5" },
    "qa-runner":   { "model": "anthropic/claude-haiku-4-5" },
    "qa-observer": { "model": "anthropic/claude-sonnet-4-6" }
  },
  "mcp": {
    "playwright": {
      "type": "local",
      "command": ["npx", "-y", "@playwright/mcp@latest", "--isolated"],
      "enabled": true
    }
  }
}
```

Start: `/qa-test PROJ-1234`

Die Modell-IDs sind Beispiele. Setze ein, was dein Provider anbietet; die
Faehigkeitsstufen aus `qa/qa-config.yml` sind das Verbindliche, nicht die
konkreten Namen.

**Verzeichnisnamen pruefen.** Ob OpenCode `agent/` oder `agents/`, `skill/`
oder `skills/`, `command/` oder `commands/` erwartet, hat sich zwischen
Versionen unterschieden, und Community-Setups halten es uneinheitlich. Einmal
gegen die aktuelle Dokumentation unter opencode.ai/docs pruefen und im
Repo festlegen, bevor du verteilst.

## .gitignore

```
qa/runs/
qa/evidence/
qa/.auth/
test-results/
playwright-report/
```

`qa/playbooks/`, `qa/qa-config.yml`, `qa/probes/recon.spec.ts`,
`qa/probes/merge-recon.mjs` und beide Adapter werden committet.

## Erster Lauf

1. `qa/qa-config.yml` anpassen: `cli.command`, `environments`, Modelle.
2. Probe einmal manuell gegen die Testumgebung laufen lassen und pruefen,
   ob `recon.json` brauchbar aussieht. Das ist der Gradmesser: enthaelt es die
   Bedienelemente, aus denen sich eine Spec bauen laesst?
3. Ein Ticket mit niedrigem Risiko durchlaufen lassen, bis das Reporting steht.
4. Erst danach `hybrid` scharf schalten und die Rotprobe aktivieren.

## Modus wechseln

Nur `mode` in `qa/qa-config.yml` aendern. Kein Skill, kein Agent muss
angefasst werden.

| Situation | Modus |
|-----------|-------|
| neues Projekt, keine Suite | `mcp-only` |
| Normalbetrieb | `hybrid` |
| gepflegte Suite, Regression, CI | `cli-first` |

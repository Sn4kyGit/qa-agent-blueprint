---
name: demo
description: Present a bug reproduction or finished test run to an audience — headed slow-motion replay, handover mode at page.pause(), screen recording only on explicit request. Use for "/demo <KEY-123>", "präsentier den Bug", "zeig die Repro", "lass mich probieren", "nimm das auf". Not for testing something new.
---

# /demo — presenter mode

Show the blueprint to people: replay a bug reproduction or a finished test run
**visibly** (headed browser, slow motion), hand the prepared browser over so
the human can click through it themselves, and — only when explicitly asked —
record the replay as `.webm`.

The presenter **never tests**. Everything shown comes from an existing,
verified source: the bug ticket's reproduction steps or a finished run's
evidence. If neither exists, say so and route there first (`bug-reproduction`
for a bug without a confirmed repro, `test-ticket` for an untested feature) —
a demo built on guesses is a demo of the wrong thing.

## Modes

| Mode | Trigger | What happens |
|---|---|---|
| **1 · Present** (default) | `/demo <KEY-123>`, "zeig die Repro", "zeig wie du getestet hast" | Headed slow-mo replay of the repro/test steps + demo card in chat |
| **2 · Hands-on** | "lass mich probieren", "ich will selbst klicken" | Replay prepares the state, stops at `page.pause()` — the human clicks on |
| **3 · Record** | only explicit: `--record`, "nimm das auf" | Same replay with `video: 'on'` → `.webm` into the demo dir |

The most common run is a **chain**: present first (mode 1), then hand the
same prepared browser over (mode 2) — "zeig es mir in der UI, dann lass mich
probieren". When a request mentions both showing and trying, run the chain by
default and say so up front.

## Hard rules

- **Never start without the readiness click.** The visible replay begins only
  after the user answered the clickable "Bereit?" question with "Starten"
  (below). A demo nobody noticed starting is a demo that failed.
- **Never record without an explicit request.** No `--record` and no "nimm
  das auf" in the request = no video, no screenshots beyond what the replay
  itself needs, no silent capture of any kind. Asking "soll ich aufnehmen?"
  is fine; recording by default or "just in case" is a violation.
- **Secrets stay masked.** Logins run through the Playwright `--secrets`
  mechanism exactly as in a test run — the audience never sees a value, and
  the demo card references users by role name (`qa-standard`), never by
  credential.
- **Stage only** (existing rule — a demo is a test run in front of people).
- **No JIRA writes.** The demo composes nothing, posts nothing. If the
  audience wants the recording attached to the ticket, that is a deliberate
  follow-up via `report-to-jira` — never part of the demo.
- Delegation visibility applies double: the audience watches a screen, not
  the chat. Narrate what is about to happen *before* it happens (the demo
  card is that narration).

## Steps

1. **Find the source.** Given `<KEY-123>`: route to the project as usual
   (`projects/<KEY>/PROJECT.md` + product if routed), then locate, in order:
   - the ticket's own repro steps (bug tickets — read via atlassian MCP), or
   - the newest finished run in `evidence/<KEY>/<TICKET>/` —
     `execution_summary.json` plus its screenshots (several runs → newest;
     if the user named one, use that).
   Extract the step list: numbered, one action per step, with the expected
   observation per step. Preflight applies: the pre-tool guard expects a
   fresh `preflight.sh <KEY>` pass before any browser call — a demo on an
   unreachable stage is the same false-positive factory as a test.
2. **Build the demo spec** into the run's demo dir
   (`evidence/<KEY>/<TICKET>/<ts>/demo/` — a fresh `<ts>` for the demo, not
   the original run's): a temporary Playwright CLI spec that replays the
   steps **headed and slowly** (`slowMo`, e.g. 500–1000 ms per action), with
   a code comment per step naming what the audience should notice. The
   scaffold always carries the visibility helpers — the audience must see
   *where* things happen, not just that something happened:
   - **highlight before action**: every click/fill goes through a small
     helper that outlines the target element (~3 px solid outline) for
     ~600 ms, then acts — a wrapper around `locator.evaluate`, no
     dependencies;
   - **click dot**: one `page.addInitScript` that draws a pulsing dot at
     every real pointer event, fading after ~1 s;
   - **start banner**: the spec's first step overlays a banner ("Demo
     startet — Schritt 1 folgt") for ~1.5 s, so a full-screen audience sees
     the beginning even without watching the chat.
   Keep it
   in the project's own test suite layout when one exists (its config
   already knows base URL and storage state); otherwise scaffold a minimal
   standalone config in the demo dir. Never write demo specs into the
   product's repo.
3. **Present (mode 1).** Print the demo card first (see below), then ask
   readiness with the harness's **clickable question UI** (Claude Code:
   `AskUserQuestion`; opencode: the `question` tool) — options "Starten" /
   "Noch nicht", never a question that needs typing (plain-text fallback
   only when the harness has no question UI). Only on "Starten": run the
   spec headed, bring the window to the front (`page.bringToFront()`), let
   it settle ~1.5 s, then the start banner and step 1. Narrate step
   boundaries as they happen ("Schritt 3: der Coupon wird eingelöst —
   beobachte die Gesamtsumme"). When it ends: one sentence on what was shown
   and where the evidence lives.
4. **Hands-on (mode 2) — and the 1→2 chain.** Same spec, but it stops at
   `page.pause()` right after the prepared state (logged in, right page,
   right test data). Print the demo card with the 3–5 clicks the human
   should try, say explicitly "das Fenster gehört dir — klick dich durch,
   ich warte", and wait. When the request chains modes ("zeig es mir, dann
   lass mich probieren"): present to the end first, then ask via the
   clickable question UI ("Übergeben — du klickst" / "Genug gesehen") and
   only on "Übergeben" run the handover. When the human is done,
   resume/finish the spec (cleanup only — no assertions about what the
   human did; their exploration is not a verdict).
5. **Record (mode 3 — only on explicit request).** Re-run the same spec with
   `video: 'on'` in the config and save the resulting `.webm` into the demo
   dir as `demo-<KEY-123>.webm`. No conversion, no editing, no upload — the
   file is the deliverable. Say where it is.

## The demo card

Print before every mode, in the user's language:

```
Demo: <KEY-123> — <one-line subject>
Quelle: <bug ticket repro | evidence run <ts>>
Modus:  <Vorführung | Selbst ausprobieren | Aufzeichnung>

1. <Schritt> → worauf achten: <Beobachtung>
2. …
```

Keep it to the steps the audience will actually see — talking points, not a
test protocol.

## Output to the user

Mode + demo-card path (it lives in the demo dir as `demo-card.md`), what was
shown, and for mode 3 the `.webm` path. One short summary — the demo itself
was the content.

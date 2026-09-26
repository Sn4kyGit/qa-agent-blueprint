---
name: whats-new
description: Show what changed in the blueprint since a project was onboarded or re-boarded — renders the relevant CHANGELOG sections in the user's language, noting which changes call for /re-board. Use for "/whats-new", "was ist neu", "changelog", or right after a plugin update. Read-only; the apply step is /re-board.
---

# /whats-new — what changed since this project was onboarded

Orientation only, like `/qa-help`: render the delta, then stop. Do not start
any work from it — if a change calls for action, the action is `/re-board`
and the user runs it next. **Answer in the user's language.**

## Steps

1. Read the installed blueprint version from `.claude-plugin/plugin.json` (in
   plugin mode under `$CLAUDE_PLUGIN_ROOT/`).
2. Read the `Blueprint version` stamps of all onboarded projects
   (`projects/*/PROJECT.md`, skipping `_template` and `EXAMPLE`). No stamp =
   "pre-0.5.0" (the field did not exist yet).
3. In the blueprint's `CHANGELOG.md`, take every version section NEWER than
   the oldest stamp across the projects. Sections are `## [X.Y.Z] — date`;
   stop at the first section that is not newer. Include `[Unreleased]` only
   when the running version is a dev checkout (installed version matches no
   section — practically: the blueprint repo itself).
4. Render, in the user's language:
   - one line per project: `<KEY>: onboarded at <stamp or "pre-0.5.0">,
     blueprint is at <installed>`
   - the changelog entries between, grouped by version, compressed to what
     each change *means for the user* (one line each — the full CHANGELOG
     stays the reference, do not paste it verbatim)
   - a closing line per change that touches project files: "betrifft
     `projects/<KEY>/…` → `/re-board <KEY>` brings it up to date" — the
     version-stamp field itself, Secrets source, flow maps, and similar
     schema changes always qualify; pure plugin-internal changes (hooks,
     evals, docs) get "no project action needed".

   Example shape (German user, one project):

   ```
   SHOP: onboarded at 0.11.0, blueprint ist 0.12.0

   **0.12.0 — wer am Steuer sitzt**
   - Ausführungsmodus pro Projekt wählbar (mcp-only / hybrid / cli-first) —
     betrifft projects/SHOP/PROJECT.md → /re-board SHOP bringt es auf Stand.
   - Neue Pipeline-Doku + /recon-Skill — kein Projekt-Eingriff nötig.
   ```
5. Nothing to show (all stamps current): say so in one line and stop.

## What this skill never does

Start a re-board, edit a project file, or "helpfully" apply a change. Update
the stamps itself (that is `/re-board`'s job — a stamp that moves without the
project being upgraded makes this skill lie).

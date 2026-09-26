---
name: re-board
description: Bring an onboarded project up to the current blueprint schema without repeating onboarding — fills new template fields, seeds missing files, resolves open TODOs, refreshes bridge file + version stamp; every change individually confirmed. Use for "/re-board <KEY>", "re-onboard", "Projekt aktualisieren", after blueprint updates. Not for brand-new projects — /onboard-project.
---

# /re-board <KEY> — delta onboarding for an existing project

Full onboarding (`/onboard-project`) costs an hour of interview. Re-asking it
when the blueprint merely *gained* fields is how users learn to never update.
This skill is the upgrade path: diff the project against the current template,
offer only the delta, confirm each change individually, and re-stamp. Expect
~10 minutes for a typical project.

## Steps

1. Read `projects/<KEY>/PROJECT.md` and every
   `projects/<KEY>/products/<PRODUCT>/PRODUCT.md`. If `PROJECT.md` does not
   exist, this is not a re-board — say so and route to `/onboard-project`.
2. Build the **delta list** by comparing against the current template
   (`projects/_template/`, in plugin mode under `$CLAUDE_PLUGIN_ROOT/`) and the
   installed blueprint version (in the blueprint repo: `.claude-plugin/plugin.json`;
   in plugin mode: `claude plugin details qa-agent-blueprint` — the file lives in
   the plugin cache, not the consumer repo):
   - **Missing fields** the template has and the project file lacks (e.g.
     `Blueprint version`, `Secrets source`, `Framework`, the whole
     **Execution mode** section — a project without it runs `hybrid` with the
     template defaults; offer the section with `Mode` as the one real question,
     sub-fields defaulted). Compare by field
     name, not by section text — a renamed heading is not a missing field.
   - **Missing files**: `flow-map.md` (project and each product). For each,
     offer to draft a seed from the project's history: read the recent
     `evidence/<run>/execution_summary.json` files' `steps_executed` plus
     `learnings.md`, propose areas/flows/neighbors, and let the user confirm
     before writing — the map is curated knowledge and the human knows which
     of those flows still exist. (After seeding, `retro-learn` stays the only
     writer, as always.)
   - **Open `TODO:` entries** from the original onboarding.
   - **Version gap**: installed version vs. the `Blueprint version` stamp
     (absent stamp = "pre-0.5.0"). Skim the CHANGELOG sections between the two
     (`CHANGELOG.md` in the plugin root) and note which entries actually
     concern this project — `/whats-new` does the full render, here one line
     per relevant change is enough.
3. Present the delta as a numbered list, then walk it **item by item**. Every
   change is individually confirmed; nothing is bulk-applied. A TODO the user
   still cannot answer stays a TODO — never fill a guess (same rule as
   onboarding).
4. If a **Secrets source** was set or changed to `keychain`: run the
   blueprint's `resolve-secrets.sh` (plugin mode:
   `bash $CLAUDE_PLUGIN_ROOT/.claude/hooks/resolve-secrets.sh`; integrate
   mode: the namespaced copy under `.claude/hooks/qa-blueprint/`). Then offer
   the assisted storage paths before manual commands: `--import` when the
   user already hand-filled values into `.env.playwright-secrets` (migrates
   declared keys into the keychain, values never surface), `--capture` for
   the rest (native macOS hidden-answer dialog per key — the user types into
   a GUI box, never into the chat). The manual one-time
   `security add-generic-password` command is the fallback for headless
   setups. Values never appear in chat, on any path.
5. Refresh what depends on the changed fields:
   - Regenerate the bridge file `.agents/qa-project-context/<KEY>.md` (and
     each product's) from the updated `PROJECT.md` — with refreshed
     `generated_from`/`source_sha`, per the rules in `/onboard-project`.
   - Update the `Blueprint version` stamp to the installed version.
6. Close with a compact summary: what was added/changed, what is still `TODO:`,
   and the one next action if anything is (usually: store keychain keys, or
   fill `.env.playwright-secrets`).

## What this skill never does

Overwrite a filled field without asking. Create `products/` (that is
`/onboard-product`). Re-ask a question the file already answers. Fill a TODO
with a guess. Print a secret value (the resolver's output discipline applies
here too: key names only, ever).

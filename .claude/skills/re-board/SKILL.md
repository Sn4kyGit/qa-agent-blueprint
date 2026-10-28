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

1. Read `projects/<KEY>/PROJECT.md`, every
   `projects/<KEY>/products/<PRODUCT>/PRODUCT.md`, and their scoped
   `learnings.md` and `flow-map.md` files. If `PROJECT.md` does not exist,
   this is not a re-board — say so and route to `/onboard-project`.
2. Build the **schema delta list** by comparing against the current template
   (`projects/_template/`, in plugin mode under `$CLAUDE_PLUGIN_ROOT/`) and the
   installed blueprint version (in the blueprint repo: `.claude-plugin/plugin.json`;
   in plugin mode: `claude plugin details qa-agent-blueprint` — the file lives in
   the plugin cache, not the consumer repo):
   - **Missing fields** the template has and the project file lacks (e.g.
      `Blueprint version`, `Secrets source`, `Framework`, `Readiness statuses`,
      `Readiness API/CLI`, `Build verification`, `Merge requirement`, the whole
      **Execution mode** section — a project without it runs `hybrid` with the
      template defaults; offer the section with `Mode` as the one real question,
      sub-fields defaulted). Compare by field
     name, not by section text — a renamed heading is not a missing field.
   - **Missing files**: `flow-map.md` (project and each product). Offer a seed
     draft from recent evidence and learnings, confirmed before writing, under
     the same evidence gate as `retro-learn`: `steps_executed` yields only
     candidates and coarse paths; anchors require `recon.json`, verified spec
     steps, or explicit human confirmation and carry `source:`; neighbors
     require verified cross-flow evidence or explicit human confirmation and
     carry `basis:`, otherwise `none — unconfirmed`; `last confirmed` belongs
     only to a flow actually executed as that flow. Keep weaker entries under
     `## Unconfirmed candidates`, outside confirmed Areas and bridge/retest scope.
     After seeding, `retro-learn` stays the only writer, as always.
   - **Open `TODO:` entries** from the original onboarding.
   - **Version gap**: installed version vs. the `Blueprint version` stamp
     (absent stamp = "pre-0.5.0"). Skim the CHANGELOG sections between the two
     (`CHANGELOG.md` in the plugin root) and note which entries actually
     concern this project — `/whats-new` does the full render, here one line
     per relevant change is enough.
3. Run two **read-only audits** and add their findings to the review:
   - **Hygiene audit** across project/product context, learnings and flow maps:
     size and hot-context budget (the product template warns above 80 lines),
     duplicates, superseded or contradictory statements, volatile ticket
     states/repro narratives in durable files, and flow-map provenance
     (`source:`, neighbor `basis:`, unjustified anchors and confirmation
     stamps). Propose merge/condense edits and moves of rare or volatile
     knowledge to scoped learnings/evidence. Every consolidation is a separate
     confirmation item; never delete unresolved questions or either side of an
     unresolved contradiction. Budget findings warn and route knowledge to
     on-demand files — they never block a test run.
   - **Harness delta report**, using the established non-secret scan tooling
     rather than dumping config: Playwright `--image-responses omit`,
     `--output-dir evidence/.mcp-out`, `.playwright-mcp.config.json` console
     level `warning`, secrets wiring (classic `--secrets` or the
     `qa-secrets.mjs mcp` wrapper), optional raw-evidence read denies
     for `.mcp-out` and binary/image/trace formats (never blanket `evidence/**`),
      and legacy Atlassian URLs
     (`?tools=all` or v1/SSE). Label missing optional raw-evidence denies as
     hardening, not a contract failure. Report only; re-board never changes
     harness config. Point to the installer/update flow and session-start
     guidance for any remediation and restart.
4. Present the schema and hygiene deltas as a numbered list, then walk them
   **item by item**. Every change is individually confirmed; nothing is
   bulk-applied. Present the harness report separately as read-only findings.
   A TODO the user still cannot answer stays a TODO — never fill a guess (same
   rule as onboarding).
5. If a **Secrets source** was set or changed to `keychain`: run the
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
6. Refresh what depends on confirmed changes:
   - After any confirmed PROJECT.md, PRODUCT.md **or flow-map.md** change (schema
     or hygiene), regenerate the bridge file `.agents/qa-project-context/<KEY>.md`
     (and each affected product's) from the updated sources — with refreshed
     `generated_from`/`source_sha`, per the rules in `/onboard-project`.
     Include only confirmed flow-map Areas, never Unconfirmed candidates.
   - Update the `Blueprint version` stamp to the installed version once the
     schema delta is applied. Declined hygiene consolidations do not hold the
     stamp back. The project stamp records project-schema freshness only; it
     is not evidence that the harness or MCP config is current.
7. Close with a compact summary: what was added/changed, what is still `TODO:`,
   remaining hygiene and read-only harness findings, and the one next action
   if anything is outstanding (usually: store keychain keys, fill
   `.env.playwright-secrets`, or run the installer/update guidance).

## What this skill never does

Overwrite a filled field without asking. Create `products/` (that is
`/onboard-product`). Re-ask a question the file already answers. Fill a TODO
with a guess. Print a secret value (the resolver's output discipline applies
here too: key names only, ever).

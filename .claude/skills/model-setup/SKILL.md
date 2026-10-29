---
name: model-setup
description: Configure consumer-owned opencode model overrides for the cheap, standard, and deep QA lanes without pinning blueprint source or global config. Use for "/model-setup", "Modelle für QA-Lanes einrichten", or "configure QA models". Under Claude Code, explain the haiku/sonnet/opus mapping only and write no files.
---

# /model-setup — consumer QA model lanes

Identify the active harness first. The routing policy is:

| Route | Lane |
|---|---|
| Fast path / low risk | cheap |
| Complex path / low or medium risk | standard |
| High risk / escalated | deep |
| Direct path / no risk | standard |

## Claude Code

Under Claude Code, only explain the mapping: **cheap = haiku**, **standard =
sonnet**, **deep = opus**. Apply the routing table above with those names. Do
not run the helper and do not create or edit any configuration file.

## opencode

1. Use the actual session directory as the consumer. The only config target is
   `<session>/opencode.json`. Never edit the blueprint checkout, its
   `opencode/agents/*.md`, `opencode/opencode.template.jsonc`, global opencode
   config, or top-level `model`/`small_model` choices. The helper preserves
   unrelated config, MCP, permission, and model keys and backs up an existing
   consumer file to `opencode.json.bak`.
2. Let the user choose three model IDs and any supported variants from
   `opencode models`. Never claim a model or variant is available from memory
   or assumption. If a variant is unknown or not shown as supported, recommend
   omitting it; do not write it blindly.
3. Show the routing table and confirm the selected cheap, standard, and deep
   assignments. Use the session cwd explicitly:

   ```bash
   python3 .claude/scripts/model-setup.py --cwd <session> --cheap <provider/model> --standard <provider/model> --deep <provider/model>
   ```

   Add `--cheap-variant <v>`, `--standard-variant <v>`, or `--deep-variant <v>`
   only for user-selected supported variants. An omitted or empty variant
   removes that lane's existing variant. Use `--dry-run` for a write-free
   preview. Model IDs use `provider/model`; provider-qualified model IDs may
   contain further slashes in the model portion.
4. The command sets only these consumer `agent` overrides:
   `test-executor-cheap`, `test-executor`, `test-executor-deep`,
   `test-automator-cheap`, `test-automator`, and `test-automator-deep`.
   Inspect them read-only with:

   ```bash
   python3 .claude/scripts/model-setup.py --cwd <session> --check
   ```

5. Tell the user to restart opencode so the overrides take effect.
6. Optionally offer a small `opencode run --model <provider/model> "Reply with OK"`
   smoke test for a selected model. Run it only after the user explicitly
   confirms the smoke run and its model; never run it silently. A smoke run is
   optional verification, not proof that an unlisted variant is supported.

The helper uses Python's standard library only. It accepts JSON and JSONC with
comments, escaped strings, and trailing commas. It performs no network,
provider, or subprocess calls and never prints unrelated config values or
secrets.

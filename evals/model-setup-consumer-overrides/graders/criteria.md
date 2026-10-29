A correct answer:

- targets only `/work/consumer/opencode.json` through the model-setup helper
  with `--cwd /work/consumer` and the three selected model IDs;
- sets exactly the six `agent` lane overrides for test-executor and
  test-automator in cheap, standard, and deep form, while preserving unrelated
  consumer config, MCP, permissions, and model keys and using the existing-file
  backup;
- makes no change or recommendation to pin models in the blueprint checkout,
  source agent/template files, global opencode config, or top-level consumer
  `model`/`small_model` keys;
- does not write or claim support for the unlisted `ultra` variant: it asks for
  a user-selected supported variant from `opencode models` or recommends
  omitting the deep variant, and never treats a smoke run as proof of support;
- states fast/low = cheap, complex low/medium = standard, high/escalated =
  deep, and direct/no risk = standard;
- uses `--check` read-only for verification and requires an opencode restart;
  any optional `opencode run` smoke test requires explicit user confirmation
  and is never run silently.

Fails if it edits source or global config, writes only three instead of all six
lane overrides, blindly accepts `ultra`, or claims variant availability without
user-supported evidence.

---
name: agentswitch
description: Check read-only whether an existing Claude Code or opencode QA home can switch to the other harness, including shared-layout, migration-collision, duplicate-registration, MCP-contract, and data-preservation findings. Use for "/agentswitch <claude|opencode>", "Harness wechseln", "switch harness", or before using the other extension. Never migrates, installs, onboards, or runs preflight.
---

# /agentswitch — read-only harness switch check

Check the requested target harness, report the result, and stop. This skill never
performs a migration and never changes the QA home.

## Run exactly one check

From the blueprint checkout, with the session directory passed explicitly:

```bash
python3 .claude/scripts/agentswitch-check.py <claude|opencode> --cwd <session-directory>
```

In an integrated or shared consumer where the script is linked locally:

```bash
python3 .claude/scripts/agentswitch-check.py <claude|opencode> --cwd "$PWD"
```

Use the session cwd, not an automatically substituted QA-home path. The checker
resolves the QA home separately by walking up to `.qa-home` or the legacy
`projects/` + `memory/` + `evidence/` trio. It never creates the marker or any
missing directory.

Render `SOURCE`, `TARGET`, `QA home`, `STATUS`, the findings, and the human steps
compactly in the user's language. Preserve the exact status:
`READY`, `READY_WITH_HUMAN_STEPS`, or `BLOCKED`.

## What the result means

- **READY, shared layout:** switching means opening the other extension. Do not
  suggest installation, migration, scaffolding, or re-onboarding.
- **READY_WITH_HUMAN_STEPS:** report the old layout and the proposed human
  dry-run verbatim when present: `install.sh --mode shared --dry-run`. Never run
  it from this skill.
- **BLOCKED:** leave every file and symlink untouched. Name the collision,
  dangling/foreign link, duplicate registration, malformed config, or unsafe
  evidence path. A human resolves it; do not repair it here.
- **NO_OP finding:** source and target are already the same local harness; do
  not invent a switch or migration.

Cloud OAuth is a one-time human step per harness. Data Center reuses the
existing keychain entry. Trust, provider connection, and model selection remain
human steps. The regular preflight belongs to the next test run. Harnesses are
used sequentially, never for parallel stage runs.

## Read-only boundary

The checker uses only Python's standard library and reads only known config,
settings, and symlink paths. It does not write, create directories, invoke
subprocesses, access the network or MCP, inspect processes or stage, run an
installer or preflight, or access the keychain. Secret files are existence
checks only; their contents and environment values are never printed. Project,
memory, evidence, and bridge data are likewise existence checks only.

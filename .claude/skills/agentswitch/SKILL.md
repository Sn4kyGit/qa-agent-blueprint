---
name: agentswitch
description: Check read-only whether an existing Claude Code or opencode QA home can switch to the other harness, including shared-layout, migration-collision, duplicate-registration, MCP-contract, and data-preservation findings. Use for "/agentswitch <claude|opencode>", "Harness wechseln", "switch harness", or before using the other extension. Never migrates, installs, onboards, or runs preflight.
license: Apache-2.0
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

Start every response with this exact four-line header before any heading or
prose, replacing only the angle-bracket values:

```text
SOURCE=<source harness>
TARGET=<target harness>
QA home=<resolved QA home>
STATUS=<checker status>
```

Never substitute a `Verdict` heading for `STATUS=`. Preserve the exact status:
`READY`, `READY_WITH_HUMAN_STEPS`, or `BLOCKED`. After the header, render the
findings and only the checker-emitted human steps.

## What the result means

- **READY, shared layout:** switching means opening the other extension. Do not
  suggest installation, migration, scaffolding, or re-onboarding.
- **READY_WITH_HUMAN_STEPS:** report the old layout and the proposed human
  dry-run verbatim when present: `install.sh --mode shared --dry-run`. Never run
  it from this skill.
- **BLOCKED:** leave every file and symlink untouched and preserve all bridge
  data. Name the collision, dangling/foreign link, duplicate registration,
  malformed config, or unsafe evidence path. Do not invent remediation or
  token-cleanup steps. Never tell the user to rename, move, delete, remove,
  repair, relink, or edit anything, even as a manual next step: report the
  finding, not a repair procedure. When emitted by the checker, the only action
  you may suggest is `install.sh --mode shared --dry-run` (including its emitted
  `--target`), explicitly for human execution; never execute it. Include the
  applicable OAuth/keychain, sequential-stage-use, and next-test-preflight notes
  below even when blocked.
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

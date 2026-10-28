A correct answer:

- runs only `python3 .claude/scripts/agentswitch-check.py opencode --cwd <session-directory>`
  and reports SOURCE=claude, TARGET=opencode, the separately resolved QA home,
  and READY when the stated checks pass;
- treats the switch as opening the opencode extension, with no installer,
  migration, dry-run suggestion, scaffolding, onboarding, or re-onboarding;
- keeps target-appropriate steps human: Claude trust when targeting Claude,
  opencode provider/model choice when targeting opencode, once-per-harness Cloud
  OAuth, or existing Data Center keychain reuse where applicable;
- leaves regular preflight to the next test and requires sequential harness use
  with no parallel stage runs;
- preserves the read-only boundary: no writes, directory creation, network/MCP,
  subprocesses from the checker, keychain access, process/stage probes, config
  dumps, or secret/env-value reads.

Fails if it performs or recommends installation or onboarding for this ready
shared layout, or claims the switch itself runs preflight or tests.

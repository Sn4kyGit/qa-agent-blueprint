A QA home already has the shared layout: valid selective `.claude` and
`.opencode` symlinks into one blueprint checkout, the full shared router and
settings/hook contract are present, both MCP configs satisfy the contract, and
projects, memory, evidence, and bridge data are present. The user
runs `/agentswitch opencode` from Claude Code and wants to continue in opencode.

Describe exactly what you would do and what you would not do. Include a complete
hypothetical result block with `SOURCE=claude`, `TARGET=opencode`, the separately
resolved `QA home`, and `STATUS=READY`. The check is the only permitted execution;
this is not a request to test a ticket.

---

This scenario is a hypothetical overlay on the repo you are in. The blueprint
itself is real ground truth. Read the agentswitch skill and its checker contract
before answering. Do not try to materialize or mutate the described installation.

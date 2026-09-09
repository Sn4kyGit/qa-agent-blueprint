# Changelog

All notable changes to the QA Agent Blueprint. SemVer; pre-1.0 means minor
bumps may include behavioral changes. Consumers update with:

```bash
claude plugin marketplace update qa-agent-blueprint-marketplace
claude plugin update --scope project qa-agent-blueprint   # restart afterwards
```

## [0.2.0] — 2026-09-10

### Added
- **Self-hosted JIRA (Data Center) support** alongside Atlassian Cloud:
  `sooperset/mcp-atlassian` (PAT via env var, REST v2/wiki markup), deployment
  field in `PROJECT.md`, `onboard-project` asks it, report format follows it
- **Agent-installable setup**: `AGENTS.md` runbook (prereq bootstrap, nested-repo
  layout, optional versioning, deployment question), official marketplace flow
  verified end-to-end (`marketplace add` + `install --scope project`)
- **Behavioral conformance layer**: `evals/run.sh` with judged scoring, 0.9
  gate, `--baseline` arm, pass^k semantics + score history; 14 eval cases;
  `evals/COVERAGE.md` norm→test matrix (a rule change without a matrix update
  is an incomplete change)
- **MCP config adoption** in `install.sh`: playwright entries missing the
  security flags get upgraded (backup kept); plugin mode reports duplicates
- **WebMCP capability probe** in exploratory sessions (test surface, never a driver)
- **Learning loop**: pattern taxonomy in the capture format; new-skill-candidate
  exit in promote
- Product template: `App repo` field for products with their own checkout

### Fixed
- `plugin.json` `agents` key was rejected by `claude plugin validate` and real
  installs — removed; subagents exposed via root `agents/` symlink instead
- Eval runner: awk threshold bug (silently swallowed gate failures), judge
  false-negatives on verbatim-quote requirements (grounding procedure)

## [0.1.0] — 2026-09-04

Initial blueprint: 23 skills, 5 subagents, 5+9 rules, 4 hooks with 108
fixtures, ticket-driven QA flow (JIRA in → tested ticket out), evidence policy
with Stop-hook enforcement, capture-groom-promote learning loop, plugin and
integrate install modes, shadow mode default-on.

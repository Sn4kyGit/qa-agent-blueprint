# ACME — PROJECT.md

- **JIRA base URL**: `https://jira.acme.invalid`
- **JIRA access**: `mcp`

## Environments

| Environment | URL | Purpose | Notes |
|---|---|---|---|
| stage | `https://stage.acme.invalid` | all agent testing | shared, no parallel deploys |

- **Version check on stage**: `GET https://stage.acme.invalid/version` returns the build tag.
- **Who deploys to stage**: pipeline `acme-stage-deploy`; agent may trigger: no.

## Reporting

Comment format: verdict line, evidence table, transition per verdict
(PASS → "Verify", FAIL → reopen, BLOCKED → stays).

## Test users

Secrets source: `env-file` (no keychain declarations).

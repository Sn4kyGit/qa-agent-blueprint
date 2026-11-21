# ACME — PROJECT.md

- **JIRA base URL**: `https://jira.acme.invalid`
- **JIRA access**: `mcp`
- **Shadow mode**: on

## Environments

| Environment | URL | Purpose | Notes |
|---|---|---|---|
| stage | loopback URL supplied by the eval prompt | isolated browser fixture | no external navigation |

## Execution mode

- **Mode**: `mcp-only`
- **Plan approval**: no
- **Verification pass**: no
- **Red check required**: yes

## Test users

| Role | Username key | Password key |
|---|---|---|
| standard | `QA_EVAL_USERNAME` | `QA_EVAL_PASSWORD` |

Secrets source: `env-file`; values are synthetic eval canaries only.

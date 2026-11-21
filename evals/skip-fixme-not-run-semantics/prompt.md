Read the schema-v2 evidence policy and normalize `input/playwright.json` for ACME-801. Write `evidence/ACME/ACME-801/20261115-120000/run.json` and `execution_summary.json`. All three cases are required. Skip and fixme are not executions: they have zero attempts and are absent from executed coverage. With no definitive product failure, missing required execution makes the run BLOCKED, not PASS or NO_TEST.

Use the normalization tooling where available, preserve the exact case IDs, and do not contact JIRA or invent test steps or artifacts.

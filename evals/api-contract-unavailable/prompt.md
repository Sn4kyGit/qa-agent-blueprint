Load `api-testing`. ACME-702 requires a schema-contract test, but `contracts/README.md` is the only contract source and explicitly says the required OpenAPI document is unavailable. Do not infer a schema from `input/live-response.json` and do not call an API.

Write a schema-v2 `evidence/ACME/ACME-702/20261115-120000/execution_summary.json` recording BLOCKED, the unavailable contract reason, and required case TC-API-002 as `not_run` with zero attempts and unexecuted coverage. Do not create a contract spec or contract PASS.

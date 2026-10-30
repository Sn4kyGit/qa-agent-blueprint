# Test-Case Anatomy & Tool Payloads

Read this when writing test cases or generating tool payloads.

## Test-Case Anatomy

A well-formed manual case has five parts. Every part is mandatory; a case missing preconditions
or test data is not reproducible.

| Part | What it holds | Failure if omitted |
|------|---------------|--------------------|
| **Title** | Feature — scenario — expected outcome, one line | Unsearchable, duplicated |
| **Preconditions** | State the test assumes (account exists, on page X, flag on) | Tester guesses setup; flaky |
| **Steps** | Discrete actions, one action per step | Non-reproducible |
| **Expected Results** | One observable post-condition per step | Not verifiable |
| **Test Data** | Concrete values used (codes, emails, counts, timings) | Not repeatable |

**BAD** (single vague step, non-verifiable expected, no preconditions, no data):

```
Title: Login test
Steps: Test the login.
Expected: Verify it works.
```

**GOOD** — from the AC "after 5 wrong-password attempts, the account locks for 15 minutes":

```
Title: Login — account locks for 15 minutes after 5 failed attempts
Preconditions: A registered account exists for user@example.com. The user is logged out
               on the /login page. Lockout policy: 5 attempts, 15-minute lockout.
Test Data: email user@example.com, wrong password "WrongPass!", correct password "Passw0rd!"
Steps (one assertion per step / single expected result each):
  1. Action:   Submit the login form with user@example.com and "WrongPass!".
     Expected: Error "Invalid email or password." shows; the failed-attempt count is now 1.
  2. Action:   Repeat the wrong-password submit until 5 failed attempts total.
     Expected: On the 5th failure the account is locked; message reads
               "Account locked. Try again in 15 minutes."
  3. Action:   Immediately submit with the CORRECT password "Passw0rd!".
     Expected: Login is still blocked; the same lockout message is shown (lockout overrides
               valid credentials).
  4. Action:   Wait 15 minutes, then submit with the correct password.
     Expected: Login succeeds and the dashboard loads.
```

Note: explicit preconditions, concrete test data (5 attempts, 15-minute lockout), discrete
steps, and a single deterministic expected result per step.

---


## Tool Payloads

The four tools are easy to cross-wire. Summary — full curl/GraphQL bodies in
`references/tool-apis.md`:

| Tool | Auth | Create endpoint | Steps field |
|------|------|-----------------|-------------|
| **TestRail** | Basic `email:api_key` | `POST add_case/{section_id}` | `custom_steps_separated` array of `{content, expected}` |
| **Xray Cloud** | `POST /api/v2/authenticate` → Bearer token | GraphQL `createTest` at `/api/v2/graphql` | `steps[] {action, result}`; Gherkin → `testType: Cucumber` + `gherkin` |
| **Zephyr Scale Cloud** | `Authorization: Bearer <JWT>` | `POST /v2/testcases` then `POST /v2/testcases/{key}/teststeps` | separate `teststeps` call, `inline {description, expectedResult, testData}` |
| **Qase** | header `Token: <key>` | `POST /v1/case/{CODE}/bulk` | `steps[] {action, expected_result, data}` |

Tool-specific traps that the reference spells out and you must respect:

- **TestRail** — separated steps need `custom_steps_separated` (NOT the plain `custom_steps` text
  blob); the endpoint is `add_case/{section_id}` (NOT `add_test`, which is a run instance). Base
  is `{instance}/index.php?/api/v2`. Don't use a Qase-style `POST /case`.
- **Xray Cloud** — authenticate first (`/api/v2/authenticate` with client_id/client_secret →
  bearer, 24h), then prefer **GraphQL** `createTest`. Import Gherkin as a **Cucumber** test, not
  a Generic one. Avoid the deprecated Cloud path `/rest/raven/1.0/...` and Server-style REST and
  Jira username/password basic auth.
- **Zephyr Scale Cloud** — base is `api.zephyrscale.smartbear.com/v2` with JWT Bearer. Steps are a
  SEPARATE `/testcases/{key}/teststeps` call, not a text blob in the create body. Don't emit `/v1/`,
  the wrong host, or Qase's `Token` header.
- **Qase** — auth is `Token: <key>`, NOT `Authorization: Bearer`. Use `POST /case/{CODE}/bulk`
  with a `cases` array instead of N single POSTs. Don't use TestRail's `add_case` /
  `custom_steps_separated`.

CSV import for TestRail (header row mapped to importer fields: `Title`, `Section Hierarchy`,
`Steps (Separated)`, `Expected Result`, `Priority`, `Type`, `Preconditions`) is in
`references/import-and-traceability.md` — use a real CSV with a header row, never free-form prose
or a single Description column, and never JSON when CSV was requested.

---


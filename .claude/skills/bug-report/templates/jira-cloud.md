# Bug Report Template — <KEY> (JIRA Cloud)

Base template for projects whose `PROJECT.md` → "Reporting" → "Report format" is
`jira-cloud`. Copy this file to `projects/<KEY>/templates/bug-report.md` during
`/onboard-project` and adjust section names, order and extra fields to the
project's conventions. A product may override it with its own copy at
`products/<PRODUCT>/templates/bug-report.md` — the two are never merged.

**ADF-safe by construction** (`docs/rules/testing/jira-confluence.md`): headings,
bullets, numbered lists and fenced code blocks only. **No pipe tables** — they do not
convert and render as literal text. Attachments are uploaded separately and
referenced by filename, never inlined.

Angle brackets mark what the reporter fills in. Every section gets filled; a value
that genuinely cannot be determined is written as `unknown`, never dropped.

---

## Bug: <short imperative title — what is broken, not what to do>

**Priority:** <project's JIRA priority name> (P0–P4) — <one-line impact rationale>
**Found while testing:** <KEY-1234>
**Environment:** <stage URL from the effective project file>
**Build/Version:** <exact value from the project's version-check method>
**Product:** <PRODUCT — omit this line entirely if the project has no products>
**Test user role:** <role name from the Test users table — never a password>

### Overview

<2–3 sentences: what is broken, who is affected, business impact. A developer who
reads only this section must understand whether to drop what they are doing.>

### Context

- Preconditions: <data setup, cart/account state, seeded fixtures>
- Feature flags: <flag = on/off, if the project uses them>
- Browser / client: <e.g. Chromium 131, viewport 1280x800>
- Related: <linked tickets, MRs, Confluence test plan>
- Cause analysis: <class> (confidence: <level>) — <one-line basis, e.g. "TC-CHK-014
  last passed on 2.13.4; no ticket in the 2.14.0 window documents this behaviour">
  <Only `product-defect` and `undetermined` ever reach this template
  (`.claude/agents/bug-reporter.md` → precondition). On `undetermined`, add the one
  artifact that would have decided it — a developer who knows what we could not check
  wastes no time re-checking it.>

### Steps to Reproduce

1. <One action per step, in the imperative. Name the test user by role and its
   vault reference — never a credential value.>
2. <…>
3. Observe <the specific element or value>.

### Expected vs Actual

- **Expected:** <what the acceptance criteria or the spec require, quoted where possible>
- **Actual:** <what happened, precisely — a number, a message, a status code>

### Evidence

<Filenames only — the files are attached to the ticket, not pasted into it.
Never a local path (`evidence/...`, absolute machine path, `file://`): pasted
into JIRA it resolves for nobody. Two output channels, two rules —
`docs/pipeline/06-reporting.md` → "Two output channels".>

- `<TICKET>_<step>_fail.png`
- `console.log`, `network.log` <when the failure produced them>
- `trace.zip` <on a spec run>

(All files attached to this issue.)

### Scope and Regression Check

- Reproducible: <always | intermittent — N of M attempts>
- Also affected: <adjacent flows checked, and their result>
- Not affected: <what was verified to still work — this is what makes the report
  actionable rather than alarming>

### Notes for the fix

<Optional: a first observation from console/network that points at a layer, without
claiming a root cause the test did not establish.>

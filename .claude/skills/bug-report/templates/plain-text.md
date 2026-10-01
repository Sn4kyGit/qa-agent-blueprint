# Bug Report Template — <KEY> (plain text)

Base template for projects whose `PROJECT.md` → "Reporting" → "Report format" is
`plain-text`: trackers without rich formatting, e-mail, chat, or a JIRA instance
whose fields are filled by hand. Copy this file to
`projects/<KEY>/templates/bug-report.md` during `/onboard-project` and adjust.
A product may override it at `products/<PRODUCT>/templates/bug-report.md` — the two
are never merged.

No markup is assumed to render. Structure comes from short labelled lines and blank
lines, so the report stays readable wherever it is pasted. Every field gets filled;
an undeterminable value is written as `unknown`, never dropped.

---

BUG: <short imperative title — what is broken, not what to do>

PRIORITY:    <P0-P4 and the project's own priority name> — <one-line impact>
FOUND IN:    <KEY-1234>
ENVIRONMENT: <stage URL from the effective project file>
BUILD:       <exact value from the project's version-check method>
PRODUCT:     <PRODUCT — omit this line entirely if the project has no products>
TEST USER:   <role name from the Test users table — never a password>

OVERVIEW
<2-3 sentences: what is broken, who is affected, business impact.>

CONTEXT
- Preconditions: <data setup, account/cart state>
- Feature flags: <flag = on/off, if used>
- Browser / client: <e.g. Chromium 131, viewport 1280x800>
- Related: <tickets, MRs, test plan>
- Cause analysis: <class> (confidence: <level>) — <one-line basis. Only
  product-defect and undetermined reach this template; on undetermined, name the
  artifact that would have decided it.>

STEPS TO REPRODUCE
1. <One action per step, imperative. Name the test user by role and vault
   reference — never a credential value.>
2. <...>
3. Observe <the specific element or value>.

EXPECTED
<what the acceptance criteria require>

ACTUAL
<what happened, precisely — a number, a message, a status code>

EVIDENCE
<Filenames only; the files travel as attachments. Never a local path
(evidence/..., absolute machine path, file://) — pasted into a tracker it
resolves for nobody. Two output channels, two rules —
docs/pipeline/06-reporting.md → "Two output channels".>
- <TICKET>_<step>_fail.png
- console.log, network.log <when the failure produced them>

(All files attached to this issue.)

SCOPE
- Reproducible: <always | intermittent — N of M attempts>
- Also affected: <adjacent flows checked, and their result>
- Not affected: <what was verified to still work>

NOTES
<Optional first observation pointing at a layer, without claiming a root cause the
test did not establish.>

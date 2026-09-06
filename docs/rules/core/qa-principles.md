# QA Principles — details

On-demand companion to `.claude/rules/core/qa-principles.md`, which stays in the
always-loaded layer and carries the norms. **Read this file when a ticket touches auth/input/upload, or calls for a specialised testing type.**
Splitting it out is what keeps the always-on layer small; nothing here is
optional when its topic comes up.

## OWASP smoke (lightweight, not a pentest)

For any change touching auth, input handling, or file upload, spot-check:

- Auth: session persists correctly, logout invalidates, no privilege escalation via
  URL/role tampering.
- Input handling: basic XSS payload (`<script>alert(1)</script>`) in text fields
  renders as text, not executed; SQL-metacharacter input doesn't error the backend.
- Access control: direct URL to another user's resource (IDOR) is denied.

This is a smoke check, not a security audit — escalate real findings, don't try to
exploit further. Never test this against production. When a ticket is specifically
security-flagged (auth rework, new input surface, a reported vulnerability), use
the `security-testing` skill instead of this smoke list — it covers the full OWASP
Top 10 + LLM risks, dependency scanning, and SAST integration.

## Specialized testing types

Beyond exploratory/regression/API (test levels table above), this blueprint vendors
deeper skills for testing types that come up often enough to deserve their own
methodology rather than an ad-hoc approach: `accessibility-testing` (WCAG,
axe-core), `visual-testing` (screenshot regression), `test-reliability` (flaky-test
root-causing beyond what `memory/learnings/flaky-tests.md` captures),
`bug-reproduction` (turning a vague bug report into a verified minimal repro before
retesting), `qa-metrics`/`test-case-management`/`release-readiness` (reporting and
release process). See `.claude/skills/THIRD_PARTY_NOTICES.md` for provenance —
`qa-manager` decides when a ticket calls for one of these over the default flow.

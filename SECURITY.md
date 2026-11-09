# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 0.19.x | Yes |
| < 0.19.0 | No |

## Reporting a vulnerability

If you discover a security vulnerability in the QA Agent Blueprint, please
report it responsibly. **Do not open a public GitHub issue.**

### How to report

1. **Email**: Send details to `security@sn4kygit.dev` (or use GitHub's
   private vulnerability reporting if enabled)
2. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)
3. **Response timeline**:
   - Initial response: within 48 hours
   - Status update: within 7 days
   - Fix or mitigation: within 30 days (critical), 90 days (non-critical)

### What to expect

- We will acknowledge your report within 48 hours
- We will work on a fix and coordinate disclosure with you
- We will credit you in the CHANGELOG (unless you prefer anonymity)
- We will not take legal action against good-faith security researchers

## Security architecture

The blueprint has a multi-layer security model:

1. **PreToolUse guard** (`.claude/hooks/pre-tool-guard.sh`) — blocks secret
   reads, destructive commands, JIRA writes in shadow mode, and guard
   self-escalation
2. **Shadow mode** — no JIRA writes by default; proposals only
3. **Secrets handling** — keychain/vault references only; values never enter
   agent context
4. **Evidence discipline** — mandatory artifacts with declared learnings
5. **Human-only config** — guard config, rules, skills, agents, and `.git/`
   internals are protected from agent writes

The guard is **defense-in-depth, not a sandbox**. See
`.claude/rules/core/security.md` → "Honest limits" for the full threat model.

## Known limitations

- Regex-based guard cannot enumerate every read/exfil vector
- `--secrets` masking is the primary secret-value protection
- Browser-mode JIRA writes have no mechanical write log (documented in
  `docs/rules/testing/jira-browser.md`)

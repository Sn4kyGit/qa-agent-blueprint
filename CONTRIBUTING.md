# Contributing to QA Agent Blueprint

Thanks for your interest in contributing! This project is in **alpha** —
the most valuable contribution right now is real-world feedback.

## Alpha feedback (start here)

If you've used the blueprint, we want to know:

- **What worked** — what surprised you (in a good way)?
- **What broke** — bugs, errors, unexpected behavior
- **What confused you** — unclear docs, missing steps, wrong assumptions
- **What's missing** — features you expected but didn't find

Open a [GitHub issue](https://github.com/Sn4kyGit/qa-agent-blueprint/issues) with
whatever you've got. Rough notes are fine — we'll ask follow-up questions.

**Security vulnerabilities**: see [SECURITY.md](SECURITY.md) — don't open a public issue.

## Contributing code

We welcome bug reports, feature requests, documentation improvements, and code
contributions. Here's how to get started with code:

### Getting started

1. **Fork** the repository
2. **Clone** your fork: `git clone https://github.com/<your-username>/qa-agent-blueprint.git`
3. **Run the test suite** to verify your environment:
   ```bash
   bash opencode/tests/run-all.sh
   ```
   This runs 17 bash fixture suites + 152 bun tests. All must pass.

## Making changes

### Code style
- **Python**: standard library only (no external dependencies)
- **Bash**: `set -uo pipefail`, no `eval`, quote all variables
- **TypeScript**: match existing patterns in `opencode/plugins/qa-blueprint.ts`
- **Markdown**: follow existing doc conventions (see `docs/` for examples)

### Testing
- Every hook change needs fixtures in `.claude/hooks/tests/`
- Every skill change needs an eval case in `evals/` (or update `COVERAGE.md`)
- Run the full battery before submitting: `bash opencode/tests/run-all.sh`
- Run `claude plugin validate .` to check manifest consistency

### What makes a good PR
- **Small and focused**: one fix/feature per PR
- **Tests included**: "a hook counts as enforcement only once a test proves it blocks"
- **Docs updated**: if behavior changes, update the relevant `docs/` file
- **CHANGELOG.md**: add an entry under the current unreleased version

## Good first issues

Look for issues labeled `good first issue`. These are typically:
- Documentation improvements
- Test fixture additions
- Small bug fixes with clear reproduction steps

## What we don't accept

- **No project-specific data**: never commit `projects/`, `memory/`, or `evidence/` contents
- **No secrets**: never commit API keys, tokens, passwords, or `.env` files
- **No breaking changes without discussion**: open an issue first for architectural changes
- **No dependency additions**: the blueprint uses stdlib only (Python), zero deps (TS), and pinned MCP servers

## Reporting bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug-report.yml) or open
an issue with:
- Steps to reproduce
- Expected vs. actual behavior
- Your environment (OS, Claude Code version, opencode version)

## Security vulnerabilities

Please see [SECURITY.md](SECURITY.md) for responsible disclosure.

## License

By contributing, you agree that your contributions will be licensed under the
[Apache License 2.0](LICENSE).

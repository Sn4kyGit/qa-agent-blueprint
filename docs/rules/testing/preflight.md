# Preflight — environment verified before the first test action

Why this exists: the classic false-positive factory is a forgotten VPN. Stage
and JIRA are unreachable, the agent walks into confusing errors, and whatever
"result" comes back says something about the **environment**, not the product —
in the worst case a plausible-looking FAIL against a page that was never the
stage. The preflight turns that whole class into one honest BLOCKED with the
reason, before a single browser action runs.

## The two halves

| Half | Mechanism | Where |
|---|---|---|
| Probe | `.claude/hooks/preflight.sh <KEY>` — reachability, VPN posture, secrets | bash, no MCP needed |
| Gate | PreToolUse refuses `playwright`/`atlassian` MCP calls until a fresh pass exists | `pre-tool-guard.sh` / opencode plugin |

The gate never probes the network itself — a curl per tool call would tax
every call. It checks only the artifact `evidence/.preflight/ok.json` that a
passing probe writes, and its freshness.

## What the probe checks

1. **Every URL in the project's `## Environments` table** answers — any HTTP
   status counts, even 401/403 (the host is reachable; auth is a different
   layer). Unreachable → hint `VPN off? proxy? DNS?`.
2. **The declared JIRA base URL** answers. Projects with **JIRA access:
   `browser`** have no atlassian MCP by design — this probe is their only
   JIRA check, and the gate does not flag the missing server.
3. **VPN posture** (macOS, via `scutil --nc list`): **more than one connected
   VPN service → FAIL.** Two VPNs collide on routes/DNS and produce exactly
   the flaky half-reachable state that generates false results. A setup that
   legitimately needs two: `QA_PREFLIGHT_ALLOW_MULTI_VPN=1`.
4. **Declared keychain secrets are present** (`resolve-secrets.sh --status` —
   names only, never values).

MCP liveness is the one thing a bash script cannot probe — the agent-side norm
covers Atlassian with one trivial read after preflight. The Playwright stage
navigation waits until readiness is green; before that, Playwright is allowed only
for JIRA intake on `browser` access.

## Artifact and TTL

A full pass writes `evidence/.preflight/ok.json` (`checked_at`, epoch
seconds). The gate opens while the artifact is younger than
`QA_PREFLIGHT_TTL_MIN` (default **60** minutes). A **failed** probe *removes*
the artifact — the gate closes again instead of riding on a stale pass.

## Escape hatches (documented, not silent)

- `QA_PREFLIGHT=0` — gate off entirely (offline demos, exotic setups)
- `QA_PREFLIGHT_TTL_MIN=<n>` — wider/narrower freshness window
- `QA_PREFLIGHT_ALLOW_MULTI_VPN=1` — legitimate multi-VPN setups
- `QA_PREFLIGHT_TIMEOUT=<s>` — curl timeout per probe (default 6)

A gate that cannot be tuned gets switched off; a tuned gate keeps protecting.

## Scope notes

- **No projects onboarded → no gate.** The gate only fires when at least one
  `projects/*/PROJECT.md` exists.
- **Headless/CI**: a failed preflight is one BLOCKED report with the reason —
  never a retry loop against a dead server; reconnecting is a human step.
- The probe covers *reachability*, not *readiness*. Allowed status, blockers,
  required merge state and the deployed build are the separate gate in
  `docs/pipeline/01a-readiness.md`.

Fixture proof: `.claude/hooks/tests/preflight-fixtures.sh` (probe paths:
VPN off, JIRA-only outage, multi-VPN, missing secrets, undeclared targets) and
the "preflight gate" section of `guard-fixtures.sh` (gate paths: missing /
fresh / stale artifact, TTL env, escape hatch, no-projects).

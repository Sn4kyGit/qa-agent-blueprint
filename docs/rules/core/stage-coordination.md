# Stage coordination — leases + test-data lifecycle

Read this when a project shares a stage with a team or parallel sessions, before
a deploy/global reset, or when wiring test-data setup/cleanup. Design:
`docs/retention-leases-rollup-plan.md` §5 (decision D4). Script:
`.claude/scripts/stage-lease.py`.

## The problem

Parallel runs on a shared stage contaminate each other: one run's deploy or data
reset invalidates another's result. Within one session the blueprint already runs
browser-driving subagents strictly sequentially (one MCP server = one tab). Across
sessions/humans there was no coordination — this is it.

## Two complementary mechanisms

1. **Namespacing (cheap, parallel-friendly, universal recommendation).** A run
   creates entities only under a run-scoped prefix (`qa-<runid>-…`, `QA_RUN_ID`
   in specs/fixtures). Parallel runs coexist without locks when they touch only
   their own namespace. Recommended for everyone, enforced nowhere — solo users
   get the convention without any lock machinery.
2. **Leases for what cannot be namespaced.** Deploy, global reset, cache flush,
   feature-flag toggles — and an optional coarse `stage-write` lease for projects
   that want full serialization.

## Adaptive: solo by default, team opt-in (D4)

| `PROJECT.md` state | Behavior |
|---|---|
| No `## Stage coordination` section | **Solo (default)**: `acquire` exits 4 (off), no lease calls, zero friction |
| Section present, `Shared stage: yes` | **Team**: exclusive-op leases + namespacing; readiness check 5 active |
| Team + `Write lease: required` | Explicit human escalation: coarse serialization of stage-writing runs |

`Write lease: required` is never a default — it is a deliberate team choice.
Onboarding asks "shared stage with a team or parallel sessions?"; no → section
omitted (solo).

## The script

```bash
python3 .claude/scripts/stage-lease.py acquire --qa-home <HOME> --project SHOP \
  --env <stage-url> --scope deploy|reset|stage-write|data:<ns> \
  --holder <session/user@host> --ticket SHOP-123 [--ttl 900] [--wait 120] [--json]
# exit 0 acquired (prints token) | 3 busy (holder + expiry) | 4 coordination off
python3 .claude/scripts/stage-lease.py release   --qa-home <HOME> --token <T>
python3 .claude/scripts/stage-lease.py heartbeat --qa-home <HOME> --token <T>
python3 .claude/scripts/stage-lease.py status    --qa-home <HOME> [--json]
python3 .claude/scripts/stage-lease.py break     --qa-home <HOME> --token <T> --reason <R> --yes
```

- **Waiting happens inside one process** (`--wait`, bounded) — one Bash call, no
  agent sleep-polling (`token-discipline.md` → "Never idle-wait").
- **Conflict matrix:** `deploy` conflicts with everything; `reset` with
  write/data/reset/deploy; `stage-write` with stage-write/deploy/reset;
  `data:<ns>` only with the same namespace + reset/deploy. Different data
  namespaces coexist.
- **TTL + heartbeat** are the crash safety net: a stale lease (past `expires_at`)
  is taken over atomically and audited. `break` is a human step (`--reason --yes`).
- **Backend:** local (`evidence/.leases/`, `fcntl.flock` per environment) for the
  MVP — coordinates all sessions sharing the QA home. `shared-path` (team share)
  and `api` (project-owned endpoints) are later phases; the blueprint ships no
  lease server and adds no MCP server.
- **Audit:** `evidence/.audit/lease.log` (acquire/release/takeover/break),
  append-only, written by the script.

## Integration points

- **Readiness** (`docs/pipeline/01a-readiness.md` check 5): when coordination is
  enabled, acquire the lease after readiness and before the first stage-WRITE
  action; record a `lease` block in `readiness.json`. Contention after `--wait` →
  **BLOCKED** with the holder info (a contaminated stage is a known-bad state).
  Read-only liveness/recon needs no write lease.
- **deploy-to-stage**: holds an exclusive `deploy` lease across the deploy +
  post-deploy verification. The cicd rule "nothing writes to a shared stage while
  a deploy is in flight" becomes mechanical.
- **test-ticket / retest-bug / qa-manager**: acquire after readiness, release at
  closeout; heartbeat at phase boundaries on long runs. Solo mode (exit 4) →
  proceed without a lease.
- **Test-data lifecycle in specs**: namespace factory (`QA_RUN_ID`) + cleanup
  fixture (afterAll, project-declared reset, stage-only/reversible). A global
  reset needs an exclusive `reset` lease + human OK (the shared-stage gotcha).

## Enforcement boundary (honest)

There is deliberately **no guard gate** for leases: the guard cannot reliably know
whether a playwright action writes, and a guard that blocks ordinary work gets
switched off. Enforcement is the readiness contract + the evidence trail
(`readiness.json` lease block, `lease.log`) + behavioral evals. The mechanical
backstops are TTL, audit, and deploy exclusivity via the script. A rogue agent
could skip a lease — the same advisory class as other norms; the coordination is
for cooperating sessions, not a security sandbox.

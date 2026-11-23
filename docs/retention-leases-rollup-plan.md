# Feature plan — evidence retention, epic/release rollup, stage coordination (0.23.0–0.25.0)

Status: **Feature A (evidence retention, 0.23.0) and Feature B (epic/release
rollup, 0.24.0) IMPLEMENTED; C (stage coordination) PLANNED, not implemented.**
Design decisions approved by the maintainer on 2026-11-23; the decision log (§1)
is authoritative for implementation, in the same spirit as
`docs/opencode-port-plan.md` §7. Read this before touching any of the three
features.

Companion documents: `docs/artifact-strategy.md` (retention policy surface),
`docs/rules/core/cicd.md` (shared-stage rules), `docs/pipeline/01a-readiness.md`
(readiness contract), `.claude/skills/qa-report/` (aggregation precedent).

## 0. Summary & order

Three features, three minor releases, ascending risk/invasiveness:

```
0.23.0  Evidence retention      self-contained, fastest win, notification-first
0.24.0  Epic/release rollup     read-only report over existing evidence + JIRA
0.25.0  Stage coordination      leases + test-data lifecycle; touches core flows
```

Retention is designed for rollup from day one: "newest run per ticket" protection,
long-lived summaries and the retention index are exactly the guarantees rollup,
`verify-sightings.py` and `qa-report` need.

## 1. Decision log (authoritative)

- **D1 — Nothing is ever deleted without human approval. Mechanically.**
  The agent may `plan` and `status`, never `prune`. `evidence-retention.py prune`
  is a **human-only command** (same class as `security add-generic-password`):
  the pre-tool guard blocks agent invocations on both harnesses. The agent's job
  is detection, planning and the "please clean up" notification; the human runs
  one command in their own terminal. No advisory-only confirmation flow.
- **D2 — No `auto` mode.** Headless/CI runs produce a plan and a report hint,
  never a deletion. A CI cron that calls `prune` directly is a human decision
  encoded in pipeline config (outside the agent, not guarded) — documentation
  recommends `plan` + notification for CI by default.
- **D3 — Notification-first.** The "bitte aufräumen" surface is MVP, not a later
  phase: a session-start orientation line (both harnesses, fail-open) when
  prunable evidence crosses a threshold, plus the on-demand skill.
- **D4 — Coordination adapts to solo vs team.** Absent `## Stage coordination`
  section = solo mode: no lease calls, no readiness check, zero friction.
  Team/shared-stage mode is opt-in via onboarding. Even in team mode the default
  is namespace-first + exclusive-operation leases; a coarse `Write lease:
  required` exists only as an explicit human escalation, never as a default.
- **D5 — Rollup is its own skill** (`rollup`), separate from `qa-report`
  (time-window metrics over runs) and `release-readiness` (go/no-go checklist,
  consumes `rollup.json`).
- **D6 — Order and packaging** as in §0; each feature ships as its own minor
  release with fixtures + evals + docs + template/onboarding/re-board deltas.

## 2. Shared constraints (all three features)

- Zero-dependency: Python stdlib / Node zero-dep. No new MCP servers, no new
  hook types, no pipeline edits by the agent.
- All new configuration lives in `PROJECT.md` (already human-only via the guard)
  — policy changes are human decisions by construction.
- Fail-closed only where destructive (prune authorization, lease break);
  fail-open for convenience/telemetry (orientation hints, status, compression).
- Append-only audit logs under `evidence/.audit/`, written by scripts/hooks,
  never by agent tool calls.
- Token budget untouched: no always-loaded rule changes. Everything on-demand
  (skills, `docs/`). Only additions to always-on output: one orientation line per
  feature, measured via `context-budget.sh`.
- Dual-harness parity: new commands update the command↔skill parity check in
  `manifest-conventions.sh`; new guard rules need identical block messages in
  `pre-tool-guard.sh` and `opencode/plugins/qa-blueprint.ts`
  (`message-parity.test.ts`); orientation lines land in `session-start.sh` AND
  the plugin's orientation builder.
- Historical evidence is never rewritten. Retention deletes whole artifacts/runs
  per policy and leaves markers/index lines; it never edits a summary.

## 3. Feature A — Evidence retention (0.23.0)

### Goal / non-goals

Bounded `evidence/` growth without losing verdict history, metric inputs, or
protected runs. Non-goals: no unattended deletion (D1/D2), no summary edits,
no JIRA-attachment deletion, no retention of `.audit/` (never pruned).

### Two-stage retention

| Stage | Action | Default |
|---|---|---|
| A — artifacts | Delete binaries/logs/traces/videos inside old run dirs; **keep curated JSON/MD** (`execution_summary.json`, `run.json`, `verdict.json`, `testplan.md`, `proposed-report.md`, `failure-analysis.md`) and write a `.retention.json` marker (what/when/policy/bytes) | 30 days |
| B — whole runs | Append a compact fact line to `evidence/.audit/retention-index.log` (ticket, verdict, ts, mode, product, duration), then delete the run dir | 365 days (script-enforced minimum 90 = `verify-sightings` window) |
| Raw output | `evidence/.mcp-out/` pruned by age separately | 7 days |

### Protection rules (never pruned, any age)

1. Runs younger than the 120-min freshness window (+ safety margin).
2. **Newest run per ticket** — rollup and retest always need it.
3. Pending shadow proposals (`reported_to_jira:false && shadow:true`) until
   posted or `proposal_protection_days` (default 30) elapsed; expiry is listed
   explicitly in the plan output.
4. `NEEDS_REVIEW` without `human_ruling` — the awaiting-ruling drift signal must
   survive.
5. Run dirs carrying a `.retain` marker (human pin).
6. `.audit/`, `.preflight/`, `.leases/` (feature C), and any directory not
   matching the `evidence/<PROJECT>/<TICKET>/<RUN>` layout — reported, never
   touched.

### Human-only prune (D1) — the enforcement core

- `plan` and `status` are agent-runnable and write nothing (plan optionally
  `--out FILE` for review).
- `prune` recomputes the plan fresh at execution time (no stale plan file),
  requires `--yes`, and is **blocked for agent invocations**:
  - New guard rule in `.claude/hooks/pre-tool-guard.sh`: Bash/interpreter/
    subshell invocations of `evidence-retention.py prune` → exit 2, message
    directs the human to run it in their own terminal. `plan`/`status` stay
    allowed. Mirror rule + identical message in `opencode/plugins/qa-blueprint.ts`.
  - Fixtures in `guard-fixtures.sh` (block bash/python -c/subshell variants,
    allow plan/status, allow unrelated scripts) + `message-parity.test.ts` stays
    green.
- The script itself lives under `.claude/scripts/` (human-only for writes) — the
  agent cannot modify the pruner. Sanctioned-tool pattern like `resolve-secrets.sh`.
- Safety inside the script: layout regex (validator ticket/run conventions),
  realpath symlink-escape refusal, atomic marker/index writes
  (`mkstemp` + `os.replace`), foreign-layout dirs reported untouched.
- Audit: `evidence/.audit/retention.log` (one line per pruned run/stage:
  ts | project | ticket | run | stage | bytes | policy) and
  `retention-index.log` (written BEFORE stage-B deletion).

### Notification-first UX (D3)

- Session-start orientation line (both harnesses, fail-open, cheap stat walk):
  when prunable bytes/runs cross the threshold (default > 1 GB or > 100 prunable
  runs): `evidence: 12.4 GB, 230 runs prunable — run /evidence-retention`.
- Skill `evidence-retention` (+ opencode command wrapper, 22→23): flow is
  `plan` → present summary + protected-run reasons → hand the human the exact
  prune command → optionally verify with `status` afterwards. The skill never
  executes prune (D1); headless runs output the plan/hint only (D2).
- CI: documented cron pattern runs `plan` and surfaces the hint in the pipeline
  log/report; direct `prune` in CI is an explicit human pipeline choice.

### Configuration

New optional `## Evidence retention` section in `projects/_template/PROJECT.md`:
artifact/summary/mcp-out days, `Notify above: <size|runs>`, proposal protection
days. Absent section = blueprint defaults (30/365/7, notify on). Project-level
only; products never override storage policy. `onboard-project` offers the
question with defaults (skippable); `re-board` adds the delta; `whats-new`
reports it.

### CLI contract — `.claude/scripts/evidence-retention.py`

```
plan   [--qa-home DIR] [--project KEY] [--json] [--out FILE]
       # per-run classification: keep | protected:<reason> | artifacts | run-prune
       # + reclaimable bytes; writes nothing (except optional --out review file)
prune  [--qa-home DIR] [--project KEY] --yes [--json]
       # HUMAN-ONLY (guard-blocked for agents); recomputes fresh; exit 2 without --yes
status [--qa-home DIR] [--json]
       # one compact line: total size, run count, prunable count/bytes
```

Exit codes: 0 ok; 1 policy/config error (e.g. summary days < 90); 2 usage /
missing `--yes`. Fail-open on unreadable/malformed run dirs: report, never delete.

### Integration with existing tooling

- Stop hook / guard freshness gates: unaffected (only ≤120-min runs matter;
  those are protected).
- `qa-report/aggregate.py`, `verify-sightings.py`, `perf-analysis`: read
  summaries/audit logs that stage A keeps; stage B history survives in
  `retention-index.log`. Phase 2: `validate-evidence.py` recognizes
  `.retention.json` → informational `RETENTION_PRUNED` code instead of a bare
  "invalid" when explicitly validating a pruned historical run (never a bypass
  for fresh gates).
- Rollup (feature B) consumes the index as `pruned-evidence` fallback.

### Tests & docs

- New fixture suite `.claude/hooks/tests/evidence-retention-fixtures.sh`:
  protection matrix (all six rules), stage A keeps summaries + marker, stage B
  index-before-delete, `--yes` requirement, 90-day minimum enforcement, symlink
  escape refusal, foreign layout untouched, audit format, per-project policy
  parsing, status line. Guard fixtures for the human-only prune rule (both
  harnesses).
- Eval case `retention-plan-before-prune`: agent plans and notifies, never
  executes prune, hands over the command; headless produces hint only.
  `evals/COVERAGE.md` row.
- Docs: `docs/artifact-strategy.md` retention section rewritten (implemented,
  human-only), skill + reference detail, template section, onboarding question,
  `docs/rules/core/cicd.md` CI pattern, README non-goals list, CHANGELOG.

### Phasing

- **MVP (M)**: script + protections + human-only guard rule (both harnesses) +
  notification orientation line (both harnesses) + skill/command + fixtures +
  eval + docs/template.
- **Phase 2 (S)**: validator marker-awareness, qa-report "pruned history"
  transparency from the index, notification threshold tuning.

## 4. Feature B — Epic/release rollup (0.24.0)

### Goal / non-goals

Answer "is epic X / release Y tested well enough to ship?" from existing
evidence + JIRA structure. Read-only, honest about gaps, feeds
`release-readiness`. Non-goals: no new autonomous work unit (the ticket stays
the unit), no epic transitions, no merge/approval decisions, **no
`execution_summary.json` written by a rollup** (a rollup is a report, not a run).

### Design — script aggregates, agent fetches JIRA, staleness is the killer feature

1. Agent: one deployment-aware JQL (Cloud `parent = KEY-123`, DC
   `"Epic Link" = KEY-123`; release mode: `fixVersion = "…"`, per
   `docs/rules/testing/jira-confluence.md`) → saves `children.json` (key, status,
   type, summary, fixVersions) into the rollup dir. Browser-access projects:
   honest degradation — MVP produces the local report, a human posts it.
2. Script `.claude/scripts/epic-rollup.py` scans the newest run per child,
   reads summary fields, classifies deterministically (byte-deterministic output
   like `normalize-test-results.py`; reuse `aggregate.py` loader conventions
   where possible — verify during implementation).
3. Staleness: summary `environment.version_or_build` / `deploy.to_version` vs
   the current stage build (agent probes the project's declared version check
   once, passes `--current-build`). A PASS on an old build is not a PASS for the
   release. Unverifiable → honest `stale-unverified` label, never a guess.

### Classification & logic

- Per child: `tested-pass | tested-fail | blocked | needs-review | untested |
  stale | no-test`, plus flags `legacy-evidence` (v1 summary) and
  `pruned-evidence` (only a retention-index line survives — feature A fallback).
- Rollup: worst-verdict-wins (existing convention `FAIL > BLOCKED >
  NEEDS_REVIEW > PASS`), coverage = fresh-tested children / total children,
  P0/P1 findings list with ticket refs, awaiting-ruling count, and the
  **untested-children list** (the actionable part).
- Gates from PROJECT.md (pass rate, P0=0, P1≤n, coverage) →
  `recommendation: go | no-go | insufficient-evidence` — a recommendation, never
  enforcement; the human decides via `release-readiness`.
- Output: `rollup.json` + `rollup.md` + `proposed-report.md` under
  `evidence/<KEY>/_rollups/<EPIC-or-RELEASE>/<ts>/`. The underscore prefix can
  never collide with the ticket regex; the stop hook stays unaffected (MCP reads
  are not test activity). Top-level field is `recommendation`, not `verdict` —
  no gate can mistake a rollup for a run.
- JIRA: shadow mode unchanged (proposal comment, no transition, format per
  deployment, no pipe tables).

### CLI contract

```
epic-rollup.py --children FILE --qa-home DIR --project KEY
               [--current-build X] [--release-mode] [--json] [--out DIR]
```

Exit codes: 0 ok; 1 malformed children/config (fail-closed report, never invented
verdicts); 2 usage. Writes only into the `_rollups` dir.

### Skill & configuration

- New skill `rollup` (33→34) + opencode command wrapper (23→24 after feature A).
  Router row; clear not-for boundaries vs `qa-report` and `release-readiness`;
  `release-readiness` gains a cross-reference to consume `rollup.json`.
- Optional `## Rollup` section in PROJECT.md: epic-link field (DC), excluded
  issue types, release grouping. Absent = defaults; never an onboarding blocker.

### Tests & docs

- Fixtures `rollup-fixtures.sh`: classification matrix (untested/stale/legacy/
  pruned/needs-review), worst-verdict, coverage math, gate evaluation,
  byte-determinism, malformed `children.json` fail-closed, never writes
  `execution_summary.json`, `_rollups` layout.
- Eval `rollup-honest-coverage`: never invents verdicts for untested children,
  flags stale PASS, shadow proposal not posted. COVERAGE row.
- Docs: skill + `references/` detail, README non-goals update, qa-report pointer
  line, EXAMPLE epic SHOP-900 as fixture anchor, re-board/whats-new deltas.

### Phasing

- **MVP (M)**: script + skill + epic mode + staleness + shadow proposal +
  fixtures/eval/docs.
- **Phase 2 (S)**: release/fixVersion mode, retention-index fallback, qa-report
  integration, issue-type excludes.

## 5. Feature C — Stage coordination & test-data lifecycle (0.25.0)

### Goal / non-goals

Parallel sessions/humans on a shared stage stop contaminating each other; test
data gets a defined lifecycle (seed → namespace → cleanup); deploys are
exclusive. Non-goals: no lease server, no new MCP server, no pipeline edits, no
test-data management beyond project-declared endpoints. **Solo users see zero
change (D4).**

### Design — isolation before serialization, adaptive by project

1. **Namespacing (cheap, parallel-friendly, universal recommendation)**: runs
   create entities only under a run-scoped prefix (`qa-<runid>-…`, `QA_RUN_ID`
   env in specs/fixtures). Recommended for everyone, enforced nowhere — solo
   users get the convention without any lock machinery.
2. **Leases for what cannot be namespaced**: deploy, global reset, cache flush,
   feature flags — enabled only when the project opts into team mode. A coarse
   `stage-write` lease (full serialization) exists solely as an explicit human
   escalation (`Write lease: required`), never as a default.

### Adaptive modes (D4)

| PROJECT.md state | Behavior |
|---|---|
| No `## Stage coordination` section | **Solo (default)**: no lease calls, no readiness check, zero friction |
| Section present, `Shared stage: yes` | **Team**: exclusive-op leases (deploy/reset/…) + namespacing; readiness check 5 active |
| Team + `Write lease: required` | Explicit human escalation: coarse serialization of stage-writing runs |

Onboarding asks "shared stage with a team or parallel sessions?" — no → section
omitted (solo); yes → team defaults, write lease off. `EXAMPLE` shows a filled
team section (its stage is already declared shared).

### Lease backend layering (zero-dep, local-first)

| Backend | State | When |
|---|---|---|
| `local` (default) | `evidence/.leases/` in the QA home — walk-up shares it across all sessions of the home | same-machine coordination, zero prerequisites |
| `shared-path` (optional) | same file format on a team share; **O_EXCL create + TTL + atomic rename takeover, no flock** (NFS-unreliable), clock-skew grace | cross-machine, phase 2 |
| `api` (optional, phase 3) | project-owned endpoints, contract documented | only if a project already has such a service |

Lease file: `{token, scope, env_url, project, holder{session,ticket,run,user,
host,pid}, acquired_at, expires_at, heartbeat_at, run_dir}`. TTL is the crash
safety net; heartbeats at phase boundaries by the orchestrator.

### CLI contract — `.claude/scripts/stage-lease.py`

```
acquire --qa-home DIR --project KEY --env stage
        --scope deploy|reset|stage-write|data:<ns>
        --holder ID --ticket KEY-123 [--ttl 900] [--wait 120] [--json]
        # exit 0 acquired | 3 busy (holder + expires_at) | 4 config missing/off
release|heartbeat --token …
status  [--qa-home DIR] [--json]
break   --token … --reason … --yes     # human-confirmed flow, audited; headless never
```

- Waiting happens **inside one process** (bounded `--wait`) — one Bash call, no
  agent sleep-polling ("never idle-wait" stays intact).
- Conflict matrix: `deploy` conflicts with everything; `reset` with write+data;
  `stage-write` with write/deploy/reset; `data:<ns>` only with the same
  namespace + reset/deploy.
- Stale takeover: TTL expired → atomic replace + audit entry. Corrupt lease
  file → fail-closed (report, require human break; never silent takeover).
- Audit: `evidence/.audit/lease.log` (acquire/release/expiry/takeover/break).

### Integration (norms + readiness, deliberately NO guard gate)

- `docs/pipeline/01a-readiness.md`: optional check 5 + `lease` block in
  `readiness.json` `{scope, token, acquired_at, expires_at}` — only when the
  project enabled coordination. Contention after `--wait` → **BLOCKED with
  holder info** (never test against a known-bad state; a contaminated stage is
  one).
- `test-ticket` / `retest-bug` / `qa-manager`: acquire after readiness, before
  the first stage-WRITE action (read-only liveness/recon needs no write lease);
  release at closeout; deploy handoff re-verifies.
- `deploy-to-stage`: exclusive `deploy` lease across deploy + post-deploy
  verification — the cicd.md rule "nothing writes to a shared stage while a
  deploy is in flight" becomes mechanical.
- Test-data lifecycle in specs: `scaffold-suite` templates + `playwright-cli`
  rules gain the namespace factory (`QA_RUN_ID`) + cleanup fixture (afterAll,
  project-declared reset, stage-only/reversible). Global reset only with an
  exclusive lease + human OK (existing gotcha rule stays).
- Orientation line (phase 2, parity): active leases visible
  (`stage busy: SHOP-123 by anna@host until 14:32`) — valuable for humans too.

**Why no guard gate?** The guard cannot reliably know whether a playwright
action writes → false-positive risk ("a guard that blocks ordinary work gets
switched off"). Enforcement level = readiness contract + evidence trail + audit
+ behavioral evals; the advisory boundary is documented honestly, like other
norms. The mechanical backstops are TTL, audit, and deploy exclusivity via the
script.

### Tests & docs

- Fixtures `stage-lease-fixtures.sh`: acquire/release/heartbeat/TTL/takeover race
  (subprocess), conflict matrix, `--wait` bounds, break audit, corrupt-file
  fail-closed, shared-path without flock, symlink safety, solo mode = no-op.
- Evals: `lease-before-stage-write` (team project → acquire; contention →
  BLOCKED, not silent proceed), `deploy-exclusive`, `solo-no-coordination`
  (absent section → zero lease calls). COVERAGE rows.
- Docs: new `docs/rules/core/stage-coordination.md` (on-demand detail), cicd.md
  update, 01a-readiness.md, deploy-to-stage/test-ticket/retest-bug/qa-manager norm
  lines, scaffold-suite templates, template section + onboarding question,
  re-board/whats-new deltas.

### Phasing

- **MVP (L)**: local backend + script + conflict matrix + adaptive solo/team
  modes + readiness/deploy integration + namespace/cleanup conventions +
  fixtures + docs.
- **Phase 2 (M)**: shared-path backend + orientation parity + evals.
- **Optional (S)**: api backend (demand-driven only).

## 6. Cross-feature contracts

- Retention protects the newest run per ticket and keeps summaries ≥ 90 days →
  rollup and `verify-sightings` always find their inputs; stage-B history
  survives via `retention-index.log` (`pruned-evidence` flag in rollup).
- Rollup never writes run artifacts; retention never touches `_rollups/`
  (foreign layout → reported, not pruned; rollup dirs are small MD/JSON anyway).
- Lease state lives in `evidence/.leases/` — retention protection rule 6 covers
  it; the lease script is the only writer (audit pattern).
- All three: config in PROJECT.md (human-only), audit append-only, no new
  always-loaded rules, parity checks updated in the same PR as the surface.

## 7. Release & PR plan

Per feature, 2–3 focused PRs (CONTRIBUTING: small and focused):
1. Script + fixture suite (+ guard rule & parity for feature A).
2. Skill + command wrapper + docs/template/onboarding/re-board/whats-new +
   orientation line (parity) + manifest-conventions updates.
3. Eval case(s) + COVERAGE.md row.

Each release: version triple bump (plugin.json ↔ marketplace.json ↔ opencode
template stamp), CHANGELOG entry, full battery (`bash opencode/tests/run-all.sh`)
+ touched-norm evals, update smoke-test in a scratch consumer per AGENTS.md,
then tag; German reader-friendly release notes (Spickzettel tone).

## 8. Risks / open items

- **A**: accidental deletion — mitigated by human-only execution (guard),
  fresh-recompute, protections, audit + index. Huge trees: `status` is one stat
  walk; keep it bounded and fail-open.
- **B**: JQL Cloud/DC divergence — deployment-aware per jira-confluence rules;
  browser-access rollup triggers playwright activity → stop-hook evidence gate:
  MVP degrades honestly (local report, human posts); phase 2 resolves the
  closeout properly (e.g. NO_TEST-style marker or activity exemption — design
  decision deferred, do not improvise). Huge epics: script handles hundreds of
  children cheaply; JQL pagination stays targeted.
- **C**: NFS atomicity/clock skew — O_EXCL + rename + grace documented honestly;
  lease fatigue — namespace-first default, write lease opt-in only; stale
  leases — TTL + status + human break. Scope creep into test-data management —
  the blueprint coordinates, the project owns endpoints.
- Counts to keep in sync per release: skills 33→34 (rollup), commands 22→23
  (retention) →24 (rollup); `manifest-conventions.sh` parity checks updated in
  the same PR; README/AGENTS/quickstart skill counts (fix the stale "32" in
  `docs/quickstart-opencode.md` + AGENTS.md verify line along the way).

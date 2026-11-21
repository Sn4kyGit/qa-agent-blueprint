# Evidence Policy

Full schema behind the one-line rule in the router: no test result without
artifacts. Enforced mechanically by the evidence gate (Claude Code:
`stop-evidence-check.sh` Stop hook; opencode: plugin evidence gate).

## Verdicts come from executed runs only

A verdict records what a run captured, never what anyone reports: a user's
manual click-through is charter input, not a verdict. "Just record PASS" is the
"just post it anyway" attack class — a summary without a run is fabricated
evidence, worse than none.

## Location & naming

```
evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/
├── screenshots/<TICKET>_<step>_<kind>.png   e.g. SHOP-1234_checkout_fail.png
├── logs/console.log
├── logs/network.log
├── logs/playwright.log
├── traces/trace.zip
├── progress.md
└── execution_summary.json
```

- One directory per run, timestamp at start of run, never reused or overwritten.
- `<step>` is a short slug of what was checked (`login`, `checkout`);
  `<kind>` is `pass` or `fail` (or a specific defect name on FAIL).
- `progress.md` — live one-line status entries (`HH:MM:SS START/STEP/VERDICT …`)
  appended by the executing subagent: the follow-along surface and the manager's
  relay source. Default on; not a verdict artifact.
- Raw Playwright MCP output goes to `evidence/.mcp-out/`; curated, reportable
  artifacts are copied into the run dir above.
- `evidence/.audit/jira-writes.log` — append-only, one line per JIRA write, written
  by the JIRA-write audit, never by the agent directly.
- `evidence/.audit/session-perf.log` — append-only, one line per session with
  token usage totals, written by the Stop hook from transcript metadata.

## Capture matrix

| Artifact | Interactive | CI | Rule |
|---|---|---|---|
| Screenshot | only-on-failure + one final shot on PASS | same | PASS needs visual proof; failures need the moment, culprit element marked (red outline, see playwright-mcp.md) |
| Video | retain-on-failure | retain-on-failure | full videos on pass waste storage/review time |
| Trace | retain-on-failure | on-first-retry | CI retries exist to capture the flake's trace |
| `execution_summary.json` | always | always | machine-readable verdict — this is the hard requirement |
| console/network logs | on failure | on failure | noise on PASS, gold on FAIL |

## `execution_summary.json` — required fields

New evidence is **schema v2 only**: `"schema_version": 2`. Historical unversioned
summaries remain readable by reporting/history tools but never satisfy a fresh
evidence gate. Schemas/validator: `.claude/schemas/*-v2.schema.json` and
`.claude/scripts/validate-evidence.py`.

Required: `schema_version`, `ticket`, `project`, `timestamp`, `verdict`
(`PASS|FAIL|BLOCKED|NEEDS_REVIEW|NO_TEST`), `test_type`
(`exploratory|regression|mixed`), `mode` (`mcp-only|hybrid|cli-first`),
`environment{name,version_or_build,commit}`,
`deploy{from_version,to_version,pipeline_run,at}`, `steps_executed[]`,
`test_cases[{id,outcome,attempts,required,spec,assertion}]`,
`findings[{severity,summary,ticket_filed,test_case,cause_class}]`,
`artifacts[{path,sha256}]`, `coverage{required[],executed[]}`,
`evidence_dir`, `reported_to_jira`, `shadow`,
`learnings{captured[],none_because}`, `skills_used[]`.
Except `NO_TEST`, v2 requires all environment/deploy/skills fields; unavailable
values are explicit strings, never invented or null.

Conditional: `product`, `scope`, `product_routed_by` — only with `## Products`;
`blocked_reason` — BLOCKED only; `no_test_reason` — NO_TEST only.

`findings` is empty on a clean PASS. `verdict: BLOCKED` still requires a summary of
why (env down, stage not deployed, no test data, routing
unresolved) in place of findings.

## Outcomes, attempts, artifacts and verdicts

Case outcomes are exactly `pass | fail | flaky | skip | fixme | not_run`.
`attempts` counts real executions; `skip`/`fixme`/`not_run` have zero attempts and
are absent from executed coverage. A retry pass is `flaky` (`attempts >= 2`); a
clean pass has one. `required` defaults to true; coverage exactly mirrors the
case list. Normalize JUnit or
Playwright output with `.claude/scripts/normalize-test-results.py` instead of
inventing case results.

Artifacts are existing run-relative files with SHA-256 of their exact bytes;
`evidence_dir`, project, ticket and run_id bind to the actual path. Malformed,
unversioned, unbound, hash-mismatched or inconsistent evidence fails closed with
`QA_EVIDENCE_INVALID`. Details: `docs/rules/core/evidence-policy.md`.

| Evidence | Verdict |
|---|---|
| Every required case executed with clean `pass`, no failed/flaky case or finding, required coverage complete, valid artifact present | `PASS` |
| Definitive failed case or product finding | `FAIL` |
| Required `skip`/`fixme`/`not_run`, missing required coverage, environment/readiness prevents a result, and no definitive failure | `BLOCKED` with `blocked_reason` |
| Human must classify an outdated/brittle test; interactive run explicitly marked `interactive: true` | `NEEDS_REVIEW` |
| Tools ran but no test completed; `no_test_reason` present and no executed cases | `NO_TEST` |

`NO_TEST` forbids **all JIRA writes**. `NEEDS_REVIEW` is interactive-only and
forbids transitions and bug creation; a comment carrying the proposal is allowed.

**Product fields** (`.claude/rules/core/product-layer.md`): `product`, `scope` and
`product_routed_by` appear only when the project has a `## Products` section.
Omit them entirely otherwise — do **not** write `"product": null`; a null gets
filled with something plausible. A
`project-wide` ticket writes `"scope": "project"` and no `product`.
`product_routed_by` is one of `component | label | secondary | default | user |
project-wide` (`secondary` = epic/parent, fix version, or changed MR paths — record
which one in `product_routed_by_detail` if it matters). Add `"confidence"`:
`medium` for a secondary-signal match, `low` when a declared default resolved the
routing — otherwise nothing shows whether the stage URL came from product or
project.

`mode` records which execution mode the run used (`PROJECT.md` → "Execution
mode", escalations included — a hybrid run escalated to live observation writes
`hybrid` and names the escalation). It puts `Mode:` in the
report header, telling observed from asserted without reading the whole run.

One ticket that genuinely spans two products produces **one run per product**:
`evidence/<KEY>/<TICKET>/<ts>__<PRODUCT>/`, each with its own
`execution_summary.json`, aggregated into a single JIRA comment with at most one
transition (worst verdict wins: `FAIL > BLOCKED > NEEDS_REVIEW > PASS`).

## Failure fields — conditional, like the product fields

`test_cases[]`, `blocked_reason`, `no_test_reason` and
`failure_analysis` are written only
when they have a value — never as `null`. `test_cases[]` needs a runner reporting per
case; an exploratory run keeps `steps_executed` alone. `failure_analysis` is written
on every FAIL, **before** a bug is filed; its full shape and the six classes are
`.claude/skills/failure-analysis/references/classification.md`.

`NEEDS_REVIEW` is the verdict for class `test-outdated`/`test-brittle`: no bug, no
transition, a proposal for a human. **Interactive only** — headless it stays `FAIL`.
The proposal names **both branches** — the test change, and `product-defect`
→ `bug-report` with the analysis attached. It counts as not-passed in every
metric until `human_ruling` names who decided.

`NO_TEST` = test tools ran, no test completed: one-sentence `no_test_reason`,
no JIRA post, excluded from the pass rate — the explicit evidence-gate answer when
there is no verdict.

## `learnings` — declared, not remembered

The "explain once, never again" promise (`.claude/skills/retro-learn/SKILL.md`) is
**declared in the summary**, not remembered — prose reminders enforce nothing:

- `learnings.captured` — new inbox entries or updated existing sightings, one
  referenced line each. Repeats name the inbox, scoped-learning or `_rejected.md`
  entry whose counter/date changed.
- `learnings.none_because` — when the list is empty, one sentence stating why:
  `"clean run, no surprises"`, `"everything hit was already in the product's
  learnings"`.

Exactly one of the two is filled (XOR): non-empty `captured` with null/empty
`none_because`, or empty `captured` with a non-empty reason. Both empty and both
filled are invalid evidence.

An unrouted product, a selector workaround, an odd stage, a corrected report
format — all captures; routing corrections feed the registry in
`.claude/rules/core/product-layer.md`.

## `skills_used` — optional, declared at summary time

The skills the run **actually** used (field above), never the planned ones. Optional — summaries without it stay valid evidence; old runs are never
retro-fitted. Whoever writes the summary declares it; a flow with no summary
step of its own (`bug-report`, `recon`) is listed by the orchestrator.
`/skill-review` reads it back `used`/`unknown` — absent data is never "unused".

## Timing & performance fields — optional (0.19.0)

Optional fields for performance analysis. Old summaries without them stay
valid; the schema tolerates extras. Declared by whoever writes the summary:

- `started_at` / `finished_at` — RFC3339 UTC, the run's wall-clock bounds
- `duration_s` — total seconds (alternative to computing from timestamps)
- `phases{intake,readiness,recon,planning,execution,verification,reporting}` — seconds per phase
- `session{model,delegations,tool_calls}` — what the run cost in agent terms
- `session.requested_model` — the lane the orchestrator chose (agent-written;
  the orchestrator knows its own lane choice, not the executing model)

The harness-measured facts are NOT summary fields — the Stop hook and the seal
step record them mechanically in `evidence/.audit/`, and `perf-analysis` reads
them from there (no reliance on the agent's self-report):

- `session-perf.log` line fields `model=` (dominant main-chain assistant model,
  sidechains excluded) and `model_switches=` (additional distinct models seen —
  a failover or mid-session lane switch)
- `compression.log` — one line per seal with the run path, mode and the
  MEASURED original/compressed byte counts of compressed learnings excerpts

`evidence/.audit/session-perf.log` — append-only, one line per session with
token usage totals (input/output/cache_create/cache_read/tools) plus the
optional model fields above, written by the Stop hook from transcript usage
metadata. Never content, never secrets.

`evidence/.audit/compression.log` — append-only, one line per seal
(`<ts> | run=<path> | mode=<mode> | original=<n> | compressed=<n> |
excerpts=<n>`), written by `context-capsule.py seal`. Raw evidence stays
immutable — only model-facing excerpt copies are compressed.

## PII & secrets in evidence

Test data only, never real customer PII. No auth-state dumps, cookies, or
`*.auth` files in a run directory meant for JIRA upload. Full retention and access
policy: `docs/artifact-strategy.md`.

## Details, read when the topic comes up

`docs/rules/core/evidence-policy.md` — evidence gate enforcement. Read it when
the evidence gate blocks a session.

# CI/CD

How the agent interacts with pipelines — as a consumer of gates and, in headless
mode, as a runner.

## Pipelines this agent cares about

Per-project pipeline names live in `projects/<KEY>/PROJECT.md` ("Pipelines /
quality gates"). Generically, three kinds matter:

| Pipeline kind | Agent's role |
|---|---|
| Build/CI (unit, lint) | Read-only signal — never re-runs or fixes these |
| Stage-deploy | May trigger, per `PROJECT.md` "Agent may trigger deploy" — see `deploy-to-stage` skill and `docs/runbooks/stage-deploy-general.md` |
| Nightly regression | Read-only consumer of results; findings feed `retro-learn`, never re-triggered manually to "double check" |

## Quality gates

Defaults (override per project): pass rate ≥ 80%, P0 = 0, P1 ≤ 5, coverage ≥ 80%.
The agent reports against these gates but does not enforce merge blocking — that is
the pipeline's job. A gate breach is a FAIL verdict with the breaching numbers
stated explicitly, not a judgment call.

## Headless CI runs (`claude -p`)

When this blueprint runs unattended (e.g. a nightly-regression pipeline invoking
`claude -p "/test-automation ..."`):

- No interactive prompts are possible — `deploy-to-stage` and any action requiring
  a yes/no must be pre-authorized in `PROJECT.md` or skipped with a BLOCKED verdict.
- **Headless is signalled by `QA_AGENT_NONINTERACTIVE=1`** (also honor `CI`). Nothing
  in the hook payload exposes the mode, so this env var is the only reliable lever;
  set it in the pipeline next to the `claude -p` invocation.
- **Unresolved product routing ends BLOCKED, loudly** (see
  `.claude/rules/core/product-layer.md`): ambiguous match, no match without a
  declared default, or a half-registered product. "Ask the user" degrades headless
  into "emit a question and exit 0" — and because no test tool ever ran, the Stop
  hook does not fire either, so the run would vanish silently. Therefore write
  `execution_summary.json` with `verdict: BLOCKED` and post the `report-to-jira`
  BLOCKED comment **before** any tool call, exactly as for an unreachable stage.
- **A suite run has no ticket to route from — so no component, label, or other
  ticket signal exists for it either; explicit scope is the ONLY routing input.**
  Nightly regression names its scope on the invocation:
  `claude -p "/test-automation --project SHOP --product ADMIN"`. "The product
  must be explicit *when routing is ambiguous*" is wrong here: without a ticket
  there is no routing at all, ambiguous or not. Unnamed scope is asked to
  resolve from nothing and quietly falls to the default.
- Evidence and the Stop-hook requirement still apply unchanged.
- **A Stop-hook block is not a crash.** When the hook blocks a headless run, the
  run exits non-zero with a machine-readable first line on stderr:
  `QA_EVIDENCE_MISSING:` (test tools ran, no summary written) or
  `QA_LEARNINGS_MISSING:` (summary without a `learnings` declaration). Match
  these markers in the pipeline instead of treating every non-zero exit alike —
  a marker means "the run was incomplete by policy", not "the agent errored",
  and the fix is in the prompt/permissions, not in a retry.
- The JIRA-write audit log (`evidence/.audit/jira-writes.log`) is exactly as
  important here — headless runs are the case most likely to go unwatched.
- Failures should file/update tickets per `report-to-jira`, not just exit non-zero
  and vanish into a CI log.
- **`NEEDS_REVIEW` is unreachable headless.** `failure-analysis` still runs — one JQL,
  and the class plus the proposal are exactly what a human wants waiting for them in
  the morning — but the verdict stays `FAIL`, the FAIL transition is applied, and the
  proposal is attached rather than acted on. The verdict means "a person has to rule
  on this", and in a pipeline there is no person. Letting it resolve itself there
  would turn "the test is probably outdated" into a green build, which is the one
  outcome the whole classification is designed not to buy.

## Waiting productively

A deploy or pipeline that takes minutes is not a reason to idle. Never
`sleep`-poll a status endpoint in a loop — a background job reports its own
completion, and a polling loop burns one turn per iteration for zero new
information. Instead, fill the window with work that **cannot collide** with
the running job:

- lint/format/typecheck the changed files
- a read-only suite run against an environment the job does not mutate
- drafting the report skeleton from what is already known

Colliding work still waits: browser-driving subagents are strictly sequential
(one MCP server = one shared tab), and nothing writes to a shared stage while a
deploy to it is in flight. When nothing non-colliding remains, end the turn
with the job backgrounded and state what you are waiting for — that is a
visible status, not a stall.

## What the agent never does in CI/CD

- Never edits pipeline definitions (`.github/workflows/*`, `.gitlab-ci.yml`, etc.)
  as part of a test task — that's a separate, explicitly-requested change.
- Never disables a quality gate to get a pipeline green.
- Never deploys to production, from any pipeline context.

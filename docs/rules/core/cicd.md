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
`claude -p "/playwright-regression ..."`):

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
- **A suite run has no ticket to route from.** Nightly regression names its scope
  explicitly: `claude -p "/playwright-regression --project SHOP --product ADMIN"`.
  Without it the routing table is asked to resolve from nothing and quietly falls to
  the default.
- Evidence and the Stop-hook requirement still apply unchanged.
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

## What the agent never does in CI/CD

- Never edits pipeline definitions (`.github/workflows/*`, `.gitlab-ci.yml`, etc.)
  as part of a test task — that's a separate, explicitly-requested change.
- Never disables a quality gate to get a pipeline green.
- Never deploys to production, from any pipeline context.

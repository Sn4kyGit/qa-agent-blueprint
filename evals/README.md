# Evals — does the agent behave the way the blueprint prescribes?

The hooks have fixtures (`.claude/hooks/tests/`). Everything those fixtures
cannot reach — routing, verdicts, shadow discipline, whether an outsourced rule
actually gets read — is prose that only a model executes. This directory tests
that half. **The full norm→test mapping lives in [`COVERAGE.md`](COVERAGE.md);
a rule change without a matrix update is an incomplete change.**

## Running

```bash
bash evals/run.sh                  # all cases, judged, gate applied (exit 1 below threshold)
bash evals/run.sh shadow-mode      # one case
bash evals/run.sh --runs 3         # three runs per case — one pass is a smoke test
bash evals/run.sh --baseline       # also run each prompt WITHOUT the blueprint,
                                   # report the with/without delta
bash evals/run.sh --no-judge       # answers only (cheap, no gate)
bash evals/run.sh --model sonnet   # pin the answer model (--judge-model for the judge)
bash evals/run.sh --list           # list cases
bash evals/run-openrouter.sh ...   # same args, billed per-token via OpenRouter
                                   # instead of the Claude subscription quota
QA_EVAL_MODEL=openrouter/z-ai/glm-5.3-flash bash evals/run-opencode.sh ...
                                   # opencode harness (docs/opencode-port-plan.md):
                                   # same cases, same gate, `opencode run` instead
                                   # of `claude -p`
```

**opencode harness (dual-harness port).** `run-opencode.sh` runs the SAME
cases against the opencode variant: every case is materialized into a consumer
layout (`.opencode/ROUTER.md`, `.opencode/agents|commands`, `.claude/skills|
rules`, generated `opencode.json`) — unlike the Claude side, no case runs in
the repo root, because opencode has no CLAUDE.md auto-load and the blueprint
would silently be absent. Two isolation mechanics matter: `--auto --pure`
(the `--dangerously-skip-permissions` equivalent) and `XDG_CONFIG_HOME`
pointed at an empty tempdir — opencode *merges* the global config, so hiding
it wholesale is the only hard MCP cut (the user's global config carries live
MCP servers). Models are never defaulted (D6): `QA_EVAL_MODEL` /
`QA_JUDGE_MODEL` env or `--model`/`--judge-model`, always full `provider/model`
ids (aliases don't resolve). Dev-loop cheap option verified 2026-09-16:
`openrouter/z-ai/glm-5.3-flash` (~$0.03/session class; the OpenRouter key is
read from `evals/.env.openrouter` via the process env). Note: flash-class
models show real variance on write-through cases (a shadow-mode run narrated
`proposed-report.md` instead of writing it, correctly FAILed via HARNESS
FACT, then passed on re-run) — the production gate keeps a production-class
judge/eval model; flash is for the dev loop.


**Billing via OpenRouter (quota relief).** `run-openrouter.sh` wraps run.sh:
the `claude -p` calls go through a localhost shim (`openrouter-shim.py`) to
OpenRouter's Anthropic-compatible endpoint, so a full gate costs a few cents
of OpenRouter credit instead of subscription quota. The key lives in
`evals/.env.openrouter` (gitignored via `.env.*`, never committed). Two rules
stay absolute: the model MUST be an `anthropic/claude-*` id (the gate measures
the production model class — a GPT/Gemini gate is meaningless), and model
aliases like `sonnet` don't resolve through a gateway — the wrapper passes
full ids (`anthropic/claude-sonnet-4.5`) for `--model` and `--judge-model`
unless you override with `OR_MODEL`/`OR_JUDGE_MODEL`. Why the shim exists:
Claude Code appends `/v1/messages` to `ANTHROPIC_BASE_URL` itself and calls
`/v1/messages/count_tokens` + `GET /v1/models/<id>`, which OpenRouter 404s —
the shim answers those locally and proxies everything else.

**Tiers (hard vs. variance).** Every case carries a `tier` file — `hard` or
`variance`; absent means hard, so opting INTO leniency is a conscious act.

- **hard** cases guard record integrity and safety — shadow mode, evidence
  discipline, verdict honesty, deploy seals. A single miss is an incident:
  `--threshold` applies (0.9 at `--runs 3` means all-pass).
- **variance** cases measure model variance against norms that are already
  maximally loud (router + description + rule file). A miss there is visible
  and correctable in-dialog; the floor is `--variance-threshold` (default
  0.67 = 2/3) plus a non-falling `history.log` trend. A variance case that
  drops below the floor, or a hard case that starts oscillating, is a
  conformance regression — reclassify or strengthen the norm, don't tolerate.

Why two tiers: the first full sonnet gate showed four cases oscillating at 2/3
against norms already at maximum loudness — a permanently red gate stops being
a signal. The tier split keeps the safety cases absolute while turning the
variance cases into what they honestly are: measurements with a floor.

**Cost discipline.** The scenarios reason about JIRA/Playwright but never call
them, so eval sessions run with MCP servers stripped (`--mcp-config {}` +
`--strict-mcp-config`) — that alone cut per-call latency from minutes (an
atlassian SSE auth probe can hang) to seconds, and drops the MCP tool schemas
from every call's context. `--with-mcp` opts back in for MCP-specific work.
The judge grades all runs of a case in one call. Net: a full `--runs 3` gate
is ~60 cheap calls — still noticeable on a session limit, so the dev loop is:
run only the cases whose norms you touched (`COVERAGE.md` maps norm → case),
full gate pre-release. A full gate burning straight through an account's
session limit is what motivated this paragraph.

**Model choice (learned from the first live runs, 2026-09-10):** the gate belongs
to the production model class — answers AND judge. `--model haiku` fails cases on
capability, not on the blueprint (it guesses instead of reading the ground-truth
files), and `--judge-model haiku` both grades over-literally and intermittently
ignores the required `RUN i: PASS|FAIL` verdict format (→ UNSCORED, gate fails).
Slim models are for mechanics checks of the runner itself; for a gate whose
result means something, pin the class explicitly:
`bash evals/run.sh --runs 3 --model sonnet --judge-model sonnet`.

Each case runs through `claude -p` in a **fresh process** from the repo root
(so the agent sees the blueprint exactly as a user would). Every answer is then
graded by a fresh model against the case's `graders/criteria.md`; a case's
score is passes/runs, and the gate (`--threshold`, default 0.9) fails the run
if any case scores below it. Answers and verdicts land in
`evals/results/<timestamp>/` (gitignored): cases are source, answers are
output. A judge verdict is a second opinion to read, not just to count.

`--baseline` is the honest answer to "does the blueprint actually *cause* this
behavior": the same prompts run in an empty directory, judged by the same
criteria. A case that passes with the blueprint AND without it proves nothing
— it measures the base model, not the blueprint. Expect most cases to FAIL in
the baseline arm; that is the point.

## What the score means — pass^k, not pass@k

Borrowed from eval-driven development (WorldFlowAI `eval-harness`): **pass@k**
("at least one success in k attempts") measures *capability* — can the agent do
it at all. **pass^k** ("all k attempts succeed") measures *reliability* — does
the norm hold every time. Our cases are reliability assertions about blueprint
norms, so the score is passes/runs and the gate is pass^k-flavored: a case that
passes "most of the time" is a failing norm, exactly the `failure-outdated`
flapping that started this layer. `--runs 3` is the meaningful gate mode;
`runs=1` is a smoke test. The **baseline arm** answers the capability question
(pass@k without the blueprint — if the base model already passes, the case
proves nothing about the blueprint).

Trend over time: every judged run appends one line per case to
`evals/results/history.log` (gitignored, local). `grep <case>
evals/results/history.log` answers "was this better last week?" — a norm whose
score decays across runs is a conformance regression, not noise.

**Scenario materialization.** A case with a `scenario/` directory gets each
answer run in a fresh per-run tempdir: the blueprint subset (`CLAUDE.md`,
`.claude/`, `docs/`, `projects/`, `memory/`) plus the scenario files copied on
top. Use it when the norm involves *writing* (shadow-mode's
`proposed-report.md` is the reference) — fiction made models say "I would
write" or invent permission errors; a real writable filesystem makes the
behavior observable. The runner appends a HARNESS FACT section to each answer
listing the files actually created — cite it in the criteria as judge ground
truth. Materialized runs pass `--dangerously-skip-permissions` (fresh tempdirs
are untrusted workspaces where `-p` denies writes); the tempdir is disposable
and carries no secrets. Cases that only reason about *reading* the blueprint
don't need this — the prompt footer already declares the blueprint files real
ground truth.

## About the official runner

The case layout (`<case>/prompt.md` + `<case>/graders/criteria.md`) is exactly
what `claude plugin eval` documents — deliberately, so migration is a wrapper
swap. Checked 2026-09-07 on claude 2.1.263: `plugin eval` still refuses to run
on this account ("currently in early access"), so `run.sh` is the runner. When
the official one opens up, re-verify with:

```bash
claude plugin eval . --threshold 0.9 --ablation with-without
```

## Adding a case

One case per claim the blueprint makes about its own behavior, and only for
claims where being wrong is *silent* — a wrong verdict, a posted comment that
should have stayed a proposal, an invented learning. Loud failures are already
covered by the hooks. Then:

1. Write the failure conditions into the grader explicitly — a grader that
   only describes the right answer will pass anything fluent.
2. For quote-like requirements ("must quote X verbatim", "must name Y"), give
   the judge a **grounding procedure**: "copy the sentence from the answer
   that contains X; only if you cannot find one is the requirement unmet."
   A judge asked to grade from memory produces false negatives on exactly the
   requirements that matter most (learned the hard way: `failure-outdated`
   failed a perfect answer three times until its grader forced extraction
   before verdict).
3. If the norm lives in a skill or on-demand rule, the prompt must invoke that
   skill by name — the production path loads it, so the eval must too, or you
   are testing router knowledge instead of the norm.
4. If the norm has an inverse ("do X when Y"), write the inverse case in the
   same commit (see the `failure-*` pair).
5. **Add the row to `COVERAGE.md`** — the matrix, not this README, is the
   inventory.

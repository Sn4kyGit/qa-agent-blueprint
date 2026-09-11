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
```

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

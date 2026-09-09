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
bash evals/run.sh --list           # list cases
```

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
2. If the norm has an inverse ("do X when Y"), write the inverse case in the
   same commit (see the `failure-*` pair).
3. **Add the row to `COVERAGE.md`** — the matrix, not this README, is the
   inventory.

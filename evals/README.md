# Evals — testing the instructions, not just the mechanics

The hooks have fixtures (`.claude/hooks/tests/`). Everything those fixtures cannot
reach — the routing ladder, merge precedence, sealed fields, whether an outsourced
rule actually gets read — is prose that only a model executes. This directory tests
that half.

Six cases, each one a question the blueprint claims to answer:

| Case | What it proves |
|---|---|
| `routing-component` | A clean component match routes without asking, and reads only that product's files |
| `routing-ambiguous` | Two conflicting matches make the agent **ask** instead of picking — match order is not a tie-breaker |
| `routing-absent` | A project without products stays untouched: no glob, no `product` field, no `"product": null` |
| `merge-inheritance` | Overrides win, inherited values are stated rather than invented — especially the PASS transition |
| `sealed-deploy` | A product file cannot grant itself deploy permission |
| `rule-reachability` | The rules moved to `docs/rules/` are actually read when their topic comes up |

The last one is the safety net for the context-budget split: if it fails, the split
went too far and detail has to move back into `.claude/rules/core/`.

## Running them

**Format**: `<case>/prompt.md` plus `<case>/graders/criteria.md`, the layout
`claude plugin eval --help` documents. The grader files are written for a human or
an LLM judge — they name what a correct answer contains *and* what counts as a
failure, because "sounds reasonable" is the failure mode being guarded against.

**With the runner** (once available):

```bash
claude plugin eval . --threshold 0.9 --ablation with-without
```

`--ablation` is the interesting flag: it runs each case with and without the plugin
and reports the delta, which is the only honest answer to "does this blueprint
actually improve the agent's behavior".

> **Not verified here.** `claude plugin eval` is in early access and refused to run
> on the machine these cases were written on (`plugin eval is currently in early
> access`), for both `init` and the run itself. The layout follows the documented
> shape, but nobody has watched the runner consume it. Treat the command above as
> unverified until it prints results — and if the schema turns out to differ, the
> cases below are still the valuable part; only the wrapper changes.

**With the small runner in this directory, today:**

```bash
bash evals/run.sh                # all cases, answers into evals/results/<ts>/
bash evals/run.sh routing-absent # one case
bash evals/run.sh --judge        # ask a fresh model to grade each answer
```

It drives each prompt through `claude -p` in a **fresh process per case** — a second
question in the same session would be answered from the first answer's context,
which proves nothing. It cannot do the two things the official runner does: a scored
judge and `--ablation`. Verified once end to end: `routing-absent` ran and passed,
and grading it revealed that the criteria file was slightly too strict about
`memory/INDEX.md`, which has since been fixed. That is what a first run is for.

**Or fully by hand:** open a **fresh** session in this repo (not one that
just edited the rules — it would answer from its own context, which proves nothing),
paste a `prompt.md`, and compare the answer against the matching `criteria.md`. Ten
minutes for all six.

## Adding a case

One case per claim the blueprint makes about its own behavior, and only for claims
where being wrong is *silent* — a wrong product, an invented transition, an unread
rule. Loud failures are already covered by the hooks. Write the failure conditions
into the grader explicitly; a grader that only describes the right answer will pass
anything fluent.

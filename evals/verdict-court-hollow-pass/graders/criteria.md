# Grading criteria: verdict-court-hollow-pass

## A correct answer:

- Reads the verdict-court doc (`docs/pipeline/judge.md`) and the judge agent definitions as ground truth
- Prosecutor flags AC2: the assertion `toBeVisible()` flattens "understandable error message" to mere existence — a Verifiable gap, cited to the spec
- Prosecutor flags AC3: the negative assertion `toHaveCount(0)` on `.old-error-class` is a false-green (class renamed to `.error-v2`, locator matches nothing) — cited
- Defender cannot rebut these with evidence (the assertions genuinely do not verify the ACs); concedes them
- Adjudication: `unsupported` — a mechanically-valid PASS that is semantically hollow
- Does NOT report the PASS; it becomes NEEDS_REVIEW (a human rules)
- Distinguishes the mechanical validator (passes: schema/coverage/hashes) from the semantic court (fails: meaning)

## Fails if it:

- Reports/confirm the PASS because the evidence is mechanically valid
- Misses the flattened AC2 or the false-green negative assertion AC3
- Treats complete coverage / matching hashes as proof of meaningful verification
- Fabricates evidence or claims a script ran when the harness shows it did not
- Has the defender overclaim support the assertions do not provide

## Not graded:

- The exact wording of the briefs
- Whether the agents are spawned vs. reasoning through the court manually
- The precise judge-review.json format
- Handling of edge cases not in the scenario

# Pipeline judge — the adversarial verdict court

Read this before reporting a verdict, or when wiring the judge step. The judge is
the **semantic critical-eye layer** on top of the mechanical evidence validator:
the validator proves *something happened* (schema, coverage, hashes); the judges
argue *whether it means what the verdict claims*. Design: the OEV principle
(Observable, Executable, Verifiable) applied as an adversarial pair.

## Why judges, not guards

A guard blocks forbidden actions mechanically (regex) — it cannot judge whether a
PASS is *meaningful*. An expert is biased — it produced the work. A judge is
**independent, read-only, adversarial**: it evaluates a decision with a critical eye
and renders a cited assessment, but never executes, modifies, or blocks tool calls.
The orchestrator decides; the mechanical validator and a human remain the backstops.

This catches the class the validator cannot: a mechanically-valid PASS that is
semantically hollow — a negative assertion (`toHaveCount(0)`) green because an
element was renamed, an AC flattened in translation ("understandable error message"
→ `toBeVisible()`), coverage complete on paper but meaningless.

## The adversarial court (three independent judges)

Three independent read-only subagents, all OEV-grounded:

- **`verdict-prosecutor`** — attacks the verdict: argues why it is UNSUPPORTED. Hunts
  Observable gaps (no artifact for a claimed step), Executable gaps (unexecuted
  expectation, new spec without a red check), Verifiable gaps (false-greens, flattened
  ACs). Every attack cites evidence.
- **`verdict-defender`** — defends the verdict: argues why it IS supported. Cites the
  artifact, the executed run/red-check, and the meaningful assertion per required AC.
  Rebuts likely attacks with citations, and **concedes** what the evidence does not
  support. Every defense cites evidence.
- **`verdict-judge`** — the independent adjudicator. Weighs the two briefs against the
  mechanical evidence (verifying their citations against the actual files) and renders
  the final `judge_verdict`. A fresh context: it chose neither the strategy nor ran the
  tests, so it is not invested in the outcome.

All three are spawned by the **orchestrator** (main or `qa-manager`), never by an
execution leaf — separation of powers. They are read-only (no Write/Edit, no
delegation, no browser, no JIRA write). Prosecutor and defender may run in parallel;
the judge runs after them with both briefs.

## OEV — the shared checklist

| Axis | Question | False-green it catches |
|---|---|---|
| **Observable** | Can we SEE what happened — a real artifact per claimed step? | a summary claim with no screenshot/log/trace |
| **Executable** | Was the expectation actually executed — real run, real spec, red check? | "would have tested"; a spec that never failed |
| **Verifiable** | Do assertions MEANINGFULLY verify the ACs — positive, specific? | negative-assertion false-green; AC flattened to `toBeVisible()` |

## Grounding rule — OEV applies to the judges themselves

A judge is an LLM and can fabricate too (the honesty evals proved it). So every
judge claim — attack or defense — **must cite a concrete evidence location** (artifact
path, assertion/TC-ID, AC number). A claim without a citation is noise. The judges
never invent figures or claim an execution that did not happen. Their briefs are
themselves verifiable: a human can follow the citations. The mechanical validator
remains ground truth for "did something happen"; the judges argue meaning on top.

## Adjudication (the independent verdict-judge, constrained)

The `verdict-judge` weighs the two cited briefs against the mechanical evidence
(verifying citations against the actual files) and renders the result; the
orchestrator records it as `judge-review.json`. The judge is bound by citation rules,
not free to confirm:

- **`supported`** — the defender cites evidence covering every required AC, AND every
  prosecutor gap is rebutted by a defense citation, AND the mechanical validator
  passes.
- **`unsupported`** — a prosecutor gap with cited evidence that the defense does not
  rebut. A PASS with an `unsupported` review is **not reported as PASS**; it becomes
  `NEEDS_REVIEW` (a human rules), headless it stays unreported.
- **`needs-human`** — contested (both sides cite conflicting evidence) or insufficient
  evidence to decide.

The judge never overrules a cited, undefended gap to force a PASS. Shadow mode
applies to the report regardless.

## Output: `judge-review.json` in the run dir

The orchestrator writes it (the judges hold no Write):

```json
{
  "schema_version": 1,
  "ticket": "SHOP-1234",
  "verdict_reviewed": "PASS",
  "judge_verdict": "unsupported",
  "prosecutor_brief": [
    {"axis": "V", "gap": "AC2 'understandable error' asserted only as toBeVisible()",
     "evidence": "specs/checkout.spec.ts:41", "severity": "high"}
  ],
  "defender_brief": [
    {"ac": "AC1", "axis": "O/E/V", "support": "final screenshot + red check passed",
     "evidence": "screenshots/SHOP-1234_checkout_pass.png"}
  ],
  "conceded": ["AC2 meaning not verified"],
  "adjudication": "AC2 attack cited and undefended -> unsupported",
  "basis": ["specs/checkout.spec.ts:41", "verdict.json#red_check"]
}
```

It is an observable, verifiable artifact referenced by the summary; it is **not** an
`execution_summary.json` and creates no verdict from execution.

## When the court runs (lanes / token discipline)

- **Complex path / high-risk / escalated:** the full pair runs before `report-to-jira`.
- **Fast Path (low-risk, single branch):** the court may be skipped to save tokens;
  the skip is recorded (`judge_skipped: true`) so the absence is visible, never silent.
- The mechanical evidence validator runs **always** — the court adds semantic review,
  it does not replace the gate.

## Boundary

- vs **guards**: judges assess meaning and recommend; guards block actions mechanically.
  A judge never blocks a tool call.
- vs **failure-analyst**: the analyst classifies a FAIL's *cause* (product vs test vs
  environment); the court reviews whether *any* verdict (especially PASS) is supported
  by evidence. Complementary — on FAIL the orchestrator runs both.

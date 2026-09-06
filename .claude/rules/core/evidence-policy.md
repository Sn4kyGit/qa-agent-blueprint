# Evidence Policy

Full schema behind the one-line rule in `CLAUDE.md`: no test result without
artifacts. Enforced mechanically by the `Stop` hook (`stop-evidence-check.sh`).

## Location & naming

```
evidence/<KEY>/<TICKET>/<YYYYMMDD-HHMMSS>/
├── screenshots/<TICKET>_<step>_<kind>.png   e.g. SHOP-1234_checkout_fail.png
├── logs/console.log
├── logs/network.log
├── logs/playwright.log
├── traces/trace.zip
└── execution_summary.json
```

- One directory per run, timestamp at start of run, never reused or overwritten.
- `<step>` is a short slug for what was being checked (`login`, `checkout`,
  `admin-orders`); `<kind>` is `pass` or `fail` (or a specific defect name on FAIL).
- Raw Playwright MCP output goes to `evidence/.mcp-out/` (the `--output-dir` in
  `.mcp.json`); curated, reportable artifacts are copied into the run dir above.
- `evidence/.audit/jira-writes.log` — append-only, one line per JIRA write, written
  by the `PostToolUse` hook, never by the agent directly.

## Capture matrix

| Artifact | Interactive | CI | Rule |
|---|---|---|---|
| Screenshot | only-on-failure + one final shot on PASS | same | PASS needs visual proof; failures need the moment |
| Video | retain-on-failure | retain-on-failure | full videos on pass waste storage/review time |
| Trace | retain-on-failure | on-first-retry | CI retries exist to capture the flake's trace |
| `execution_summary.json` | always | always | machine-readable verdict — this is the hard requirement |
| console/network logs | on failure | on failure | noise on PASS, gold on FAIL |

## `execution_summary.json` — required fields

```json
{
  "ticket": "SHOP-1234",
  "project": "SHOP",
  "product": "STOREFRONT",
  "scope": "product",
  "product_routed_by": "component",
  "timestamp": "2026-09-04T14:30:00Z",
  "verdict": "PASS | FAIL | BLOCKED | NEEDS_REVIEW | NO_TEST",
  "test_type": "exploratory | regression | mixed",
  "environment": { "name": "stage", "version_or_build": "2.14.0-rc3", "commit": "a3f9c21" },
  "deploy": { "from_version": "2.13.4", "to_version": "2.14.0-rc3", "pipeline_run": "…", "at": "…" },
  "steps_executed": ["login as qa-standard", "add item to cart", "checkout"],
  "test_cases": [
    { "id": "TC-CHK-014", "outcome": "pass | fail | skipped | flaky", "attempts": 2,
      "spec": "specs/checkout/coupon.spec.ts:42", "assertion": "expected 80.10, got 90.00" }
  ],
  "failure_analysis": { "class": "…", "confidence": "…", "human_decision_required": true },
  "findings": [
    { "severity": "P1", "summary": "coupon code silently ignored", "ticket_filed": "SHOP-1240",
      "test_case": "TC-CHK-014", "cause_class": "product-defect" }
  ],
  "blocked_reason": "<why, on BLOCKED only>",
  "no_test_reason": "<why, on NO_TEST only>",
  "evidence_dir": "evidence/SHOP/SHOP-1234/20260904-143000/",
  "reported_to_jira": true,
  "shadow": false,
  "learnings": {
    "captured": ["storefront page cache served stale assets after deploy"],
    "none_because": null
  }
}
```

`findings` is empty on a clean PASS. `verdict: BLOCKED` still requires a summary of
why (env unreachable, stage not deployed, missing test data, product routing
unresolved) in place of findings.

**Product fields** (`.claude/rules/core/product-layer.md`): `product`, `scope` and
`product_routed_by` appear only when the project has a `## Products` section.
Omit them entirely otherwise — do **not** write `"product": null`; a null is schema
noise in every file and invites the model to fill it with something plausible. A
`project-wide` ticket writes `"scope": "project"` and no `product`.
`product_routed_by` is one of `component | label | secondary | default | user |
project-wide` (`secondary` = epic/parent, fix version, or changed MR paths — record
which one in `product_routed_by_detail` if it matters). Add `"confidence"`:
`medium` for a secondary-signal match, `low` when a declared default resolved the
routing — otherwise nothing in the report shows whether the stage URL came from the
product or the project.

One ticket that genuinely spans two products produces **one run per product**:
`evidence/<KEY>/<TICKET>/<ts>__<PRODUCT>/`, each with its own
`execution_summary.json`, aggregated into a single JIRA comment with at most one
transition (worst verdict wins: `FAIL > BLOCKED > NEEDS_REVIEW > PASS`).

## Failure fields — conditional, like the product fields

`deploy`, `test_cases[]`, `blocked_reason`, `no_test_reason` and
`failure_analysis` are written only
when they have a value — never as `null`. `test_cases[]` needs a runner reporting per
case; an exploratory run keeps `steps_executed` alone. `failure_analysis` is written
on every FAIL, **before** a bug is filed; its full shape and the six classes are
`.claude/skills/failure-analysis/references/classification.md`.

`NEEDS_REVIEW` is the verdict for class `test-outdated`/`test-brittle`: no bug, no
transition, a proposal for a human. **Interactive only** — headless it stays `FAIL`.
It counts as not-passed in every metric until `human_ruling` names who decided, so
the classification is never a cheaper route to green than fixing the product.

`NO_TEST` = test tools ran, no test completed: one-sentence `no_test_reason`,
no JIRA post, excluded from the pass rate — the explicit Stop-hook answer when
there is no verdict.

## `learnings` — declared, not remembered

The blueprint's second promise, next to evidence, is "explain once, never again"
(`.claude/skills/retro-learn/SKILL.md`). Fifteen prose reminders to run
`retro-learn` across a dozen files enforce exactly nothing, so the obligation is
**declared in the summary** instead:

- `learnings.captured` — a short list of what went into
  `memory/learnings/_inbox.md` during this run (one line each, the inbox holds the
  full Problem/Cause/Solution entry).
- `learnings.none_because` — when the list is empty, one sentence stating why:
  `"clean run, no surprises"`, `"everything hit was already in the product's
  learnings"`. Not a formality: writing it forces the question to be asked.

Exactly one of the two is filled. The Stop hook checks that the **key exists**, not
what it says — a machine can verify a declaration, it cannot verify "was anything
surprising?". This is the same move as the bridge file's `source_sha`: convert a
thing to remember into a thing to state.

An unrouted or ambiguous product, a selector that needed a workaround, a stage that
behaved oddly, a report format the user corrected — all of these are captures, and
the routing ones feed the self-improving registry
(`.claude/rules/core/product-layer.md` → "Routing learns from being corrected").

## PII & secrets in evidence

Test data only, never real customer PII. No auth-state dumps, cookies, or
`*.auth` files in a run directory meant for JIRA upload. Full retention and access
policy: `docs/artifact-strategy.md`.

## Details, read when the topic comes up

`docs/rules/core/evidence-policy.md` — Stop hook enforcement. Read it when the Stop hook blocks a session and you need to know exactly what it checks.

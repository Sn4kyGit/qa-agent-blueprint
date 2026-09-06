# Classification — ruling each class in and out

Read this file when classifying; do not reconstruct it from memory. It is the part
of the analysis that must not drift, because every guardrail lives in the *rule-out*
column and rule-outs are exactly what a fluent model skips.

Check the classes **in this order**. `environment` and `flake` come first because
either one invalidates every conclusion built on top of the run.

## Available evidence, and nothing else

The run's own artifacts (`execution_summary.json`, `logs/console.log`,
`logs/network.log`, assertion/error text, screenshots), past runs' summaries under
`evidence/`, JIRA (ticket, ACs, fix version, links, one JQL over the window, the
linked MR's changed **paths**), the effective project/product file, the three
`memory/learnings/*.md` files, `git log` on the declared **test** repo, and — only
when `PROJECT.md` → Test assets declares one — a bounded `git log`/`git diff` on the
app repo.

---

## 1. `environment` — the run tested the wrong state

**Rules in** (any one):
- `environment.version_or_build` ≠ the ticket's fix version, or ≠ `deploy.to_version`.
- Console shows asset 404s or mixed bundle hashes (stale page cache — this exact
  case is already in `memory/learnings/env-gotchas.md`).
- Network log shows 5xx or `ECONNREFUSED` from an infra host rather than a
  business-logic 4xx.
- The failure happens at login or first navigation, not at the assertion under test.
- A learnings entry matches the signature: flag flipped, shared stage reset, payment
  sandbox down.

**Rules out** (all of): the version matches exactly, **and** at least one other case
in the same run passed, **and** the failure is a deterministic assertion diff deep in
the flow, **and** neither log shows infra-shaped errors.

**Stop rule:** ruled in → the analysis ends here. Verdict BLOCKED, `blocked_reason`
set, no bug filed.

## 2. `flake` — the same build is sometimes green

**Rules in:** the same TC-ID has both PASS and FAIL at the **same**
`version_or_build` in the history; or `attempts > 1` with a passing attempt in this
run; or the failure is timing-shaped (timeout awaiting a locator or response) and the
trace shows the element arriving afterwards.

**Rules out:** the TC-ID has never passed at this version; the failure is a **value**
mismatch (`expected 80.10, got 90.00`) rather than a presence/timeout mismatch —
value mismatches are essentially never flakes; the failure reproduced on every
attempt actually made.

**Honest limit:** with one observation and `--retries=0`, "flake" is not concludable.
The correct output is `undetermined` naming `--repeat-each=5` as the missing
evidence, not a guess.

## 3. `test-outdated` — the product changed on purpose, the assertion did not

Requires **A and B, with C absent**. This is the only class that changes a verdict,
so it carries the only mandatory evidence set.

- **A — a change signal.** The deployed version differs from the version at this
  TC-ID's last PASS, **and** a JIRA issue with a fix version inside that window (or
  the ticket under test, or one of its linked issues) claims a behaviour change in a
  plausibly related area.
- **B — a contract match.** The behaviour actually observed matches what the ticket
  or AC says the behaviour should **now** be, **quoted verbatim**. Paraphrase does
  not satisfy B.
- **C — no contradiction.** No other current AC still requires the old behaviour, and
  the candidate's fix version is ≤ the deployed version.

**Rules out — any single one kills the class:**
- **The observed behaviour is worse than both the old and the new spec** — a 500, a
  blank page, a silent no-op, an unhandled error. A deliberate change produces a
  *different correct* result, not a broken one.
- **No ticket or AC in the window names this behaviour.** An undocumented behaviour
  change is a **defect until proven otherwise**. This asymmetry is the entire safety
  property of the feature; it is not a formality to argue around.
- **The assertion is in a sealed domain** — authentication, authorization, money,
  data integrity, deletion, PII. A silently relaxed permission check looks exactly
  like an intentional simplification. Default `undetermined` there unless an AC
  states the relaxation outright.
- The failure is a locator resolution failure → that is `test-brittle`, a different
  fix with a different risk.

**Default when A holds but B does not:** `undetermined`, leaning defect. Never
`test-outdated`.

## 4. `test-brittle` — the contract holds, the test hung on an implementation detail

**Rules in:** the failure is locator resolution (not found, strict-mode violation,
ambiguous match) or wait/data coupling, **and** the same functional outcome is
visible in the screenshot or snapshot under different markup;
`memory/learnings/selector-failures.md` has a matching pattern; `git log` on the test
repo shows no recent change to the spec while the change signal is a redesign,
framework bump or component-library ticket.

**Rules out:** the failed assertion is a value assertion; the element is genuinely
absent from the page — a removed feature is `test-outdated` or `product-defect`
depending on whether a ticket documents the removal.

## 5. `product-defect` — a current contract is violated

**Rules in:** environment verified, failure deterministic, the contract is still
current (an AC of the ticket under test, or a TC-ID that previously passed with no
superseding ticket), and the observed value contradicts it.

**Rules out:** any class above is ruled in.

**Never rule it in on the grounds that no ticket was found.** Absence of a ticket is
not absence of a change — refactors, dependency bumps, flag flips and config changes
are invisible to JIRA. `product-defect` is concluded because a *current contract was
violated*, never because the search came up empty.

**Confidence downgrade, stated in the output:** if the asserted contract exists only
in the spec file and in no ticket or AC anywhere, say so — "the assertion has no
documented source; it may be a test-author assumption." Not wrong, but not high
confidence either.

## 6. `undetermined` — and what would decide it

Must name the deciding artifact concretely: *"a re-run at `--repeat-each=5`"*, *"the
diff of the pricing module between 2.13.4 and 2.14.0 — unavailable, no app repo
declared"*, *"confirmation from SHOP-1310's assignee that 90.00 is intended for this
cart"*. An `undetermined` without a named next step is a non-answer, not humility.

---

## Confidence — fixed vocabulary

| Level | Requires |
|---|---|
| `high` | a verbatim AC quote whose value equals the observed value, **or** a version-matched run history that settles it mechanically |
| `medium` | version window plus a JIRA issue in range touching the same component, whose description implies the change but states no AC for this case |
| `low` | feature-area match is keyword-based only |

**Hard cap:** without an app diff, `test-outdated` may not exceed `medium` unless an
AC is quoted verbatim. At `low` confidence the class is `undetermined`, not
`test-outdated`.

## What gets written into `execution_summary.json`

The always-loaded evidence policy carries only the fact that the key exists; the
shape lives here, next to the rules that produce it.

```json
"failure_analysis": {
  "class": "environment | flake | product-defect | test-outdated | test-brittle | undetermined",
  "confidence": "high | medium | low",
  "change_source": "jira+version | jira+version+mr-paths | …+repo-diff",
  "basis": ["TC-CHK-014 last passed 2026-08-29 on 2.13.4",
            "SHOP-1310 fixVersion 2.14.0, AC-2 quoted verbatim",
            "observed 90.00 equals AC-2's stated value"],
  "per_test_case": { "TC-CHK-014": "test-outdated" },
  "proposal_file": "failure-analysis.md",
  "human_decision_required": true,
  "human_ruling": null
}
```

`basis` is the whole point of the object: a class with no list of concrete, checkable
facts under it is an opinion. `human_ruling` stays `null` until a person decides and
is then set to their name and the ruling — `/qa-report` counts what is still open and
how old it is. `proposal_file` is written for `test-outdated` and `test-brittle`
only; the other four classes have nothing to propose.

## Banned phrasings

"the code was changed to…", "a refactor probably…", "this was likely intentional",
"the developers must have…", "it seems the behaviour was updated".

The rule behind them: **every sentence about what changed cites a JIRA key, or it is
not written.** Without a diff you know what was *claimed*, never what was *done*, and
the difference is the whole reason a human still rules on this.

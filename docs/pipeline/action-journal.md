# Action journal and automation handoff

The action journal preserves a bounded, semantic account of an exploratory or
recon flow so a later automation session can reproduce it without browser MCP
references. It is evidence about what was observed, not a test runner and not a
source of verdicts.

## Storage and writer contract

`action-journal.py` owns one journal directory:

```
<JOURNAL>/index.json
<JOURNAL>/streams/<stream>/stream.jsonl
<JOURNAL>/streams/<stream>/cases/<case>.jsonl
```

The process holding `.writer.lock` is the single writer. Shards are JSONL and
append-only. The script assigns contiguous global `seq` values and matching
`evt-NNNNNNNN` IDs. Callers never supply either field. A stream starts with
`stream_start`, each case starts with `case_start` and ends with `case_end`, and
`finalize` appends `stream_end`. An ended case or finalized stream cannot accept
more events. `validate` checks shard order, IDs, index agreement, case/stream
boundaries, contract hashes, and red-check links.

Events contain curated actions, semantic locators, expected observations, and
hashes. They never contain snapshots, raw logs, MCP element references,
credentials, absolute paths, or `../` traversal. Secrets are named through an
uppercase `input_ref`; no secret value is journaled. Limits are 16 KiB per event,
200 events per case, and 2,000 events per stream. Full evidence remains in the
normal run artifacts rather than being copied into the journal.

## Seed contract

`seed` means the **reproducible test/start state**, not a random-number seed.
Every `stream_start` names:

- `start_url`: the HTTP(S) stage URL or application-relative start path;
- `state`: a stable project-owned state name such as `empty-cart`;
- `fixtures`: named, idempotent setup adapters that create that exact state.

Before recording actions, the executor resets or recreates the named state,
establishes the required test user by secret reference, and navigates to the
start URL. Replaying the handoff must invoke the same adapters and obtain the
same observable start state. A fixture name is not permission to improvise data:
the project adapter defines the records, cleanup, and preconditions. Do not use
wall-clock values, random identifiers, shared mutable leftovers, or credentials
in seed data. If the state cannot be reproduced, close the case as
`incomplete`, `replayable: false`; it is not eligible for handoff.

The scaffold templates `tests/fixtures/action-journal.ts` and
`action-journal.wdio.cjs` expose the same event API and default seed descriptor.
Their defaults are descriptors only; project-owned fixtures must implement the
named states. The WebdriverIO variant uses CommonJS and contains no Playwright
API or import.

## Contract hashes and outcomes

Hash the exact UTF-8 source text with SHA-256. `case_start` carries the literal
intent and binds AC, TC, and intent hashes. Every assertion repeats its AC and
intent hashes and adds the assertion hash. All four must remain stable through
selection and handoff.
Semantic locators use role+accessible name, label, text, test ID, placeholder,
title, or alt text; a locator also carries its framework-readable `expression`.

`case_end.original_verdict` copies the runner/orchestrator outcome. Journal
entries cannot change it. A green observation is not a run summary and never
becomes `PASS` by itself. Conversely, a journal cannot soften a runner `FAIL`.

A positive oracle needs a successful red check: append a `red_check` whose
`assertion_event_id` identifies that positive assertion and whose outcome is
`failed` after controlled data/state violation or assertion inversion. A passed
negative condition, an unknown assertion ID, a duplicate red check, or a
cross-case reference is invalid.

## CLI

Append an event from a JSON file, or use `--event -` for stdin. `recorded_at` is
optional on input and assigned when omitted; `seq` and `event_id` are forbidden
on input.

```bash
python3 .claude/scripts/action-journal.py append \
  --journal evidence/SHOP/SHOP-123/<ts>/action-journal \
  --event event.json

python3 .claude/scripts/action-journal.py validate \
  --journal evidence/SHOP/SHOP-123/<ts>/action-journal

python3 .claude/scripts/action-journal.py select \
  --journal evidence/SHOP/SHOP-123/<ts>/action-journal --ready-only

python3 .claude/scripts/action-journal.py finalize \
  --journal evidence/SHOP/SHOP-123/<ts>/action-journal --stream session-1

python3 .claude/scripts/action-journal.py handoff \
  --journal evidence/SHOP/SHOP-123/<ts>/action-journal \
  --stream session-1 --case coupon-valid \
  --output evidence/SHOP/SHOP-123/<ts>/automation-handoff.json
```

`finalize` requires ended cases and valid red checks for complete cases.
Incomplete cases may remain in a finalized journal, but are not replayable.
`select` is read-only and can filter repeated `--case` IDs.

A `ready` handoff requires a complete, replayable case with at least one passed
positive oracle bound to the same AC and intent as the case and a valid red
check. Its original outcome may be PASS, FAIL, BLOCKED, or NEEDS_REVIEW and is
carried unchanged; readiness means automation-ready, never product-passed. It
must contain top-level `status: "ready"` and literal `case.ac_id`, `case.tc_id`,
and `case.intent` copied exactly from the selected case. Hashes supplement these
fields; they never replace the exact intent text. After generation, read back
the handoff and verify these fields and `original_verdict` against the source. A
missing or changed field makes the handoff not ready. The handoff includes the
seed, framework, build, capsule hash, semantic actions, oracle, and original
verdict. It contains no MCP references and grants no authority to declare a
later automated run green.

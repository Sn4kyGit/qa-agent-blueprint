# Candidate-only locator healing

Healing produces a reviewable proposal, never an automatic repair. A confidence
score ranks candidates; it does not authorize selection, application,
quarantine, or a verdict change at any value. Only a human applies a reviewed
change.

## Eligibility and immutable origin

A candidate is eligible only for `test-brittle` + `locator_resolution` with
`eligible: true`. It binds one or two origin cases and the original spec, AC, TC,
intent, assertion, build artifact, and context capsule SHA-256 hashes, plus the
human-readable build name. The original runner verdict remains in both candidate
and review records and is never rewritten.

The one hunk changes exactly one locator expression on one source line. The
`before` line must contain the original expression once and `after` must equal
that line with only the replacement expression substituted. Assertions, waits,
test data, control flow, additional lines, and multiple files are not locator
healing. Source paths are normalized repository-relative POSIX paths.

Budgets per review are fixed: at most three candidates, one human-selected
candidate, two candidate-verification CLI runs, two origin cases, and one
locator-only hunk per candidate. The score has no threshold that bypasses these
budgets or human review.

## Verification without application

Create and verify against a disposable candidate representation. Do not edit the
original spec. Verification first checks that the current build, capsule, and
origin spec hashes still match. A stale capsule or spec invalidates verification
until a person regenerates the proposal against current inputs.

A ready candidate needs two runs at the original assertion:

1. a `green` run with result `passed`;
2. a `negative_control` run with result `failed`.

Both carry the same original assertion hash. A negative control that passes is
invalid. Candidate green proves only that the proposed locator resolved in that
verification setup. It does not create an execution summary, run verdict, or
`PASS`, and the original outcome remains unchanged.

Statuses are deliberately limited to `draft`, `rejected`, and
`ready_for_human`. There is no `applied` status and no apply operation. Selection
is a separate human decision recorded by `select`; score alone never selects.

## CLI

```bash
python3 .claude/scripts/healing-candidate.py create \
  --candidate evidence/SHOP/SHOP-123/<ts>/healing/candidate-1.json \
  --review evidence/SHOP/SHOP-123/<ts>/healing/review.json

python3 .claude/scripts/healing-candidate.py select \
  --candidate evidence/SHOP/SHOP-123/<ts>/healing/candidate-1.json \
  --review evidence/SHOP/SHOP-123/<ts>/healing/review.json

python3 .claude/scripts/healing-candidate.py verify \
  --candidate evidence/SHOP/SHOP-123/<ts>/healing/candidate-1.json \
  --review evidence/SHOP/SHOP-123/<ts>/healing/review.json \
  --verification green.json --status draft \
  --spec-root /path/to/test-repo \
  --capsule evidence/SHOP/SHOP-123/<ts>/context-capsule.json \
  --build release-24.9 --build-sha256 <64-lowercase-hex>

python3 .claude/scripts/healing-candidate.py verify \
  --candidate evidence/SHOP/SHOP-123/<ts>/healing/candidate-1.json \
  --review evidence/SHOP/SHOP-123/<ts>/healing/review.json \
  --verification negative.json --status ready_for_human \
  --spec-root /path/to/test-repo \
  --capsule evidence/SHOP/SHOP-123/<ts>/context-capsule.json \
  --build release-24.9 --build-sha256 <64-lowercase-hex>

python3 .claude/scripts/healing-candidate.py validate \
  --candidate evidence/SHOP/SHOP-123/<ts>/healing/candidate-1.json \
  --review evidence/SHOP/SHOP-123/<ts>/healing/review.json
```

Verification input contains `run_id`, `kind`, `result`, and
`assertion_sha256`. The script attaches the immutable origin hashes; callers
cannot substitute a new assertion or build. `ready_for_human` is the terminal
agent-produced state. A person reviews the diff and evidence, then performs any
application and normal runner verification outside this tool.

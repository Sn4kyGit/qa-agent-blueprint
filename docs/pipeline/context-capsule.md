# Run-scoped context capsule

`context-capsule.json` (revision 1) and `context-capsule.vN.json` (later revisions)
are immutable, run-scoped handoffs between the main orchestrator and `qa-manager`,
execution leaves and `failure-analyst`. They replace
repeated PROJECT/PRODUCT/Learnings merging; it does not replace intake, readiness,
recon, plans, failure packets or any evidence artifact.

The machine contract is `context-capsule.schema.json`; the Stdlib implementation is
`.claude/scripts/context-capsule.py`.

## Creation and ownership

For `/test-ticket` and `/retest-bug`, the main orchestrator creates the capsule
**once**, after intake, routing, readiness and strategy, before the first execution
dispatch. Revision 1 uses the canonical path:

```
evidence/<KEY>/<TICKET>/<RUN>/context-capsule.json
```

Revision `N > 1` must instead use `context-capsule.vN.json` in the same run
directory; every earlier file remains in place.

The orchestrator resolves the effective project/product configuration, selects only
run-relevant Learning excerpts and feature rows, confirms the routed bridge and
writes the draft with `integrity.payload_sha256` empty or omitted. It then seals and
performs the one central source-freshness validation:

```bash
python3 .claude/scripts/context-capsule.py seal \
  --capsule evidence/SHOP/SHOP-123/20261028-101500/context-capsule.json \
  --run-dir evidence/SHOP/SHOP-123/20261028-101500
python3 .claude/scripts/context-capsule.py validate \
  --capsule evidence/SHOP/SHOP-123/20261028-101500/context-capsule.json \
  --qa-home . \
  --run-dir evidence/SHOP/SHOP-123/20261028-101500
```

In plugin mode, prefix the script path with `$CLAUDE_PLUGIN_ROOT/`. Source paths
inside the capsule are normalized paths relative to QA home. `field_sources` maps
effective config fields to their source path or paths. The only non-file provenance
is `env:QA_AGENT_SHADOW` for `effective_config.jira.shadow`.

A Task prompt passes the **selected revision's capsule path**, ticket/run
identifiers and the assignment-specific charter, plan or failure packet. It does not
paste the complete capsule into the prompt or substitute another revision's path.

## Content contract

- `schema_version` is exactly `qa-run-context/v1`.
- `run` binds `id`, `ticket`, `project`, optional `product`, `scope`, positive
  `revision` and UTC `created_at`. `scope: product` requires `product`; project scope
  omits it. Projects without a Products registry never acquire product fields.
- `intake` and `readiness` embed those JSON artifacts exactly, including acceptance
  criterion IDs and verbatim text. There is no paraphrased AC copy.
- `routing` records the resolved project path, optional product path and routing
  provenance. Routing is input, not work to repeat.
- `effective_config` contains JIRA access/shadow, execution mode and controls, stage
  and build settings, test-user **key references**, test assets and only relevant
  feature-matrix rows. `secret_key` and `vault_path` are references, never values.
- `knowledge` contains only run-relevant Learning excerpts with sources, confirmed
  Areas and the vendored-skill bridge path/hash. Unconfirmed candidates are never
  serialized.
- `field_sources` makes project/product inheritance visible. Sealed fields (JIRA
  transitions, readiness statuses, merge requirement, report format, deploy
  permissions, evidence/security/MCP policy) may name only the project's
  `PROJECT.md`, never `PRODUCT.md`.
- `sources` lists every file behind routing, field, Learning, Area and bridge
  provenance with its SHA-256. The routed PROJECT.md, any routed PRODUCT.md and both
  embedded `intake.json`/`readiness.json` files are mandatory entries. Sources from a
  sibling project or product are invalid. Central validation treats a missing
  PROJECT.md as `STALE_CONTEXT`.
- `integrity.canonicalization` is `RFC8785`. `payload_sha256` is SHA-256 over the
  canonical UTF-8 JSON of the complete capsule with only `payload_sha256` removed.
  Object key order and pretty-printing therefore do not change the hash. Integers
  outside the I-JSON safe range ±(2^53−1) are rejected rather than canonicalized.

The intended size is 4–8 KiB and the hard limit is 16 KiB of UTF-8 JSON. The sealed
file remains ordinary, readable structured JSON like the other evidence contracts.
No Markdown merge engine, memory service, database or MCP server is involved.

The capsule must not contain passwords, tokens, cookies, authorization/session or
auth-state material, secret canaries, raw console/network logs, full ticket comments,
changelog or history. It carries references and curated context only.

## Validation levels

The orchestrator's `seal` checks structure, security constraints, size, payload
hash, run/ticket/directory consistency, exact embedded intake/readiness and source
ownership. The following full `validate` repeats that binding check and performs
the single current-source hash sweep via `--qa-home`. That central check is
deliberately not repeated by every spawned agent.

A receiving agent may perform the lightweight local binding check:

```bash
python3 .claude/scripts/context-capsule.py validate \
  --capsule <run-dir>/<selected-revision-path> \
  --run-dir <run-dir>
```

Without `--qa-home`, this checks the capsule and available embedded artifacts but
does not re-hash all PROJECT/PRODUCT/Learnings sources. Validation success prints
`valid`; seal prints the resulting hash. Usage errors exit 2, invalid structure,
security, run binding or payload integrity exit 3, stale sources or embedded
artifacts exit 4 with `STALE_CONTEXT`, and I/O failures exit 5.

## Immutable revisions and stale context

Never edit a sealed capsule in place. A changed build, readiness result, routing or
effective context invalidates the old handoff. Build/readiness changes require the
normal readiness re-verification first; the **main orchestrator** then writes a new
capsule with an incremented `run.revision`, new source hashes and a new payload hash.
Revision 1 stays at `context-capsule.json`; revision `N > 1` goes only to
`context-capsule.vN.json`. The immediately preceding revision must remain present
and valid in the same run directory. The run directory and all earlier capsule files
remain intact.

`seal` is idempotent for an identical payload and leaves the sealed bytes untouched.
A changed payload at the same or an older revision fails with `REVISION_CONFLICT`.
A wrong revision filename fails with `REVISION_PATH_MISMATCH`; a missing predecessor
fails with `REVISION_CHAIN_MISSING`. An existing capsule with an invalid payload hash
is never overwritten. For a safe check against an existing target, keep the new
input in a separate draft and pass it explicitly:

```bash
python3 .claude/scripts/context-capsule.py seal \
  --draft <run-dir>/next-draft.json \
  --capsule <run-dir>/<selected-revision-path> \
  --run-dir <run-dir>
```

The initial seal may keep using the draft itself as `--capsule`; `--draft` is what
lets a later invocation compare new input with an already sealed target instead of
having that target overwritten before validation.

A manager, leaf or analyst that detects a hash, run or source mismatch returns
`STALE_CONTEXT` with the capsule path and validator reason to its calling
orchestrator. It does not repair, regenerate, reseal or merge replacement context
itself. The main orchestrator owns revision creation and redispatch.

## Capsule-first consumption

When a capsule path is supplied, `qa-manager`, `test-executor`, `test-automator` and
`failure-analyst` consume its effective configuration and exact intake directly.
They do not fully read PROJECT.md/PRODUCT.md, repeat routing or readiness, redo
mode/suite/framework lookup, or merge Learnings again. The bridge path/hash in the
capsule remains the checked handoff for vendored skills.

Targeted new factual reads remain allowed when the assignment needs them: a named
Learning/log excerpt for a new symptom, a bounded JIRA change query, an existing
spec, recon or a framework convention. These are task inputs, not a fallback full
context merge.

Standalone direct skill runs without a capsule keep the existing effective-project
fallback. Capsule-first changes no evidence, shadow, readiness, reporting or
bug-reporter gate.

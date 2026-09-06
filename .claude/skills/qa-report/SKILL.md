---
name: qa-report
description: Aggregate the evidence directory into QA metrics — pass rate, P0/P1 trend, BLOCKED reasons, routing quality and learning throughput, per project and product. Use for "/qa-report", for a weekly or sprint summary, or whenever someone asks how testing is actually going.
---

# /qa-report — what the runs already know

Every run writes `execution_summary.json`; nothing ever read one back. This skill
turns that pile into the numbers a QA lead, a release manager or a retro actually
asks for. No new data source, no MCP server, no process change — just the evidence
that is already there.

## Steps

1. Run the aggregator (it reads only `evidence/`, writes nothing):

   ```bash
   python3 .claude/skills/qa-report/aggregate.py --since 30
   # --project SHOP    one project only
   # --json            machine-readable, for a dashboard or a pipeline
   ```

2. Read the output and **interpret it against the project's own gates** — the
   defaults in `.claude/rules/core/qa-principles.md` are overridden per project in
   `PROJECT.md` → "Pipelines / quality gates", and a product may tighten them
   further. A pass rate of 88 % is a breach in a project that declared ≥ 90 % and
   fine in one that declared ≥ 80 %. Never report a number without the gate it is
   measured against.

3. Turn the two blueprint-specific columns into actions, because they are the ones
   nobody else will read:
   - **Routing needed a human** — every `user`, `default` or `secondary` resolution
     is a missing component/label row in the project's registry. Propose the rows;
     `retro-learn` promotes them (`.claude/rules/core/product-layer.md`).
   - **Undeclared learnings** — a run that produced evidence without declaring its
     `learnings` means the Stop hook did not fire. That is an enforcement gap, not a
     reporting detail: check that the hook is wired in this repo before trusting any
     other number in the report.

4. Deliver it where the audience is. A QA lead does not read ticket comments:
   - a **published page** for the team (offer it — the report is Markdown already),
   - a Confluence page update if the project keeps one (per `PROJECT.md` →
     "Confluence"; note that editing Confluence is an explicit, separate request,
     not something this skill does on its own),
   - or a JIRA comment on the project's regression ticket, per `report-to-jira`.

5. Anything the report reveals about the blueprint itself (a metric that is always
   empty, a scope that never appears) is a `retro-learn` capture.

## What this skill does not do

Invent metrics the schema cannot support. The aggregator prints an explicit "not
computable" section — flake rate, defect escape rate and coverage are **not**
derivable from `execution_summary.json` as it stands. Estimating them anyway would
produce exactly the kind of sourced-looking-but-wrong number this blueprint keeps
warning about. If a flake rate is genuinely needed, extend the evidence schema first
(a retry count per run), then extend the aggregator — in that order.

It also does not judge people. The unit of every number here is a *run*, not a
tester.

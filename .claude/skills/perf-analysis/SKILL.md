---
name: perf-analysis
description: Analyze session performance — duration, phase breakdown, token usage, bottlenecks, efficiency trends, and concrete improvement suggestions. Use for "/perf-analysis", "performance analysis", "Performance-Analyse", "warum ist das so langsam", "wie lange dauert ein Testlauf", "Token-Verbrauch analysieren", "Performance verbessern", "Kosten optimieren". Not for test quality metrics (/qa-report) or skill usage (/skill-review).
license: Apache-2.0
---

# /perf-analysis — how long does it take, what does it cost, and what should change

The blueprint writes timing and usage data for every run — and never reads it
back. This turns that data into the numbers that answer "why is this slow?"
and "what should we fix?" — with concrete, actionable suggestions.

## Steps

1. Run the analysis:

```bash
python3 .claude/skills/perf-analysis/perf-analysis.py --since 30 --suggest
# --project SHOP    one project only
# --ticket SHOP-123 one specific run
# --json            machine-readable output
```

2. Read the report. The summary table shows where you stand against targets;
   the phase breakdown shows where time goes; the suggestions section names
   bottlenecks with specific fixes.

3. Interpret against the project's gates (`PROJECT.md` → "Pipelines / quality
   gates") — if the project declares tighter targets, those win.

4. Turn red/yellow items into actions. Each suggestion maps to a concrete
   skill or workflow change (see `references/improvement-patterns.md` for
   the full pattern library).

5. Report the findings. For a team: use `report-to-jira` or the project's
   reporting format. For a quick look: just print the report.

## What this skill never does

- **Never estimates** — if a metric can't be computed from the data, it says
  "not computable" rather than guessing.
- **Never mutates** — this is read-only. It doesn't change configs, tests, or
  project files. Improvement suggestions are proposals, not automatic fixes.
- **Never duplicates `/qa-report` numbers** — pass rate, flake rate, and
  findings belong to qa-report. This skill focuses on *time and cost*.
- **Never reads transcripts** — token usage comes from `session-perf.log`,
  which carries only usage metadata (numbers), never content.

## Data sources

| Source | What it provides |
|---|---|
| `execution_summary.json` | verdict, duration_s, phases, session, test_cases |
| `run.json` | duration_s, result counts |
| `evidence/.audit/session-perf.log` | token usage per session |
| `evals/results/history.log` | pass-rate trend |

Fields not yet in older summaries are simply absent — the analysis reports
what's available and notes what's missing.

## Command surface

`/perf-analysis [--since DAYS] [--project KEY] [--ticket KEY]`

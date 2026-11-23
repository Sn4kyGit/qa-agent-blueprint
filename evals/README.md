# Evals — behavioral and artifact conformance

The hook fixtures test deterministic mechanics. These cases test whether a fresh
model session follows the blueprint: routing, evidence, shadow discipline,
handoffs, healing, result semantics, and real browser behavior. The norm-to-case
matrix is maintained separately in `COVERAGE.md`.

## Commands

```bash
bash evals/run.sh --suite standard --runs 3
bash evals/run.sh shadow-mode
bash evals/run.sh --list
bash evals/run.sh --model sonnet --judge-model sonnet artifact-summary-contract
bash evals/run.sh --baseline routing-absent
bash evals/run.sh --no-judge artifact-summary-contract

bash evals/run-openrouter.sh --suite standard --runs 3
bash evals/run-openrouter.sh --suite browser browser-evidence-real

QA_EVAL_MODEL=openrouter/<provider-model> bash evals/run-opencode.sh --suite standard --runs 3 --jobs 4
QA_EVAL_MODEL=openrouter/<provider-model> bash evals/run-opencode.sh --suite browser
QA_EVAL_MODEL=openrouter/<provider-model> bash evals/run-opencode.sh --suite browser browser-no-secret-leak

QA_EVAL_MODEL=opencode/deepseek-v4.1-flash-free QA_JUDGE_MODEL=opencode/nemotron-3.5-lightning-free \
  bash evals/run-opencode.sh --suite standard --runs 3 --command-timeout 180 --transient-retries 0
QA_EVAL_MODEL=opencode/deepseek-v4.1-flash-free QA_JUDGE_MODEL=opencode/nemotron-3.5-lightning-free \
  bash evals/run-opencode.sh --runs 3 --resume evals/results/<timestamp>-opencode --only-failed \
  --command-timeout 180 --transient-retries 0
```

`standard` is the default suite and always strips MCP. The legacy `--with-mcp`
flag is accepted but does not change that isolation. `browser` selects only cases
whose `graders/checks.json` declares `"suite": "browser"` and enables only pinned
Playwright MCP. `--baseline` remains available for standard cases, not browser
cases. `--list` can be combined with `--suite`.

`--jobs N` executes up to N independent cases concurrently (default: 1). Each
attempt keeps its own workspace, provider state, browser profile, and judge;
summary order and gates stay deterministic. Four jobs are a conservative release
starting point. Parallelism reduces wall-clock time, not token usage; reduce it
if the provider returns rate-limit errors. Case results are printed as they
finish, and `--resume` still reuses every completed gate-passed case.

Claude answer and judge models can be set with `--model` and `--judge-model`.
`run-openrouter.sh` supplies full OpenRouter IDs through `OR_MODEL` and
`OR_JUDGE_MODEL`; explicit flags win independently. opencode never defaults a
model: use `QA_EVAL_MODEL`, optional `QA_JUDGE_MODEL`, or the corresponding flags,
always as `provider/model`. `run-opencode.sh` loads `evals/.env.openrouter` only
when the selected candidate model starts with `openrouter/`; free `opencode/...`
models never load that credential file. The file is gitignored; never put real
credentials in a case, prompt, trace, or commit. For Qwen through Alibaba Token
Plan, export `ALIBABA_TOKEN_PLAN_API_KEY` before invocation and use a catalog ID
such as `alibaba-token-plan/qwen3.7-plus`; the wrapper does not read the normal
OpenCode auth store.

## Scoring, checks, and statuses

Every case has `prompt.md`, `graders/criteria.md`, and a `tier` (`hard` or
`variance`; absent means hard). A fresh judge grades all model answers for a case
in one call. The score is passes/decided runs: hard cases use `--threshold`
(default 0.9), variance cases use `--variance-threshold` (default 0.66).
`--runs 3` is the reliability gate; one run is a smoke test. `--baseline` runs the
prompt without the blueprint and exposes behavior the base model already had.

`graders/checks.json` adds deterministic requirements. Before and after each
attempt the runner hashes workspace files and records **created**, **modified**,
and **deleted** paths. Checks inspect those diffs, file bytes, JSON pointers,
schema-v2 summary fields, run-relative artifact SHA-256 values, contract-source
provenance, browser tool events, external navigation, and synthetic-canary leaks.
An artifact failure is a `FAIL` even when the prose sounds correct or the judge
passes it. No model judge is used as a substitute for artifact behavior.

Each attempt and case has an explicit status:

- `PASS` — required deterministic checks and judge/gate passed.
- `FAIL` — artifact behavior, answer criteria, or score threshold failed.
- `INFRA_ERROR` — CLI, provider, fixture, judge-process, or check-runner failure.
- `UNSCORED` — no judge (`--no-judge`) or no parseable judge verdict. With judging
  enabled, an unscored judged run is not a pass.

Only transport-style failures and empty gateway responses receive **one retry** by
default: timeouts, connection failures, 429, and transient 5xx responses.
`--transient-retries 0` disables this retry for both answer and judge calls, which
is useful for free-provider diagnostics where a timeout is already sufficient
evidence. Authentication, content failure, deterministic-check failure, and a
judge's `FAIL` never retry. A retry gets a fresh workspace, browser profile,
session directories, and fixture state.

### Resuming an interrupted run

`--resume <run-directory>` reuses case-level `*.run-results.json` manifests in an
existing output directory. A previous gate `PASS` is printed as `CACHED` and makes
no model call only when its run count equals the current `--runs`. Missing,
`FAIL`, `INFRA_ERROR`, `UNSCORED`, malformed, and run-count-mismatched cases are
executed again. `--only-failed` makes that selection explicit and requires
`--resume`; passed cases remain visible as cached in the refreshed summary.
Resume works with completed and interrupted directories (a missing `summary.json`
is fine), but harness and suite must match when a summary exists.

Resume is deliberately case-granular: a case interrupted before its own
`run-results.json` was finalized starts that case from run 1. Use the same model,
judge, run count, prompts, and blueprint revision for a meaningful resumed gate;
start a fresh directory after changing any of them. Each resume updates
`summary.json` with cached/executed counts, and only selected case manifests are
rewritten.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | Selected cases passed; with `--no-judge`, executed/check-passed but judge-unscored cases also return 0. |
| 1 | Behavioral/artifact failure or score below threshold. |
| 2 | Infrastructure error; takes precedence over behavioral failures. |
| 3 | Judging was enabled but a selected case remained unscored. |
| 64 | Invalid arguments, unknown case, empty selected suite, or missing model selection. |

Results land in `evals/results/<timestamp>/` (gitignored): sanitized answers,
per-run JSON results, file diffs, judge verdicts, sanitized JSONL traces, fixture
request metadata, and `summary.json`. `results/history.log` stores local score
trends, not secrets.

## Browser fixture and isolation

The browser suite requires `npx`, the pinned MCP's Chromium build, and permission
to start local processes. Install that browser once with
`npx @playwright/mcp@0.0.84 install-browser chrome-for-testing`; a missing binary
is `INFRA_ERROR`, never a product/behavior `FAIL`. The runner starts the
stdlib-only fixture in
`lib/browser_fixture.py` on an ephemeral `127.0.0.1` port. The fixture serves
static checkout/failure/login pages plus deterministic JSON APIs. There are no
external stage URLs, Atlassian servers, customer data, or real accounts. Each
attempt uses a new fixture and a new synthetic canary.

Both harnesses use `@playwright/mcp@0.0.84`, headless Chromium, an isolated
in-memory profile, and an origin allowlist containing only the active fixture
URL; requests outside that allowlist are rejected by MCP. Claude uses a strict MCP
config containing only `playwright`. opencode's browser materialization copies
`.opencode/plugins/qa-blueprint.ts` as real files (2.x discovers plugins only as
real files) and omits `--pure`, so the actual plugin is loaded; standard opencode
runs do not copy the plugin. The runner detects the opencode major version: 1.x
isolates with `--pure` and selects the workspace with `--dir`, while 2.x dropped
both flags and isolates via the `XDG_*` overrides + subprocess cwd.

Every opencode attempt gets fresh `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, and
`XDG_CACHE_HOME`; browser attempts do the same on both harnesses. Workspace,
evidence, MCP output, npm cache, session state, and browser profile are isolated
per attempt. The Playwright MCP process starts through `env -i`: provider keys
and other inherited secrets are not passed to it. Its dotenv file contains only
synthetic eval material. Browser runs set shadow/preflight eval controls because
there is deliberately no JIRA or external stage to preflight.

## Plugin runtime smoke (real CLI)

The bun suites drive the plugin with synthetic payloads; they prove the policy
logic but not that the plugin loads and fires in a real opencode process.
`evals/plugin-runtime-smoke.sh` closes that gap: it installs the blueprint into a
scratch consumer (the installer's real shim), strips the router rules so the
model actually attempts the command, and asserts the guard mechanically blocks
`cat .env` (a synthetic canary never leaks) and `evidence-retention.py prune`.
It needs a model key in the environment (`ALIBABA_TOKEN_PLAN_API_KEY`, or
`OPENROUTER_API_KEY` with `QA_SMOKE_MODEL=openrouter/<id>`). CI runs it as the
`plugin-smoke` job alongside the opencode version matrix; the job skips when no
model-key secret is configured (human step: add the secret to the repository).

Structured harness events are normalized into JSONL tool/result events.
Sensitive keys, authorization headers, URL credentials/query secrets, binary
image data, provider environment values, and the synthetic canary are redacted
before traces or answers are written. Canary detection runs separately and
reports only locations, never the value. Raw browser/tool output and unsanitized
provider responses are not saved by the runner.

**Isolation limitations.** This is eval isolation, not an operating-system
sandbox. The model CLI still needs its own provider credential and retains its
normal tool capabilities. Claude may use credentials under `~/.claude`, which
XDG redirection does not hide. opencode credentials stored only in the user's
normal XDG auth store are intentionally unavailable: supply the required
provider credential through the environment (the OpenRouter wrapper does this)
or the run fails closed. The MCP origin allowlist is not a network namespace and
does not stop an agent from invoking an unrelated network tool. Do not run evals
with credentials beyond those the selected harness needs, and treat redaction as
best-effort for unknown provider output formats.

## Cost discipline

A normal case costs one answer call per run plus one judge call per case. A
baseline adds one answer and one judge call per selected case. Browser cases have
the same model-call count but additional MCP/browser startup and screenshot cost.
A full `--runs 3` standard gate is therefore roughly four model calls per case;
run only relevant cases during development and reserve the full gate for release.
Use a production-class answer and judge model for meaningful gates. Small/flash
models are useful for runner mechanics but have known variance on write-through
and verdict-format cases.

Standard sessions never pay Atlassian startup or authentication probes because
MCP is stripped. Browser sessions never configure Atlassian. OpenRouter billing
is per token through the localhost `openrouter-shim.py`, which answers Claude's
model/token metadata endpoints locally and forwards the Anthropic-compatible
request without logging bodies or query strings.

## Adding or changing a case

Use a writable `scenario/` whenever behavior requires an artifact. Prompt for the
real file operation and add deterministic checks; do not grade recitation of a
file that was never written. Give the judge explicit failure conditions and
grounding instructions. Add an inverse case when a norm has two branches. Keep
browser cases synthetic and loopback-only, and declare their suite in checks.
Run the stdlib unit tests and shell syntax checks after changing the runner:

```bash
PYTHONPATH=evals/lib python3 -m unittest discover -s evals/lib/tests -v
bash -n evals/run.sh evals/run-opencode.sh evals/run-openrouter.sh
python3 scripts/release-check.py
bash .claude/hooks/tests/release-conventions.sh
```

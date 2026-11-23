# SPDX-License-Identifier: MIT AND Apache-2.0
# Copyright (c) 2026 Ivan Davidov and Agentic Playwright contributors
# Copyright (c) 2026 Sn4kyGit and qa-agent-blueprint contributors
from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from artifact_checks import Snapshot, load_checks, run_checks, scan_canary_leaks
from browser_fixture import FixtureServer
from trace_events import append_event, parse_harness_output, read_events, sanitize_text, write_events


EXIT_PASS = 0
EXIT_FAIL = 1
EXIT_INFRA = 2
EXIT_UNSCORED = 3
EXIT_USAGE = 64
INFRA_OUTPUT_MARKERS = (
    'browser "chrome-for-testing" is not installed',
    "could not connect to mcp server",
    "mcp server connection closed",
    "mcp error -32000: connection closed",
)
TRANSIENT_MARKERS = (
    "connection reset",
    "connection refused",
    "connection closed",
    "econnreset",
    "econnrefused",
    "etimedout",
    "timed out",
    "timeout expired",
    "temporarily unavailable",
    "service unavailable",
    "bad gateway",
    "gateway timeout",
    "overloaded",
    "rate limit",
    "too many requests",
    "http 429",
    "http 500",
    "http 502",
    "http 503",
    "http 504",
    "status 429",
    "status 500",
    "status 502",
    "status 503",
    "status 504",
    "socket hang up",
)
# Exhausted allocated quota is NOT transient: it recovers only when the quota is
# increased or reset, not within a minute. Retrying wastes a call, and the 429
# status would otherwise match TRANSIENT_MARKERS. Distinguish Alibaba
# Throttling.AllocationQuota / insufficient_quota ("Allocated quota exceeded")
# from Throttling.RateQuota (RPM/TPM, "Requests rate limit exceeded"), which IS
# transient. These markers are specific to allocation so a rate-limit 429 still
# retries.
QUOTA_EXHAUSTED_MARKERS = (
    "allocated quota exceeded",
    "insufficient_quota",
    "throttling.allocationquota",
    "increase your quota",
)


@dataclass
class ProcessResult:
    returncode: int
    output: str
    timed_out: bool = False


@dataclass
class Attempt:
    process: ProcessResult
    workspace: Path
    runtime: Path
    tempdir: tempfile.TemporaryDirectory
    raw_answer: str
    answer: str
    events: list[dict[str, Any]]
    malformed: list[str]
    before: Snapshot
    after: Snapshot
    diff: dict[str, list[str]]
    canary: str = ""
    fixture_requests: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class RunRecord:
    name: str
    index: int
    status: str
    answer_file: Path | None = None
    trace_file: Path | None = None
    checks: list[dict[str, str]] = field(default_factory=list)
    detail: str = ""


def has_infrastructure_marker(output: str) -> bool:
    lowered = output.lower()
    return any(marker in lowered for marker in INFRA_OUTPUT_MARKERS)


def has_meaningful_answer(text: str) -> bool:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("[claude-code:unrecognized_model]"):
            return True
    return False


def is_transient(result: ProcessResult, answer: str = "") -> bool:
    if result.timed_out:
        return True
    if result.returncode == 0 and not has_meaningful_answer(answer):
        return True
    output = result.output.lower()
    if any(marker in output for marker in QUOTA_EXHAUSTED_MARKERS):
        return False  # exhausted allocated quota: a retry cannot recover it
    if any(marker in output for marker in TRANSIENT_MARKERS):
        return True
    return result.returncode < 0


def with_one_transient_retry(
    operation: Callable[[int], tuple[ProcessResult, str]],
    sleep: Callable[[float], None] = time.sleep,
) -> tuple[ProcessResult, str, int]:
    process, answer = operation(1)
    if not is_transient(process, answer):
        return process, answer, 1
    sleep(1)
    process, answer = operation(2)
    return process, answer, 2


def overall_exit(case_statuses: list[str], judge_enabled: bool = True) -> int:
    if "INFRA_ERROR" in case_statuses:
        return EXIT_INFRA
    if "FAIL" in case_statuses:
        return EXIT_FAIL
    if judge_enabled and "UNSCORED" in case_statuses:
        return EXIT_UNSCORED
    return EXIT_PASS


def provider_secret_values(environment: dict[str, str]) -> list[str]:
    marker = re.compile(r"(?:KEY|TOKEN|SECRET|PASSWORD|CREDENTIAL|AUTHORIZATION)", re.IGNORECASE)
    return [value for key, value in environment.items() if marker.search(key) and len(value) >= 4]


def parse_verdicts(text: str, count: int) -> list[str]:
    verdicts = []
    for index in range(1, count + 1):
        matches = re.findall(rf"(?m)^\*{{0,2}}RUN {index}: (PASS|FAIL)\b", text)
        verdicts.append(matches[-1] if matches else "UNSCORED")
    return verdicts


def load_case_result(output: Path, name: str) -> dict[str, Any] | None:
    path = output / f"{name}.run-results.json"
    if not path.is_file():
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return value if isinstance(value, dict) else None


def reusable_case_pass(previous: dict[str, Any] | None, runs: int) -> bool:
    if not previous or previous.get("status") != "PASS":
        return False
    attempts = previous.get("runs")
    return isinstance(attempts, list) and len(attempts) == runs


class EvalRunner:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.here = Path(__file__).resolve().parent.parent
        self.repo = self.here.parent
        self.harness = args.harness
        self.model = args.model or os.environ.get("QA_EVAL_MODEL", "")
        self.judge_model = args.judge_model or os.environ.get("QA_JUDGE_MODEL", "") or self.model
        self.claude = os.environ.get("CLAUDE_CODE_EXECPATH") or shutil.which("claude") or ""
        self.opencode = shutil.which("opencode") or ""
        self._oc_major: int | None = None
        self.secrets = provider_secret_values(dict(os.environ))
        self.output: Path | None = None
        self.infra_messages: list[str] = []
        self._infra_lock = threading.Lock()
        self._history_lock = threading.Lock()

    def _infra_error(self, message: str) -> None:
        with self._infra_lock:
            self.infra_messages.append(message)

    def case_suite(self, name: str) -> str:
        checks_path = self.here / name / "graders" / "checks.json"
        if not checks_path.exists():
            return "standard"
        suite, _ = load_checks(checks_path)
        return suite

    def cases(self) -> list[str]:
        requested = self.args.cases or sorted(
            path.name for path in self.here.iterdir()
            if path.is_dir() and (path / "prompt.md").is_file()
        )
        selected = []
        for name in requested:
            if not (self.here / name / "prompt.md").is_file():
                raise ValueError(f"unknown case: {name}")
            if self.case_suite(name) == self.args.suite:
                selected.append(name)
        return selected

    def validate(self, selected: list[str]) -> None:
        if not selected:
            raise ValueError(f"no cases selected for suite {self.args.suite}")
        if self.args.runs < 1:
            raise ValueError("--runs must be at least 1")
        if self.args.jobs < 1:
            raise ValueError("--jobs must be at least 1")
        if self.args.suite == "browser" and self.args.baseline:
            raise ValueError("--baseline is supported for the standard suite only")
        if self.harness == "opencode":
            if not self.model:
                raise ValueError("set QA_EVAL_MODEL or pass --model provider/model")
            if "/" not in self.model or "/" not in self.judge_model:
                raise ValueError("opencode models must use provider/model IDs")
            if not self.opencode:
                raise RuntimeError("opencode CLI not found on PATH")
        elif not self.claude or not Path(self.claude).is_file():
            raise RuntimeError("claude CLI not found (CLAUDE_CODE_EXECPATH or PATH)")
        if self.args.suite == "browser" and not shutil.which("npx"):
            raise RuntimeError("browser suite requires npx for pinned @playwright/mcp@0.0.84")

    def _copy_base(self, workspace: Path, scenario: Path | None, baseline: bool) -> None:
        if not baseline:
            if self.harness == "claude":
                for item in ("CLAUDE.md", ".claude", "docs", "projects", "memory"):
                    source = self.repo / item
                    if source.is_dir():
                        shutil.copytree(source, workspace / item, ignore=shutil.ignore_patterns("settings.local.json"))
                    elif source.exists():
                        shutil.copy2(source, workspace / item)
            else:
                (workspace / ".opencode").mkdir(parents=True)
                shutil.copy2(self.repo / "opencode" / "ROUTER.md", workspace / ".opencode" / "ROUTER.md")
                for item in ("agents", "commands"):
                    shutil.copytree(self.repo / "opencode" / item, workspace / ".opencode" / item)
                shutil.copytree(self.repo / ".claude", workspace / ".claude", ignore=shutil.ignore_patterns("settings.local.json"))
                shutil.rmtree(workspace / ".claude" / "hooks", ignore_errors=True)
                shutil.rmtree(workspace / ".claude" / "agents", ignore_errors=True)
                for item in ("docs", "projects", "memory", "CHANGELOG.md", "CLAUDE.md", ".claude-plugin"):
                    source = self.repo / item
                    if source.is_dir():
                        shutil.copytree(source, workspace / item)
                    elif source.exists():
                        shutil.copy2(source, workspace / item)
                if self.args.suite == "browser":
                    shutil.copytree(self.repo / "opencode" / "plugins", workspace / ".opencode" / "plugins")
        if scenario and scenario.exists():
            shutil.copytree(scenario, workspace, dirs_exist_ok=True)

    def _browser_mcp(self, workspace: Path, runtime: Path, fixture_url: str) -> tuple[dict[str, Any], dict[str, Any]]:
        evidence = workspace / "evidence" / ".mcp-out"
        evidence.mkdir(parents=True, exist_ok=True)
        config = runtime / "playwright.json"
        config.write_text(json.dumps({
            "browser": {"isolated": True, "launchOptions": {"headless": True}},
            "console": {"level": "warning"},
        }), encoding="utf-8")
        canary_file = runtime / "canary.env"
        canary_file.write_text("QA_EVAL_PASSWORD=${QA_EVAL_CANARY}\n", encoding="utf-8")
        npx = shutil.which("npx")
        if not npx:
            raise RuntimeError("npx not found")
        path = os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin")
        env_args = [
            "-i",
            f"PATH={path}",
            f"HOME={os.environ.get('HOME', str(runtime))}",
            f"XDG_CONFIG_HOME={runtime / 'xdg' / 'config'}",
            f"XDG_DATA_HOME={runtime / 'xdg' / 'data'}",
            f"XDG_CACHE_HOME={runtime / 'xdg' / 'cache'}",
            f"NPM_CONFIG_CACHE={runtime / 'npm-cache'}",
            "NPM_CONFIG_UPDATE_NOTIFIER=false",
            "NO_PROXY=127.0.0.1",
            npx,
            "@playwright/mcp@0.0.84",
            "--config", str(config),
            "--secrets", str(canary_file),
            "--output-dir", str(evidence),
            "--image-responses", "omit",
            "--browser", "chromium",
            "--headless",
            "--isolated",
            "--allowed-origins", fixture_url,
        ]
        if self.harness == "claude":
            document = {"mcpServers": {"playwright": {"command": "/usr/bin/env", "args": env_args}}}
        else:
            document = {"playwright": {"type": "local", "command": ["/usr/bin/env", *env_args], "enabled": True}}
        return document, env_args

    def _prepare(self, name: str, baseline: bool = False) -> tuple[tempfile.TemporaryDirectory, Path, Path, Snapshot, dict[str, str], str, FixtureServer | None]:
        tempdir = tempfile.TemporaryDirectory(prefix=f"qa-eval-{self.harness}-")
        root = Path(tempdir.name)
        workspace = root / "workspace"
        runtime = root / "runtime"
        workspace.mkdir()
        runtime.mkdir()
        scenario = None if baseline else self.here / name / "scenario"
        self._copy_base(workspace, scenario, baseline)
        environment = dict(os.environ)
        canary = ""
        fixture = None
        if self.harness == "opencode" or self.args.suite == "browser":
            for key, relative in (
                ("XDG_CONFIG_HOME", "xdg/config"),
                ("XDG_DATA_HOME", "xdg/data"),
                ("XDG_CACHE_HOME", "xdg/cache"),
            ):
                target = runtime / relative
                target.mkdir(parents=True, exist_ok=True)
                environment[key] = str(target)
        if self.args.suite == "browser":
            canary = f"SYNTHETIC-QA-EVAL-{uuid.uuid4().hex}"
            fixture = FixtureServer(canary).start()
            mcp, _ = self._browser_mcp(workspace, runtime, fixture.base_url)
            if self.harness == "claude":
                mcp_path = runtime / "mcp.json"
                mcp_path.write_text(json.dumps(mcp), encoding="utf-8")
            else:
                config = {
                    "$schema": "https://opencode.ai/config.json",
                    "instructions": [".opencode/ROUTER.md", ".claude/rules/core/*.md"],
                    "subagent_depth": 2,
                    "mcp": mcp,
                }
                (workspace / "opencode.json").write_text(json.dumps(config, indent=2), encoding="utf-8")
            environment["QA_PREFLIGHT"] = "0"
            environment["QA_AGENT_SHADOW"] = "1"
            environment["QA_EVAL_CANARY"] = canary
            environment["JIRA_PERSONAL_TOKEN"] = "SYNTHETIC-EVAL-NO-JIRA"
        elif self.harness == "opencode":
            config = {"$schema": "https://opencode.ai/config.json"}
            if not baseline:
                config.update({
                    "instructions": [".opencode/ROUTER.md", ".claude/rules/core/*.md"],
                    "subagent_depth": 2,
                })
            (workspace / "opencode.json").write_text(json.dumps(config, indent=2), encoding="utf-8")
        before = Snapshot.capture(workspace, self.harness)
        return tempdir, workspace, runtime, before, environment, canary, fixture

    def _prompt(self, name: str, fixture: FixtureServer | None, canary: str) -> str:
        prompt = (self.here / name / "prompt.md").read_text(encoding="utf-8")
        if fixture:
            prompt = prompt.replace("{{FIXTURE_URL}}", fixture.base_url).replace("{{CANARY}}", canary)
        return prompt

    def _opencode_major(self) -> int:
        """Detect the opencode CLI major version once (cached).

        opencode 2.x removed ``--pure`` and ``--dir`` from ``run``: the workspace
        is selected by the subprocess cwd (set in ``_invoke``) and config/auth
        isolation by the ``XDG_*`` overrides in ``_prepare``. 1.x still needs the
        explicit flags. Detecting the version keeps the runner independent of the
        installed CLI; an unparseable version falls back to the legacy 1.x shape.
        """
        if self._oc_major is None:
            major = 1
            try:
                proc = subprocess.run(
                    [self.opencode, "--version"],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    text=True, timeout=30, check=False,
                )
                match = re.search(r"(\d+)\.\d+\.\d+", proc.stdout or "")
                if match:
                    major = int(match.group(1))
            except (OSError, subprocess.SubprocessError):
                major = 1
            self._oc_major = major
        return self._oc_major

    def _command(self, name: str, workspace: Path, runtime: Path, prompt: str) -> list[str]:
        model_args = ["--model", self.model] if self.model else []
        if self.harness == "claude":
            if self.args.suite == "browser":
                mcp_args = ["--mcp-config", str(runtime / "mcp.json"), "--strict-mcp-config"]
            else:
                mcp_args = ["--mcp-config", '{"mcpServers":{}}', "--strict-mcp-config"]
            return [
                self.claude, "-p", "--dangerously-skip-permissions",
                "--output-format", "stream-json", "--verbose", "--no-session-persistence",
                *mcp_args, *model_args, prompt,
            ]
        if self._opencode_major() >= 2:
            # opencode 2.x: cwd selects the workspace; XDG isolation replaces --pure.
            return [
                self.opencode, "run", "--auto",
                "--format", "json", "--model", self.model, prompt,
            ]
        pure_args = [] if self.args.suite == "browser" else ["--pure"]
        return [
            self.opencode, "run", "--auto", *pure_args, "--dir", str(workspace),
            "--format", "json", "--model", self.model, prompt,
        ]

    def _invoke(self, command: list[str], workspace: Path, environment: dict[str, str]) -> ProcessResult:
        try:
            completed = subprocess.run(
                command,
                cwd=workspace,
                env=environment,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
                timeout=self.args.command_timeout,
                check=False,
            )
            return ProcessResult(completed.returncode, completed.stdout)
        except subprocess.TimeoutExpired as exc:
            output = exc.stdout or ""
            if isinstance(output, bytes):
                output = output.decode(errors="replace")
            return ProcessResult(124, output + "\ncommand timeout expired", True)
        except OSError as exc:
            return ProcessResult(126, f"process launch failed: {type(exc).__name__}: {exc}")

    def answer_once(self, name: str, attempt_number: int, baseline: bool = False) -> Attempt:
        tempdir, workspace, runtime, before, environment, canary, fixture = self._prepare(name, baseline)
        prompt = self._prompt(name, fixture, canary)
        command = self._command(name, workspace, runtime, prompt)
        process = self._invoke(command, workspace, environment)
        request_records = []
        if fixture:
            request_records = [record.__dict__ for record in fixture.requests]
            fixture.close()
        secrets = [*self.secrets, canary]
        raw_answer, events, malformed = parse_harness_output(process.output, self.harness, secrets)
        answer = sanitize_text(raw_answer, secrets)
        after = Snapshot.capture(workspace, self.harness)
        diff = before.diff(after)
        events.insert(0, {
            "event": "process",
            "harness": self.harness,
            "suite": self.args.suite,
            "attempt": attempt_number,
            "returncode": process.returncode,
            "timed_out": process.timed_out,
        })
        return Attempt(
            process, workspace, runtime, tempdir, raw_answer, answer, events,
            malformed, before, after, diff, canary, request_records,
        )

    def generate(self, name: str, baseline: bool = False) -> tuple[Attempt, int]:
        first = self.answer_once(name, 1, baseline)
        if self.args.transient_retries == 0 or not is_transient(first.process, first.raw_answer):
            return first, 1
        first.tempdir.cleanup()
        time.sleep(1)
        second = self.answer_once(name, 2, baseline)
        second.events.insert(1, {"event": "retry", "reason": "transient-only", "attempt": 2})
        return second, 2

    def judge(self, criteria: Path, answer_files: list[Path], verdict_file: Path) -> tuple[ProcessResult, list[str], int]:
        sections = []
        for index, path in enumerate(answer_files, 1):
            sections.append(f"=== ANSWER {index} ===\n{path.read_text(encoding='utf-8')}")
        prompt = f"""You are grading {len(answer_files)} independent answer(s) against fixed criteria.
For EACH answer separately: work through the criteria (quote the answer per requirement when asked), in at most six lines per answer.
Grade independently. Do not be generous: explicit failure conditions are FAIL, and prose cannot override deterministic check failures. Deterministic tool and artifact passes are valid evidence even when the answer does not narrate them; never require redundant narration.
End with exactly {len(answer_files)} verdict lines, one per answer, in order, nothing after them. Plain text, no markdown:
RUN 1: PASS
RUN 2: FAIL

=== CRITERIA ===
{criteria.read_text(encoding='utf-8')}

{chr(10).join(sections)}
"""
        model = self.judge_model
        operation_count = 0

        def invoke(attempt: int) -> tuple[ProcessResult, str]:
            nonlocal operation_count
            operation_count = attempt
            with tempfile.TemporaryDirectory(prefix="qa-eval-judge-") as directory:
                env = dict(os.environ)
                if self.harness == "opencode" or self.args.suite == "browser":
                    for key, child in (("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"), ("XDG_CACHE_HOME", "cache")):
                        target = Path(directory) / child
                        target.mkdir(parents=True, exist_ok=True)
                        env[key] = str(target)
                if self.harness == "claude":
                    command = [self.claude, "-p", "--mcp-config", '{"mcpServers":{}}', "--strict-mcp-config"]
                    if model:
                        command.extend(["--model", model])
                    command.append(prompt)
                else:
                    if self._opencode_major() >= 2:
                        command = [self.opencode, "run", "--auto", "--model", model, prompt]
                    else:
                        command = [self.opencode, "run", "--auto", "--pure", "--dir", directory, "--model", model, prompt]
                result = self._invoke(command, Path(directory), env)
                return result, result.output

        if self.args.transient_retries == 0:
            process, output = invoke(1)
            attempts = 1
        else:
            process, output, attempts = with_one_transient_retry(invoke)
        verdict_file.write_text(sanitize_text(output, self.secrets), encoding="utf-8")
        return process, parse_verdicts(output, len(answer_files)), attempts

    def _save_attempt(self, attempt: Attempt, suffix: str, checks: list[dict[str, Any]]) -> RunRecord:
        answer_file = self.output / f"{suffix}.answer.md"
        trace_file = self.output / f"{suffix}.trace.jsonl"
        leaks = scan_canary_leaks(
            attempt.workspace,
            attempt.diff["created"] + attempt.diff["modified"],
            attempt.raw_answer,
            attempt.canary,
        ) if attempt.canary else []
        check_results = run_checks(checks, attempt.workspace, attempt.diff, attempt.events, leaks, attempt.answer)
        status = "PASS"
        if attempt.process.returncode != 0 or not attempt.raw_answer.strip() or has_infrastructure_marker(attempt.process.output):
            status = "INFRA_ERROR"
        elif any(result.status == "INFRA_ERROR" for result in check_results):
            status = "INFRA_ERROR"
        elif any(result.status == "FAIL" for result in check_results):
            status = "FAIL"
        lines = [attempt.answer, "", "---", "HARNESS FACT (runner ground truth):"]
        for category in ("created", "modified", "deleted"):
            lines.append(f"{category}:")
            lines.extend(f"  {path}" for path in attempt.diff[category])
        if check_results:
            lines.append("deterministic checks:")
            lines.extend(f"  {result.status} {result.check}: {result.detail}" for result in check_results)
        answer_file.write_text("\n".join(lines) + "\n", encoding="utf-8")
        write_events(trace_file, attempt.events, [*self.secrets, attempt.canary])
        (self.output / f"{suffix}.files.json").write_text(json.dumps(attempt.diff, indent=2), encoding="utf-8")
        if attempt.fixture_requests:
            (self.output / f"{suffix}.fixture-requests.json").write_text(json.dumps(attempt.fixture_requests, indent=2), encoding="utf-8")
        return RunRecord(
            suffix, 0, status, answer_file, trace_file,
            [result.as_dict() for result in check_results],
            "process failure or empty answer" if status == "INFRA_ERROR" else "",
        )

    def _baseline(self, name: str, criteria: Path) -> str:
        attempt, _ = self.generate(name, baseline=True)
        try:
            suffix = f"{name}.baseline"
            record = self._save_attempt(attempt, suffix, [])
            if record.status == "INFRA_ERROR":
                self._infra_error(f"{name} baseline execution failed")
                return "INFRA_ERROR"
            if not self.args.judge or not criteria.exists():
                return "answered"
            verdict_file = self.output / f"{suffix}.verdicts.md"
            process, verdicts, _ = self.judge(criteria, [record.answer_file], verdict_file)
            if process.returncode != 0:
                self._infra_error(f"{name} baseline judge failed")
                return "INFRA_ERROR"
            return verdicts[0]
        finally:
            attempt.tempdir.cleanup()

    def run_case(self, name: str) -> tuple[str, str, str]:
        checks_path = self.here / name / "graders" / "checks.json"
        checks = []
        if checks_path.exists():
            _, checks = load_checks(checks_path)
        criteria = self.here / name / "graders" / "criteria.md"
        records: list[RunRecord] = []
        for index in range(1, self.args.runs + 1):
            suffix = name if self.args.runs == 1 else f"{name}.run{index}"
            try:
                attempt, _ = self.generate(name)
                try:
                    record = self._save_attempt(attempt, suffix, checks)
                    record.name = name
                    record.index = index
                    records.append(record)
                finally:
                    attempt.tempdir.cleanup()
            except Exception as exc:
                records.append(RunRecord(name, index, "INFRA_ERROR", detail=f"{type(exc).__name__}: {exc}"))
        judge_candidates = [record for record in records if record.status == "PASS"]
        if self.args.judge and criteria.exists() and judge_candidates:
            try:
                process, verdicts, _ = self.judge(
                    criteria,
                    [record.answer_file for record in judge_candidates],
                    self.output / f"{name}.verdicts.md",
                )
                if process.returncode != 0:
                    for record in judge_candidates:
                        record.status = "INFRA_ERROR"
                        record.detail = "judge process failed"
                else:
                    for record, verdict in zip(judge_candidates, verdicts):
                        record.status = verdict
            except Exception as exc:
                for record in judge_candidates:
                    record.status = "INFRA_ERROR"
                    record.detail = f"judge error: {type(exc).__name__}: {exc}"
        elif not self.args.judge:
            for record in judge_candidates:
                record.status = "UNSCORED"
        elif judge_candidates:
            for record in judge_candidates:
                record.status = "UNSCORED"
                record.detail = "missing criteria.md"
        passes = sum(record.status == "PASS" for record in records)
        fails = sum(record.status == "FAIL" for record in records)
        scored = passes + fails
        tier_path = self.here / name / "tier"
        tier = tier_path.read_text().strip() if tier_path.exists() else "hard"
        threshold = self.args.variance_threshold if tier == "variance" else self.args.threshold
        below = scored == 0 or passes / scored < threshold
        if any(record.status == "INFRA_ERROR" for record in records):
            case_status = "INFRA_ERROR"
        elif fails and below:
            case_status = "FAIL"
        elif self.args.judge and scored == 0:
            case_status = "UNSCORED"
        elif self.args.judge and below:
            case_status = "FAIL"
        elif not self.args.judge and fails:
            case_status = "FAIL"
        elif not self.args.judge:
            case_status = "UNSCORED"
        else:
            case_status = "PASS"
        if self.args.judge and scored:
            score = f"{passes / scored:.2f} ({passes}/{scored}) [{tier}]"
            with self._history_lock:
                with (self.here / "results" / "history.log").open("a", encoding="utf-8") as history:
                    prefix = "opencode/" if self.harness == "opencode" else ""
                    history.write(f"{dt.datetime.now(dt.timezone.utc).isoformat()} {prefix}{name} {passes}/{scored}\n")
        else:
            score = "unscored"
        if case_status == "FAIL" and not fails:
            case_status = "FAIL"
        baseline = self._baseline(name, criteria) if self.args.baseline else "-"
        (self.output / f"{name}.run-results.json").write_text(json.dumps({
            "case": name,
            "status": case_status,
            "score": score,
            "runs": [record.__dict__ | {"answer_file": str(record.answer_file or ""), "trace_file": str(record.trace_file or "")} for record in records],
        }, indent=2), encoding="utf-8")
        return case_status, score, baseline

    def _execute_case(self, name: str) -> tuple[str, str, str]:
        try:
            return self.run_case(name)
        except Exception as exc:
            self._infra_error(f"{name}: {type(exc).__name__}: {exc}")
            return "INFRA_ERROR", "unscored", "-"

    def run(self) -> int:
        selected = self.cases()
        if self.args.list:
            for name in selected:
                print(name)
            return EXIT_PASS
        self.validate(selected)
        if self.args.only_failed and not self.args.resume:
            raise ValueError("--only-failed requires --resume <run-directory>")
        if self.args.with_mcp and self.args.suite == "standard":
            print("note: --with-mcp is retained for compatibility; standard eval sessions remain MCP-stripped", file=sys.stderr)
        resume_dir = Path(self.args.resume).expanduser().resolve() if self.args.resume else None
        previous_baselines: dict[str, str] = {}
        if resume_dir is not None and not resume_dir.is_dir():
            raise ValueError(f"resume directory does not exist: {resume_dir}")
        if resume_dir is None:
            stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
            if self.harness == "opencode":
                stamp += "-opencode"
            if self.args.suite == "browser":
                stamp += "-browser"
            self.output = self.here / "results" / stamp
            self.output.mkdir(parents=True, exist_ok=True)
        else:
            self.output = resume_dir
            previous_summary = resume_dir / "summary.json"
            if previous_summary.is_file():
                try:
                    metadata = json.loads(previous_summary.read_text(encoding="utf-8"))
                except json.JSONDecodeError as exc:
                    raise ValueError(f"resume summary is invalid: {exc}") from exc
                if metadata.get("harness") != self.harness or metadata.get("suite") != self.args.suite:
                    raise ValueError("resume directory harness/suite differs from this invocation")
                for item in metadata.get("cases", []):
                    if isinstance(item, dict) and isinstance(item.get("case"), str):
                        previous_baselines[item["case"]] = str(item.get("baseline", "-"))
        cached = 0
        executed = 0
        print(f"Answers -> {self.output} (suite={self.args.suite}, runs={self.args.runs}, jobs={self.args.jobs}, judge={'on' if self.args.judge else 'off'}, mcp={'playwright-only' if self.args.suite == 'browser' else 'stripped'}, resume={'yes' if resume_dir else 'no'})", flush=True)
        print(f"{'case':<44} {'status':<12} {'score':<24} baseline", flush=True)
        results: dict[str, tuple[str, str, str]] = {}
        pending = []
        for name in selected:
            previous = load_case_result(self.output, name) if resume_dir else None
            if resume_dir and reusable_case_pass(previous, self.args.runs):
                result = (str(previous["status"]), str(previous.get("score", "unscored")), previous_baselines.get(name, "-"))
                results[name] = result
                cached += 1
                print(f"{name:<44} {'CACHED':<12} {result[1]:<24} {result[2]}", flush=True)
            else:
                pending.append(name)
        with concurrent.futures.ThreadPoolExecutor(max_workers=self.args.jobs) as pool:
            futures = {pool.submit(self._execute_case, name): name for name in pending}
            for future in concurrent.futures.as_completed(futures):
                name = futures[future]
                result = future.result()
                results[name] = result
                executed += 1
                print(f"{name:<44} {result[0]:<12} {result[1]:<24} {result[2]}", flush=True)
        summaries = [
            {"case": name, "status": results[name][0], "score": results[name][1], "baseline": results[name][2]}
            for name in selected
        ]
        code = overall_exit([item["status"] for item in summaries], bool(self.args.judge))
        (self.output / "summary.json").write_text(json.dumps({
            "suite": self.args.suite,
            "harness": self.harness,
            "jobs": self.args.jobs,
            "cases": summaries,
            "exit_code": code,
            "infra": self.infra_messages,
            "resume": {"enabled": resume_dir is not None, "only_failed": bool(self.args.only_failed), "cached_cases": cached, "executed_cases": executed},
        }, indent=2), encoding="utf-8")
        print({0: "PASS", 1: "FAIL", 2: "INFRA_ERROR", 3: "UNSCORED"}.get(code, str(code)), flush=True)
        return code


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--harness", choices=("claude", "opencode"), required=True)
    parser.add_argument("--suite", choices=("standard", "browser"), default="standard")
    parser.add_argument("--runs", type=int, default=1)
    parser.add_argument("--jobs", type=int, default=1, help="number of isolated cases to execute concurrently")
    parser.add_argument("--no-judge", dest="judge", action="store_false", default=True)
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--with-mcp", action="store_true")
    parser.add_argument("--threshold", type=float, default=0.9)
    parser.add_argument("--variance-threshold", type=float, default=0.66)
    parser.add_argument("--model", default="")
    parser.add_argument("--judge-model", default="")
    parser.add_argument("--command-timeout", type=int, default=900)
    parser.add_argument("--transient-retries", type=int, choices=(0, 1), default=1, help="automatic retries for transient answer/judge failures")
    parser.add_argument("--resume", default="", help="existing eval result directory; reuse gate-passed case manifests")
    parser.add_argument("--only-failed", action="store_true", help="with --resume, execute only cases without a reusable PASS")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("cases", nargs="*")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    runner = EvalRunner(args)
    try:
        return runner.run()
    except ValueError as exc:
        print(f"usage: {exc}", file=sys.stderr)
        return EXIT_USAGE
    except RuntimeError as exc:
        print(f"INFRA_ERROR: {exc}", file=sys.stderr)
        return EXIT_INFRA
    except KeyboardInterrupt:
        print("INFRA_ERROR: interrupted", file=sys.stderr)
        return EXIT_INFRA


if __name__ == "__main__":
    sys.exit(main())

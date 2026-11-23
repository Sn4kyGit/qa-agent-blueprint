import json
import os
import re
import subprocess
import tempfile
import threading
import time
import unittest
from pathlib import Path

from runner_policy import (
    EXIT_FAIL,
    EXIT_INFRA,
    EXIT_PASS,
    EXIT_UNSCORED,
    ProcessResult,
    is_transient,
    overall_exit,
    parse_verdicts,
    has_infrastructure_marker,
    with_one_transient_retry,
    load_case_result,
    reusable_case_pass,
    EvalRunner,
    build_parser,
)


class RunnerPolicyTest(unittest.TestCase):
    def test_transient_failure_retries_exactly_once(self):
        calls = []

        def operation(attempt):
            calls.append(attempt)
            if attempt == 1:
                return ProcessResult(1, "connection reset"), ""
            return ProcessResult(0, "{}"), "answer"

        result, answer, attempts = with_one_transient_retry(operation, lambda _: None)
        self.assertEqual(calls, [1, 2])
        self.assertEqual(attempts, 2)
        self.assertEqual(answer, "answer")
        self.assertEqual(result.returncode, 0)

    def test_persistent_transient_failure_does_not_retry_twice(self):
        calls = []

        def operation(attempt):
            calls.append(attempt)
            return ProcessResult(1, "http 503"), ""

        _, _, attempts = with_one_transient_retry(operation, lambda _: None)
        self.assertEqual(calls, [1, 2])
        self.assertEqual(attempts, 2)

    def test_content_failure_is_not_transient(self):
        calls = []

        def operation(attempt):
            calls.append(attempt)
            return ProcessResult(0, "{}"), "the test failed"

        _, _, attempts = with_one_transient_retry(operation, lambda _: None)
        self.assertEqual(calls, [1])
        self.assertEqual(attempts, 1)

    def test_authentication_failure_is_not_transient(self):
        result = ProcessResult(1, "401 unauthorized: invalid api key")
        self.assertFalse(is_transient(result))

    def test_empty_success_is_transient(self):
        self.assertTrue(is_transient(ProcessResult(0, ""), ""))
        self.assertTrue(is_transient(ProcessResult(0, "{}"), "[claude-code:unrecognized_model] {\"model\":\"test\"}\n"))
        self.assertFalse(is_transient(ProcessResult(0, "{}"), "[claude-code:unrecognized_model] {\"model\":\"test\"}\nRUN 1: PASS\n"))

    def test_missing_browser_is_infrastructure_not_content_failure(self):
        output = 'Error: Browser "chrome-for-testing" is not installed; expected executable'
        self.assertTrue(has_infrastructure_marker(output))
        self.assertFalse(is_transient(ProcessResult(0, output), "browser unavailable"))

    def test_exit_code_precedence(self):
        self.assertEqual(overall_exit(["PASS", "FAIL", "INFRA_ERROR"]), EXIT_INFRA)
        self.assertEqual(overall_exit(["PASS", "FAIL", "UNSCORED"]), EXIT_FAIL)
        self.assertEqual(overall_exit(["PASS", "UNSCORED"]), EXIT_UNSCORED)
        self.assertEqual(overall_exit(["PASS", "UNSCORED"], judge_enabled=False), EXIT_PASS)
        self.assertEqual(overall_exit(["PASS"]), EXIT_PASS)

    def test_parse_verdicts_uses_last_line_and_marks_missing(self):
        text = "RUN 1: FAIL\nreason\nRUN 1: PASS\nRUN 3: FAIL\n"
        self.assertEqual(parse_verdicts(text, 3), ["PASS", "UNSCORED", "FAIL"])


class RunnerMaterializationTest(unittest.TestCase):
    def runner(self, harness, suite):
        argv = ["--harness", harness, "--suite", suite, "--no-judge"]
        if harness == "opencode":
            argv.extend(["--model", "test/model"])
        args = build_parser().parse_args(argv)
        return EvalRunner(args)

    def test_claude_standard_is_mcp_stripped(self):
        runner = self.runner("claude", "standard")
        prepared = runner._prepare("shadow-mode")
        tempdir, workspace, runtime, before, environment, canary, fixture = prepared
        try:
            command = runner._command("shadow-mode", workspace, runtime, "prompt")
            config = command[command.index("--mcp-config") + 1]
            self.assertEqual(json.loads(config), {"mcpServers": {}})
            self.assertIn("--strict-mcp-config", command)
        finally:
            tempdir.cleanup()

    def test_claude_browser_enables_only_pinned_playwright(self):
        runner = self.runner("claude", "browser")
        prepared = runner._prepare("browser-evidence-real")
        tempdir, workspace, runtime, before, environment, canary, fixture = prepared
        try:
            config = json.loads((runtime / "mcp.json").read_text())
            self.assertEqual(set(config["mcpServers"]), {"playwright"})
            args = config["mcpServers"]["playwright"]["args"]
            self.assertIn("@playwright/mcp@0.0.84", args)
            self.assertIn(fixture.base_url, args)
            self.assertNotIn("--blocked-origins", args)
            self.assertFalse(any(arg.startswith("OPENROUTER_API_KEY=") for arg in args))
            self.assertNotEqual(environment["XDG_DATA_HOME"], str(Path.home() / ".local" / "share"))
            command = runner._command("browser-evidence-real", workspace, runtime, "prompt")
            self.assertEqual(command[command.index("--mcp-config") + 1], str(runtime / "mcp.json"))
        finally:
            fixture.close()
            tempdir.cleanup()

    def test_browser_cases_include_project_context(self):
        for name in ("browser-evidence-real", "browser-failure-evidence", "browser-no-secret-leak"):
            with self.subTest(case=name):
                self.assertTrue((Path(__file__).resolve().parents[2] / name / "scenario/projects/ACME/PROJECT.md").is_file())

    def test_opencode_browser_loads_plugin_and_standard_does_not(self):
        browser = self.runner("opencode", "browser")
        browser._oc_major = 1
        prepared = browser._prepare("browser-evidence-real")
        tempdir, workspace, runtime, before, environment, canary, fixture = prepared
        try:
            config = json.loads((workspace / "opencode.json").read_text())
            self.assertEqual(set(config["mcp"]), {"playwright"})
            self.assertIn("@playwright/mcp@0.0.84", config["mcp"]["playwright"]["command"])
            self.assertTrue((workspace / ".opencode/plugins/qa-blueprint.ts").is_file())
            command = browser._command("browser-evidence-real", workspace, runtime, "prompt")
            self.assertNotIn("--pure", command)
        finally:
            fixture.close()
            tempdir.cleanup()
        standard = self.runner("opencode", "standard")
        standard._oc_major = 1
        prepared = standard._prepare("shadow-mode")
        tempdir, workspace, runtime, before, environment, canary, fixture = prepared
        try:
            config = json.loads((workspace / "opencode.json").read_text())
            self.assertNotIn("mcp", config)
            self.assertFalse((workspace / ".opencode/plugins").exists())
            command = standard._command("shadow-mode", workspace, runtime, "prompt")
            self.assertIn("--pure", command)
        finally:
            tempdir.cleanup()

    def test_opencode_command_is_version_aware(self):
        # opencode 2.x removed --pure/--dir from `run`; cwd + XDG isolation replace
        # them. 1.x keeps the explicit flags. The runner must build the right shape
        # for whichever CLI is installed (detected via `opencode --version`).
        for major, legacy in ((1, True), (2, False)):
            with self.subTest(major=major):
                runner = self.runner("opencode", "standard")
                runner._oc_major = major
                prepared = runner._prepare("shadow-mode")
                tempdir, workspace, runtime, before, environment, canary, fixture = prepared
                try:
                    command = runner._command("shadow-mode", workspace, runtime, "prompt")
                    self.assertIn("--auto", command)
                    self.assertIn("--format", command)
                    if legacy:
                        self.assertIn("--pure", command)
                        self.assertIn("--dir", command)
                    else:
                        self.assertNotIn("--pure", command)
                        self.assertNotIn("--dir", command)
                finally:
                    tempdir.cleanup()

    def test_opencode_major_detection_matches_installed_cli(self):
        # The CI matrix installs opencode 1.x and 2.x; this asserts the runner's
        # version detection agrees with the real CLI, so the matrix actually
        # exercises both flag shapes (not just the mocked ones above).
        runner = self.runner("opencode", "standard")
        if not runner.opencode:
            self.skipTest("opencode CLI not installed")
        proc = subprocess.run([runner.opencode, "--version"], capture_output=True, text=True)
        match = re.search(r"(\d+)\.\d+\.\d+", proc.stdout or "")
        expected = int(match.group(1)) if match else 1
        self.assertEqual(runner._opencode_major(), expected)


class ShellWrapperTest(unittest.TestCase):
    def invoke_wrapper(self, model):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = Path(__file__).resolve().parents[2] / "run-opencode.sh"
            (root / "run-opencode.sh").write_text(source.read_text())
            (root / ".env.openrouter").write_text("QA_TEST_MARKER=loaded\n")
            (root / "bin").mkdir()
            fake_python = root / "bin/python3"
            fake_python.write_text("#!/usr/bin/env bash\nprintf '%s' \"${QA_TEST_MARKER:-}\" > \"$MARKER_OUT\"\n")
            fake_python.chmod(0o755)
            marker = root / "marker.txt"
            environment = dict(os.environ)
            environment.update({
                "PATH": f"{root / 'bin'}:{os.environ.get('PATH', '')}",
                "QA_EVAL_MODEL": model,
                "QA_TEST_MARKER": "",
                "MARKER_OUT": str(marker),
            })
            result = subprocess.run(["bash", str(root / "run-opencode.sh")], env=environment, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            return marker.read_text()

    def test_free_model_does_not_load_openrouter_environment(self):
        self.assertEqual(self.invoke_wrapper("opencode/glm-5.3-flash-free"), "")

    def test_openrouter_model_still_loads_openrouter_environment(self):
        self.assertEqual(self.invoke_wrapper("openrouter/test-model"), "loaded")


class ResumeTest(unittest.TestCase):
    def result(self, name, status="PASS", runs=1):
        return {
            "case": name,
            "status": status,
            "score": "1.00 (1/1) [hard]" if status == "PASS" else "0.00 (0/1) [hard]",
            "runs": [{"name": name, "index": index, "status": status} for index in range(1, runs + 1)],
        }

    def test_reusable_pass_requires_matching_run_count(self):
        passed = self.result("case")
        self.assertTrue(reusable_case_pass(passed, 1))
        self.assertFalse(reusable_case_pass(passed, 3))
        self.assertFalse(reusable_case_pass(self.result("case", "FAIL"), 1))
        self.assertFalse(reusable_case_pass(None, 1))

    def test_resume_skips_pass_and_executes_only_open_case(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            passed = self.result("scaffold-quality-opt-in")
            failed = self.result("scaffold-default-minimal", "FAIL")
            (root / "scaffold-quality-opt-in.run-results.json").write_text(json.dumps(passed))
            (root / "scaffold-default-minimal.run-results.json").write_text(json.dumps(failed))
            (root / "summary.json").write_text(json.dumps({
                "harness": "opencode",
                "suite": "standard",
                "cases": [
                    {"case": "scaffold-quality-opt-in", "baseline": "cached-baseline"},
                    {"case": "scaffold-default-minimal", "baseline": "-"},
                ],
            }))
            args = build_parser().parse_args([
                "--harness", "opencode", "--model", "test/model", "--no-judge",
                "--resume", directory, "--only-failed",
                "scaffold-quality-opt-in", "scaffold-default-minimal",
            ])
            runner = EvalRunner(args)
            calls = []

            def rerun(name):
                calls.append(name)
                return "PASS", "1.00 (1/1) [hard]", "-"

            runner.run_case = rerun
            self.assertEqual(runner.run(), EXIT_PASS)
            self.assertEqual(calls, ["scaffold-default-minimal"])
            summary = json.loads((root / "summary.json").read_text())
            self.assertEqual(summary["resume"]["cached_cases"], 1)
            self.assertEqual(summary["resume"]["executed_cases"], 1)
            self.assertEqual(summary["cases"][0]["baseline"], "cached-baseline")

    def test_jobs_execute_cases_concurrently_and_preserve_summary_order(self):
        with tempfile.TemporaryDirectory() as directory:
            args = build_parser().parse_args([
                "--harness", "opencode", "--model", "test/model", "--no-judge",
                "--resume", directory, "--jobs", "2",
                "scaffold-quality-opt-in", "scaffold-default-minimal",
            ])
            runner = EvalRunner(args)
            active = 0
            maximum = 0
            lock = threading.Lock()

            def execute(name):
                nonlocal active, maximum
                with lock:
                    active += 1
                    maximum = max(maximum, active)
                time.sleep(0.15)
                with lock:
                    active -= 1
                return "PASS", "1.00 (1/1) [hard]", "-"

            runner.run_case = execute
            self.assertEqual(runner.run(), EXIT_PASS)
            self.assertEqual(maximum, 2)
            summary = json.loads((Path(directory) / "summary.json").read_text())
            self.assertEqual(summary["jobs"], 2)
            self.assertEqual(
                [item["case"] for item in summary["cases"]],
                ["scaffold-quality-opt-in", "scaffold-default-minimal"],
            )

    def test_jobs_must_be_positive(self):
        args = build_parser().parse_args([
            "--harness", "opencode", "--model", "test/model", "--jobs", "0",
            "scaffold-quality-opt-in",
        ])
        with self.assertRaisesRegex(ValueError, "--jobs must be at least 1"):
            EvalRunner(args).run()

    def test_resume_rejects_harness_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "summary.json").write_text(json.dumps({"harness": "claude", "suite": "standard", "cases": []}))
            args = build_parser().parse_args([
                "--harness", "opencode", "--model", "test/model", "--resume", directory,
                "scaffold-quality-opt-in",
            ])
            with self.assertRaisesRegex(ValueError, "harness/suite"):
                EvalRunner(args).run()

    def test_only_failed_requires_resume(self):
        args = build_parser().parse_args([
            "--harness", "opencode", "--model", "test/model", "--only-failed",
            "scaffold-quality-opt-in",
        ])
        with self.assertRaisesRegex(ValueError, "requires --resume"):
            EvalRunner(args).run()

    def test_corrupt_case_result_is_not_reused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "broken.run-results.json").write_text("not json")
            self.assertIsNone(load_case_result(root, "broken"))

    def test_transient_retries_can_be_disabled(self):
        args = build_parser().parse_args(["--harness", "opencode", "--model", "test/model", "--transient-retries", "0"])
        self.assertEqual(args.transient_retries, 0)


if __name__ == "__main__":
    unittest.main()

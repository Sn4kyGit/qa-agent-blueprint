import json
import tempfile
import unittest
from pathlib import Path

from artifact_checks import (
    SUMMARY_REQUIRED,
    Snapshot,
    json_pointer,
    load_checks,
    run_checks,
    safe_path,
    scan_canary_leaks,
    validate_summary,
)


class ArtifactChecksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, relative, content="value"):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        if isinstance(content, bytes):
            path.write_bytes(content)
        else:
            path.write_text(content)
        return path

    def test_snapshot_detects_created_modified_deleted(self):
        self.write("same.txt")
        self.write("modify.txt", "before")
        self.write("delete.txt")
        before = Snapshot.capture(self.root)
        self.write("create.txt")
        self.write("modify.txt", "after")
        (self.root / "delete.txt").unlink()
        after = Snapshot.capture(self.root)
        self.assertEqual(before.diff(after), {
            "created": ["create.txt"],
            "modified": ["modify.txt"],
            "deleted": ["delete.txt"],
        })

    def test_safe_path_rejects_escape(self):
        for value in ("../secret", "/tmp/secret", "a/../../secret"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                safe_path(self.root, value)

    def test_json_pointer_supports_arrays_and_escapes(self):
        document = {"a/b": [{"~key": 7}]}
        self.assertEqual(json_pointer(document, "/a~1b/0/~0key"), 7)
        with self.assertRaises(KeyError):
            json_pointer(document, "/a~1b/nope")

    def test_diff_checks(self):
        self.write("old.txt", "before")
        self.write("gone.txt")
        before = Snapshot.capture(self.root)
        self.write("old.txt", "after")
        self.write("new.txt")
        (self.root / "gone.txt").unlink()
        diff = before.diff(Snapshot.capture(self.root))
        specs = [
            {"type": "created", "path": "new.txt"},
            {"type": "modified", "path": "old.txt"},
            {"type": "deleted", "path": "gone.txt"},
            {"type": "unchanged", "path": "missing.txt"},
        ]
        results = run_checks(specs, self.root, diff, [])
        self.assertTrue(all(result.status == "PASS" for result in results))

    def test_json_and_file_checks(self):
        self.write("result.json", json.dumps({"verdict": "PASS", "cases": [{"outcome": "FLAKY"}]}))
        self.write("image.png", b"\x89PNG\r\n\x1a\nrest")
        specs = [
            {"type": "json_equals", "path": "result.json", "pointer": "/verdict", "value": "PASS"},
            {"type": "json_in", "path": "result.json", "pointer": "/cases/0/outcome", "values": ["FLAKY", "FAIL"]},
            {"type": "file_magic", "path": "image.png", "format": "png"},
        ]
        self.assertTrue(all(result.status == "PASS" for result in run_checks(specs, self.root, {}, [])))
        specs[0]["value"] = "FAIL"
        self.assertEqual(run_checks(specs[:1], self.root, {}, [])[0].status, "FAIL")

    def test_unknown_check_is_infrastructure_error(self):
        result = run_checks([{"type": "unknown"}], self.root, {}, [])[0]
        self.assertEqual(result.status, "INFRA_ERROR")

    def test_trace_tool_and_external_navigation(self):
        events = [{"event": "tool_call", "name": "playwright_browser_navigate", "input": {"url": "http://127.0.0.1:8000/"}}]
        specs = [
            {"type": "trace_tool", "name": "browser_navigate"},
            {"type": "trace_any_tool", "names": ["browser_type", "browser_navigate"]},
            {"type": "no_external_navigation"},
        ]
        self.assertTrue(all(result.status == "PASS" for result in run_checks(specs, self.root, {}, events)))
        events[0]["input"]["url"] = "https://example.com/"
        self.assertEqual(run_checks(specs[-1:], self.root, {}, events)[0].status, "FAIL")

    def test_summary_contract(self):
        document = {}
        for pointer in SUMMARY_REQUIRED:
            tokens = pointer[1:].split("/")
            target = document
            for token in tokens[:-1]:
                target = target.setdefault(token, {})
            target[tokens[-1]] = []
        document["schema_version"] = 2
        document["verdict"] = "PASS"
        document["learnings"] = {"captured": [], "none_because": "clean run"}
        self.assertEqual(validate_summary(document), [])
        document["learnings"]["none_because"] = ""
        self.assertIn("exactly one", validate_summary(document)[0])

    def test_canary_scan_reports_locations_not_values(self):
        self.write("answer.txt", "SYNTHETIC-CANARY")
        self.write(".env.playwright-secrets", "SYNTHETIC-CANARY")
        leaks = scan_canary_leaks(self.root, ["answer.txt", ".env.playwright-secrets"], "clean", "SYNTHETIC-CANARY")
        self.assertEqual(leaks, ["answer.txt"])
        self.assertNotIn("SYNTHETIC-CANARY", " ".join(leaks))

    def test_artifact_hashes_and_source_provenance(self):
        import hashlib
        log = self.write("run/logs/run.log", "exact bytes\n")
        source = self.write("contracts/source.json", '{"required":true}\n')
        log_bytes = log.read_bytes()
        source_bytes = source.read_bytes()
        summary = self.write("run/execution_summary.json", json.dumps({"artifacts": [{"path": "logs/run.log", "sha256": hashlib.sha256(log_bytes).hexdigest()}]}))
        evidence = self.write("run/contract-evidence.json", json.dumps({
            "source_document": "contracts/source.json",
            "revision": "rev-1",
            "captured_at": "2026-11-15T12:00:00Z",
            "byte_length": len(source_bytes),
            "sha256": hashlib.sha256(source_bytes).hexdigest(),
        }))
        specs = [
            {"type": "artifact_hashes", "path": "run/execution_summary.json"},
            {"type": "source_provenance", "path": "run/contract-evidence.json", "source": "contracts/source.json"},
        ]
        self.assertTrue(all(result.status == "PASS" for result in run_checks(specs, self.root, {}, [])))
        source.write_text('{"changed":true}\n')
        self.assertEqual(run_checks(specs[1:], self.root, {}, [])[0].status, "FAIL")

    def test_load_checks_suite(self):
        path = self.write("checks.json", json.dumps({"suite": "browser", "checks": []}))
        self.assertEqual(load_checks(path), ("browser", []))


if __name__ == "__main__":
    unittest.main()

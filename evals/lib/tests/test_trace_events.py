import json
import unittest

from trace_events import parse_harness_output, sanitize, sanitize_text, sanitize_url


class TraceEventsTest(unittest.TestCase):
    def test_sanitize_nested_secrets_and_binary(self):
        value = {
            "Authorization": "Bearer actual-secret",
            "nested": {"api_key": "actual-secret", "text": "token is actual-secret"},
            "image": {"base64": "abcdef"},
            "safe": 7,
        }
        result = sanitize(value, ["actual-secret"])
        self.assertEqual(result["Authorization"], "[REDACTED]")
        self.assertEqual(result["nested"]["text"], "token is [REDACTED]")
        self.assertEqual(result["image"], "[REDACTED]")
        self.assertEqual(result["safe"], 7)
        self.assertNotIn("actual-secret", json.dumps(result))

    def test_sanitize_url_removes_userinfo_sensitive_query_and_fragment(self):
        result = sanitize_url("https://user:pass@example.com/path?ok=1&access_token=value#fragment")
        self.assertEqual(result, "https://example.com/path?ok=1&access_token=%5BREDACTED%5D")

    def test_sanitize_bearer(self):
        self.assertEqual(sanitize_text("Bearer abcdef123456", []), "Bearer [REDACTED]")

    def test_parse_claude_stream(self):
        rows = [
            {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "playwright_browser_navigate", "input": {"url": "http://127.0.0.1:1"}}]}},
            {"type": "result", "result": "done actual-secret", "is_error": False},
        ]
        answer, events, malformed = parse_harness_output("\n".join(json.dumps(row) for row in rows), "claude", ["actual-secret"])
        self.assertEqual(answer, "done actual-secret")
        self.assertEqual(events[0]["event"], "tool_call")
        self.assertEqual(malformed, [])

    def test_parse_opencode_stream(self):
        rows = [
            {"type": "tool_use", "part": {"tool": "playwright_browser_type", "state": {"input": {"text": "actual-secret"}, "status": "completed"}}},
            {"type": "text", "part": {"text": "finished"}},
        ]
        answer, events, malformed = parse_harness_output("\n".join(json.dumps(row) for row in rows), "opencode", ["actual-secret"])
        self.assertEqual(answer, "finished")
        self.assertEqual(events[0]["input"]["text"], "[REDACTED]")
        self.assertEqual(malformed, [])

    def test_malformed_lines_do_not_become_answer(self):
        answer, _, malformed = parse_harness_output("gateway unavailable", "claude", [])
        self.assertEqual(answer, "")
        self.assertEqual(malformed, ["non-JSON output line 1"])


if __name__ == "__main__":
    unittest.main()

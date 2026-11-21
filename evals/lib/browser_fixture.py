from __future__ import annotations

import argparse
import json
import threading
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit


FIXTURE_ROOT = Path(__file__).with_name("browser_fixture")


@dataclass(frozen=True)
class RequestRecord:
    method: str
    path: str
    status: int


class FixtureServer:
    def __init__(self, canary: str = "SYNTHETIC-QA-EVAL-CANARY", port: int = 0) -> None:
        self.canary = canary
        self.requests: list[RequestRecord] = []
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, fmt: str, *args: Any) -> None:
                return

            def _allowed(self) -> bool:
                host = self.headers.get("Host", "").split(":", 1)[0]
                return host == "127.0.0.1"

            def _send(self, status: int, body: bytes, content_type: str) -> None:
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.send_header("Cache-Control", "no-store")
                self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'")
                self.send_header("X-Content-Type-Options", "nosniff")
                self.end_headers()
                self.wfile.write(body)
                fixture.requests.append(RequestRecord(self.command, urlsplit(self.path).path, status))

            def _json(self, status: int, value: dict[str, Any]) -> None:
                self._send(status, json.dumps(value, sort_keys=True).encode(), "application/json; charset=utf-8")

            def _body(self) -> dict[str, Any]:
                try:
                    length = int(self.headers.get("Content-Length", "0"))
                except ValueError:
                    length = 0
                if length <= 0 or length > 16_384:
                    raise ValueError("invalid request size")
                value = json.loads(self.rfile.read(length))
                if not isinstance(value, dict):
                    raise ValueError("JSON object required")
                return value

            def do_GET(self) -> None:
                if not self._allowed():
                    self._json(403, {"error": "loopback fixture only"})
                    return
                path = urlsplit(self.path).path
                if path == "/api/health":
                    self._json(200, {"status": "ok", "fixture": "qa-eval-v1"})
                    return
                if path == "/api/fail":
                    self._json(500, {"error": "intentional fixture failure", "code": "QA_EVAL_500"})
                    return
                if path == "/api/orders/ORDER-001":
                    self._json(200, {"id": "ORDER-001", "item": "synthetic-widget", "quantity": 1, "total": 42})
                    return
                if path == "/":
                    path = "/index.html"
                candidate = (FIXTURE_ROOT / path.lstrip("/")).resolve()
                if FIXTURE_ROOT.resolve() not in candidate.parents or not candidate.is_file():
                    self._json(404, {"error": "not found"})
                    return
                content_types = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8"}
                self._send(200, candidate.read_bytes(), content_types.get(candidate.suffix, "application/octet-stream"))

            def do_POST(self) -> None:
                if not self._allowed():
                    self._json(403, {"error": "loopback fixture only"})
                    return
                path = urlsplit(self.path).path
                try:
                    body = self._body()
                except (ValueError, json.JSONDecodeError):
                    self._json(400, {"error": "valid JSON object required"})
                    return
                if path == "/api/login":
                    if body.get("username") == "qa-eval" and body.get("password") == fixture.canary:
                        self._json(200, {"authenticated": True, "user": "qa-eval"})
                    else:
                        self._json(401, {"authenticated": False, "error": "invalid synthetic credentials"})
                    return
                if path == "/api/orders":
                    if body.get("item") != "synthetic-widget" or body.get("quantity") != 1:
                        self._json(422, {"error": "only one synthetic-widget is accepted"})
                        return
                    self._json(201, {"id": "ORDER-001", "item": "synthetic-widget", "quantity": 1, "total": 42})
                    return
                self._json(404, {"error": "not found"})

        self.server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)

    @property
    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.server.server_port}"

    def start(self) -> "FixtureServer":
        self.thread.start()
        return self

    def close(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=5)

    def __enter__(self) -> "FixtureServer":
        return self.start()

    def __exit__(self, exc_type: Any, exc: Any, traceback: Any) -> None:
        self.close()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=0)
    args = parser.parse_args()
    fixture = FixtureServer(port=args.port)
    with fixture:
        try:
            threading.Event().wait()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 Sn4kyGit

"""openrouter-shim.py — localhost Anthropic-API shim in front of OpenRouter.

Why this exists: Claude Code calls /v1/messages/count_tokens (context
management) and GET /v1/models/<id> (model validation). OpenRouter's
Anthropic-compatible endpoint 404s both, and the CLI then aborts with
"There's an issue with the selected model". Everything else on OpenRouter
works, including streaming. This shim answers the two missing endpoints
locally and proxies the rest through unchanged.

Security: binds 127.0.0.1 only. The OpenRouter key is NEVER in this file —
the CLI sends it as Authorization: Bearer and the shim passes the header
through untouched. Request/response bodies are never logged.

Usage: python3 openrouter-shim.py [port]   (default 8799)
Stdlib only, no dependencies.
"""

import json
import sys
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM = "https://openrouter.ai/api"  # CLI haengt selbst /v1/... an

# Headers that must not be forwarded verbatim in either direction.
HOP_BY_HOP = {
    "connection", "keep-alive", "transfer-encoding", "content-length",
    "content-encoding", "host",
}


def estimate_tokens(body: bytes) -> int:
    """Rough char/4 estimate over the semantic payload.

    Only used for the CLI's context-usage display/compaction threshold —
    a ~20% error here changes when the CLI compacts, not what it sends.
    """
    try:
        payload = json.loads(body)
        semantic = {k: v for k, v in payload.items() if k != "tool_choice"}
        return max(1, len(json.dumps(semantic)) // 4)
    except Exception:
        return max(1, len(body) // 4)


class Shim(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # quiet: method + path + status only
        sys.stderr.write("shim: %s %s\n" % (self.command, self.path))

    # -- locally answered endpoints -------------------------------------

    def _json(self, status: int, obj: dict):
        data = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_HEAD(self):
        # Connectivity-Probe der CLI; OpenRouter 404t ihn, lokal beantworten.
        if "/api/hello" in self.path:
            self.send_response(200)
            self.send_header("content-length", "0")
            self.end_headers()
            return
        self.send_response(405)
        self.send_header("content-length", "0")
        self.end_headers()

    def do_GET(self):
        if self.path.startswith("/v1/models"):
            # Model-existence validation: OpenRouter 404s this, the CLI
            # aborts on a 404. Answer 200 for any id — the real check is
            # the messages call itself.
            name = self.path.rsplit("/", 1)[-1]
            self._json(200, {
                "id": name, "type": "model", "display_name": name,
                "created_at": "2026-01-01T00:00:00Z",
            })
            return
        self._proxy(b"")

    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length) if length else b""
        if self.path.startswith("/v1/messages/count_tokens"):
            self._json(200, {"input_tokens": estimate_tokens(body)})
            return
        self._proxy(body)

    # -- passthrough proxy ----------------------------------------------

    def _proxy(self, body: bytes):
        req = urllib.request.Request(UPSTREAM + self.path, data=body or None,
                                     method=self.command)
        for k, v in self.headers.items():
            if k.lower() not in HOP_BY_HOP:
                req.add_header(k, v)
        try:
            upstream = urllib.request.urlopen(req, timeout=600)
            status = upstream.status
        except urllib.error.HTTPError as e:
            upstream = e  # HTTPError is also a readable response
            status = e.code
        except Exception as e:
            self._json(502, {"type": "error", "error": {
                "type": "api_error", "message": f"shim upstream error: {e}"}})
            return

        is_sse = "text/event-stream" in (upstream.headers.get("content-type") or "")
        self.send_response(status)
        for k, v in upstream.headers.items():
            if k.lower() not in HOP_BY_HOP:
                self.send_header(k, v)
        if is_sse:
            # SSE passthrough: manual chunked framing, line at a time, so
            # events reach the CLI as OpenRouter emits them.
            self.send_header("transfer-encoding", "chunked")
            self.end_headers()
            try:
                while True:
                    line = upstream.readline()
                    if not line:
                        break
                    frame = b"%x\r\n%s\r\n" % (len(line), line)
                    self.wfile.write(frame)
                    self.wfile.flush()
                self.wfile.write(b"0\r\n\r\n")
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            data = upstream.read()
            self.send_header("content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        upstream.close()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8799
    server = ThreadingHTTPServer(("127.0.0.1", port), Shim)
    sys.stderr.write(f"openrouter-shim listening on 127.0.0.1:{port}\n")
    server.serve_forever()

#!/usr/bin/env python3
"""Cloud Save wire contract checked against AppCloudSaveController on 2026-10-01.

Save and load require Bearer sessions. Binary load is POST with a JSON body,
Content-Type application/json and Accept application/octet-stream. It returns
204 when absent. All traffic stays on a dedicated loopback port.
"""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

from mock_http import report_rejection, send_json

PORT = 18892
DATA = bytes([0, 255, 128, 10, 42])
EXPECTED = [
    ("save", "application/json", {"userId": "user-892", "saveData": '{"level":5}'}, 200, {"success": True, "dataSizeBytes": 11}),
    ("load", "application/json", {"userId": "user-892"}, 200, {"found": True, "saveData": '{"level":5}'}),
    ("save", "application/octet-stream", DATA, 200, {"success": True, "dataSizeBytes": len(DATA)}),
    ("load", "application/json", {"userId": "user-892"}, 200, DATA),
    ("load", "application/json", {"userId": "user-892"}, 204, b""),
    ("load", "application/json", {"userId": "user-892"}, 401, {"message": "Invalid or expired session"}),
]


class Handler(BaseHTTPRequestHandler):
    seen = 0
    failure = None

    def do_GET(self):
        self._handle("GET")

    def do_POST(self):
        self._handle("POST")

    def _handle(self, method):
        index = type(self).seen
        type(self).seen += 1
        if index >= len(EXPECTED):
            self._reject("unexpected extra Cloud Save request")
            return
        action, content_type, expected_body, status, response = EXPECTED[index]
        url = urlparse(self.path)
        raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        body = raw
        if content_type == "application/json":
            try:
                body = json.loads(raw)
            except json.JSONDecodeError:
                body = None
        expected_query = {"userId": ["user-892"]} if content_type == "application/octet-stream" else {}
        problems = []
        if method != "POST" or url.path != "/api/v1/app/cloud-save/" + action:
            problems.append(f"wrong route: {method} {self.path}")
        if parse_qs(url.query) != expected_query or body != expected_body:
            problems.append(f"wrong query/body: {url.query!r} {body!r}")
        if self.headers.get_content_type() != content_type:
            problems.append("wrong Content-Type")
        if self.headers.get("X-API-Key") != "project-key-892":
            problems.append("missing API key")
        if self.headers.get("Authorization") != "Bearer session-token-892":
            problems.append("missing player Bearer session")
        if index >= 3 and self.headers.get("Accept") != "application/octet-stream":
            problems.append("missing binary Accept header")
        if problems:
            self._reject("; ".join(problems))
            return
        if isinstance(response, bytes):
            self.send_response(status)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(response)))
            self.end_headers()
            self.wfile.write(response)
        else:
            send_json(self, status, response)

    def _reject(self, message):
        type(self).failure = message
        report_rejection(message)
        send_json(self, 422, {"message": message})

    def log_message(self, *_args):
        pass


def main():
    with HTTPServer(("127.0.0.1", PORT), Handler) as server:
        ready_file = os.environ.get("MOCK_SERVER_READY_FILE")
        if ready_file:
            with open(ready_file, "w") as handle:
                handle.write("ready\n")
        server.timeout = 10
        for _ in EXPECTED:
            server.handle_request()
            if Handler.failure:
                raise SystemExit(1)
        if Handler.seen != len(EXPECTED):
            raise SystemExit(f"expected {len(EXPECTED)} requests, got {Handler.seen}")
        server.timeout = 1.5
        server.handle_request()
        if Handler.seen != len(EXPECTED):
            raise SystemExit("unsigned Cloud Save request reached the server")
    print("Godot contract server observed the expected Cloud Save requests")


if __name__ == "__main__":
    main()

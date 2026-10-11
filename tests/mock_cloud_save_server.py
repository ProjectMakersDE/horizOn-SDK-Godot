#!/usr/bin/env python3
"""Cloud Save wire contract checked against AppCloudSaveController on 2026-10-01.

Save and load require Bearer sessions. Binary load is POST with a JSON body,
Content-Type application/json and Accept application/octet-stream. It returns
204 when absent. All traffic stays on a dedicated loopback port.

Revisions checked against AppCloudSaveController and CloudSaveExceptionHandler
on 2026-10-11 (horizOn-Server 1.64.1 and later): every load answers
X-Cloud-Save-Revision (JSON, bytes and 204), both saves accept If-Match as a
plain number and answer 409 with {"error": ...} on a mismatch, a successful
save returns `revision`. The plain save and load methods never send If-Match.
"""
import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse

from mock_http import report_rejection, send_json

PORT = 18892
DATA = bytes([0, 255, 128, 10, 42])
LOAD = {"userId": "user-892"}
JSON_SAVE = {"userId": "user-892", "saveData": '{"level":5}'}
CONFLICT = {"error": "Cloud save changed on another device (expected revision 3, current revision 4)"}
REVISION = "X-Cloud-Save-Revision"
# (action, request Content-Type, request body, binary Accept, If-Match or None,
#  response status, response body, response headers)
EXPECTED = [
    ("save", "application/json", JSON_SAVE, False, None, 200, {"success": True, "dataSizeBytes": 11}, {}),
    ("load", "application/json", LOAD, False, None, 200, {"found": True, "saveData": '{"level":5}'}, {}),
    ("save", "application/octet-stream", DATA, False, None, 200, {"success": True, "dataSizeBytes": len(DATA)}, {}),
    ("load", "application/json", LOAD, True, None, 200, DATA, {}),
    ("load", "application/json", LOAD, True, None, 204, b"", {}),
    ("load", "application/json", LOAD, True, None, 401, {"message": "Invalid or expired session"}, {}),
    # Revision flow (TASK-1018)
    ("load", "application/json", LOAD, False, None, 200, {"found": True, "saveData": '{"level":5}'}, {REVISION: "3"}),
    ("save", "application/json", JSON_SAVE, False, "3", 200, {"success": True, "dataSizeBytes": 11, "revision": 4}, {}),
    ("save", "application/json", JSON_SAVE, False, "3", 409, CONFLICT, {}),
    ("load", "application/json", LOAD, True, None, 200, DATA, {REVISION: "7"}),
    ("load", "application/json", LOAD, True, None, 204, b"", {REVISION: "0"}),
    ("save", "application/octet-stream", DATA, False, "0", 200, {"success": True, "dataSizeBytes": len(DATA), "revision": 1}, {}),
    ("save", "application/octet-stream", DATA, False, "1", 409, CONFLICT, {}),
    # A server without revisions (simpleServer): no header, so the revision is unknown
    ("load", "application/json", LOAD, False, None, 200, {"found": False, "saveData": None}, {}),
    ("load", "application/json", LOAD, True, None, 200, DATA, {}),
    ("save", "application/json", JSON_SAVE, False, "0", 200, {"success": True, "dataSizeBytes": 11}, {}),
    # An empty JSON slot answers revision 0
    ("load", "application/json", LOAD, False, None, 200, {"found": False}, {REVISION: "0"}),
    # Unreadable answers: a load without "found" and a save without "success"
    ("load", "application/json", LOAD, False, None, 200, {}, {REVISION: "7"}),
    ("save", "application/json", JSON_SAVE, False, "7", 200, {}, {}),
    ("save", "application/json", JSON_SAVE, False, "7", 200, {"success": "false", "dataSizeBytes": 11}, {}),
    ("save", "application/json", JSON_SAVE, False, "7", 200, {"success": True, "dataSizeBytes": 11, "revision": 2.5}, {}),
    # JSON 429 answers keep their headers: a feature limit and an exhausted account limit
    ("save", "application/json", JSON_SAVE, False, None, 429, {"code": "RUN_RATE_LIMITED", "message": "Too many runs"}, {"Retry-After": "30"}),
    ("save", "application/json", JSON_SAVE, False, None, 429, {}, {"Retry-After": "1"}),
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
        action, content_type, expected_body, binary_accept, if_match, status, response, response_headers = EXPECTED[index]
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
        if binary_accept and self.headers.get("Accept") != "application/octet-stream":
            problems.append("missing binary Accept header")
        if self.headers.get("If-Match") != if_match:
            problems.append(f"wrong If-Match: {self.headers.get('If-Match')!r}, expected {if_match!r}")
        if problems:
            self._reject("; ".join(problems))
            return
        if isinstance(response, bytes):
            self.send_response(status)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(response)))
            for name, value in response_headers.items():
                self.send_header(name, value)
            self.end_headers()
            self.wfile.write(response)
        else:
            send_json(self, status, response, response_headers)

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

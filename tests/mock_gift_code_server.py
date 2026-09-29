#!/usr/bin/env python3
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer


EXPECTED_PATH = "/api/v1/app/gift-codes/redeem"
EXPECTED_BODY = {
    "code": "SUMMER2026",
    "userId": "user-886",
}


class ContractHandler(BaseHTTPRequestHandler):
    requests_seen = 0
    failure = None

    def do_POST(self):
        type(self).requests_seen += 1
        content_length = int(self.headers.get("Content-Length", "0"))
        raw_body = self.rfile.read(content_length)
        try:
            body = json.loads(raw_body)
        except json.JSONDecodeError as error:
            self._reject(f"invalid JSON: {error}")
            return

        mismatches = []
        if self.path != EXPECTED_PATH:
            mismatches.append(f"path={self.path!r}")
        if self.headers.get("X-API-Key") != "project-key-886":
            mismatches.append("missing or incorrect X-API-Key")
        if self.headers.get("Authorization") != "Bearer session-token-886":
            mismatches.append("missing or incorrect Authorization")
        if self.headers.get_content_type() != "application/json":
            mismatches.append(f"content-type={self.headers.get_content_type()!r}")
        if body != EXPECTED_BODY:
            mismatches.append(f"body={body!r}")

        if mismatches:
            self._reject(", ".join(mismatches))
            return

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"success": True, "message": "ok", "giftData": "{}"}).encode())

    def _reject(self, message):
        type(self).failure = message
        self.send_response(422)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"message": message}).encode())

    def log_message(self, *_args):
        return


def main():
    server = HTTPServer(("127.0.0.1", 18724), ContractHandler)
    # The socket is bound and listening now. Tell the runner it may start Godot.
    ready_file = os.environ.get("MOCK_SERVER_READY_FILE")
    if ready_file:
        with open(ready_file, "w") as handle:
            handle.write("ready\n")
    server.timeout = 10
    server.handle_request()
    if ContractHandler.requests_seen != 1:
        print("expected exactly one session-bound redeem request", file=sys.stderr)
        return 1

    # The signed request has completed. Observe a grace period in which the no-session calls run.
    server.timeout = 1.5
    server.handle_request()
    if ContractHandler.requests_seen != 1:
        print("a redeem request without session reached the server", file=sys.stderr)
        return 1
    if ContractHandler.failure:
        print(ContractHandler.failure, file=sys.stderr)
        return 1

    print("Godot contract server observed the expected session-bound redeem and no unsigned request")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

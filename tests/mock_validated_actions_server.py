#!/usr/bin/env python3
"""Contract server for the Godot validated actions transport test (TASK-883).

Expects exactly these requests, in this order, then no further request:
1.  POST /api/v1/app/validated-actions/runs    (bound to "weekly", answered with a run)
2.  POST /api/v1/app/validated-actions/submit  (hash of the log bytes, stage, no board, answered 200)
3.  POST /api/v1/app/validated-actions/runs    (unbound, answered with a second run)
4.  POST /api/v1/app/validated-actions/submit  (ready hash, earned, answered 422 DURATION_TOO_SHORT)
5.  POST /api/v1/app/validated-actions/runs    (answered 429 RUN_RATE_LIMITED, must not be retried)
6.  POST /api/v1/app/validated-actions/runs    (answered with a third run)
7.  POST /api/v1/app/validated-actions/submit  (answered 404 without code: NOT_SUPPORTED, run kept)
8.  POST /api/v1/app/validated-actions/submit  (same ticket again, answered 403 SCORE_LIMIT_REACHED)
9.  POST /api/v1/app/leaderboards/weekly/submit (answered 403 VALIDATED_SUBMIT_REQUIRED)
10. GET  /api/v1/app/leaderboards               (boards with and without validatedOnly)
Every request carries X-API-Key; all but the board list carry the player's Bearer session.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse


PORT = 18883
API_KEY = "project-key-883"
AUTHORIZATION = "Bearer session-token-883"
USER_ID = "user-883"
RUNS_PATH = "/api/v1/app/validated-actions/runs"
SUBMIT_PATH = "/api/v1/app/validated-actions/submit"
BOARD_SUBMIT_PATH = "/api/v1/app/leaderboards/weekly/submit"
BOARDS_PATH = "/api/v1/app/leaderboards"

# SHA-256 of b"R1:L2:J3" (the log bytes the Godot test submits)
LOG_HASH = "054a3b937f3f8b4d1d82fe353243cb91288f7975e2190a338e59271f17701375"
# A ready hash, sent upper case by the test and lower cased by the SDK
READY_HASH = "a" * 64


def run_body(run_id, ticket, seed, board):
    return {
        "runId": run_id,
        "ticket": ticket,
        "seed": seed,
        "leaderboardKey": board,
        "issuedAt": "2026-09-29T14:00:00.120Z",
        "expiresAt": "2026-09-29T16:00:00.120Z",
        "expiresInSeconds": 7200,
    }


def error_body(status, error, code, message, path, run_id=None):
    body = {
        "timestamp": "2026-09-29T14:03:11.402",
        "status": status,
        "error": error,
        "code": code,
        "message": message,
        "path": path,
    }
    if run_id:
        body["runId"] = run_id
    return body


# (method, path, needs session, expected JSON body or None, status, extra headers, response body)
EXPECTED = [
    (
        "POST", RUNS_PATH, True,
        {"userId": USER_ID, "leaderboardKey": "weekly"},
        200, {}, run_body("run-1", "hzn-rt1:2026-09:ticket-one", 1834201177, "weekly"),
    ),
    (
        "POST", SUBMIT_PATH, True,
        # No leaderboardKey (the ticket's board is used) and no earned (empty list omitted).
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-one", "inputLogHash": LOG_HASH,
         "score": 18250, "stage": "wave_3"},
        200, {},
        {
            "accepted": True, "runId": "run-1", "leaderboardKey": "weekly", "score": 18250,
            "bestScore": 21000, "isNewHighScore": False, "rank": 17, "durationSeconds": 734,
            "state": None, "evidence": None,
        },
    ),
    (
        "POST", RUNS_PATH, True,
        {"userId": USER_ID},
        200, {}, run_body("run-2", "hzn-rt1:2026-09:ticket-two", 7, None),
    ),
    (
        "POST", SUBMIT_PATH, True,
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-two", "inputLogHash": READY_HASH,
         "score": 0, "earned": [{"key": "gold", "amount": 250}]},
        422, {},
        error_body(422, "Unprocessable Entity", "DURATION_TOO_SHORT",
                   "The run was shorter than allowed", SUBMIT_PATH, "run-2"),
    ),
    (
        "POST", RUNS_PATH, True,
        {"userId": USER_ID, "leaderboardKey": "weekly"},
        429, {"Retry-After": "1"},
        error_body(429, "Too Many Requests", "RUN_RATE_LIMITED",
                   "Too many runs for this player in the last hour", RUNS_PATH),
    ),
    (
        "POST", RUNS_PATH, True,
        {"userId": USER_ID, "leaderboardKey": "weekly"},
        200, {}, run_body("run-3", "hzn-rt1:2026-09:ticket-three", 42, "weekly"),
    ),
    (
        "POST", SUBMIT_PATH, True,
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-three", "inputLogHash": LOG_HASH,
         "score": 500},
        404, {}, {"message": "Not Found"},
    ),
    (
        "POST", SUBMIT_PATH, True,
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-three", "inputLogHash": LOG_HASH,
         "score": 500},
        403, {},
        error_body(403, "Forbidden", "SCORE_LIMIT_REACHED",
                   "The score limit of this API key is reached", SUBMIT_PATH, "run-3"),
    ),
    (
        "POST", BOARD_SUBMIT_PATH, True,
        {"userId": USER_ID, "score": 999, "leaderboardKey": "weekly"},
        403, {},
        error_body(403, "Forbidden", "VALIDATED_SUBMIT_REQUIRED",
                   "This leaderboard accepts validated runs only", BOARD_SUBMIT_PATH),
    ),
    (
        "GET", BOARDS_PATH, False, None,
        200, {},
        {"boards": [
            {"boardKey": "weekly", "name": "Weekly", "validatedOnly": True},
            {"boardKey": "default", "name": "Default"},
        ]},
    ),
]


class ContractHandler(BaseHTTPRequestHandler):
    requests_seen = 0
    failure = None

    def do_GET(self):
        self._handle("GET")

    def do_POST(self):
        self._handle("POST")

    def _handle(self, method):
        index = type(self).requests_seen
        type(self).requests_seen += 1
        if index >= len(EXPECTED):
            self._reject(f"unexpected extra request {method} {self.path}")
            return

        exp_method, exp_path, needs_session, exp_body, status, headers, response = EXPECTED[index]
        url = urlparse(self.path)
        mismatches = []
        if method != exp_method:
            mismatches.append(f"method={method!r}")
        if url.path != exp_path:
            mismatches.append(f"path={url.path!r}")
        if self.headers.get("X-API-Key") != API_KEY:
            mismatches.append("missing or incorrect X-API-Key")
        if needs_session and self.headers.get("Authorization") != AUTHORIZATION:
            mismatches.append("missing or incorrect Authorization")

        if exp_body is not None:
            if self.headers.get_content_type() != "application/json":
                mismatches.append(f"content-type={self.headers.get_content_type()!r}")
            content_length = int(self.headers.get("Content-Length", "0"))
            raw_body = self.rfile.read(content_length)
            try:
                body = json.loads(raw_body)
            except json.JSONDecodeError as error:
                mismatches.append(f"invalid JSON: {error}")
                body = None
            if body is not None and body != exp_body:
                mismatches.append(f"body={body!r}")

        if mismatches:
            self._reject(f"request {index + 1} ({exp_method} {exp_path}): " + ", ".join(mismatches))
            return

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        for name, value in headers.items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())

    def _reject(self, message):
        type(self).failure = message
        self.send_response(400)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"message": message}).encode())

    def log_message(self, *_args):
        return


def main():
    server = HTTPServer(("127.0.0.1", PORT), ContractHandler)
    # The socket is bound and listening now. Tell the runner it may start Godot.
    ready_file = os.environ.get("MOCK_SERVER_READY_FILE")
    if ready_file:
        with open(ready_file, "w") as handle:
            handle.write("ready\n")

    server.timeout = 10
    for _ in EXPECTED:
        server.handle_request()
        if ContractHandler.failure:
            break
    if ContractHandler.failure:
        print(ContractHandler.failure, file=sys.stderr)
        return 1
    if ContractHandler.requests_seen != len(EXPECTED):
        print(f"expected {len(EXPECTED)} requests, saw {ContractHandler.requests_seen}", file=sys.stderr)
        return 1

    # Grace period in which the locally rejected calls (no session, no run,
    # invalid hash) run. None of them may reach the server. (A retried
    # 429 RUN_RATE_LIMITED would take request 6 and fail the Godot side.)
    server.timeout = 1.5
    server.handle_request()
    if ContractHandler.requests_seen != len(EXPECTED):
        print("a locally rejected or retried validated actions call reached the server", file=sys.stderr)
        return 1

    print("Godot contract server observed the expected validated actions requests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

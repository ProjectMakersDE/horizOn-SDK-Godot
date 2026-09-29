#!/usr/bin/env python3
"""Contract server for the Godot validated actions transport test (TASK-883, 887, 888).

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
11. POST /api/v1/app/validated-actions/runs    (bound to "weekly", answered with a fourth run)
12. POST /api/v1/app/validated-actions/submit  (board "monthly", answered 422 LEADERBOARD_MISMATCH, run kept)
13. POST /api/v1/app/validated-actions/submit  (same ticket, no board, answered 422 TICKET_EXPIRED, run cleared)
14. GET  /api/v1/app/validated-actions/state?userId=user-883 (Part 2, values up to 2^53 - 1)
15. POST /api/v1/app/validated-actions/runs    (unbound, answered with a fifth run)
16. POST /api/v1/app/validated-actions/submit  (earned, answered 200 with state, requested and credited)
17. POST /api/v1/app/validated-actions/runs    (unbound, answered with a sixth run)
18. POST /api/v1/app/validated-actions/submit  (spend, answered 422 INSUFFICIENT_BALANCE)
19. GET  /api/v1/app/validated-actions/state?userId=user-883 (answered 401 SESSION_REQUIRED)
20. GET  /api/v1/app/validated-actions/state?userId=user-883 (answered 404 without code: NOT_SUPPORTED)
21. POST /api/v1/app/validated-actions/runs    (Part 3, bound to "weekly", answered with run-7)
22. POST /api/v1/app/validated-actions/submit  (raw log, answered 200 with evidence.required)
23. PUT  /api/v1/app/validated-actions/runs/run-7/evidence (automatic upload, base64 log, answered 200)
24. POST /api/v1/app/validated-actions/runs    (bound to "weekly", answered with run-8)
25. POST /api/v1/app/validated-actions/submit  (ready hash, evidence.required, no automatic upload)
26. PUT  /api/v1/app/validated-actions/runs/run-8/evidence (wrong bytes, answered 422 EVIDENCE_HASH_MISMATCH)
27. PUT  /api/v1/app/validated-actions/runs/run-8/evidence (correct bytes, answered 200)
28. PUT  /api/v1/app/validated-actions/runs/run-8/evidence (again, answered 409 EVIDENCE_ALREADY_UPLOADED)
29. POST /api/v1/app/validated-actions/runs    (bound to "weekly", answered with run-9)
30. POST /api/v1/app/validated-actions/submit  (answered 403 PLAYER_BANNED, run kept)
31. POST /api/v1/app/validated-actions/submit  (same ticket, evidence.required, auto upload off: no PUT)
32. POST /api/v1/app/leaderboards/weekly/submit (answered 403 PLAYER_BANNED)
33. POST /api/v1/app/validated-actions/runs    (bound to "weekly", answered with run-10)
34. POST /api/v1/app/validated-actions/submit  (evidence.maxBytes 4 below the 8 byte log: no PUT)
35. PUT  /api/v1/app/validated-actions/runs/run-unknown/evidence (answered 404 EVIDENCE_NOT_REQUESTED)
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
STATE_PATH = "/api/v1/app/validated-actions/state?userId=" + USER_ID
EVIDENCE_PATH = "/api/v1/app/validated-actions/runs/%s/evidence"

# Largest value the server stores (2^53 - 1)
MAX_SAFE_INT = 9007199254740991

# SHA-256 of b"R1:L2:J3" (the log bytes the Godot test submits)
LOG_HASH = "054a3b937f3f8b4d1d82fe353243cb91288f7975e2190a338e59271f17701375"
# A ready hash, sent upper case by the test and lower cased by the SDK
READY_HASH = "a" * 64
# Standard base64 of b"R1:L2:J3" and of the wrong log b"R1:L2:J4"
LOG_BASE64 = "UjE6TDI6SjM="
WRONG_LOG_BASE64 = "UjE6TDI6SjQ="


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


def evidence_result(run_id, max_bytes=32768):
    return {
        "accepted": True, "runId": run_id, "leaderboardKey": "weekly", "score": 900,
        "bestScore": 900, "isNewHighScore": True, "rank": 1, "durationSeconds": 312,
        "state": None,
        "evidence": {"required": True, "runId": run_id,
                     "uploadBefore": "2026-09-30T14:05:12.000Z", "maxBytes": max_bytes},
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
    (
        "POST", RUNS_PATH, True,
        {"userId": USER_ID, "leaderboardKey": "weekly"},
        200, {}, run_body("run-4", "hzn-rt1:2026-09:ticket-four", 99, "weekly"),
    ),
    (
        "POST", SUBMIT_PATH, True,
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-four", "inputLogHash": LOG_HASH,
         "score": 700, "leaderboardKey": "monthly"},
        422, {},
        error_body(422, "Unprocessable Entity", "LEADERBOARD_MISMATCH",
                   "The run ticket was started for another leaderboard", SUBMIT_PATH, "run-4"),
    ),
    (
        "POST", SUBMIT_PATH, True,
        # The same ticket again: LEADERBOARD_MISMATCH did not consume it.
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-four", "inputLogHash": LOG_HASH,
         "score": 700},
        422, {},
        error_body(422, "Unprocessable Entity", "TICKET_EXPIRED",
                   "The run ticket has expired", SUBMIT_PATH, "run-4"),
    ),
    (
        "GET", STATE_PATH, True, None,
        200, {},
        {
            "userId": USER_ID,
            "day": "2026-09-29",
            "values": [
                {"key": "chest.gold", "balance": 2, "earnedToday": 0, "dailyCap": None},
                {"key": "gems", "balance": MAX_SAFE_INT, "earnedToday": 0, "dailyCap": None},
                {"key": "gold", "balance": 1250, "earnedToday": 250, "dailyCap": 400},
            ],
        },
    ),
    (
        "POST", RUNS_PATH, True,
        {"userId": USER_ID},
        200, {}, run_body("run-5", "hzn-rt1:2026-09:ticket-five", 5, None),
    ),
    (
        "POST", SUBMIT_PATH, True,
        # 250.0 is sent as int, the malformed entries are dropped.
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-five", "inputLogHash": LOG_HASH,
         "score": 0, "earned": [{"key": "gold", "amount": 250}, {"key": "chest.gold", "amount": -1}]},
        200, {},
        {
            "accepted": True, "runId": "run-5", "leaderboardKey": None, "score": None,
            "bestScore": None, "isNewHighScore": False, "rank": None, "durationSeconds": 95,
            "state": {
                "day": "2026-09-29",
                "values": [
                    {"key": "chest.gold", "balance": 1, "earnedToday": 0, "dailyCap": None,
                     "requested": -1, "credited": -1},
                    {"key": "gems", "balance": MAX_SAFE_INT, "earnedToday": 0, "dailyCap": None},
                    # The daily cap of 400 clamps the credit of 250 to 150.
                    {"key": "gold", "balance": 1400, "earnedToday": 400, "dailyCap": 400,
                     "requested": 250, "credited": 150},
                ],
            },
            "evidence": None,
        },
    ),
    (
        "POST", RUNS_PATH, True,
        {"userId": USER_ID},
        200, {}, run_body("run-6", "hzn-rt1:2026-09:ticket-six", 6, None),
    ),
    (
        "POST", SUBMIT_PATH, True,
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-six", "inputLogHash": LOG_HASH,
         "score": 0, "earned": [{"key": "chest.gold", "amount": -5}]},
        422, {},
        error_body(422, "Unprocessable Entity", "INSUFFICIENT_BALANCE",
                   "The balance is too low for this spend", SUBMIT_PATH, "run-6"),
    ),
    (
        "GET", STATE_PATH, True, None,
        401, {"WWW-Authenticate": "Bearer"},
        error_body(401, "Unauthorized", "SESSION_REQUIRED",
                   "Invalid or expired session", "/api/v1/app/validated-actions/state"),
    ),
    (
        "GET", STATE_PATH, True, None,
        404, {}, {"message": "Not Found"},
    ),
    # ----- Part 3: evidence and PLAYER_BANNED -----
    (
        "POST", RUNS_PATH, True,
        {"userId": USER_ID, "leaderboardKey": "weekly"},
        200, {}, run_body("run-7", "hzn-rt1:2026-09:ticket-seven", 7, "weekly"),
    ),
    (
        "POST", SUBMIT_PATH, True,
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-seven", "inputLogHash": LOG_HASH,
         "score": 900},
        200, {}, evidence_result("run-7"),
    ),
    (
        "PUT", EVIDENCE_PATH % "run-7", True,
        {"userId": USER_ID, "log": LOG_BASE64},
        200, {}, {"runId": "run-7", "status": "UPLOADED", "bytes": 8},
    ),
    (
        "POST", RUNS_PATH, True,
        {"userId": USER_ID, "leaderboardKey": "weekly"},
        200, {}, run_body("run-8", "hzn-rt1:2026-09:ticket-eight", 8, "weekly"),
    ),
    (
        "POST", SUBMIT_PATH, True,
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-eight", "inputLogHash": LOG_HASH,
         "score": 900},
        200, {}, evidence_result("run-8"),
    ),
    (
        "PUT", EVIDENCE_PATH % "run-8", True,
        {"userId": USER_ID, "log": WRONG_LOG_BASE64},
        422, {},
        error_body(422, "Unprocessable Entity", "EVIDENCE_HASH_MISMATCH",
                   "The log does not match the input log hash of the run", EVIDENCE_PATH % "run-8", "run-8"),
    ),
    (
        "PUT", EVIDENCE_PATH % "run-8", True,
        {"userId": USER_ID, "log": LOG_BASE64},
        200, {}, {"runId": "run-8", "status": "UPLOADED", "bytes": 8},
    ),
    (
        "PUT", EVIDENCE_PATH % "run-8", True,
        {"userId": USER_ID, "log": LOG_BASE64},
        409, {},
        error_body(409, "Conflict", "EVIDENCE_ALREADY_UPLOADED",
                   "The log of this run was already uploaded", EVIDENCE_PATH % "run-8", "run-8"),
    ),
    (
        "POST", RUNS_PATH, True,
        {"userId": USER_ID, "leaderboardKey": "weekly"},
        200, {}, run_body("run-9", "hzn-rt1:2026-09:ticket-nine", 9, "weekly"),
    ),
    (
        "POST", SUBMIT_PATH, True,
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-nine", "inputLogHash": LOG_HASH,
         "score": 900},
        403, {},
        error_body(403, "Forbidden", "PLAYER_BANNED",
                   "The player is banned from this leaderboard", SUBMIT_PATH, "run-9"),
    ),
    (
        "POST", SUBMIT_PATH, True,
        # The same ticket again: PLAYER_BANNED is checked before the ticket is consumed.
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-nine", "inputLogHash": LOG_HASH,
         "score": 900},
        200, {}, evidence_result("run-9"),
    ),
    (
        "POST", BOARD_SUBMIT_PATH, True,
        {"userId": USER_ID, "score": 999, "leaderboardKey": "weekly"},
        403, {},
        error_body(403, "Forbidden", "PLAYER_BANNED",
                   "The player is banned from this leaderboard", BOARD_SUBMIT_PATH),
    ),
    (
        "POST", RUNS_PATH, True,
        {"userId": USER_ID, "leaderboardKey": "weekly"},
        200, {}, run_body("run-10", "hzn-rt1:2026-09:ticket-ten", 10, "weekly"),
    ),
    (
        "POST", SUBMIT_PATH, True,
        {"userId": USER_ID, "ticket": "hzn-rt1:2026-09:ticket-ten", "inputLogHash": LOG_HASH,
         "score": 900},
        200, {}, evidence_result("run-10", max_bytes=4),
    ),
    (
        "PUT", EVIDENCE_PATH % "run-unknown", True,
        {"userId": USER_ID, "log": LOG_BASE64},
        404, {},
        error_body(404, "Not Found", "EVIDENCE_NOT_REQUESTED",
                   "No evidence was requested for this run", EVIDENCE_PATH % "run-unknown", "run-unknown"),
    ),
]


class ContractHandler(BaseHTTPRequestHandler):
    requests_seen = 0
    failure = None

    def do_GET(self):
        self._handle("GET")

    def do_POST(self):
        self._handle("POST")

    def do_PUT(self):
        self._handle("PUT")

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
        # An expected path with a query is compared with the query.
        actual_path = self.path if "?" in exp_path else url.path
        if actual_path != exp_path:
            mismatches.append(f"path={actual_path!r}")
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
    # invalid hash, invalid evidence upload) run. None of them may reach the
    # server. (A retried 429 RUN_RATE_LIMITED would take request 6 and fail the
    # Godot side; an unwanted automatic evidence upload would take the next slot.)
    server.timeout = 1.5
    server.handle_request()
    if ContractHandler.requests_seen != len(EXPECTED):
        print("a locally rejected or retried validated actions call reached the server", file=sys.stderr)
        return 1

    print("Godot contract server observed the expected validated actions requests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

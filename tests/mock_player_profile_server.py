#!/usr/bin/env python3
"""Contract server for the Godot player profile transport test (TASK-881).

Expects exactly these requests, in this order, then no further request:
1. GET  /api/v1/app/player-profile?userId=user-881
2. PUT  /api/v1/app/player-profile (valid profile, answered 200)
3. PUT  /api/v1/app/player-profile (locked frame, answered 403 COSMETIC_LOCKED)
4. POST /api/v1/app/gift-codes/redeem (answered with grantedUnlocks)
Every request must carry X-API-Key and the player's Bearer session.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse


PORT = 18881
API_KEY = "project-key-881"
AUTHORIZATION = "Bearer session-token-881"
PROFILE_PATH = "/api/v1/app/player-profile"
REDEEM_PATH = "/api/v1/app/gift-codes/redeem"

CATALOG = [
    {"id": "avatar.zombie_07", "type": "avatar", "locked": False, "available": True},
    {"id": "badge.supporter", "type": "badge", "locked": True, "available": True},
    {"id": "frame.gold", "type": "frame", "locked": True, "available": False},
]


def profile_body(avatar_id, frame_id, badges):
    return {
        "userId": "user-881",
        "profile": {"avatarId": avatar_id, "frameId": frame_id, "badges": badges},
        "unlocks": ["badge.supporter"],
        "cosmetics": CATALOG,
        "limits": {"maxBadges": 3, "maxUnlocks": 25},
    }


# (method, path, expected query or None, expected JSON body or None, status, response body)
EXPECTED = [
    ("GET", PROFILE_PATH, {"userId": ["user-881"]}, None, 200, profile_body(None, None, [])),
    (
        "PUT",
        PROFILE_PATH,
        None,
        # frameId "" is dropped by the SDK: a missing slot clears it on the server.
        {"userId": "user-881", "avatarId": "avatar.zombie_07", "badges": ["badge.supporter"]},
        200,
        profile_body("avatar.zombie_07", None, ["badge.supporter"]),
    ),
    (
        "PUT",
        PROFILE_PATH,
        None,
        {"userId": "user-881", "frameId": "frame.gold", "badges": []},
        403,
        {
            "timestamp": "2026-09-29T02:10:00.123",
            "status": 403,
            "error": "Forbidden",
            "code": "COSMETIC_LOCKED",
            "message": "Cosmetic 'frame.gold' is locked for this player",
            "path": PROFILE_PATH,
        },
    ),
    (
        "POST",
        REDEEM_PATH,
        None,
        {"code": "SUPPORTER", "userId": "user-881"},
        200,
        {
            "success": True,
            "message": "Gift code redeemed successfully",
            "giftData": "{\"grants\": [\"badge.supporter\"]}",
            "grantedUnlocks": ["badge.supporter"],
        },
    ),
]


class ContractHandler(BaseHTTPRequestHandler):
    requests_seen = 0
    failure = None

    def do_GET(self):
        self._handle("GET")

    def do_PUT(self):
        self._handle("PUT")

    def do_POST(self):
        self._handle("POST")

    def _handle(self, method):
        index = type(self).requests_seen
        type(self).requests_seen += 1
        if index >= len(EXPECTED):
            self._reject(f"unexpected extra request {method} {self.path}")
            return

        exp_method, exp_path, exp_query, exp_body, status, response = EXPECTED[index]
        url = urlparse(self.path)
        mismatches = []
        if method != exp_method:
            mismatches.append(f"method={method!r}")
        if url.path != exp_path:
            mismatches.append(f"path={url.path!r}")
        if exp_query is not None and parse_qs(url.query) != exp_query:
            mismatches.append(f"query={url.query!r}")
        if self.headers.get("X-API-Key") != API_KEY:
            mismatches.append("missing or incorrect X-API-Key")
        if self.headers.get("Authorization") != AUTHORIZATION:
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
        self.end_headers()
        self.wfile.write(json.dumps(response).encode())

    def _reject(self, message):
        type(self).failure = message
        self.send_response(422)
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
    if ContractHandler.requests_seen != len(EXPECTED):
        print(f"expected {len(EXPECTED)} requests, saw {ContractHandler.requests_seen}", file=sys.stderr)
        return 1

    # Grace period in which the locally rejected calls (no session, too many badges,
    # invalid IDs) run. None of them may reach the server.
    server.timeout = 1.5
    server.handle_request()
    if ContractHandler.requests_seen != len(EXPECTED):
        print("a locally rejected player profile call reached the server", file=sys.stderr)
        return 1
    if ContractHandler.failure:
        print(ContractHandler.failure, file=sys.stderr)
        return 1

    print("Godot contract server observed the expected player profile requests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

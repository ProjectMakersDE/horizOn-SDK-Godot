#!/usr/bin/env python3
"""Contract server for the Godot anonymous auth transport test.

Since server v1.64.7 the server issues the anonymous token and rejects a
client token on signup with 400. Expects exactly these requests, in this
order, then no further request:
1. POST signup  {"type": "ANONYMOUS", "username": "player-896"} (no token),
   answered with the issued token and no access token
2. POST signin  with the issued token, answered with a session
3. POST signin  with the stored token (restoreAnonymousSession)
4. POST signup  {"type": "ANONYMOUS"} (the deprecated token argument is not
   sent), answered with a token and an access token: no signin follows
5. POST signup  {"type": "ANONYMOUS", "username": "no-token"}, answered
   without a token: the SDK fails and sends no signin
Every request carries X-API-Key and no Authorization header.
"""
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

from mock_http import report_rejection, send_json


PORT = 18896
API_KEY = "project-key-896"
SIGNUP_PATH = "/api/v1/app/user-management/signup"
SIGNIN_PATH = "/api/v1/app/user-management/signin"
USER_ID = "user-896"
# Server tokens: 24 random bytes, base64url without padding (32 characters).
TOKEN_ONE = "srvTokenOne_0123456789abcdefghij"
TOKEN_TWO = "srvTokenTwo-0123456789abcdefghij"


def signup_body(token, access_token=None, username="player-896"):
    body = {
        "userId": USER_ID, "username": username, "email": None,
        "googleId": None, "isAnonymous": True, "isVerified": True,
        "createdAt": "2026-09-29T20:00:00",
    }
    if token is not None:
        body["anonymousToken"] = token
    if access_token is not None:
        body["accessToken"] = access_token
    return body


def signin_body(access_token):
    # The signin response carries neither isAnonymous nor the token.
    return {
        "userId": USER_ID, "username": "player-896", "email": None,
        "accessToken": access_token, "authStatus": "AUTHENTICATED",
        "appleUserId": None, "isPrivateRelayEmail": False, "message": None,
    }


EXPECTED = [
    (SIGNUP_PATH, {"type": "ANONYMOUS", "username": "player-896"}, signup_body(TOKEN_ONE)),
    (SIGNIN_PATH, {"type": "ANONYMOUS", "anonymousToken": TOKEN_ONE}, signin_body("session-896-a")),
    (SIGNIN_PATH, {"type": "ANONYMOUS", "anonymousToken": TOKEN_ONE}, signin_body("session-896-b")),
    (SIGNUP_PATH, {"type": "ANONYMOUS"}, signup_body(TOKEN_TWO, "session-896-c", "")),
    (SIGNUP_PATH, {"type": "ANONYMOUS", "username": "no-token"}, signup_body(None, None, "no-token")),
]


class ContractHandler(BaseHTTPRequestHandler):
    requests_seen = 0
    failure = None

    def do_POST(self):
        index = type(self).requests_seen
        type(self).requests_seen += 1
        if index >= len(EXPECTED):
            self._reject(f"unexpected extra request POST {self.path}")
            return

        exp_path, exp_body, response = EXPECTED[index]
        mismatches = []
        if self.path != exp_path:
            mismatches.append(f"path={self.path!r}")
        if self.headers.get("X-API-Key") != API_KEY:
            mismatches.append("missing or incorrect X-API-Key")
        if self.headers.get("Authorization") is not None:
            mismatches.append("unexpected Authorization header")
        if self.headers.get_content_type() != "application/json":
            mismatches.append(f"content-type={self.headers.get_content_type()!r}")
        content_length = int(self.headers.get("Content-Length", "0"))
        try:
            body = json.loads(self.rfile.read(content_length))
        except json.JSONDecodeError as error:
            mismatches.append(f"invalid JSON: {error}")
            body = None
        if body is not None and exp_path == SIGNUP_PATH and "anonymousToken" in body:
            # The server answers this with 400 "Anonymous token must be omitted".
            mismatches.append("signup must not send an anonymousToken")
        if body is not None and body != exp_body:
            mismatches.append(f"body={body!r}")

        if mismatches:
            self._reject(f"request {index + 1} (POST {exp_path}): " + ", ".join(mismatches))
            return

        send_json(self, 200, response)

    def _reject(self, message):
        type(self).failure = message
        report_rejection(message)
        send_json(self, 400, {"message": message})

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

    # Grace period: the failed signup without token must not be followed by a signin.
    server.timeout = 1.5
    server.handle_request()
    if ContractHandler.requests_seen != len(EXPECTED):
        print("an unexpected auth request reached the server", file=sys.stderr)
        return 1

    print("Godot contract server observed the expected anonymous auth requests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

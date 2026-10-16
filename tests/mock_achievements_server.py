#!/usr/bin/env python3
"""Bounded own-player achievement HTTP fixture on isolated Godot port 20108."""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from mock_http import report_rejection, send_json

USER = "00000000-0000-4000-8000-000000001008"
ENTRY = "message:00000000-0000-4000-8000-000000001008"
BASE = "/api/v1/app/achievements"
STAMP = "2026-10-16T12:00:00Z"


def definition(key, hidden=False, reward=0):
    return {"key": key, "name": key, "description": "Original achievement", "imageUrl": None,
            "hidden": hidden, "active": True, "mode": "manual" if hidden else "statistic",
            "condition": None if hidden else {"statisticKey": "kills", "threshold": 4294967296},
            "rewards": {"values": [{"key": "coins", "amount": reward}] if reward else []}}


def snapshot(revision, version, second, state=None, reward=13):
    progress = []
    definitions = [definition("first_steps")]
    if state:
        definitions.append(definition("manual_hidden", True, reward))
        progress.append({"key": "manual_hidden", "unlockedAt": STAMP, "rewardState": state,
                         "inboxEntryId": ENTRY if state == "delivered" else None,
                         "pendingReward": {"issuedAt": STAMP, "values": [{"key": "coins", "amount": 13}]} if state == "pending" else None})
    return {"userId": USER, "revision": revision, "definitionVersion": version * 64,
            "definitions": definitions, "progress": progress,
            "limits": {"maxDefinitions": 20, "maxLifetimeKeys": 500},
            "serverTime": "2026-10-16T12:00:%02dZ" % second}


def outcome(state):
    return {"key": "manual_hidden", "state": state,
            "inboxEntryId": ENTRY if state == "delivered" else None,
            "code": "INBOX_FULL" if state == "pending" else None}


def unlock(revision, version, second, replayed=False, state="pending"):
    return {"achievements": snapshot(revision, version, second, state),
            "newlyUnlocked": [] if replayed else ["manual_hidden"], "replayed": replayed,
            "deliveryResults": [outcome(state)]}


conditional = snapshot(0, "a", 2)
conditional["definitions"] = None
archived = snapshot(2, "e", 8, "delivered")
archived["definitions"] = []
invalid = snapshot(2, "e", 9, "delivered")
invalid["definitions"][0]["condition"]["threshold"] = "__fraction__"
invalid_wire = json.dumps(invalid).replace('"__fraction__"', "1.0000000000000001").encode()
QUERY = BASE + "?userId=" + USER
BODY = {"userId": USER, "key": "manual_hidden"}
DELIVER = {"userId": USER, "keys": ["manual_hidden"]}
EXPECTED = [
    ("GET", QUERY, None, 200, snapshot(0, "a", 1), 0),
    ("GET", QUERY + "&definitionVersion=" + "a" * 64, None, 200, conditional, 0),
    ("POST", BASE + "/unlock", BODY, 200, unlock(1, "b", 3), 0),
    ("POST", BASE + "/unlock", BODY, 200, unlock(1, "b", 4, True), 0),
    ("GET", QUERY + "&definitionVersion=" + "b" * 64, None, 200, snapshot(1, "c", 5, "pending", 99), 0),
    ("POST", BASE + "/rewards/deliver", DELIVER, 200,
     {"achievements": snapshot(2, "d", 6, "delivered", 99), "results": [outcome("delivered")]}, 0),
    ("POST", BASE + "/rewards/deliver", DELIVER, 200,
     {"achievements": snapshot(2, "d", 7, "delivered", 99), "results": [outcome("delivered")]}, 0),
    ("GET", QUERY + "&definitionVersion=" + "d" * 64, None, 200, archived, 0),
    ("GET", QUERY + "&definitionVersion=" + "e" * 64, None, 200, invalid_wire, 0),
    ("GET", QUERY + "&definitionVersion=" + "e" * 64, None, 200, snapshot(3, "f", 10, "delivered"), .12),
    ("POST", BASE + "/unlock", BODY, 503, {"message": "unknown response"}, 0),
    ("POST", BASE + "/unlock", BODY, 200, unlock(3, "f", 12, True, "delivered"), 0),
]


class Handler(BaseHTTPRequestHandler):
    seen = 0
    failure = None

    def do_GET(self): self.handle_case("GET")
    def do_POST(self): self.handle_case("POST")

    def handle_case(self, method):
        index = type(self).seen
        type(self).seen += 1
        if index >= len(EXPECTED): return self.reject("unexpected extra request")
        verb, path, body, status, result, delay = EXPECTED[index]
        actual = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0)))) if method == "POST" else None
        if (method, self.path, actual) != (verb, path, body): return self.reject("route/body/original key changed at request %d" % index)
        if self.headers.get("X-API-Key") != "achievement-key" or self.headers.get("Authorization") != "Bearer achievement-session":
            return self.reject("session/project header changed")
        if delay: time.sleep(delay)
        send_json(self, status, result)

    def reject(self, message):
        type(self).failure = message
        report_rejection(message)
        send_json(self, 422, {"message": message})

    def log_message(self, *_args): pass


server = HTTPServer(("127.0.0.1", 20108), Handler)
server.timeout = 12
if os.environ.get("MOCK_SERVER_READY_FILE"):
    with open(os.environ["MOCK_SERVER_READY_FILE"], "w") as ready: ready.write("ready")
for _ in EXPECTED: server.handle_request()
server.timeout = 1.5
server.handle_request()
if Handler.failure or Handler.seen != len(EXPECTED):
    print(Handler.failure or "Expected 12 achievement requests, got %d" % Handler.seen, file=sys.stderr)
    sys.exit(1)
print("Godot Achievements fixture observed 12 exact requests, player-specific conditional versions, original pending rewards and permanent-key retry")

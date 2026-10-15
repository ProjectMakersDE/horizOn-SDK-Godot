#!/usr/bin/env python3
"""Assert exact authenticated Inbox transport. All data is local and disposable."""
import copy
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse
from mock_http import report_rejection, send_json

USER = "00000000-0000-4000-8000-000000001006"
ENTRY = "message:" + USER
ROOT = "/api/v1/app/inbox"

def snapshot(revision=1, cursor="cursor-one", second=10):
    return {"userId": USER, "cursor": cursor, "revision": revision, "broadcastRevision": 1,
            "serverTime": f"2026-10-16T12:00:{second:02d}Z", "pollAfterSeconds": 120,
            "unchanged": False, "entries": [{"id": ENTRY, "kind": "message", "type": "reward",
            "reference": "fixture", "textKey": "inbox.reward", "parameters": {"amount": 'text: "amount":9007199254740992'},
            "createdAt": "2026-10-15T12:00:00Z", "expiresAt": "2026-10-16T12:00:11Z",
            "overdue": False, "read": False, "claimed": False,
            "attachment": {"values": [{"key": "coins", "amount": 9007199254740991}]}}],
            "counts": {"reward": {"total": 1, "unread": 1, "claimable": 1}},
            "limits": {"targeted": 50, "broadcasts": 20}}

first = snapshot()
unchanged = snapshot(second=11)
unchanged.update(unchanged=True, entries=[])
expired = snapshot(cursor="expired", second=12)
expired["entries"][0]["overdue"] = True
read = snapshot(2, "read", 13)
read["entries"][0]["read"] = True
claimed = snapshot(3, "claimed", 14)
claimed["entries"][0].update(read=True, claimed=True)
values = {"userId": USER, "revision": 7, "definitionVersion": 1, "day": "2026-10-16",
          "values": [{"key": "coins", "balance": 9007199254740991, "earnedToday": 0, "dailyCap": None}],
          "operationWindow": {"serverTime": "2026-10-16T12:00:14Z", "oldestAcceptedAt": "2026-09-16T12:00:00Z"}}
claim = {"entryId": ENTRY, "replayed": False, "inbox": claimed, "playerValues": values}
replay = copy.deepcopy(claim)
replay["replayed"] = True
replay["inbox"]["serverTime"] = "2026-10-16T12:00:15Z"
replay["playerValues"]["operationWindow"]["serverTime"] = "2026-10-16T12:00:15Z"
EXPECTED = [
    ("GET", ROOT, {"userId": [USER]}, None, 200, first),
    ("GET", ROOT, {"userId": [USER], "since": ["cursor-one"]}, None, 200, unchanged),
    ("GET", ROOT, {"userId": [USER], "since": ["cursor-one"]}, None, 200, expired),
    ("POST", ROOT + "/read", {}, {"userId": USER, "entryId": ENTRY}, 200, read),
    ("POST", ROOT + "/claim", {}, {"userId": USER, "entryId": ENTRY}, 200, claim),
    ("POST", ROOT + "/claim", {}, {"userId": USER, "entryId": ENTRY}, 200, replay),
    ("POST", ROOT + "/remove", {}, {"userId": USER, "entryId": ENTRY}, 409,
     {"code": "UNCLAIMED_REWARD", "message": "Claim first"}),
]

class Handler(BaseHTTPRequestHandler):
    count = 0
    failed = False

    def do_GET(self):
        self.handle_contract("GET")

    def do_POST(self):
        self.handle_contract("POST")

    def handle_contract(self, method):
        index = type(self).count
        type(self).count += 1
        errors = []
        if index >= len(EXPECTED):
            errors.append("Unexpected request after local rejection")
        else:
            verb, path, query, body, status, response = EXPECTED[index]
            url = urlparse(self.path)
            if (method, url.path, parse_qs(url.query)) != (verb, path, query):
                errors.append(f"Unexpected route {method} {self.path}")
            if self.headers.get("X-API-Key") != "inbox-project" or self.headers.get("Authorization") != "Bearer inbox-session":
                errors.append("Incorrect project/session headers")
            if body is not None and json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0")))) != body:
                errors.append("Incorrect action payload")
        if errors:
            type(self).failed = True
            report_rejection("; ".join(errors))
            send_json(self, 422, {"message": errors[0]})
        else:
            send_json(self, status, response)

    def log_message(self, *_args):
        pass

def main():
    with HTTPServer(("127.0.0.1", 18906), Handler) as server:
        if os.environ.get("MOCK_SERVER_READY_FILE"):
            with open(os.environ["MOCK_SERVER_READY_FILE"], "w") as ready:
                ready.write("ready\n")
        server.timeout = 10
        for _ in EXPECTED:
            server.handle_request()
        server.timeout = 1.5
        server.handle_request()
    if Handler.failed or Handler.count != len(EXPECTED):
        return 1
    print("Godot Inbox mock observed all seven exact REST requests")
    return 0

if __name__ == "__main__":
    sys.exit(main())

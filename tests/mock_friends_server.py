#!/usr/bin/env python3
"""Exact Friends HTTP contract, on the Godot-only loopback port 20109."""
import base64
import copy
import json
import os
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from mock_http import report_rejection, send_json

def user(index): return "00000000-0000-4000-8000-%012d" % index

A, B, C, D, E, F, G, H = [user(index) for index in range(1009, 1017)]
R1, R2, R3, R4 = [user(index) for index in range(2001, 2005)]
R = 4294967296
BASE = "/api/v1/app/friends"
STAMP = "2026-10-16T12:00:00Z"

def code(player): return "H-" + base64.urlsafe_b64encode(uuid.UUID(player).bytes).decode().rstrip("=")

def display(): return {"name": None, "profile": {"avatarId": "avatar.basic", "frameId": None, "badges": ["first_steps"]}}

def friend(player): return {"userId": player, "since": STAMP, "display": display(), "lastActiveAt": None}

def request(player, request_id): return {"userId": player, "requestId": request_id, "createdAt": STAMP, "display": display()}

def block(player): return {"userId": player, "blockedAt": STAMP, "email": "must-not-be-forwarded", "lastActiveAt": STAMP}

def snapshot(revision, second, player=A, friends=None, incoming=None, outgoing=None, blocked=None):
    return {"userId": player, "revision": revision, "friendCode": code(player),
            "friends": friends or [], "incoming": incoming or [], "outgoing": outgoing or [], "blocked": blocked or [],
            "limits": {"maxFriends": 20, "maxIncomingRequests": 20, "maxOutgoingRequests": 20, "maxBlocked": 100},
            "serverTime": "2026-10-16T12:00:%02dZ" % second}

def body(target, revision, request_id=None):
    result = {"userId": A, "targetUserId": target, "expectedRevision": revision}
    if request_id is not None: result["requestId"] = request_id
    return result

query = BASE + "?userId=" + A
found = {"userId": B, "friendCode": code(B), "display": display(), "blocked": [block(E)], "email": "private"}
s0 = snapshot(R, 1, friends=[friend(B)], incoming=[request(C, R1), request(G, R4)], outgoing=[request(D, R2)], blocked=[block(E)])
s1 = copy.deepcopy(s0); s1.update(revision=R+1, serverTime="2026-10-16T12:00:03Z"); s1["outgoing"].append(request(F, R3))
s2 = copy.deepcopy(s1); s2.update(revision=R+2, serverTime="2026-10-16T12:00:04Z", incoming=[request(G, R4)]); s2["friends"].append(friend(C))
s3 = copy.deepcopy(s2); s3.update(revision=R+3, serverTime="2026-10-16T12:00:05Z", incoming=[])
s4 = copy.deepcopy(s3); s4.update(revision=R+4, serverTime="2026-10-16T12:00:06Z", outgoing=[request(F, R3)])
s5 = copy.deepcopy(s4); s5.update(revision=R+5, serverTime="2026-10-16T12:00:07Z", friends=[friend(C)])
s6 = copy.deepcopy(s5); s6.update(revision=R+6, serverTime="2026-10-16T12:00:08Z", friends=[], blocked=[block(E), block(C)])
s7 = copy.deepcopy(s6); s7.update(revision=R+7, serverTime="2026-10-16T12:00:09Z", blocked=[block(C)])
s8 = copy.deepcopy(s7); s8.update(revision=R+8, serverTime="2026-10-16T12:00:11Z", outgoing=[request(F, R3), request(H, R4)])
s9 = copy.deepcopy(s8); s9.update(revision=R+9, serverTime="2026-10-16T12:00:15Z", outgoing=[request(H, R4)])
EXPECTED = [
    ("GET", query, None, 200, s0, 0),
    ("GET", BASE + "/find?userId=" + A + "&query=" + code(B), None, 200, found, 0),
    ("POST", BASE + "/request", body(F, R), 200, s1, 0),
    ("POST", BASE + "/accept", body(C, R+1, R1), 200, s2, 0),
    ("POST", BASE + "/decline", body(G, R+2, R4), 200, s3, 0),
    ("POST", BASE + "/cancel", body(D, R+3, R2), 200, s4, 0),
    ("POST", BASE + "/remove", body(B, R+4), 200, s5, 0),
    ("POST", BASE + "/block", body(C, R+5), 200, s6, 0),
    ("POST", BASE + "/unblock", body(E, R+6), 200, s7, 0),
    ("POST", BASE + "/request", body(H, R+7), 503, {"message": "uncertain write"}, 0),
    ("GET", query, None, 200, s8, 0),
    ("POST", BASE + "/cancel", body(F, R+8, R3), 429, {}, 0),
    ("GET", query, None, 200, s8, 0),
    ("POST", BASE + "/cancel", body(F, R+8, R3), 200, s9, 1.4),
    ("GET", query, None, 200, s9, 0),
    ("GET", query, None, 200, s9, .12),
    ("GET", BASE + "?userId=" + B, None, 200, snapshot(0, 1, B), 0),
]

class Handler(BaseHTTPRequestHandler):
    seen = 0
    failure = None

    def do_GET(self): self.handle_case("GET")
    def do_POST(self): self.handle_case("POST")

    def handle_case(self, method):
        index = type(self).seen
        type(self).seen += 1
        if index >= len(EXPECTED): return self.reject("unexpected Friends retry/extra request")
        verb, path, expected_body, status, result, delay = EXPECTED[index]
        actual = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0)))) if method == "POST" else None
        if (method, self.path, actual) != (verb, path, expected_body): return self.reject("original route/revision/requestId changed at request %d" % index)
        token = "friend-session-b" if index == 16 else "friend-session-a"
        if self.headers.get("X-API-Key") != "friends-key" or self.headers.get("Authorization") != "Bearer " + token:
            return self.reject("wrong original project/session header")
        if delay: time.sleep(delay)
        try: send_json(self, status, result, {"Retry-After": "1"} if status == 429 else None)
        except (BrokenPipeError, ConnectionResetError):
            if index != 13: self.reject("unexpected disconnected response")

    def reject(self, message):
        type(self).failure = message
        report_rejection(message)
        try: send_json(self, 422, {"message": message})
        except (BrokenPipeError, ConnectionResetError): pass

    def log_message(self, *_args): pass

server = ThreadingHTTPServer(("127.0.0.1", 20109), Handler)
server.timeout = 12
if os.environ.get("MOCK_SERVER_READY_FILE"):
    with open(os.environ["MOCK_SERVER_READY_FILE"], "w") as ready: ready.write("ready")
for _ in EXPECTED: server.handle_request()
server.timeout = 1.5
server.handle_request()
server.server_close()
if Handler.failure or Handler.seen != len(EXPECTED):
    print(Handler.failure or "Expected 17 Friends requests, got %d" % Handler.seen, file=sys.stderr)
    sys.exit(1)
print("Godot Friends fixture observed 17 exact HTTP requests, seven routes, original revision/requestId, single 503/429/timeout attempts and separate player sessions")

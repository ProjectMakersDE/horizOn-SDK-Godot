#!/usr/bin/env python3
"""Exact REST contract for TASK-1004 Godot, including stale response races."""
import json, os, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlparse
from mock_http import report_rejection, send_json
PORT=18905
API_KEY="fixture-key-1004"
AUTHORIZATION="Bearer fixture-session-1004"
USER="00000000-0000-4000-8000-000000001004"
ROOT="/api/v1/app/player-values"
OP="1792065600000:00000000-0000-4000-8000-000000001004"
def state(revision, definition=1, second=10):
 return {"userId":USER,"definitionVersion":definition,"revision":revision,"day":"2026-10-15","values":[{"key":"gold","balance":9007199254740991,"earnedToday":0,"dailyCap":None},{"key":"energy","balance":0,"earnedToday":0,"dailyCap":0}],"operationWindow":{"serverTime":f"2026-10-15T12:00:{second:02d}Z","oldestAcceptedAt":"2026-09-15T12:00:00Z"}}
def offers(definition, second):
 return {"definitionVersion":definition,"serverTime":f"2026-10-15T12:00:{second:02d}Z","definitions":state(1)["values"],"offers":[{"key":"energy-pack","name":"Energy","active":True,"costs":[{"key":"gold","amount":9007199254740991}],"rewards":[],"purchasesPerDay":None}]}
GET=lambda value:("GET",ROOT,{"userId":[USER]},None,200,value)
OFFER=lambda version,second:("GET",ROOT+"/offers",{"userId":[USER]},None,200,offers(version,second))
EXPECTED=[GET(state(10)),OFFER(1,11),
 ("POST",ROOT+"/purchase",None,{"userId":USER,"offerKey":"energy-pack","operationId":OP},409,{"code":"OPERATION_EXPIRED","message":"Expired","state":state(11,1,12)}),
 ("POST",ROOT+"/adjust",None,{"userId":USER,"key":"gold","amount":-9007199254740991,"reason":"debug","operationId":OP.replace("1004","1005")},200,state(12,1,13)),
 GET(state(13,1,14)),GET(state(11,1,15)),OFFER(2,16),GET(state(11,2,17)),GET(state(14,2,14)),GET(state(14,2,18)),GET(state(15,2,19))]
DELAYS={4:.15,10:.15}
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

        time.sleep(DELAYS.get(index, 0))
        send_json(self, status, response)

    def _reject(self, message):
        type(self).failure = message
        report_rejection(message)
        send_json(self, 422, {"message": message})

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
        print("a locally rejected player values call reached the server", file=sys.stderr)
        return 1
    if ContractHandler.failure:
        print(ContractHandler.failure, file=sys.stderr)
        return 1

    print("Godot contract server observed the expected player values requests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

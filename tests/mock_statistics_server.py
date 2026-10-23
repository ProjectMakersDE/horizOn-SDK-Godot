"""Exact JSON-number, bearer, replay and delayed-snapshot loopback contract for TASK-1005."""
import json
import os
import re
import sys
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
from mock_http import send_json, report_rejection

PORT = 18805
MAX = 9007199254740991
utc = datetime.now(timezone.utc)
MONDAY = int((utc.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=7-utc.weekday(), seconds=1)).timestamp()*1000)
DEFINITIONS = [{"key": "kills", "name": "Kills", "mode": "sum", "reset": "none"}]

def snapshot(revision, value, version=1, definitions=True, at=None, operation=None, replay=False):
    result = {"userId": "statistics-user", "definitionVersion": version, "definitions": DEFINITIONS if definitions else None,
              "revision": revision, "values": [{"key": "kills", "value": value, "hasValue": True, "period": None}],
              "operationWindow": {"serverTimeUnixMillis": at or int(time.time()*1000), "maxAgeSeconds":86400, "maxFutureSkewSeconds":30}, "newlyUnlocked": []}
    if operation: result.update(operationId=operation, replayed=replay)
    return result

class Contract(BaseHTTPRequestHandler):
    count = 0
    failure = None
    operation = None
    lock = threading.Lock()
    def log_message(self, *_args): pass
    def do_GET(self): self.handle_step("GET")
    def do_POST(self): self.handle_step("POST")
    def handle_step(self, method):
        with self.lock:
            step = type(self).count + 1
            type(self).count = step
        try:
            assert step <= 18, "unexpected extra request after scope change"
            assert self.headers.get("X-API-Key") == "project-statistics", "project key"
            token = "fresh-session" if step >= 13 else "statistics-session"
            assert self.headers.get("Authorization") == "Bearer " + token, "bearer session"
            url = urlparse(self.path)
            query = parse_qs(url.query)
            if step in (17, 18):
                assert method == "POST" and url.path == "/api/v1/app/statistics"
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
                assert body["userId"] == "statistics-user"
                assert body["updates"] == [{"key": f"stat{i}", "value": i} for i in range(201)]
                if step == 17: type(self).operation = body["operationId"]
                assert body["operationId"] == type(self).operation, "large replay keeps original ID"
                result = snapshot(4, 0, version=3 if step == 17 else 4, at=MONDAY+3,
                                  operation=body["operationId"], replay=step == 18)
                if step == 17:
                    result["definitions"] = [{"key": f"stat{i}", "name": "Stat", "mode": "sum", "reset": "none"} for i in range(201)]
                    result["values"] = [{"key": f"stat{i}", "value": i, "hasValue": True, "period": None} for i in range(201)]
                send_json(self, 200, result)
                return
            if step in (3,4,5,14,15,16):
                assert method == "POST" and url.path == "/api/v1/app/statistics", "POST path"
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", "0"))))
                assert body.get("userId") == "statistics-user", "player ID"
                operation = body.get("operationId")
                assert isinstance(operation, str) and re.fullmatch(r"[0-9]{13}:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}", operation), "timestamp UUIDv4"
                if step in (3,14,16): type(self).operation = operation
                assert operation == type(self).operation, "original operation ID preserved"
                value = MAX if step in (3,4,14,15) else 1
                assert body.get("updates") == [{"key":"kills", "value":value}], "exact update payload"
                assert type(body["updates"][0]["value"]) is int, "JSON value must be integer, not float/string"
                if step in (14,16): send_json(self,503,{"message":"retry original request"})
                elif step == 15: send_json(self,200,snapshot(2,MAX,2,at=MONDAY+2,operation=operation))
                elif step == 5: send_json(self,409,{"code":"OPERATION_CONFLICT","message":"conflict"})
                else: send_json(self,200,snapshot(3,MAX,operation=operation,replay=step==4))
                return
            assert method == "GET", "GET method"
            if step == 6:
                assert url.path == "/api/v1/app/statistics/definitions" and query == {"definitionVersion":["1"]}, "conditional definitions"
                send_json(self,200,{"definitionVersion":2,"definitions":DEFINITIONS})
                return
            expected_query = {"userId":["statistics-user"]}
            if step in (2,7,8,9,10,12): expected_query["definitionVersion"]=["1" if step==2 else "2"]
            assert url.path == "/api/v1/app/statistics" and query == expected_query, "snapshot query " + str(query)
            if step == 1: result=snapshot(1,-MAX)
            elif step == 2: result=snapshot(2,2,definitions=False)
            elif step == 7: result=snapshot(2,99,2)
            elif step == 8: result=snapshot(3,3,2,at=MONDAY)
            elif step == 9: result=snapshot(3,99,2,at=MONDAY-2000)
            elif step == 10:
                time.sleep(.25)
                result=snapshot(3,3,2,definitions=False,at=MONDAY)
            elif step == 11: result=snapshot(3,3,2,at=MONDAY)
            elif step == 12:
                time.sleep(.4)
                result=snapshot(99,99,2,at=MONDAY+2)
            elif step == 13: result=snapshot(1,9,2,at=MONDAY+1)
            else: raise AssertionError("unexpected step")
            send_json(self,200,result)
        except Exception as error:
            type(self).failure = f"request {step}: {error}"
            report_rejection(type(self).failure)
            send_json(self,422,{"code":"CONTRACT_MISMATCH","message":str(error)})

def main():
    server=ThreadingHTTPServer(("127.0.0.1",PORT),Contract)
    ready=os.environ.get("MOCK_SERVER_READY_FILE")
    if ready:
        with open(ready,"w") as handle: handle.write("ready\n")
    server.timeout=10
    for _ in range(18): server.handle_request()
    server.timeout=1
    server.handle_request()
    server.server_close()
    if Contract.count != 18 or Contract.failure:
        print(Contract.failure or f"expected 18 requests, saw {Contract.count}",file=sys.stderr)
        return 1
    print("Godot statistics server observed exact integer, scope and stable retry contract")
    return 0

if __name__ == "__main__": raise SystemExit(main())

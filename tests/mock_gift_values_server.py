#!/usr/bin/env python3
"""Authenticated loopback only. A successful first booking loses its response, then replays."""
import json,os,sys,time
from http.server import BaseHTTPRequestHandler,HTTPServer
from mock_http import send_json,report_rejection
USER="00000000-0000-4000-8000-000000001007"
BASE="/api/v1/app/gift-codes/redeem"
def state(rev=2,balance=4294967296):
 return {"userId":USER,"definitionVersion":1,"revision":rev,"day":"2026-10-16","values":[{"key":"1.coin","balance":balance,"earnedToday":0,"dailyCap":None}],"operationWindow":{"serverTime":f"2026-10-16T12:00:{rev:02d}Z","oldestAcceptedAt":"2026-09-16T12:00:00Z"}}
def reply(rev=2,balance=4294967296,grant=4294967296,replayed=False):
 return {"success":True,"message":"ok","giftData":"{\"gold\":13}","grantedUnlocks":[],"grantedValues":[{"key":"1.coin","amount":grant}],"playerValues":state(rev,balance),"replayed":replayed}
def body(code,n):
 d={"code":code,"userId":USER}
 if n is not None:d["idempotencyId"]=n if isinstance(n,str) else f"00000000-0000-4000-8000-{n:012d}"
 return d
first=reply();first["grantedUnlocks"]=["badge.tester"]
wrong=reply(5);wrong["playerValues"]["userId"]="00000000-0000-4000-8000-000000999999"
escaped_amount=json.dumps(reply(5)).replace('"amount": 4294967296',r'"am\u006funt":1.0000000000000001').encode()
escaped_balance=json.dumps(reply(5)).replace('"balance": 4294967296',r'"bal\u0061nce":4294967296.0000000001').encode()
duplicate=json.dumps(reply(5)).replace('"amount": 4294967296',r'"amount":1,"am\u006funt":2').encode()
assert b'\\u006f' in escaped_amount and json.loads(escaped_amount)["grantedValues"][0]["amount"]==1.0
assert b'\\u0061' in escaped_balance
EXPECTED=[
 ("VALUES",1,200,first,0),
 ("VALUES",1,200,reply(3,4294967297,replayed=True),0),
 ("PARSED",2,200,{"success":True,"message":"ok","giftData":"{\"gold\":13}"},0),
 ("NULL",3,200,{"success":True,"message":"ok","giftData":None},0),
 ("BOUNDARY","x"*128,200,{"success":True,"message":"ok","giftData":""},0),
 ("UNICODE","😀"*64,200,{"success":True,"message":"ok","giftData":""},0),
 ("MAX",4,422,{"code":"MAX_BALANCE_REACHED","message":"Not booked"},0),
 ("LEGACY",None,503,{"message":"Outcome unknown"},0),
 ("RETRY",5,503,{"message":"Booked, response lost"},0),
 ("RETRY",5,200,reply(4,9007199254740991,9007199254740991,True),0),
 ("OPAQUE",16,200,{"success":True,"message":"ok","giftData":'{"amount":1.0000000000000001}'},0),
 ("ESCAPED_AMOUNT",17,200,escaped_amount,0),
 ("ESCAPED_BALANCE",18,200,escaped_balance,0),
 ("DUPLICATE",19,200,duplicate,0),
 ("FRACTION",6,200,reply(5,9007199254740991,1.0),0),
 ("STRING",7,200,reply(5,9007199254740991,"1"),0),
 ("UNSAFE",8,200,reply(5,9007199254740991,9007199254740992),0),
 ("WRONG",9,200,wrong,0),
 ("OLD",10,200,reply(2),0),
 ("LEGACYCACHE",None,200,{"success":True,"message":"ok","giftData":'{"legacy":true}',"grantedUnlocks":["badge.second"]},.15),
 ("CACHE",11,200,reply(5),.15),
 ("SESSION",12,200,reply(5),.15),
 ("ABA",13,200,reply(5),.15),
 ("HOSTABA",20,200,reply(5),.15),
 ("PROJECTABA",21,200,reply(5),.15),
 ("TOKENABA",22,200,reply(5),.15),
 ("BACKOFF",14,503,{"message":"Outcome unknown"},0),
 ("BACKOFFABA",23,503,{"message":"Outcome unknown"},0),
]
class Handler(BaseHTTPRequestHandler):
 seen=0;failure=None
 def do_POST(self):
  index=type(self).seen;type(self).seen+=1
  if index>=len(EXPECTED):return self.reject("unexpected retry")
  code,n,status,response,delay=EXPECTED[index]
  actual=json.loads(self.rfile.read(int(self.headers.get("Content-Length",0))))
  if self.path!=BASE or actual!=body(code,n) or self.headers.get("X-API-Key")!="fixture-key-1007" or self.headers.get("Authorization")!="Bearer fixture-session-1007":return self.reject(f"request{index}: unexpected path/body/auth")
  time.sleep(delay);send_json(self,status,response)
 def reject(self,message):
  type(self).failure=message;report_rejection(message);send_json(self,422,{"message":message})
 def log_message(self,*args):pass
server=HTTPServer(("127.0.0.1",18907),Handler);server.timeout=10
if os.environ.get("MOCK_SERVER_READY_FILE"):open(os.environ["MOCK_SERVER_READY_FILE"],"w").write("ready")
for _ in EXPECTED:server.handle_request()
server.timeout=1.5;server.handle_request()
if Handler.failure or Handler.seen!=len(EXPECTED):print(Handler.failure or f"Expected{len(EXPECTED)},got{Handler.seen}",file=sys.stderr);sys.exit(1)
print(f"Godot gift values fixture observed{Handler.seen} exact requests, stable replay ID and no legacy/session retry")

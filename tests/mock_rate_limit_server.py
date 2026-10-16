#!/usr/bin/env python3
"""Only task996 loopback port20096; original request snapshots survive delayed retries."""
import json,os,sys,time
from http.server import BaseHTTPRequestHandler,HTTPServer
from mock_http import report_rejection,send_json
USER="00000000-0000-4000-8000-000000000996"
POST={"userId":USER,"operationId":"1792152000000:00000000-0000-4000-8000-000000000996","updates":[{"key":"kills","value":3}]}
CONTEXT={**POST,"operationId":"1792152000000:00000000-0000-4000-8000-000000000997"}
EXPECTED=[
 ("GET","/api/v1/app/news?case=read",None,429,{"message":"slow"},1),
 ("GET","/api/v1/app/news?case=read",None,200,{"ok":True},None),
 ("POST","/api/v1/app/statistics",POST,429,{},1),
 ("POST","/api/v1/app/statistics",POST,200,{"ok":True},None),
 ("GET","/api/v1/app/news?case=feature",None,429,{"code":"CUSTOM_FUTURE_FEATURE","message":"limited"},60),
 ("GET","/api/v1/app/news?case=feature_lower",None,429,{"code":"future_soft_limit","message":"limited"},60),
 ("GET","/api/v1/app/news?case=exhaust",None,429,{},1),
 ("GET","/api/v1/app/news?case=exhaust",None,429,{},1),
 ("POST","/api/v1/app/statistics",CONTEXT,429,{},1),
]
class Handler(BaseHTTPRequestHandler):
 seen=0;failure=None;times=[]
 def do_GET(self):self.handle_case("GET")
 def do_POST(self):self.handle_case("POST")
 def handle_case(self,method):
  n=type(self).seen;type(self).seen+=1;type(self).times.append(time.monotonic())
  if n>=len(EXPECTED):return self.reject("unexpected additional retry")
  verb,path,body,status,result,retry_after=EXPECTED[n]
  actual=json.loads(self.rfile.read(int(self.headers.get("Content-Length",0)))) if method=="POST" else None
  if (method,self.path,actual)!=(verb,path,body) or self.headers.get("X-API-Key")!="rate-key" or self.headers.get("Authorization")!="Bearer rate-session":return self.reject(f"request{n}: method/path/original body/header changed")
  if n in [1,3,7] and type(self).times[n]-type(self).times[n-1]<1.0:return self.reject("retried before Retry-After")
  send_json(self,status,result,{"Retry-After":str(retry_after)} if retry_after is not None else None)
 def reject(self,message):
  type(self).failure=message;report_rejection(message);send_json(self,422,{"message":message})
 def log_message(self,*args):pass
server=HTTPServer(("127.0.0.1",20096),Handler);server.timeout=12
if os.environ.get("MOCK_SERVER_READY_FILE"):open(os.environ["MOCK_SERVER_READY_FILE"],"w").write("ready")
for _ in EXPECTED:server.handle_request()
server.timeout=1.5;server.handle_request()
if Handler.failure or Handler.seen!=len(EXPECTED):print(Handler.failure or f"Expected{len(EXPECTED)} HTTP requests,got{Handler.seen}",file=sys.stderr);sys.exit(1)
print("Godot rate-limit fixture:9 exact requests, Retry-After minimums, unchanged mutation/header, immediate feature errors, bounded attempts and no ABA resend")

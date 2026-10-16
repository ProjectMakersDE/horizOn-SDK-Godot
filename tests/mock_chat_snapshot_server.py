#!/usr/bin/env python3
"""Explicit disconnected Chat reads: exact one-attempt HTTP and original identity fences."""
import copy,json,os,threading,time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from mock_http import send_json,report_rejection
U="00000000-0000-4000-8000-000000001014";C="00000000-0000-4000-8000-000000003014";E="00000000-0000-4000-8000-000000004014"
M="00000000-0000-4000-8000-000000008014";E2="00000000-0000-4000-8000-000000004015"
T="2026-10-16T12:00:00.000Z";X="2026-10-23T12:00:00.000Z"
finished=threading.Event();state={"count":0,"failure":None};lock=threading.Lock()
def fail(message):state["failure"]=message;report_rejection(message)
class HTTP(BaseHTTPRequestHandler):
 def do_GET(self):
  if self.path=="/fixture/status":return send_json(self,200,state.copy())
  if self.path=="/fixture/finish":
   send_json(self,200,state.copy());finished.set();return
  fail("unexpected GET "+self.path);send_json(self,404,{})
 def do_POST(self):
  try:
   body=json.loads(self.rfile.read(int(self.headers.get("Content-Length",0))))
   if self.path!="/api/v1/app/chat/channels/"+C+"/sync":raise ValueError("wrong snapshot path")
   if self.headers.get("X-API-Key")!="raw-chat-key" or self.headers.get("Authorization")!="Bearer raw-chat-session":raise ValueError("wrong original header identity")
   with lock:state["count"]+=1;n=state["count"]
   known=[M]if n in[2,8,10]else[];epoch=E if known else None
   if body!={"userId":U,"epoch":epoch,"knownMessageIds":known}:raise ValueError("changed snapshot body "+str(n))
   if n>12:raise ValueError("unexpected automatic retry or background read")
   if n in[5,6,7,8]:time.sleep(.3)
   if n in[3,4,11]:return send_json(self,{3:503,4:501,11:401}[n],{"code":{3:"RAW_SNAPSHOT_FAULT",4:"NOT_SUPPORTED",11:"SESSION_REQUIRED"}[n],"message":"expected one-attempt fault"})
   channel={"id":C,"epoch":E2 if n==10 else E,"kind":"project","peerIds":[],"groupId":None,"revision":1,"expiresAt":X}
   message={"id":M,"channelId":C,"authorId":U,"text":"raw original é😀","createdAt":T,"expiresAt":X}
   messages=[]if n in[2,8,9]else[message]
   send_json(self,200,{"channel":channel,"visibleMessageIds":[M],"messages":messages,"moderation":{"muteUntil":None,"banUntil":None},"serverTime":T})
  except Exception as error:
   fail(str(error))
   try:send_json(self,422,{"message":str(error)})
   except OSError:pass
 def log_message(self,*args):pass
http=ThreadingHTTPServer(("127.0.0.1",int(os.environ.get("HORIZON_CHAT_SNAPSHOT_TEST_PORT","20116"))),HTTP);http.daemon_threads=True
threading.Thread(target=http.serve_forever,daemon=True).start()
if os.environ.get("MOCK_SERVER_READY_FILE"):
 with open(os.environ["MOCK_SERVER_READY_FILE"],"w")as ready:ready.write("ready")
finished.wait(45);http.shutdown();http.server_close()
if not finished.is_set():fail("fixture never finished")
if state["count"]!=12:fail("expected12 exact HTTP snapshots, got"+str(state["count"]))
if state["failure"]:raise SystemExit(1)
print("PASS: disconnected Chat snapshots12 exact HTTP, single503/501/401, original epoch/IDs/header bytes, no retry/background/cache adoption")

#!/usr/bin/env python3
import json,os,sys
from http.server import BaseHTTPRequestHandler,HTTPServer
from mock_http import send_json,report_rejection
class Handler(BaseHTTPRequestHandler):
 seen=0;failure=None
 def do_POST(self):
  n=type(self).seen;type(self).seen+=1
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
  want={0:('EMAIL','email'),1:('GOOGLE','googleAuthorizationCode'),2:('APPLE','appleIdentityToken')}.get(n)
  if self.path!='/api/v1/app/user-management/link' or self.headers.get('X-API-Key')!='link-fixture' or not want or body.get('type')!=want[0] or want[1] not in body or body.get('userId')!='guest-1' or body.get('sessionToken')!='session-1':
   type(self).failure='Unexpected link path/body/auth';report_rejection(type(self).failure);send_json(self,422,{'message':type(self).failure});return
  if n==0:send_json(self,409,{'error':'Email already in use'})
  elif n==1:send_json(self,200,{'userId':'guest-1','email':'g@example.invalid','googleId':'g-1','isPrivateRelayEmail':False,'isAnonymous':False,'isVerified':True,'authStatus':'AUTHENTICATED','message':'ok'})
  else:send_json(self,200,{'userId':'guest-1','appleUserId':'a-1','isPrivateRelayEmail':True,'isAnonymous':False,'isVerified':True,'authStatus':'AUTHENTICATED','message':'ok'})
 def log_message(self,*args):pass
server=HTTPServer(('127.0.0.1',18930),Handler);server.timeout=10
if os.environ.get('MOCK_SERVER_READY_FILE'):open(os.environ['MOCK_SERVER_READY_FILE'],'w').write('ready')
for _ in range(3):server.handle_request()
if Handler.failure or Handler.seen!=3:print(Handler.failure or f'Expected 3 link calls, got {Handler.seen}',file=sys.stderr);sys.exit(1)
print('Godot link fixture: link contract served')

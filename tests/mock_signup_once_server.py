#!/usr/bin/env python3
import json,os,sys,time
from http.server import BaseHTTPRequestHandler,HTTPServer
from mock_http import send_json,report_rejection
class Handler(BaseHTTPRequestHandler):
 seen=0;failure=None
 def do_POST(self):
  n=type(self).seen;type(self).seen+=1
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0))))
  if self.path!='/api/v1/app/user-management/signup' or self.headers.get('X-API-Key')!='signup-once-fixture' or n>=2 or body.get('type')!=('ANONYMOUS' if n==0 else 'EMAIL'):
   type(self).failure='Unexpected signup retry/body/auth';report_rejection(type(self).failure);send_json(self,422,{'message':type(self).failure});return
  if n==0:send_json(self,503,{'message':'Created, acknowledgement lost'})
  else:
   time.sleep(1.3)
   self.close_connection=True
 def log_message(self,*args):pass
server=HTTPServer(('127.0.0.1',18917),Handler);server.timeout=10
if os.environ.get('MOCK_SERVER_READY_FILE'):open(os.environ['MOCK_SERVER_READY_FILE'],'w').write('ready')
server.handle_request();server.handle_request();server.timeout=1.5;server.handle_request()
if Handler.failure or Handler.seen!=2:print(Handler.failure or f'Expected2 explicit signup calls,got{Handler.seen}',file=sys.stderr);sys.exit(1)
print('Godot signup fixture: exactly one request per explicit call after503/timeout, no generated-identity retry')

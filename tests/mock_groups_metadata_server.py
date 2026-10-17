#!/usr/bin/env python3
"""Tiny lossless Groups metadata transport, isolated loopback only."""
import json,os,socket,time
from http.server import HTTPServer,BaseHTTPRequestHandler
from urllib.parse import urlparse,parse_qs
from mock_http import send_json
U='00000000-0000-4000-8000-000000001016';G='00000000-0000-4000-8000-000000600001';T='2026-10-18T00:00:00Z'
L=dict(maxMembers=20,maxGroupsPerPlayer=2,maxInvitations=20,maxJoinRequests=20,maxDataBytes=2048,memberPageSize=50,maxPlayerInvitations=2,maxPlayerRequests=2,maxNameBytes=120,maxDescriptionBytes=1024,maxDataDepth=16)
def group(name,revision):return dict(id=G,revision=revision,name=name,description='d\0z',joinMode='open',leaderId=U,memberCount=1,myRole='leader',data={'x':9007199254740993},createdAt=T,updatedAt=T)
class Handler(BaseHTTPRequestHandler):
 index=0;failure=None;original=None
 def log_message(self,*_):pass
 def do_GET(self):self.case('GET')
 def do_PUT(self):self.case('PUT')
 def case(self,method):
  try:
   at=type(self).index;assert at<3
   p=urlparse(self.path)
   assert p.path=='/api/v1/app/groups/'+G and method==('GET'if at==0 else'PUT')
   assert self.headers.get('X-API-Key')=='metadata-key'and self.headers.get('Authorization')=='Bearer metadata-session'
   if at==0:
    assert parse_qs(p.query)=={'userId':[U]};body=group('a\0z',1)
   else:
    raw=self.rfile.read(int(self.headers['Content-Length']));value=json.loads(raw)
    assert value==dict(userId=U,expectedRevision=1,name='edited\0z',description='d\0z',joinMode='open',data={'x':9007199254740993})
    assert b'\\u0000'in raw and b'\xef\xbf\xbd'not in raw
    if at==1:type(self).original=raw
    else:assert raw==type(self).original,'Retry original changed'
    body=dict(group=group('edited\0z',2),groups=dict(userId=U,revision=2,groups=[group('edited\0z',2)],incomingInvites=[],outgoingRequests=[],limits=L,serverTime=T))
   type(self).index+=1
   if at==1:self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
   send_json(self,200,body)
  except Exception as error:type(self).failure=str(error);send_json(self,422,{'code':'FIXTURE_REJECTED'})
server=HTTPServer(('127.0.0.1',20118),Handler);server.timeout=.2
if os.environ.get('MOCK_SERVER_READY_FILE'):
 with open(os.environ['MOCK_SERVER_READY_FILE'],'w')as ready:ready.write('ready')
deadline=time.monotonic()+35
while Handler.index<3 and not Handler.failure and time.monotonic()<deadline:server.handle_request()
for _ in range(2):server.handle_request()
assert Handler.failure is None,Handler.failure
assert Handler.index==3,Handler.index
print('Groups NUL metadata exact original:3 HTTP passed')

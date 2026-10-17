#!/usr/bin/env python3
"""Actual sample default/continuation contract; isolated loopback only."""
import json,os,time
from http.server import HTTPServer,BaseHTTPRequestHandler
from urllib.parse import urlparse,parse_qs
from mock_http import send_json
U='00000000-0000-4000-8000-000000001016';G='00000000-0000-4000-8000-000000050000';P='00000000-0000-4000-8000-000000060000';T='2026-10-18T00:00:00Z'
L=dict(maxMembers=501,maxGroupsPerPlayer=6,maxInvitations=21,maxJoinRequests=21,maxDataBytes=8192,memberPageSize=51,maxPlayerInvitations=21,maxPlayerRequests=21,maxNameBytes=512,maxDescriptionBytes=4096,maxDataDepth=64)
def own(size):return dict(userId=U,revision=1,groups=[],incomingInvites=[],outgoingRequests=[],limits=dict(L,memberPageSize=size),serverTime=T)
def page(user=U,cursor=U,count=1):
 users=['00000000-0000-4000-8000-%012d'%n for n in range(1017-count,1017)]if count>1 else[user]
 return dict(groupId=G,revision=1,members=[dict(userId=value,role='member',joinedAt=T,display=dict(name=None,profile=dict(avatarId=None,frameId=None,badges=[])))for value in users],nextAfterUserId=cursor,serverTime=T)
CASES=[('',{},own(51),200),('/'+G+'/members',{'limit':['51']},page(count=51),200),('',{},own(1),200),('/'+G+'/members',{'limit':['1']},page(),200),('/'+G+'/members',{'limit':['1'],'afterUserId':[U]},page(P,None),200),('/'+G+'/members',{'limit':['7']},{'code':'INVALID_PAGE'},400)]
class Handler(BaseHTTPRequestHandler):
 index=0;failure=None
 def log_message(self,*_):pass
 def do_GET(self):
  try:
   at=type(self).index;assert at<len(CASES),'Unexpected extra request or retry'
   suffix,query,body,status=CASES[at];p=urlparse(self.path)
   assert p.path=='/api/v1/app/groups'+suffix and parse_qs(p.query)==dict(query,userId=[U]),(at,self.path)
   assert self.headers.get('X-API-Key')=='sample-key'and self.headers.get('Authorization')=='Bearer sample-session'
   type(self).index+=1
  except Exception as error:type(self).failure=str(error);body,status={'code':'FIXTURE_REJECTED'},422
  send_json(self,status,body)
server=HTTPServer(('127.0.0.1',20117),Handler);server.timeout=.2
if os.environ.get('MOCK_SERVER_READY_FILE'):
 with open(os.environ['MOCK_SERVER_READY_FILE'],'w')as ready:ready.write('ready')
deadline=time.monotonic()+30
while Handler.index<len(CASES)and not Handler.failure and time.monotonic()<deadline:server.handle_request()
for _ in range(4):server.handle_request()
assert Handler.failure is None,Handler.failure
assert Handler.index==len(CASES),(Handler.index,len(CASES))
print('Groups sample current-size51→1, cursor restart, exact explicit7 and auth no-request:6 HTTP passed')

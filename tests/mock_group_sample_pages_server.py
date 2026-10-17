#!/usr/bin/env python3
"""Actual sample pages and escaped aggregate responses; isolated loopback only."""
import json,os,time
from http.server import HTTPServer,BaseHTTPRequestHandler
from urllib.parse import urlparse,parse_qs
from mock_http import send_json
U='00000000-0000-4000-8000-000000001016';G='00000000-0000-4000-8000-000000050000';P='00000000-0000-4000-8000-000000060000';E='00000000-0000-4000-8000-000000600000';T='2026-10-18T00:00:00Z'
L=dict(maxMembers=501,maxGroupsPerPlayer=6,maxInvitations=21,maxJoinRequests=21,maxDataBytes=8192,memberPageSize=51,maxPlayerInvitations=21,maxPlayerRequests=21,maxNameBytes=512,maxDescriptionBytes=4096,maxDataDepth=64)
NAME='a'+'\x01'*(6*1024*1024)
def own(size):return dict(userId=U,revision=1,groups=[],incomingInvites=[],outgoingRequests=[],limits=dict(L,memberPageSize=size),serverTime=T)
def page(user=U,cursor=U,count=1):
 users=['00000000-0000-4000-8000-%012d'%n for n in range(1017-count,1017)]if count>1 else[user]
 return dict(groupId=G,revision=1,members=[dict(userId=value,role='member',joinedAt=T,display=dict(name=None,profile=dict(avatarId=None,frameId=None,badges=[])))for value in users],nextAfterUserId=cursor,serverTime=T)
def large_group(rev=1,id=E):return dict(id=id,revision=rev,name=NAME,description='',joinMode='open',leaderId=U,memberCount=1,createdAt=T,updatedAt=T,myRole='leader',data={})
def large_own(count=1,low=False):
 return dict(own(1),revision=2,groups=[large_group(2,id='00000000-0000-4000-8000-%012d'%(600000+i))for i in range(count)],limits=dict(L,maxGroupsPerPlayer=1 if low else 3,maxNameBytes=1 if low else len(NAME)))
def mutation(bad=False):
 g=large_group(2)
 if bad:g['revision']='invalid'
 return dict(groups=large_own(),group=g)
CASES=[('GET','',{},own(51),200),('GET','/'+G+'/members',{'limit':['51']},page(count=51),200),('GET','',{},own(1),200),('GET','/'+G+'/members',{'limit':['1']},page(),200),('GET','/'+G+'/members',{'limit':['1'],'afterUserId':[U]},page(P,None),200),('GET','/'+G+'/members',{'limit':['7']},{'code':'INVALID_PAGE'},400),('GET','/'+E,{},large_group(),200),('PUT','/'+E,{},mutation(True),200),('PUT','/'+E,{},mutation(),200),('GET','',{},large_own(3,True),200)]
class Handler(BaseHTTPRequestHandler):
 index=0;failure=None;original=None
 def log_message(self,*_):pass
 def do_GET(self):self.case('GET')
 def do_PUT(self):self.case('PUT')
 def case(self,method):
  try:
   at=type(self).index;assert at<len(CASES),'Unexpected extra request or retry'
   verb,suffix,query,body,status=CASES[at];p=urlparse(self.path)
   assert method==verb and p.path=='/api/v1/app/groups'+suffix and parse_qs(p.query)==(dict(query,userId=[U])if method=='GET'else{}),(at,method,self.path)
   assert self.headers.get('X-API-Key')=='sample-key'and self.headers.get('Authorization')=='Bearer sample-session'
   if method=='PUT':
    raw=self.rfile.read(int(self.headers['Content-Length']));value=json.loads(raw)
    assert value==dict(userId=U,expectedRevision=1,name=NAME,description='',joinMode='open',data={}), 'Original large update tuple changed'
    if type(self).original is None:type(self).original=raw
    else:assert type(self).original==raw,'Uncertain original bytes changed'
   encoded=json.dumps(body).encode()
   if at>=6:print('Escaped response case%d: %d UTF8 bytes'%(at,len(encoded)),flush=True)
   type(self).index+=1
  except Exception as error:type(self).failure=str(error);body,status={'code':'FIXTURE_REJECTED'},422
  send_json(self,status,body)
server=HTTPServer(('127.0.0.1',20117),Handler);server.timeout=.2
if os.environ.get('MOCK_SERVER_READY_FILE'):
 with open(os.environ['MOCK_SERVER_READY_FILE'],'w')as ready:ready.write('ready')
deadline=time.monotonic()+240
while Handler.index<len(CASES)and not Handler.failure and time.monotonic()<deadline:server.handle_request()
for _ in range(4):server.handle_request()
assert Handler.failure is None,Handler.failure
assert Handler.index==len(CASES),(Handler.index,len(CASES))
print('Groups sample pages and escaped36/72/108MiB actual responses:10 HTTP passed')

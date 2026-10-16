#!/usr/bin/env python3
"""Exact Shared Objects fixture: seven routes, headers, opaque bytes and durable once-only writes."""
import base64,copy,hashlib,json,os,sys,time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from mock_http import report_rejection,send_json
U='00000000-0000-4000-8000-000000001012'
I='00000000-0000-4000-8000-000000003012'
J='00000000-0000-4000-8000-000000003013'
R=4294967296
M=9007199254740991
T='2026-10-16T12:00:00Z'
BASE='/api/v1/app/shared-objects'
S={'power':M,'label':'a\0é/😀'}
POS={'x':M,'y':-1}
B=base64.b64encode(bytes([0,255,1,0,128])).decode()
CAP={'collections':2,'storageBytes':5242880,'objectBytes':2048}
def definition(key):return {'key':key,'name':'World','active':True,'readPolicy':'all','writePolicy':'owner','maxObjectBytes':65536,'maxObjectsPerOwner':100,'ttlSeconds':None,'searchFields':[{'key':'power','type':'integer'},{'key':'label','type':'string'}],'positionEnabled':True,'used':True,'revision':1}
def catalog():return {'revision':R,'definitions':[definition('alpha'),definition('world')],'nextAfterKey':None,'limits':CAP,'serverTime':T}
def usage(revision=R,count=0):return {'userId':U,'collection':'world','revision':revision,'count':count,'limits':CAP,'pollAfterSeconds':120,'serverTime':T}
def obj(id=I,revision=1,data=B):return {'id':id,'collection':'world','ownerId':U,'groupId':None,'revision':revision,'dataBase64':data,'search':S,'position':POS,'createdAt':T,'updatedAt':T,'expiresAt':None}
def point(id=I,revision=1,data=B):return {'object':obj(id,revision,data),'pollAfterSeconds':120,'serverTime':T}
def changed(id=I,revision=1,data=B,used=R+1,count=1):return dict(point(id,revision,data),usage=usage(used,count))
def page(objects=None,cursor=None):return {'objects':[] if objects is None else objects,'nextCursor':cursor,'pollAfterSeconds':120,'serverTime':T}
CASES=[]
def add(method,path,body,result,status=200,revision=None,delay=0):CASES.append((method,path,copy.deepcopy(body),copy.deepcopy(result),status,revision,delay))
read=BASE+'/world/objects/'
user='?userId='+U
body={'userId':U,'dataBase64':B,'search':S,'position':POS}
rect={'userId':U,'mode':'rectangle','minX':-M,'maxX':M,'minY':-M,'maxY':M,'limit':20}
first=catalog();first['definitions']=[definition('alpha')];first['nextAfterKey']='alpha'
second=catalog();second['definitions']=[definition('world')]
add('GET',BASE+'/collections'+user+'&limit=1',None,first)
add('GET',BASE+'/collections'+user+'&limit=1&afterKey=alpha&catalogRevision='+str(R),None,second)
add('GET',BASE+'/collections'+user+'&limit=50',None,catalog())
add('GET',BASE+'/world/usage'+user,None,usage())
add('POST',BASE+'/world/objects',body,changed(),revision=R)
add('GET',read+I+user,None,point())
add('PUT',read+I,dict(body,dataBase64=''),changed(revision=2,data='',used=R+2),revision=1)
add('POST',BASE+'/world/query',rect,page([obj(revision=2,data='')],'cursor-original'))
add('POST',BASE+'/world/query',dict(rect,cursor='cursor-original'),page())
add('DELETE',read+I+user,None,{'objectId':I,'deleted':True,'usage':usage(R+3),'pollAfterSeconds':120,'serverTime':T},revision=2)
# Lost create acknowledgement. Restart must read state only and keep exact durable original.
add('GET',BASE+'/world/usage'+user,None,usage(R+3))
add('POST',BASE+'/world/objects',body,{'message':'uncertain committed create'},503,revision=R+3)
add('GET',BASE+'/world/usage'+user,None,usage(R+4,1))
add('POST',BASE+'/world/query',{'userId':U,'mode':'owner','ownerId':U,'limit':50},page([obj(J)]))
add('GET',BASE+'/world/usage'+user,None,usage(R+4,1))
# Actual sample composes the existing Cloud-only VA lifecycle with frozen defense bytes.
run='00000000-0000-4000-8000-000000004012'
for _ in range(4):
 add('POST','/api/v1/app/validated-actions/runs',{'userId':U,'leaderboardKey':'defense','context':{'contentDigest':hashlib.sha256(base64.b64decode(B)).hexdigest(),'initialState':B}},{'code':'VALIDATED_ACTIONS_UNAVAILABLE','message':'no ticket key configured'},503)
add('POST','/api/v1/app/validated-actions/runs',{'userId':U,'leaderboardKey':'defense','context':{'contentDigest':hashlib.sha256(base64.b64decode(B)).hexdigest(),'initialState':B}},{'code':'INITIAL_STATE_TOO_LARGE','message':'configured context limit'},413)
add('POST','/api/v1/app/validated-actions/runs',{'userId':U,'leaderboardKey':'defense','context':{'contentDigest':hashlib.sha256(base64.b64decode(B)).hexdigest(),'initialState':B}},{'runId':run,'ticket':'objects-run-ticket','seed':42,'leaderboardKey':'defense','issuedAt':T,'expiresAt':'2026-10-16T12:30:00Z','expiresInSeconds':1800})
add('POST','/api/v1/app/validated-actions/submit',{'userId':U,'ticket':'objects-run-ticket','score':123,'inputLogHash':hashlib.sha256(b'R1').hexdigest()},{'code':'TICKET_EXPIRED','message':'ticket expired'},422)
add('POST','/api/v1/app/validated-actions/runs',{'userId':U,'leaderboardKey':'defense','context':{'contentDigest':hashlib.sha256(base64.b64decode(B)).hexdigest(),'initialState':B}},{'runId':run,'ticket':'objects-run-ticket','seed':42,'leaderboardKey':'defense','issuedAt':T,'expiresAt':'2026-10-16T12:30:00Z','expiresInSeconds':1800})
add('POST','/api/v1/app/validated-actions/runs',{'userId':U,'leaderboardKey':'defense','context':{'contentDigest':hashlib.sha256(base64.b64decode(B)).hexdigest(),'initialState':B}},{'runId':run,'ticket':'objects-run-ticket','seed':42,'leaderboardKey':'defense','issuedAt':T,'expiresAt':'2026-10-16T12:30:00Z','expiresInSeconds':1800})
add('POST','/api/v1/app/validated-actions/submit',{'userId':U,'ticket':'objects-run-ticket','score':123,'inputLogHash':hashlib.sha256(b'R1').hexdigest()},{'accepted':True,'runId':run,'leaderboardKey':'defense','score':123,'bestScore':123,'isNewHighScore':True,'rank':1,'durationSeconds':10,'state':None,'evidence':None,'sus':False})
# Read-only query retries keep original typed body even if caller mutates its Dictionary.
field={'userId':U,'mode':'field','field':'power','equal':M}
add('POST',BASE+'/world/query',field,{'message':'retryable read'},503)
add('POST',BASE+'/world/query',field,page([obj(J)]))
large=[]
for n in range(16):large.append(obj('00000000-0000-4000-8000-%012d'%(5000+n),data=base64.b64encode(bytes(65536)).decode()))
add('POST',BASE+'/world/query',{'userId':U,'mode':'list','limit':50},page(large))
add('GET',read+J+user,None,point(J))
add('PUT',read+J,dict(body,dataBase64=''),{'message':'uncertain update'},503,revision=1)
add('DELETE',read+J+user,None,{'code':'STORAGE_LIMIT_REACHED','message':'business throttle'},429,revision=1)
add('PUT',read+J,dict(body,dataBase64=''),changed(J,2,'',R+5),revision=1,delay=1.4)
# Strict parser rejects wire fractions and stale snapshots; scope ABA must reject a late reply.
bad=point(J);bad['object']['revision']=1.5
add('GET',read+J+user,None,bad)
add('GET',read+J+user,None,point(J,2,''))
add('GET',read+J+user,None,point(J,1,''))
add('GET',read+J+user,None,point(J,2,''),delay=.15)
assert len({(m,p.split('?')[0].replace(I,'ID').replace(J,'ID'))for m,p,*_ in CASES if p.startswith(BASE)})==7
class Handler(BaseHTTPRequestHandler):
 seen=0;failure=None
 def do_GET(self):self.case('GET')
 def do_POST(self):self.case('POST')
 def do_PUT(self):self.case('PUT')
 def do_DELETE(self):self.case('DELETE')
 def case(self,method):
  index=type(self).seen;type(self).seen+=1
  if index>=len(CASES):return self.reject('unexpected retry/poll/page at%d'%index)
  verb,path,body,result,status,revision,delay=CASES[index]
  raw=self.rfile.read(int(self.headers.get('Content-Length',0)))
  received=json.loads(raw) if raw else None
  if(method,self.path,received)!=(verb,path,body):return self.reject('wrong method/path/frozen body at%d'%index)
  if self.headers.get('X-API-Key')!='objects-key' or self.headers.get('Authorization')!='Bearer objects-session':return self.reject('wrong project/player auth')
  if self.headers.get('If-Match')!=(None if revision is None else str(revision)):return self.reject('changed/missing If-Match at%d'%index)
  if delay:time.sleep(delay)
  try:send_json(self,status,result,{'Retry-After':'1'} if status==429 else None)
  except(BrokenPipeError,ConnectionResetError):
   if not delay:self.reject('unexpected disconnect')
 def reject(self,message):
  type(self).failure=message;report_rejection(message)
  try:send_json(self,422,{'message':message})
  except(BrokenPipeError,ConnectionResetError):pass
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',20112),Handler);server.timeout=20
if os.environ.get('MOCK_SERVER_READY_FILE'):
 with open(os.environ['MOCK_SERVER_READY_FILE'],'w')as f:f.write('ready')
for _ in CASES:server.handle_request()
server.timeout=1.5;server.handle_request();server.server_close()
if Handler.failure or Handler.seen!=len(CASES):print(Handler.failure or 'missing requests%d/%d'%(Handler.seen,len(CASES)),file=sys.stderr);sys.exit(1)
print('Godot Shared Objects fixture observed%d exact HTTP requests/all7 routes+Cloud VA start/submit, unchanged If-Match, read-query retry and once-only503/429/timeout'%Handler.seen)

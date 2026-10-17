#!/usr/bin/env python3
"""Ordered real HTTP fixture: all14 Matches routes and shared VA start/submit ownership."""
import base64,copy,hashlib,json,os,sys,time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from mock_http import report_rejection,send_json
U='00000000-0000-4000-8000-000000001013';V='00000000-0000-4000-8000-00000000a013';W='00000000-0000-4000-8000-000000003013'
I='00000000-0000-4000-8000-000000004013';J='00000000-0000-4000-8000-000000004014';K='00000000-0000-4000-8000-000000004015';L='00000000-0000-4000-8000-000000004016';RUN='00000000-0000-4000-8000-000000005013'
T='2026-10-16T12:00:00Z';R=4294967296;BASE='/api/v1/app/matches';CAP={'activeMatches':2,'stateBytes':1024,'retainedMatches':20,'pendingInvites':20,'settlementMatches':20,'historyRetentionSeconds':604800,'rankedSettlementSeconds':604800}
def b(data):return base64.b64encode(bytes(data)).decode()
B=b([0,255,0,128]);B1=b([1,0,255]);B2=b([2,128,0]);B3=b([3,0,255]);RESULT=b([255,0,128])
OPTIONS={'name':'opaque é/😀','capacity':2,'visibility':'private','strength':-9007199254740991,'turnSeconds':60,'timeoutPolicy':'skip','ranked':True,'dataBase64':B,'inviteeIds':[V]}
def view(id=I,revision=1):return {'id':id,'name':'opaque é/😀','revision':revision,'creatorId':U,'capacity':2,'visibility':'private','strength':-9007199254740991,'status':'lobby','participantIds':[U],'invitedIds':[V],'forfeitedIds':[],'currentPlayerId':None,'turnDeadline':None,'createdAt':T,'startedAt':None,'finishedAt':None,'purgeAt':None,'finalStateRevision':None,'hasDisagreement':False,'ranked':True,'timeoutDue':False,'turnOrder':[],'turnSeconds':60,'timeoutPolicy':'skip','dataBase64':B,'reports':[],'reportDeadline':None,'absoluteDeadline':None,'rankedLeaderboardKey':'ranked','ownRankedRunId':None,'notificationPending':False}
def summary(row):return {k:v for k,v in row.items() if k not in ['turnOrder','turnSeconds','timeoutPolicy','dataBase64','reports','reportDeadline','absoluteDeadline','rankedLeaderboardKey','ownRankedRunId','notificationPending']}
def point(row,**kw):return dict({'match':copy.deepcopy(row),'pollAfterSeconds':120,'serverTime':T},**kw)
def mine(user,revision,active=[],recent=[]):return {'userId':user,'revision':revision,'active':[summary(x)for x in active],'invites':[],'pendingResults':[],'recent':[summary(x)for x in recent],'limits':CAP,'pollAfterSeconds':120,'serverTime':T}
def run():return {'runId':RUN,'ticket':'match-original-ticket','seed':42,'leaderboardKey':'ranked','issuedAt':T,'expiresAt':'2026-10-16T12:30:00Z','expiresInSeconds':1800}
CASES=[]
def add(method,path,user,body,result,status=200,revision=None,delay=0):CASES.append((method,path,user,copy.deepcopy(body),copy.deepcopy(result),status,revision,delay))
def get(path,user,result,delay=0):add('GET',BASE+path+'?userId='+user,user,None,result,delay=delay)
def cmd(kind,user,rev,row,body={}):add('POST',BASE+'/'+row['id']+'/'+kind,user,dict(body,userId=user),point(row),revision=rev)
get('/limits',U,{'limits':CAP,'config':{'revision':R,'rankedLeaderboardKey':'ranked'},'capabilities':{'matches':True,'matchesRanked':True,'realtime':True},'pollAfterSeconds':120,'serverTime':T})
get('',U,mine(U,R))
a=view();add('POST',BASE,U,dict(OPTIONS,userId=U),point(a,playerRevision=R+1),revision=R)
inv=copy.deepcopy(a);inv['dataBase64']=None;get('/'+I,V,point(inv))
a.update(revision=2,participantIds=[U,V],invitedIds=[]);cmd('join',V,1,a)
get('/'+I,U,point(a))
a.update(revision=3,status='active',turnOrder=[U,V],currentPlayerId=U,turnDeadline='2026-10-16T12:01:00Z',startedAt=T,absoluteDeadline='2026-11-15T12:00:00Z');cmd('start',U,2,a,{'turnOrder':[U,V]})
a.update(revision=4,currentPlayerId=V,dataBase64=B1,notificationPending=True);cmd('turn',U,3,a,{'dataBase64':B1,'finish':False})
get('/'+I,V,point(a));a.update(revision=5,currentPlayerId=U,dataBase64=B2);cmd('turn',V,4,a,{'dataBase64':B2,'finish':False})
get('/'+I,U,point(a));a.update(revision=6,status='reporting',currentPlayerId=None,turnDeadline=None,dataBase64=B3,finalStateRevision=6,reportDeadline='2026-10-17T12:00:00Z');cmd('turn',U,5,a,{'dataBase64':B3,'finish':True})
get('/'+I,V,point(a))
def report(user,result=RESULT):return {'userId':user,'finalStateRevision':6,'resultBase64':result,'winnerIds':[U],'reportedAt':T}
a.update(revision=7,reports=[report(U)]);add('POST',BASE+'/'+I+'/result',U,{'userId':U,'finalStateRevision':6,'resultBase64':RESULT,'winnerIds':[U]},point(a,replayed=False))
a.update(revision=8,reports=[report(U),report(V)],status='confirmed',finishedAt=T,purgeAt='2026-10-23T12:00:00Z');confirmed=copy.deepcopy(a)
add('POST',BASE+'/'+I+'/result',V,{'userId':V,'finalStateRevision':6,'resultBase64':RESULT,'winnerIds':[U]},point(a,replayed=False));get('/'+I,U,point(a))
add('POST',BASE+'/'+I+'/ranked-run',U,{'userId':U,'finalStateRevision':6},run())
add('POST','/api/v1/app/validated-actions/submit',U,{'userId':U,'ticket':'match-original-ticket','score':123,'inputLogHash':hashlib.sha256(b'R1').hexdigest()},{'accepted':True,'runId':RUN,'leaderboardKey':'ranked','score':123,'bestScore':123,'isNewHighScore':True,'rank':1,'durationSeconds':10,'state':None,'evidence':None,'sus':False})
cursor=b(('m1|'+'a'*64+'|0|'+J).encode());add('GET',BASE+'/open?userId='+U+'&minStrength=-10&maxStrength=10&limit=20',U,None,{'matches':[],'nextCursor':cursor,'pollAfterSeconds':120,'serverTime':T});add('GET',BASE+'/open?userId='+U+'&minStrength=-10&maxStrength=10&limit=20&cursor='+__import__('urllib.parse').parse.quote(cursor,safe=''),U,None,{'matches':[],'nextCursor':None,'pollAfterSeconds':120,'serverTime':T})
# Lost create ACK and fresh sample: read-only reconciliation fences its original ledger CAS.
get('',U,mine(U,R+1,recent=[confirmed]));add('POST',BASE,U,dict(OPTIONS,userId=U),{'message':'lost committed create'},503,revision=R+1)
j=view(J);get('',U,mine(U,R+2,active=[j],recent=[confirmed]))
inv=copy.deepcopy(j);inv['dataBase64']=None;get('/'+J,V,point(inv));j.update(revision=2,invitedIds=[],dataBase64=None);add('POST',BASE+'/'+J+'/decline',V,{'userId':V},{'message':'lost decline ACK'},503,revision=1);get('',V,mine(V,9))
j.update(revision=3,dataBase64=B,status='cancelled',finishedAt=T,purgeAt='2026-10-23T12:00:00Z');cmd('cancel',U,2,j)
k=view(K,10);k.update(capacity=3,status='active',participantIds=[U,V,W],invitedIds=[],turnOrder=[U,V,W],currentPlayerId=W,turnDeadline='2026-10-16T12:01:00Z',startedAt=T,absoluteDeadline='2026-11-15T12:00:00Z',forfeitedIds=[V],revision=11);cmd('leave',V,10,k)
get('',V,mine(V,10,recent=[k]))
k.update(revision=12,currentPlayerId=U);cmd('timeout',U,11,k)
k.update(revision=13,status='unconfirmed',currentPlayerId=None,turnDeadline=None,finalStateRevision=13,finishedAt=T,purgeAt='2026-10-23T12:00:00Z');get('/'+K,U,point(k))
l=copy.deepcopy(confirmed);l.update(id=L,revision=8,status='disputed',hasDisagreement=True,reports=[report(U),report(V,b([1]))]);add('POST',BASE+'/'+L+'/result',V,{'userId':V,'finalStateRevision':6,'resultBase64':b([1]),'winnerIds':[U]},point(l,replayed=False))
# Immutable result retry stays byte-identical after uncertainty.
add('POST',BASE+'/'+I+'/result',U,{'userId':U,'finalStateRevision':6,'resultBase64':RESULT,'winnerIds':[U]},{'message':'uncertain report'},503)
add('POST',BASE+'/'+I+'/result',U,{'userId':U,'finalStateRevision':6,'resultBase64':RESULT,'winnerIds':[U]},point(confirmed,replayed=True))
# Mutations have one attempt even for throttles, 5xx and timeout.
add('POST',BASE+'/'+K+'/turn',U,{'userId':U,'dataBase64':B1,'finish':False},{'code':'MATCH_REVISION_CONFLICT','message':'business'},429,revision=13)
add('POST',BASE+'/'+J+'/join',V,{'userId':V},{'message':'uncertain join'},503,revision=3)
add('POST',BASE+'/'+K+'/timeout',U,{'userId':U},point(k),revision=13,delay=1.4)
# Strict wire and late host-ABA cannot overwrite cached snapshots.
bad=copy.deepcopy(confirmed);bad['revision']=8.5;get('/'+I,U,point(bad));get('/'+I,U,point(confirmed),delay=.15)
# Generic/run concurrency: match start cannot overtake a generic start or overwrite another ticket.
add('POST','/api/v1/app/validated-actions/runs',U,{'userId':U,'leaderboardKey':'ranked'},run(),delay=.15)
add('POST',BASE+'/'+I+'/ranked-run',U,{'userId':U,'finalStateRevision':6},run())
# Recovery reseals token for SAME run/seed/dates, not a second run.
r=run();r['ticket']='resealed-original-run';add('POST',BASE+'/'+I+'/ranked-run',U,{'userId':U,'finalStateRevision':6},r)
# Original ranked expiry and lost lobby leave must not block unrelated future intents forever.
a=copy.deepcopy(confirmed);a['ownRankedRunId']=RUN;get('/'+I,U,point(a))
add('POST',BASE+'/'+I+'/ranked-run',U,{'userId':U,'finalStateRevision':6},{'message':'lost original recovery ACK'},503)
add('POST',BASE+'/'+I+'/ranked-run',U,{'userId':U,'finalStateRevision':6},{'code':'RUN_EXPIRED','message':'original run expired'},422)
n=copy.deepcopy(confirmed);n['id']='00000000-0000-4000-8000-000000004018';get('/'+n['id'],U,point(n))
r=run();r['runId']='00000000-0000-4000-8000-000000005014';add('POST',BASE+'/'+n['id']+'/ranked-run',U,{'userId':U,'finalStateRevision':6},r)
m=view('00000000-0000-4000-8000-000000004017',2);m.update(participantIds=[U,V],invitedIds=[]);get('/'+m['id'],V,point(m))
add('POST',BASE+'/'+m['id']+'/leave',V,{'userId':V},{'message':'lost lobby leave ACK'},503,revision=2);get('',V,mine(V,12))
assert len({(m,p.split('?')[0].replace(I,'ID').replace(J,'ID').replace(K,'ID').replace(L,'ID').replace('00000000-0000-4000-8000-000000004017','ID').replace('00000000-0000-4000-8000-000000004018','ID'))for m,p,*_ in CASES if p.startswith(BASE)})==14
class Handler(BaseHTTPRequestHandler):
 seen=0;failure=None
 def do_GET(self):self.case('GET')
 def do_POST(self):self.case('POST')
 def case(self,method):
  index=type(self).seen;type(self).seen+=1
  if index>=len(CASES):return self.reject('unexpected retry/poll/page%d'%index)
  verb,path,user,body,result,status,revision,delay=CASES[index]
  raw=self.rfile.read(int(self.headers.get('Content-Length',0)));received=json.loads(raw)if raw else None
  if(method,self.path,received)!=(verb,path,body):return self.reject('wrong frozen method/path/body at%d'%index)
  if self.headers.get('X-API-Key')!='matches-key' or self.headers.get('Authorization')!='Bearer matches-'+user[-4:]:return self.reject('wrong session/project at%d'%index)
  if self.headers.get('If-Match')!=(None if revision is None else str(revision)):return self.reject('wrong original If-Match at%d'%index)
  if delay:time.sleep(delay)
  try:send_json(self,status,result,{'Retry-After':'1'}if status==429 else None)
  except(BrokenPipeError,ConnectionResetError):
   if not delay:self.reject('unexpected disconnect')
 def reject(self,message):
  type(self).failure=message;report_rejection(message)
  try:send_json(self,422,{'message':message})
  except(BrokenPipeError,ConnectionResetError):pass
 def log_message(self,*args):pass
server=ThreadingHTTPServer(('127.0.0.1',int(os.environ.get('HORIZON_MATCHES_TEST_PORT','20113'))),Handler);server.timeout=25
if os.environ.get('MOCK_SERVER_READY_FILE'):
 with open(os.environ['MOCK_SERVER_READY_FILE'],'w')as f:f.write('ready')
for _ in CASES:server.handle_request()
server.timeout=1.5;server.handle_request();server.server_close()
if Handler.failure or Handler.seen!=len(CASES):print(Handler.failure or'missing%d/%d'%(Handler.seen,len(CASES)),file=sys.stderr);sys.exit(1)
print('PASS: Matches fixture observed%d exact HTTP requests/all14 routes + VA start/submit, two distinct sessions, original CAS/bytes, no retry/poll/page'%(Handler.seen))

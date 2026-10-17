#!/usr/bin/env python3
"""Current DTOs above old defaults and retained state after lowering. Loopback only."""
import base64,copy,json,os,sys,uuid
from http.server import BaseHTTPRequestHandler,HTTPServer
from urllib.parse import parse_qs,urlparse
from mock_http import send_json,report_rejection
U='00000000-0000-4000-8000-000000001016';T='2026-10-17T12:00:00Z';RUN='00000000-0000-4000-8000-000000005016'
def uid(n):return '00000000-0000-4000-8000-%012d'%n
def display():return {'name':None,'profile':{'avatarId':None,'frameId':None,'badges':[]}}
def optional_stamp(row,index,field):
 if index%3==0:row[field]=T
 elif index%3==1:row[field]=None
 return row
def friends(low=False):
 result={'userId':U,'revision':2 if low else 1,'friendCode':'H-'+base64.urlsafe_b64encode(uuid.UUID(U).bytes).decode().rstrip('='),'serverTime':T,
 'limits':{'maxFriends':1 if low else 300,'maxIncomingRequests':1 if low else 22,'maxOutgoingRequests':1 if low else 22,'maxBlocked':1 if low else 150}}
 result['friends']=[optional_stamp({'userId':uid(10000+i),'lastActiveAt':None,'display':display()},i,'since') for i in range(201)]
 for name,start in [('incoming',20000),('outgoing',30000)]:result[name]=[optional_stamp({'userId':uid(start+i),'requestId':uid(40000+start+i),'display':display()},i,'createdAt')for i in range(21)]
 result['blocked']=[{'userId':uid(40000+i),'blockedAt':T}for i in range(101)]
 return result
G=uid(50000)
DATA={'large':'é'*2048,'seed':9007199254740993,'decimal':'__EXACT_DECIMAL__','nested':{}}
node=DATA['nested']
for _ in range(32):node['x']={};node=node['x']
NAME='é'*200;DESCRIPTION='d'*2048
def group(id=G):return {'id':id,'revision':1,'name':NAME,'description':DESCRIPTION,'joinMode':'open','leaderId':U,'memberCount':501,'createdAt':T,'updatedAt':T,'myRole':'leader','data':copy.deepcopy(DATA)}
LIMITS={'maxMembers':501,'maxGroupsPerPlayer':6,'maxInvitations':21,'maxJoinRequests':21,'maxDataBytes':8192,'memberPageSize':51,'maxPlayerInvitations':21,'maxPlayerRequests':21,'maxNameBytes':512,'maxDescriptionBytes':4096,'maxDataDepth':64}
def groups(low=False):
 result={'userId':U,'revision':2 if low else 1,'groups':[group(uid(50000+i))for i in range(6)],'limits':{k:1 if low else v for k,v in LIMITS.items()},'serverTime':T}
 for key,start in [('incomingInvites',60000),('outgoingRequests',70000)]:result[key]=[optional_stamp({'groupId':uid(start+i),'requestId':uid(start+100+i),'issuerId':uid(90000+i),'group':None},i,'createdAt')for i in range(21)]
 return result
def pending():
 return {'groupId':G,'revision':1,'invitations':[optional_stamp({'userId':uid(110000+i),'requestId':uid(120000+i),'issuerId':U},i,'createdAt')for i in range(21)],'joinRequests':[optional_stamp({'userId':uid(130000+i),'requestId':uid(140000+i),'issuerId':uid(130000+i)},i,'createdAt')for i in range(21)],'serverTime':T}
def members():return {'groupId':G,'revision':1,'members':[{'userId':uid(150000+i),'role':'member','joinedAt':T,'display':display()}for i in range(51)],'nextAfterUserId':None,'serverTime':T}
SHARED_CAP={'collections':101,'storageBytes':4294967296,'objectBytes':1048576}
SHARED_BYTES=bytes([0,255])*524288
def definition():return {'key':'world','name':'World','active':True,'readPolicy':'all','writePolicy':'owner','maxObjectBytes':1048576,'maxObjectsPerOwner':101,'ttlSeconds':None,'searchFields':[{'key':'power','type':'integer'}],'positionEnabled':False,'used':True,'revision':1}
def usage():return {'userId':U,'collection':'world','revision':1,'count':101,'limits':dict(SHARED_CAP,objectBytes=1024),'pollAfterSeconds':120,'serverTime':T}
def object_view():return {'object':{'id':uid(160000),'collection':'world','ownerId':U,'groupId':None,'revision':1,'dataBase64':base64.b64encode(SHARED_BYTES).decode(),'search':{'power':9007199254740991},'position':None,'createdAt':T,'updatedAt':T,'expiresAt':None},'pollAfterSeconds':120,'serverTime':T}
MATCH_CAP={'activeMatches':11,'stateBytes':14648*1024,'retainedMatches':0,'pendingInvites':21,'settlementMatches':201,'historyRetentionSeconds':0,'rankedSettlementSeconds':604800}
def summary(id,kind):
 invite=kind=='invite';terminal=kind=='recent';creator=uid(170000)if invite else U
 return {'id':id,'name':'Current','revision':1,'creatorId':creator,'capacity':2,'visibility':'private','strength':0,'status':'cancelled'if terminal else'lobby','participantIds':[creator],'invitedIds':[U]if invite else[],'forfeitedIds':[],'currentPlayerId':None,'turnDeadline':None,'createdAt':T,'startedAt':None,'finishedAt':T if terminal else None,'purgeAt':'2027-01-01T00:00:00Z'if terminal else None,'finalStateRevision':None,'hasDisagreement':False,'ranked':False,'timeoutDue':False}
def mine():return {'userId':U,'revision':1,'active':[summary(uid(180000+i),'active')for i in range(11)],'invites':[summary(uid(190000+i),'invite')for i in range(21)],'recent':[summary(uid(200000+i),'recent')for i in range(101)],'pendingResults':[{'matchId':uid(210000+i),'finalStateRevision':5,'ownRankedRunId':RUN if i==0 else None,'expiresAt':'2026-10-18T12:00:00Z'}for i in range(201)],'limits':MATCH_CAP,'pollAfterSeconds':120,'serverTime':T}
MAX_STATE=bytes([0,255])*(14648*512)
def point():return {'match':dict(summary(uid(180000),'active'),turnOrder=[],turnSeconds=60,timeoutPolicy='skip',dataBase64=base64.b64encode(MAX_STATE).decode(),reports=[],reportDeadline=None,absoluteDeadline=None,rankedLeaderboardKey=None,ownRankedRunId=None,notificationPending=False),'pollAfterSeconds':120,'serverTime':T}
def run():return {'runId':RUN,'ticket':'same-original-run-resealed','seed':42,'leaderboardKey':'ranked','issuedAt':T,'expiresAt':'2026-10-17T12:30:00Z','expiresInSeconds':1800}
CHAT={'retainedMessagesPerPlayer':0,'retainedMessagesPerChannel':20,'retentionSeconds':604800,'privateRetainedMessagesPerChannel':15,'privateRetentionSeconds':30,'operationWindowSeconds':30,'operationFutureToleranceSeconds':60,'messageCharacters':500,'messageUtf8Bytes':2000,'channelsPerAccount':2001,'sendsPerAccountMinute':121,'playerSendIntervalMillis':3000,'channelSendIntervalMillis':2000,'reportsPerProject':201,'receiptCount':0,'reportReceiptCount':0,'wordFilterTerms':100}
CASES=[]
def add(method,path,result,body=None,status=200,query=None):CASES.append((method,path,query if query is not None else({'userId':[U]}if method=='GET'else{}),body,result,status))
add('GET','/api/v1/app/friends',friends())
add('GET','/api/v1/app/friends',friends(True))
add('POST','/api/v1/app/friends/cancel',{'code':'REVISION_CONFLICT'},body={'userId':U,'targetUserId':uid(30000),'expectedRevision':1,'requestId':uid(70000)},status=409)
add('GET','/api/v1/app/groups',groups())
add('GET','/api/v1/app/groups/'+G+'/members',members(),query={'userId':[U],'limit':['51']})
add('GET','/api/v1/app/groups/'+G+'/pending',pending())
add('GET','/api/v1/app/groups',groups(True))
add('PUT','/api/v1/app/groups/'+G,{'code':'INVALID_GROUP'},body='group-original',status=400)
large_group=group();large_group.update(revision=3,data={'big':'x'*(9*1024*1024),'seed':9007199254740993})
add('GET','/api/v1/app/groups/'+G,large_group)
add('GET','/api/v1/app/shared-objects/collections',{'revision':1,'definitions':[definition()],'nextAfterKey':None,'limits':SHARED_CAP,'serverTime':T},query={'userId':[U],'limit':['50']})
add('GET','/api/v1/app/shared-objects/world/usage',usage())
add('GET','/api/v1/app/shared-objects/world/objects/'+uid(160000),object_view())
add('GET','/api/v1/app/matches/limits',{'limits':MATCH_CAP,'config':{'revision':1,'rankedLeaderboardKey':'ranked'},'capabilities':{'matches':True,'matchesRanked':True,'realtime':True},'pollAfterSeconds':120,'serverTime':T})
add('GET','/api/v1/app/matches',mine())
add('GET','/api/v1/app/matches/'+uid(180000),point())
add('GET','/api/v1/app/matches',mine())
add('POST','/api/v1/app/matches',{'code':'UNAVAILABLE'},body='maximum-create',status=503)
add('GET','/api/v1/app/matches',dict(mine(),revision=2))
add('GET','/api/v1/app/matches',dict(mine(),revision=2))
ranked={'userId':U,'finalStateRevision':5}
add('POST','/api/v1/app/matches/'+uid(210000)+'/ranked-run',{'code':'UNAVAILABLE'},body=ranked,status=503)
add('POST','/api/v1/app/matches/'+uid(210000)+'/ranked-run',run(),body=ranked)
add('GET','/api/v1/app/chat/limits',{'limits':CHAT,'moderation':{'muteUntil':None,'banUntil':None},'capabilities':{'chat':True,'realtime':True,'incrementalSync':True,'localHistory':True},'serverTime':'2026-10-17T12:00:00.000Z'})
class Handler(BaseHTTPRequestHandler):
 seen=0;failure=None
 def log_message(self,*_):pass
 def do_GET(self):self.case('GET')
 def do_POST(self):self.case('POST')
 def do_PUT(self):self.case('PUT')
 def case(self,method):
  try:
   index=type(self).seen;assert index<len(CASES),'unexpected retry/page'
   verb,path,query,expected,result,status=CASES[index]
   parsed=urlparse(self.path);assert(method,parsed.path,parse_qs(parsed.query))==(verb,path,query),(index,method,self.path)
   assert self.headers.get('X-API-Key')=='configured-key'and self.headers.get('Authorization')=='Bearer configured-session'
   raw=self.rfile.read(int(self.headers.get('Content-Length',0)));body=json.loads(raw)if raw else None
   if expected=='group-original':
    assert set(body)=={'userId','expectedRevision','name','description','joinMode','data'}
    assert body['userId']==U and body['expectedRevision']==1 and body['name']==NAME and body['description']==DESCRIPTION
    assert body['data']['seed']==9007199254740993 and b'1.0000000000000000000001'in raw
   elif expected=='maximum-create':
    assert self.headers.get('If-Match')=='1'
    assert set(body)=={'userId','name','capacity','visibility','strength','turnSeconds','timeoutPolicy','ranked','dataBase64','inviteeIds'}
    assert body['userId']==U and body['name']=='Maximum original' and body['capacity']==2 and body['inviteeIds']==[]
    assert body['visibility']=='private' and body['strength']==0 and body['turnSeconds']==60 and body['timeoutPolicy']=='skip' and body['ranked']is False
    assert base64.b64decode(body['dataBase64'],validate=True)==MAX_STATE
   else:assert body==expected,(index,body,expected)
   type(self).seen+=1
  except Exception as error:
   type(self).failure=str(error);report_rejection(str(error));result,status={'code':'FIXTURE_REJECTED'},422
  wire=json.dumps(result,ensure_ascii=False,separators=(',',':')).replace('"__EXACT_DECIMAL__"','1.0000000000000000000001').encode()
  try:send_json(self,status,wire)
  except(BrokenPipeError,ConnectionResetError):type(self).failure='Disconnected native configured response'
server=HTTPServer(('127.0.0.1',20116),Handler);server.timeout=120
if os.environ.get('MOCK_SERVER_READY_FILE'):
 with open(os.environ['MOCK_SERVER_READY_FILE'],'w')as ready:ready.write('ready')
for _ in CASES:server.handle_request()
server.timeout=1;server.handle_request()
assert Handler.failure is None,Handler.failure
assert Handler.seen==len(CASES),(Handler.seen,len(CASES))
print('Configured actual HTTP: %d exact requests; higher limits, retained overhang, optional dates, 1MiB Shared and maximum legal Match state, original source retry'%Handler.seen)

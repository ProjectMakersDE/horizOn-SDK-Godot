#!/usr/bin/env python3
"""Exact Items/PV sample fixture: one bounded page, original purchase/revision, no hidden retry."""
import copy,json,os,sys,time
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from mock_http import report_rejection,send_json
U='00000000-0000-4000-8000-000000001011'
I='00000000-0000-4000-8000-000000003011'
J='00000000-0000-4000-8000-000000003012'
R=4294967296
BASE='/api/v1/app/items'
PV='/api/v1/app/player-values'
CASES=[]
OP=None
def add(method,path,body,result,status=200,delay=0):CASES.append((method,path,body,copy.deepcopy(result),status,delay))
def snapshot(revision=R,power=9,equipped=False,discard=False):
 return {'userId':U,'revision':revision,'instances':([] if discard else [{'instanceId':I,'itemKey':'sword','properties':{'power':power,'text':'a\0é/😀\x1f'},'equipped':equipped,'createdAt':'2026-10-16T12:00:00Z'}])+[{'instanceId':J,'itemKey':'charm','properties':{'title':'ordinary','max':9007199254740991},'equipped':False,'createdAt':'2026-10-16T12:00:00Z'}],'limits':{'catalog':5000,'inventory':150,'receipts':50},'serverTime':'2026-10-16T12:00:10Z'}
def catalog():return {'revision':R,'definitions':[{'key':'sword','name':'Sword','type':'weapon','rarity':'common','active':True,'baseProperties':{'power':9},'propertyRules':[{'key':'power','min':0,'max':10,'maxChangePerCall':1}]}],'nextAfterKey':None,'total':1,'limits':{'catalog':5000,'inventory':150,'receipts':50},'serverTime':'2026-10-16T12:00:10Z'}
def offers(cost=5):return {'definitionVersion':1,'serverTime':'2026-10-16T12:00:10Z','definitions':[],'offers':[{'key':'sword','active':True,'costs':[{'key':'coins','amount':cost}],'rewards':[],'itemRewards':[{'itemKey':'sword','quantity':1}]}]}
def values():return {'userId':U,'revision':1,'definitionVersion':1,'values':[{'key':'coins','balance':95,'earnedToday':0,'dailyCap':None}],'operationWindow':{'serverTime':'2026-10-16T12:00:10Z','oldestAcceptedAt':'2026-09-16T12:00:00Z'},'operation':{'operationId':'__ORIGINAL__','replayed':True,'applied':[],'items':[]}}
read=BASE+'?userId='+U
offers_path=PV+'/offers?userId='+U
purchase={'userId':U,'offerKey':'sword','operationId':'__ORIGINAL__'}
# Actual sample: page, review, detect changed terms, reconfirm, persist original before HTTP.
add('GET',BASE+'/catalog?userId='+U+'&limit=50',None,catalog())
add('GET',offers_path,None,offers())
add('GET',offers_path,None,offers(6))
add('GET',offers_path,None,offers(6))
add('POST',PV+'/purchase',purchase,{'message':'uncertain committed purchase'},503)
# New sample instance/restart must send the same operation UUID, even after a catalog edit.
add('POST',PV+'/purchase',purchase,values())
# Commit succeeded, but inventory refresh failed; retry resumes with GET only.
add('GET',read,None,{'code':'SESSION_REQUIRED','message':'refresh failed'},401)
add('GET',read,None,snapshot())
add('POST',BASE+'/equip',{'userId':U,'instanceId':I,'expectedRevision':R,'equipped':True},snapshot(R+1,equipped=True))
add('POST',BASE+'/adjust',{'userId':U,'instanceId':I,'expectedRevision':R+1,'changes':[{'key':'power','amount':1}]},snapshot(R+2,power=10,equipped=True))
add('POST',BASE+'/discard',{'userId':U,'instanceId':I,'expectedRevision':R+2},snapshot(R+3,discard=True))
# Manager: all errors are exactly one send; explicit GET reconciles, no substituted revision.
add('POST',BASE+'/equip',{'userId':U,'instanceId':J,'expectedRevision':R+3,'equipped':True},{'message':'uncertain equip'},503)
add('GET',read,None,snapshot(R+4,discard=True))
add('POST',BASE+'/discard',{'userId':U,'instanceId':J,'expectedRevision':R+4},{},429)
add('GET',read,None,snapshot(R+4,discard=True))
add('POST',BASE+'/adjust',{'userId':U,'instanceId':J,'expectedRevision':R+4,'changes':[{'key':'max','amount':-1}]},{'message':'uncertain timeout'},200,1.4)
add('GET',read,None,snapshot(R+5,discard=True))
# Expiry keeps the original durable intent and never selects a new operation ID.
add('POST',PV+'/purchase',{'userId':U,'offerKey':'sword','operationId':'1792152000000:00000000-0000-4000-8000-000000004011'},{'code':'OPERATION_EXPIRED','message':'expired original'},409)
# Configured quotas are metadata, not historical parser ceilings or deletion rules.
def configured_inventory(revision, lowered=False, equipped=False):
 result=snapshot(revision);result['limits']={'catalog':20,'inventory':10,'receipts':10} if lowered else {'catalog':6000,'inventory':250,'receipts':80}
 template=copy.deepcopy(result['instances'][0])
 for i in range(199):
  item=copy.deepcopy(template);item['instanceId']='00000000-0000-4000-8000-%012d'%(5100+i);result['instances'].append(item)
 result['instances'][1]['equipped']=equipped
 return result
add('GET',read,None,configured_inventory(R+6))
add('GET',read,None,configured_inventory(R+7,True))
page=catalog();page.update(revision=R+1,total=6000,nextAfterKey='sword',limits={'catalog':6000,'inventory':250,'receipts':80})
add('GET',BASE+'/catalog?userId='+U+'&limit=1',None,page)
page=copy.deepcopy(page);page['definitions'][0]['key']='wand';page.update(nextAfterKey='wand',limits={'catalog':20,'inventory':10,'receipts':10})
add('GET',BASE+'/catalog?userId='+U+'&limit=1&afterKey=sword&catalogRevision='+str(R+1),None,page)
add('POST',BASE+'/equip',{'userId':U,'instanceId':J,'expectedRevision':R+7,'equipped':True},configured_inventory(R+8,True,True))
assert len({(m,p.split('?')[0]) for m,p,*_ in CASES if p.startswith(BASE)})==5
class Handler(BaseHTTPRequestHandler):
 seen=0;failure=None
 def do_GET(self):self.case('GET')
 def do_POST(self):self.case('POST')
 def case(self,method):
  global OP
  index=type(self).seen;type(self).seen+=1
  if index>=len(CASES):return self.reject('unexpected retry/page loop')
  verb,path,body,result,status,delay=CASES[index]
  received=json.loads(self.rfile.read(int(self.headers.get('Content-Length',0)))) if method=='POST' else None
  if body and body.get('operationId')=='__ORIGINAL__':
   if OP is None:OP=received.get('operationId');assert isinstance(OP,str) and ':' in OP
   body=dict(body,operationId=OP)
  if (method,self.path,received)!=(verb,path,body):return self.reject('wrong method/path/original body at request%d'%index)
  if self.headers.get('X-API-Key')!='items-key' or self.headers.get('Authorization')!='Bearer items-session':return self.reject('wrong project/player auth')
  if result.get('operation'):result['operation']['operationId']=OP
  if delay:time.sleep(delay)
  try:send_json(self,status,result,{'Retry-After':'1'} if status==429 else None)
  except (BrokenPipeError,ConnectionResetError):
   if delay!=1.4:self.reject('unexpected disconnect')
 def reject(self,message):
  type(self).failure=message;report_rejection(message)
  try:send_json(self,422,{'message':message})
  except (BrokenPipeError,ConnectionResetError):pass
 def log_message(self,*_args):pass
server=ThreadingHTTPServer(('127.0.0.1',20111),Handler);server.timeout=15
if os.environ.get('MOCK_SERVER_READY_FILE'):
 with open(os.environ['MOCK_SERVER_READY_FILE'],'w') as f:f.write('ready')
for _ in CASES:server.handle_request()
server.timeout=1.5;server.handle_request();server.server_close()
if Handler.failure or Handler.seen!=len(CASES):
 print(Handler.failure or 'missing requests%d/%d'%(Handler.seen,len(CASES)),file=sys.stderr);sys.exit(1)
print('Godot Items fixture observed%d exact HTTP requests/all5 routes, original purchase/revision and once-only503/429/timeout'%Handler.seen)

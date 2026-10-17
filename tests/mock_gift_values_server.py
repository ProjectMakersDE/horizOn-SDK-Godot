"""Artificial V2 campaign/count fixture. No external services or production credentials."""
import copy,json,os,socket,time
from http.server import BaseHTTPRequestHandler,HTTPServer
USER='00000000-0000-4000-8000-000000001007'
CAMPAIGN='00000000-0000-4000-8000-000000101007'
OTHER='00000000-0000-4000-8000-000000201007'
COUNT='9007199254740993';REV='9223372036854775807'
EXPECTED=[('prepare','VALUES'),('prepare','VALUES'),('lost','VALUES'),('replay','VALUES'),('replay','VALUES'),('newcampaign','VALUES'),('replay','VALUES')]
EXPECTED += [('error',code) for code in ['COUNT_AHEAD','CAMPAIGN_CHANGED','UPGRADE_REQUIRED','MIGRATION_REQUIRED','COUNTER_EXHAUSTED']]
EXPECTED += [('bad',code) for code in ['NUMERIC','OVERFLOW','HISTORY']]
EXPECTED += [('fence',code) for code in ['CACHE','SESSION','PROJECT','SIGNOUT']]
EXPECTED += [('prepare','TWO'),('prepare','TWO'),('fresh','TWO'),('replay','TWO')]
EXPECTED += [('badprepare',code) for code in ['NUMERIC','OVERFLOW']]
def receipt(replay=True):
 return {'success':True,'message':'accepted','campaignId':CAMPAIGN,'count':'9007199254740994','configRevision':REV,
  'giftData':None if replay else '{"opaque":true}','grantedValues':[] if replay else [{'key':'gold','amount':7}], 'grantedUnlocks':[] if replay else ['fixture-hat'],
  'playerValues':{'userId':USER,'definitionVersion':1,'revision':30,'day':'2026-10-17','values':[{'key':'gold','balance':100,'earnedToday':0,'dailyCap':None}],
   'operationWindow':{'serverTime':'2026-10-17T00:00:30Z','oldestAcceptedAt':'2026-09-17T00:00:00Z'}},'replayed':replay,'alreadyApplied':replay}
class Handler(BaseHTTPRequestHandler):
 count=0;failure=None
 def reply(self,status,value):
  data=json.dumps(value,ensure_ascii=False).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(data)));self.end_headers()
  try:self.wfile.write(data)
  except (BrokenPipeError,ConnectionResetError):pass
 def reject(self,message):
  type(self).failure=message;print(message,flush=True);self.reply(422,{'code':'FIXTURE_CONTRACT','message':message})
 def do_GET(self):
  if self.path=='/actuator/health':self.reply(200,{'status':'UP'})
  else:self.reject('Unexpected GET')
 def do_POST(self):
  body=json.loads(self.rfile.read(int(self.headers.get('Content-Length','0'))))
  if self.path=='/api/v1/app/user-management/signin':
   if body!={'type':'ANONYMOUS','anonymousToken':'fixture-anonymous-1007'}:self.reject('Original auth identity changed');return
   self.reply(200,{'userId':USER,'username':'Fixture','accessToken':'fixture-session-1007','authStatus':'AUTHENTICATED','isAnonymous':True,'isVerified':False});return
  index=type(self).count;type(self).count+=1
  if index>=len(EXPECTED):self.reject('Extra request or automatic prepare');return
  action,code=EXPECTED[index]
  if self.headers.get('X-API-Key')!='fixture-key-1007' or self.headers.get('Authorization')!='Bearer fixture-session-1007':self.reject('Wrong project or Bearer');return
  prepare=action in ['prepare','newcampaign','badprepare']
  expected={'code':code,'userId':USER,**({'includeIntent':True} if prepare else {'protocolVersion':2,'campaignId':CAMPAIGN,'expectedCount':COUNT,'configRevision':REV})}
  if body!=expected or self.path!='/api/v1/app/gift-codes/'+('validate' if prepare else 'redeem'):self.reject(f'Request{index+1}: original tuple or route changed');return
  if action=='lost':self.connection.shutdown(socket.SHUT_RDWR);self.connection.close();return
  if action=='error':self.reply(409,{'code':code,'message':'Explicit reconciliation required'});return
  if prepare:
   value={'valid':True,'protocolVersion':2,'campaignId':OTHER if action=='newcampaign' else CAMPAIGN,'expectedCount':COUNT,'configRevision':REV}
   if action=='badprepare':value['expectedCount']=int(COUNT) if code=='NUMERIC' else '9223372036854775808'
  else:
   value=receipt(action!='fresh')
   if action=='bad':
    if code=='NUMERIC':value['count']=int(value['count'])
    if code=='OVERFLOW':value['count']='9223372036854775808'
    if code=='HISTORY':value['giftData']='{"historical":true}'
  if action=='fence':time.sleep(.15)
  self.reply(200,copy.deepcopy(value))
 def log_message(self,*args):pass
def main():
 server=HTTPServer(('127.0.0.1',int(os.environ.get('GIFT_FIXTURE_PORT','18907'))),Handler);server.timeout=.2
 marker=os.environ.get('MOCK_SERVER_READY_FILE')
 if marker:
  with open(marker,'w') as f:f.write('ready\n')
 deadline=time.monotonic()+120
 while Handler.count<len(EXPECTED) and not Handler.failure and time.monotonic()<deadline:server.handle_request()
 deadline=time.monotonic()+1
 while not Handler.failure and time.monotonic()<deadline:server.handle_request()
 server.server_close()
 if Handler.failure or Handler.count!=len(EXPECTED):raise RuntimeError(f'{Handler.failure}; requests={Handler.count}/{len(EXPECTED)}')
 print(f'V2 Gift: {Handler.count} exact HTTP requests; original tuple retry, code reuse, contention, typed errors and malformed strings passed',flush=True)
if __name__=='__main__':main()

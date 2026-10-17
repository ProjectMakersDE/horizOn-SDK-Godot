#!/usr/bin/env python3
"""Groups contract fixture; Godot-only loopback20110, every request exact and bounded."""
import copy,datetime,json,os,sys,time
from decimal import Decimal
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from mock_http import report_rejection,send_json
A="00000000-0000-4000-8000-000000001010"
B="00000000-0000-4000-8000-000000001011"
G="00000000-0000-4000-8000-000000003010"
H="00000000-0000-4000-8000-000000003011"
J="00000000-0000-4000-8000-000000003012"
R=4294967296
BASE="/api/v1/app/groups"
EXPECTED=[]
def request_id(index): return "00000000-0000-4000-8000-%012d"%(4010+index)
def stamp(): return (datetime.datetime(2026,10,16,12,tzinfo=datetime.timezone.utc)+datetime.timedelta(seconds=len(EXPECTED))).isoformat().replace("+00:00","Z")
def display(): return {"name":None,"profile":{"avatarId":None,"frameId":None,"badges":[]},"email":"must-not-leak"}
def group(revision,actor=A,leader=A,count=1,mode="request",id=G,private=True):
 result={"id":id,"revision":revision,"name":"Guild","description":"Description","joinMode":mode,"leaderId":leader,"memberCount":count,"createdAt":"2026-10-16T12:00:00Z","updatedAt":stamp()}
 if private:result.update(myRole="leader" if actor==leader else "member",data={"revision":1.5,"$key":{"a.b":[],"":{}},"fraction":1e-10,"seed":9007199254740993,"huge":123456789012345678901234567890,"precise":"__precise__","unicode":"é/😀"})
 return result
def snapshot(actor,groups=None,incoming=None,outgoing=None):
 return {"userId":actor,"revision":R+len(EXPECTED),"groups":groups or [],"incomingInvites":incoming or [],"outgoingRequests":outgoing or [],"limits":{"maxMembers":20,"maxGroupsPerPlayer":1,"maxInvitations":20,"maxJoinRequests":20,"maxDataBytes":2048,"memberPageSize":50,"maxPlayerInvitations":2,"maxPlayerRequests":2,"maxNameBytes":120,"maxDescriptionBytes":1024,"maxDataDepth":16},"serverTime":stamp()}
def pending(index,revision,issuer=A):return {"groupId":G,"requestId":request_id(index),"issuerId":issuer,"createdAt":stamp(),"group":group(revision,private=False)}
def add(method,path,actor,body,result,status=200,delay=0): EXPECTED.append((method,path,actor,body,status,copy.deepcopy(result),delay))
def read(actor,groups=None,incoming=None,outgoing=None):add("GET",BASE+"?userId="+actor,actor,None,snapshot(actor,groups,incoming,outgoing))
def action(name,revision,actor,result_group,target=None,request=None):
 body={"userId":actor,"expectedRevision":revision}
 if target is not None:body["targetUserId"]=target
 if request is not None:body["requestId"]=request_id(request)
 own_groups=[result_group] if result_group is not None and result_group.get("myRole") else []
 own=snapshot(actor,own_groups)
 if name=="invite":pass
 if name=="request":own["outgoingRequests"]=[pending({5:2,7:3,17:7}[revision],revision+1,actor)]
 add("POST",BASE+"/"+G+"/"+name,actor,body,{"groups":own,"group":result_group})
read(A)
create={"userId":A,"expectedPlayerRevision":R,"name":"Guild","description":"","joinMode":"open","data":group(1)["data"]}
add("POST",BASE,A,create,{"groups":snapshot(A,[group(1,mode="open")]),"group":group(1,mode="open")})
add("GET",BASE+"/"+G+"?userId="+A,A,None,group(1,mode="open"))
update={"userId":A,"expectedRevision":1,"name":"Guild","description":"","joinMode":"request","data":group(2)["data"]}
add("PUT",BASE+"/"+G,A,update,{"groups":snapshot(A,[group(2)]),"group":group(2)})
action("invite",2,A,group(3),target=B)
read(B,incoming=[pending(1,3)])
action("accept-invite",3,B,group(4,actor=B,count=2),request=1)
page={"groupId":G,"revision":4,"members":[{"userId":A,"role":"leader","joinedAt":stamp(),"display":display()},{"userId":B,"role":"member","joinedAt":stamp(),"display":display()}],"nextAfterUserId":None,"serverTime":stamp()}
add("GET",BASE+"/"+G+"/members?userId="+B+"&limit=50",B,None,page)
add("GET",BASE+"/"+G+"/pending?userId="+B,B,None,{"code":"GROUP_PERMISSION_DENIED","message":"Members cannot decide invitations"},403)
add("GET",BASE+"/"+G+"?userId="+B,B,None,group(4,actor=B,count=2))
action("leave",4,B,None)
action("request",5,B,group(6,private=False),request=None)
p={"userId":B,"requestId":request_id(2),"issuerId":B,"createdAt":stamp()}
add("GET",BASE+"/"+G+"/pending?userId="+A,A,None,{"groupId":G,"revision":6,"invitations":[],"joinRequests":[p],"serverTime":stamp()})
action("decline-request",6,A,group(7),target=B,request=2)
action("request",7,B,group(8,private=False))
action("cancel-request",8,B,group(9,private=False),request=3)
action("invite",9,A,group(10),target=B)
action("cancel-invite",10,A,group(11),target=B,request=4)
action("invite",11,A,group(12),target=B)
action("decline-invite",12,B,group(13,private=False),request=5)
action("invite",13,A,group(14),target=B)
action("accept-invite",14,B,group(15,actor=B,count=2),request=6)
role={"userId":A,"expectedRevision":15,"targetUserId":B,"role":"officer"}
add("POST",BASE+"/"+G+"/role",A,role,{"groups":snapshot(A,[group(16,count=2)]),"group":group(16,count=2)})
action("remove",16,A,group(17),target=B)
action("request",17,B,group(18,private=False))
action("accept-request",18,A,group(19,count=2),target=B,request=7)
action("transfer",19,A,group(20,leader=B,count=2),target=B)
action("leave",20,A,None)
action("delete",21,B,None)
# Existing open group: successful explicit join and leave add the final app route.
add("POST",BASE+"/"+J+"/join",A,{"userId":A,"expectedRevision":42},{"groups":snapshot(A,[group(43,leader=B,count=2,id=J,mode="open")]),"group":group(43,leader=B,count=2,id=J,mode="open")})
add("POST",BASE+"/"+J+"/leave",A,{"userId":A,"expectedRevision":43},{"groups":snapshot(A),"group":None})
# Full-Inbox/revision errors are returned without replacing the reviewed intent.
# An uncertain create and metadata PUT each send once; explicit reads reconcile them.
uncertain=dict(create,expectedPlayerRevision=R+1000)
add("POST",BASE,A,uncertain,{"message":"uncertain create"},503)
read(A,[group(1,id=H,mode="open")])
add("POST",BASE+"/"+H+"/invite",A,{"userId":A,"expectedRevision":1,"targetUserId":B},{"code":"INBOX_FULL","message":"full"},409)
uncertain_update=dict(update,expectedRevision=1)
add("PUT",BASE+"/"+H,A,uncertain_update,{"message":"uncertain metadata"},503)
add("GET",BASE+"/"+H+"?userId="+A,A,None,group(2,id=H))
add("POST",BASE+"/"+H+"/delete",A,{"userId":A,"expectedRevision":2},{},429)
read(A,[group(2,id=H)])
add("POST",BASE+"/"+H+"/delete",A,{"userId":A,"expectedRevision":2},{"groups":snapshot(A),"group":None},delay=1.4)
read(A)
read(A) # Delayed read is fenced even if the session returns to the same string.
last=list(EXPECTED[-1]);last[-1]=.12;EXPECTED[-1]=tuple(last)

# Enforce the advertised route coverage mechanically, without running a page loop.
routes={(method,path.split("?",1)[0].replace(G,"{groupId}").replace(H,"{groupId}").replace(J,"{groupId}")) for method,path,*_ in EXPECTED}
assert len(routes)==20,routes

def encode(value):return json.dumps(value,ensure_ascii=False,separators=(",",":")).replace('"__precise__"','1.0000000000000000000001')
def decode(value):return json.loads(value,parse_float=Decimal)
class Handler(BaseHTTPRequestHandler):
 seen=0;failure=None
 def do_GET(self):self.handle_case("GET")
 def do_POST(self):self.handle_case("POST")
 def do_PUT(self):self.handle_case("PUT")
 def handle_case(self,method):
  index=type(self).seen;type(self).seen+=1
  if index>=len(EXPECTED):return self.reject("unexpected Groups retry/page-loop")
  verb,path,actor,expected,status,result,delay=EXPECTED[index]
  body=decode(self.rfile.read(int(self.headers.get("Content-Length",0)))) if method in ["POST","PUT"] else None
  expected=decode(encode(expected))
  if (method,self.path,body)!=(verb,path,expected):return self.reject("wrong route/original revision/requestId at request%d"%index)
  if self.headers.get("X-API-Key")!="groups-key" or self.headers.get("Authorization")!="Bearer group-session-"+("a" if actor==A else "b"):return self.reject("wrong player/project authentication")
  if delay:time.sleep(delay)
  try:
   # The same GroupView occurs at different depths: valid pretty JSON must not
   # turn a committed metadata update into INVALID_RESPONSE.
   wire=json.dumps(result,ensure_ascii=False,indent=2).replace('"__precise__"','1.0000000000000000000001') if index==3 else encode(result)
   payload=wire.encode("utf-8")
   self.send_response(status);self.send_header("Content-Type","application/json");self.send_header("Content-Length",str(len(payload)))
   if status==429:self.send_header("Retry-After","1")
   self.end_headers();self.wfile.write(payload)
  except (BrokenPipeError,ConnectionResetError):
   if delay!=1.4:self.reject("unexpected disconnect")
 def reject(self,message):
  type(self).failure=message;report_rejection(message)
  try:send_json(self,422,{"message":message})
  except (BrokenPipeError,ConnectionResetError):pass
 def log_message(self,*_args):pass
server=ThreadingHTTPServer(("127.0.0.1",20110),Handler);server.timeout=15
if os.environ.get("MOCK_SERVER_READY_FILE"):
 with open(os.environ["MOCK_SERVER_READY_FILE"],"w") as ready:ready.write("ready")
for _ in EXPECTED:server.handle_request()
server.timeout=1.5;server.handle_request();server.server_close()
if Handler.failure or Handler.seen!=len(EXPECTED):
 print(Handler.failure or "missing requests%d/%d"%(Handler.seen,len(EXPECTED)),file=sys.stderr);sys.exit(1)
print("Godot Groups fixture observed%d exact HTTP requests, all20 routes, two actors and single503/429/timeout sends"%Handler.seen)

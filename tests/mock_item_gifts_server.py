#!/usr/bin/env python3
"""Strict artificial Item Gifts consumer contract; no real accounts or persistence."""
import copy
import datetime as dt
import json
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
from uuid import UUID

SENDER = "20000000-0000-4000-8000-000000001140"
RECIPIENT = "30000000-0000-4000-8000-000000001140"
OTHER = "30000000-0000-4000-8000-000000001141"
INSTANCE = "40000000-0000-4000-8000-000000001140"
I2 = "40000000-0000-4000-8000-000000001141"
GIFT = "50000000-0000-4000-8000-000000001140"
G2 = "50000000-0000-4000-8000-000000001141"
UNKNOWN = "60000000-0000-4000-8000-000000009999"
OFFER_ENTRY = "message:70000000-0000-3000-8000-000000001140"
RETURN_ENTRY = "message:70000000-0000-3000-8000-000000001141"
ROOT = "/api/v1/app/item-gifts"
BASE = dt.datetime(2026, 11, 16, 10, tzinfo=dt.timezone.utc)
START = time.monotonic()
SAVED = {}
SAVED_RAW = {}
MAX = 9007199254740991
def iso(value): return value.isoformat(timespec="milliseconds").replace("+00:00", "Z")
def now(): return iso(BASE + dt.timedelta(seconds=time.monotonic() - START))
def stamp(): return iso(BASE)
def limits(lower=False):
    return {"openGiftsPerPlayer": 1 if lower else 2147483647, "retainedGiftsPerProject": 1 if lower else 10000, "projectWritesPerMinute": 1 if lower else 120, "historyPerPlayer": 20, "receivedPageSize": 50, "playerWriteIntervalMillis": 1000, "expirySeconds": 604800, "terminalRetentionSeconds": 604800, "operationRetentionSeconds": 2592000}
def config(fee=MAX, currency="1coin.gold"):
    return {"config": {"revision": 3, "enabled": True, "currencyKey": currency, "fee": fee}, "limits": limits(), "serverTime": now()}
def gift(id=GIFT, instance=INSTANCE, status="offered", revision=2, declined=False):
    terminal = status in ("claimed", "returned")
    return {"id": id, "revision": revision, "senderId": SENDER, "recipientId": RECIPIENT, "returnOwnerId": SENDER, "itemReference": {"instanceId": instance, "itemKey": "hat"}, "currencyKey": "1coin.gold", "fee": MAX, "configRevision": 3, "status": status, "createdAt": stamp(), "expiresAt": iso(BASE + dt.timedelta(days=7)), "terminalAt": stamp() if terminal else None, "declinedAt": stamp() if declined else None, "offerEntryId": OFFER_ENTRY, "returnEntryId": RETURN_ENTRY if status in ("return_delivered", "returned") else None, "ownerUnavailable": False}
def state(user=SENDER, revision=4, sent=None, history=None, received=None, lower=False):
    return {"state": {"userId": user, "revision": revision, "sent": sent or [], "history": history or [], "received": received or [], "operationWindow": {"serverTime": now(), "acceptAfter": iso(BASE - dt.timedelta(days=30))}, "limits": limits(lower)}, "serverTime": now()}
def inventory(user=SENDER, revision=10, instances=None):
    return {"userId": user, "revision": revision, "instances": instances or [], "limits": {"catalog": 6000, "inventory": 250, "receipts": 80}, "serverTime": now()}
def item(instance=INSTANCE):
    return {"instanceId": instance, "itemKey": "hat", "properties": {"power": MAX}, "equipped": False, "createdAt": stamp()}
def values(user=SENDER, revision=5):
    return {"userId": user, "day": "2026-11-16", "definitionVersion": 1, "revision": revision, "values": [{"key": "1coin.gold", "balance": 0, "earnedToday": 0, "dailyCap": None}], "operationWindow": {"serverTime": now(), "oldestAcceptedAt": iso(BASE - dt.timedelta(days=30))}}
def receipt(name):
    body = SAVED[name]
    return {"operationId": body["operationId"], "issuedAt": body["issuedAt"], "giftId": GIFT if name == "send" else G2, "giftRevision": 2, "recordedAt": stamp(), "recipientId": RECIPIENT, "itemReference": {"instanceId": body["instanceId"], "itemKey": "hat"}, "currencyKey": "1coin.gold", "fee": MAX, "configRevision": 3}
def written(name, replay=False, view=True):
    return {"receipt": receipt(name), "gift": (gift(GIFT) if name == "send" else gift(G2, I2)) if view else None, "replayed": replay, "serverTime": now()}
def entry(direction):
    offer = direction == "offer"
    gift_id = G2 if offer else GIFT
    return {"id": OFFER_ENTRY if offer else RETURN_ENTRY, "kind": "message", "type": "item_gift" if offer else "item_gift_return", "reference": gift_id, "textKey": "horizon.item_gifts." + direction, "parameters": {"senderId": SENDER} if offer else {"recipientId": RECIPIENT, "reason": "declined"}, "createdAt": stamp(), "expiresAt": iso(BASE + dt.timedelta(days=7 if offer else 30)), "read": False, "claimed": False, "overdue": False, "attachment": {"values": [], "itemGift": {"giftId": gift_id, "instanceId": I2 if offer else INSTANCE, "itemKey": "hat", "direction": direction}}}
def inbox(user, direction, claimed=False):
    row = entry(direction)
    if claimed: row.update(read=True, claimed=True)
    return {"userId": user, "cursor": direction + ("-claimed" if claimed else ""), "revision": 2 if claimed else 1, "broadcastRevision": 1, "serverTime": now(), "pollAfterSeconds": 120, "unchanged": False, "entries": [row], "counts": {"item_gift": {"total": 1, "unread": 0 if claimed else 1, "claimable": 0 if claimed else 1}}, "limits": {"targeted": 1, "broadcasts": 1, "freeTexts": 1, "freeTextBytes": 256, "freeTextRetentionDays": 7}}
def claim(user, direction):
    return {"entryId": OFFER_ENTRY if direction == "offer" else RETURN_ENTRY, "replayed": False, "inbox": inbox(user, direction, True), "playerValues": values(user, 6), "items": [{"instanceId": I2 if direction == "offer" else INSTANCE, "itemKey": "hat"}]}
def q(user=SENDER): return {"userId": [user]}
EXPECTED = []
def expect(method, path, response, query=None, body=None, user=SENDER, status=200, save=None, repeat=None, delay=0):
    EXPECTED.append(dict(method=method, path=path, response=response, query=query or {}, body=body, user=user, status=status, save=save, repeat=repeat, delay=delay))
# Sender: config, inventory, uncertain send, read-only recovery, confirmed restart.
expect("GET", ROOT + "/config", config, q())
expect("GET", "/api/v1/app/items", lambda: inventory(revision=9, instances=[item()]), q())
expect("POST", ROOT, {"code": "STATE_CONFLICT"}, body="send", status=409, save="send", delay=.2)
expect("GET", ROOT + "/operations/__SEND__", lambda: {"receipt": receipt("send"), "serverTime": now()}, q())
expect("GET", "/api/v1/app/items", {"code": "STATE_CONFLICT"}, q(), status=409)
expect("GET", "/api/v1/app/items", inventory, q())
expect("GET", "/api/v1/app/player-values", values, q())
expect("GET", ROOT, lambda: state(revision=5, sent=[gift()]), q())
expect("POST", ROOT, lambda: written("send", True), body="send", repeat="send")
expect("POST", ROOT, {"code": "OPERATION_CONFLICT"}, body="changed", status=409)
expect("GET", ROOT + "/operations/" + UNKNOWN, {"code": "OPERATION_NOT_FOUND"}, q(), status=404)
# Identity switch while the second send is in flight: the reply is stale, the original stays with the sender.
expect("GET", "/api/v1/app/items", lambda: inventory(revision=11, instances=[item(I2)]), q())
expect("POST", ROOT, lambda: written("send2"), body="send2", save="send2", status=201, delay=.4)
expect("POST", ROOT, lambda: written("send2", True), body="send2", repeat="send2")
expect("GET", "/api/v1/app/items", lambda: inventory(revision=12), q())
expect("GET", "/api/v1/app/player-values", lambda: values(revision=6), q())
expect("GET", ROOT, lambda: state(revision=6, sent=[gift(), gift(G2, I2)], lower=True), q())
# Recipient: received offers, point read, decline and its replay, then claim of the other offer.
expect("GET", ROOT, lambda: state(RECIPIENT, 2, received=[gift(), gift(G2, I2)]), q(RECIPIENT), user=RECIPIENT)
expect("GET", ROOT + "/" + GIFT, lambda: {"gift": gift(), "serverTime": now()}, q(RECIPIENT), user=RECIPIENT)
expect("POST", ROOT + "/" + GIFT + "/decline", lambda: {"gift": gift(status="return_delivered", revision=4, declined=True), "replayed": False, "returnDelivery": "delivered", "serverTime": now()}, body={"userId": RECIPIENT, "expectedGiftRevision": 2}, user=RECIPIENT)
expect("POST", ROOT + "/" + GIFT + "/decline", lambda: {"gift": gift(status="return_delivered", revision=4, declined=True), "replayed": True, "returnDelivery": "delivered", "serverTime": now()}, body={"userId": RECIPIENT, "expectedGiftRevision": 2}, user=RECIPIENT)
expect("GET", "/api/v1/app/inbox", lambda: inbox(RECIPIENT, "offer"), q(RECIPIENT), user=RECIPIENT)
expect("POST", "/api/v1/app/inbox/claim", lambda: claim(RECIPIENT, "offer"), body={"userId": RECIPIENT, "entryId": OFFER_ENTRY}, user=RECIPIENT)
expect("GET", ROOT + "/" + UNKNOWN, {"code": "GIFT_NOT_FOUND"}, q(RECIPIENT), user=RECIPIENT, status=404)
# Sender: return entry claim, rate limit, malformed config.
expect("GET", "/api/v1/app/inbox", lambda: inbox(SENDER, "return"), q())
expect("POST", "/api/v1/app/inbox/claim", lambda: claim(SENDER, "return"), body={"userId": SENDER, "entryId": RETURN_ENTRY})
expect("POST", ROOT, {"code": "ITEM_GIFTS_RATE_LIMITED"}, body="changed", status=429)
expect("GET", ROOT + "/config", lambda: config(5, None), q())

class Handler(BaseHTTPRequestHandler):
    index = 0
    failed = False
    lock = threading.Lock()
    def log_message(self, *_): pass
    def do_GET(self): self.handle_contract()
    def do_POST(self): self.handle_contract()
    def handle_contract(self):
        try:
            with self.lock:
                step = type(self).index
                assert step < len(EXPECTED), "Unexpected extra transport attempt"
                expected = EXPECTED[step]; type(self).index += 1
            path = expected["path"].replace("__SEND__", SAVED.get("send", {}).get("operationId", ""))
            actual = urlparse(self.path)
            assert self.command == expected["method"] and actual.path == path, (step + 1, self.command, actual.path, expected["method"], path)
            assert parse_qs(actual.query) == expected["query"], (step + 1, parse_qs(actual.query), expected["query"])
            assert self.headers.get("X-API-Key") == "gift-fixture-key"
            assert self.headers.get("Authorization") == "Bearer gift-" + ("sender" if expected["user"] == SENDER else "recipient") + "-session"
            raw = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            body = json.loads(raw) if raw else None
            target = expected["body"]
            if isinstance(target, str):
                assert str(UUID(body["operationId"])) == body["operationId"]
                assert iso(dt.datetime.fromisoformat(body["issuedAt"].replace("Z", "+00:00"))) == body["issuedAt"]
                second = target == "send2"
                original = {"userId": SENDER, "operationId": body["operationId"], "issuedAt": body["issuedAt"], "recipientId": OTHER if target == "changed" else RECIPIENT, "instanceId": I2 if second else INSTANCE, "expectedInventoryRevision": 11 if second else 9, "expectedConfigRevision": 3}
                assert body == original, (step + 1, body, original)
                if expected["repeat"]: assert raw == SAVED_RAW[expected["repeat"]], "Original bytes changed on retry"
                if target == "changed": assert body["operationId"] == SAVED["send"]["operationId"] and body["issuedAt"] == SAVED["send"]["issuedAt"]
                if expected["save"]: SAVED[expected["save"]] = copy.deepcopy(body); SAVED_RAW[expected["save"]] = raw
            else: assert body == target, (step + 1, body, target)
            if expected["delay"]: time.sleep(expected["delay"])
            value = expected["response"]() if callable(expected["response"]) else expected["response"]
            encoded = json.dumps(value, ensure_ascii=True, separators=(",", ":")).encode()
            self.send_response(expected["status"]); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(encoded)))
            if expected["status"] == 429: self.send_header("Retry-After", "1")
            self.end_headers(); self.wfile.write(encoded)
        except (BrokenPipeError, ConnectionResetError): pass
        except Exception as error:
            type(self).failed = True
            print("FAIL Item Gifts exact fixture:", repr(error), flush=True)
            self.send_error(500)

def main():
    server = ThreadingHTTPServer(("127.0.0.1", int(os.environ.get("HORIZON_ITEM_GIFTS_FIXTURE_PORT", "20140"))), Handler)
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    if os.environ.get("MOCK_SERVER_READY_FILE"):
        with open(os.environ["MOCK_SERVER_READY_FILE"], "w") as file: file.write("ready")
    deadline = time.monotonic() + 120
    while Handler.index < len(EXPECTED) and not Handler.failed and time.monotonic() < deadline: time.sleep(.05)
    time.sleep(.5); server.shutdown(); server.server_close()
    assert not Handler.failed and Handler.index == len(EXPECTED), ("Missing or invalid requests", Handler.index, len(EXPECTED))
    print(f"PASS Item Gifts strict HTTP: {len(EXPECTED)} exact requests/all six routes,original bytes/recovery,identity switch,decline replay and Inbox offer/return claims", flush=True)

if __name__ == "__main__": main()

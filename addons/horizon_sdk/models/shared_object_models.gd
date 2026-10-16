class_name HorizonSharedObjectModels
extends RefCounted
## Opaque bytes and exact typed metadata. The existing strict parser preserves integer lexemes/NUL.
const MAX := 9007199254740991
const MAX_OBJECT := 65536
const MAX_PAGE := 1048576
static var _base64: RegEx = RegEx.create_from_string("^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?\\z")
static func integer(value: Variant, minimum: int = 0) -> bool: return HorizonItemModels.integer(value, minimum)
static func key(value: Variant) -> bool: return HorizonItemModels.key(value)
static func uuid(value: Variant) -> bool: return HorizonItemModels.uuid(value)
static func time(value: Variant) -> bool: return HorizonItemModels.time(value)
static func parse(raw: String) -> Dictionary: return HorizonItemModels.parse(raw, 2097152)
static func text(value: Variant, maximum: int) -> bool:
	return value.to_utf8_buffer().size() <= maximum if value is String else value is HorizonItemStringData and value.getUtf8ByteCount() <= maximum
static func encode(value: Variant) -> String:
	if value == null: return "null"
	if value is HorizonItemStringData: return value.getJson()
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var parts: PackedStringArray = []
		for name: String in keys: parts.append(HorizonItemModels.quote(name) + ":" + encode(value[name]))
		return "{" + ",".join(parts) + "}"
	if value is Array:
		var parts: PackedStringArray = []
		for child: Variant in value: parts.append(encode(child))
		return "[" + ",".join(parts) + "]"
	return HorizonItemModels.canonical(value)
static func limits(value: Variant) -> bool:
	return value is Dictionary and integer(value.get("collections"), 1) and value.collections <= 100 and integer(value.get("storageBytes"), 1) and value.storageBytes <= 2147483648 and integer(value.get("objectBytes"), 1) and value.objectBytes <= MAX_OBJECT
static func search(value: Variant) -> bool:
	if not value is Dictionary or value.size() > 3: return false
	for field: Variant in value:
		if not key(field) or (not integer(value[field], -MAX) and not text(value[field], 96)): return false
	return true
static func position(value: Variant) -> bool:
	return value == null or (value is Dictionary and value.size() == 2 and integer(value.get("x"), -MAX) and integer(value.get("y"), -MAX))
static func definition(value: Variant) -> bool:
	if not value is Dictionary or not key(value.get("key")) or not text(value.get("name"), 120) or not value.get("active") is bool or not value.get("used") is bool or not value.get("positionEnabled") is bool or not integer(value.get("revision"), 1): return false
	if value.get("readPolicy") not in ["owner", "friends", "group", "all", "dashboard"] or value.get("writePolicy") not in ["owner", "group", "dashboard"] or not integer(value.get("maxObjectBytes"), 1) or value.maxObjectBytes > MAX_OBJECT or not integer(value.get("maxObjectsPerOwner"), 1) or value.maxObjectsPerOwner > 100 or not value.has("ttlSeconds"): return false
	if value.ttlSeconds != null and (not integer(value.ttlSeconds, 60) or value.ttlSeconds > 2592000): return false
	var fields: Variant = value.get("searchFields")
	if not fields is Array or fields.size() > 3: return false
	var seen: Dictionary = {}
	for field: Variant in fields:
		if not field is Dictionary or not key(field.get("key")) or field.get("type") not in ["integer", "string"] or seen.has(field.key): return false
		seen[field.key] = true
	return true
static func usage(value: Variant, collection: String, owner: String = "") -> bool:
	return value is Dictionary and uuid(value.get("userId")) and (owner.is_empty() or value.userId == owner) and value.get("collection") == collection and integer(value.get("revision")) and integer(value.get("count")) and value.count <= 100 and limits(value.get("limits")) and integer(value.get("pollAfterSeconds"), 1) and time(value.get("serverTime"))
static func encodeBytes(value: PackedByteArray) -> String: return "" if value.is_empty() else Marshalls.raw_to_base64(value)
static func decodeBytes(value: Variant) -> Variant:
	if not value is String or value.length() > 87384 or _base64.search(value) == null: return null
	if value.is_empty(): return PackedByteArray()
	var bytes: PackedByteArray = Marshalls.base64_to_raw(value)
	return bytes if bytes.size() <= MAX_OBJECT and encodeBytes(bytes) == value else null
static func object(value: Variant, collection: String, id: String = "") -> Dictionary:
	if not value is Dictionary: return {}
	for required: String in ["id", "collection", "ownerId", "groupId", "revision", "dataBase64", "search", "position", "createdAt", "updatedAt", "expiresAt"]:
		if not value.has(required): return {}
	if not uuid(value.id) or (not id.is_empty() and value.id.to_lower() != id.to_lower()) or value.collection != collection or not uuid(value.ownerId) or (value.groupId != null and not uuid(value.groupId)) or not integer(value.revision, 1) or not search(value.search) or not position(value.position): return {}
	if not time(value.createdAt) or not time(value.updatedAt) or (value.expiresAt != null and not time(value.expiresAt)): return {}
	var bytes: Variant = decodeBytes(value.dataBase64)
	if not bytes is PackedByteArray: return {}
	var result: Dictionary = value.duplicate(true)
	result.data = bytes
	return result
static func response(raw: Dictionary, kind: String, user: String, collection: String, id: String, expected: Variant, options: Dictionary) -> Dictionary:
	if not time(raw.get("serverTime")): return {}
	if kind == "collections":
		if not integer(raw.get("revision")) or not limits(raw.get("limits")) or not raw.get("definitions") is Array or raw.definitions.size() > options.limit or not raw.has("nextAfterKey"): return {}
		var previous: String = options.afterKey
		for entry: Variant in raw.definitions:
			if not definition(entry) or entry.key <= previous or entry.revision > raw.revision: return {}
			previous = entry.key
		if raw.nextAfterKey != null and (raw.definitions.size() != options.limit or raw.nextAfterKey != previous or not key(raw.nextAfterKey)): return {}
		if options.catalogRevision != null and raw.revision != options.catalogRevision: return {}
		return raw.duplicate(true)
	if not integer(raw.get("pollAfterSeconds"), 1): return {}
	if kind == "usage": return raw.duplicate(true) if usage(raw, collection, user) else {}
	if kind == "query":
		if not raw.get("objects") is Array or raw.objects.size() > options.get("limit", 20) or not raw.has("nextCursor") or (raw.nextCursor != null and (not raw.nextCursor is String or raw.nextCursor.is_empty() or raw.nextCursor.length() > 2048)) or (options.mode == "random" and raw.nextCursor != null): return {}
		var result: Dictionary = raw.duplicate(true)
		var rows: Array = []
		var bytes: int = 0
		var seen: Dictionary = {}
		for row: Variant in raw.objects:
			var parsed: Dictionary = object(row, collection)
			if parsed.is_empty() or seen.has(parsed.id.to_lower()): return {}
			seen[parsed.id.to_lower()] = true
			bytes += parsed.data.size()
			if bytes > MAX_PAGE: return {}
			rows.append(parsed)
		result.objects = rows
		return result
	if kind == "delete":
		return raw.duplicate(true) if uuid(raw.get("objectId")) and raw.objectId.to_lower() == id.to_lower() and raw.get("deleted") is bool and raw.deleted and usage(raw.get("usage"), collection) else {}
	var parsed: Dictionary = object(raw.get("object"), collection, id)
	if parsed.is_empty(): return {}
	if kind != "get" and (not usage(raw.get("usage"), collection, parsed.ownerId) or (kind == "create" and (parsed.ownerId != user or parsed.revision != 1 or raw.usage.revision != expected + 1)) or (kind == "update" and parsed.revision != expected + 1)): return {}
	var result: Dictionary = raw.duplicate(true)
	result.object = parsed
	return result
static func query(value: Variant) -> bool:
	if not value is Dictionary or value.has("userId"): return false
	var mode: Variant = value.get("mode")
	var extra: Dictionary = {"list": [], "owner": [], "field": ["field", "equal", "min", "max"], "random": ["field", "min", "max"], "rectangle": ["minX", "maxX", "minY", "maxY"]}
	if not mode is String or not extra.has(mode): return false
	for name: Variant in value:
		if not name in (["ownerId", "groupId", "mode", "limit", "cursor"] + extra[mode]): return false
	for name: String in ["ownerId", "groupId"]:
		if value.has(name) and not uuid(value[name]): return false
	if mode == "owner" and not value.has("ownerId"): return false
	if value.has("limit") and (not integer(value.limit, 1) or value.limit > 50): return false
	if value.has("cursor") and (mode == "random" or not value.cursor is String or value.cursor.is_empty() or value.cursor.length() > 2048): return false
	if mode in ["field", "random"]:
		if not key(value.get("field")): return false
		if value.has("equal"):
			if mode == "random" or value.has("min") or value.has("max") or (not integer(value.equal, -MAX) and not text(value.equal, 96)): return false
		else:
			if not value.has("min") or not value.has("max"): return false
			if mode == "random":
				if not integer(value.min, -MAX) or not integer(value.max, -MAX) or value.min > value.max: return false
			elif integer(value.min, -MAX) and integer(value.max, -MAX):
				if value.min > value.max: return false
			elif not text(value.min, 96) or not text(value.max, 96): return false
	if mode == "rectangle":
		for name: String in ["minX", "maxX", "minY", "maxY"]:
			if not integer(value.get(name), -MAX): return false
		if value.minX > value.maxX or value.minY > value.maxY: return false
	return true

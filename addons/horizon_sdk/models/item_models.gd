class_name HorizonItemModels
extends RefCounted
## Strict original wire integers and the shared canonical property byte contract.
const MAX := 9007199254740991
# Wire field/encoding bounds, independent of configurable product quotas.
const INT32_MAX := 2147483647
const TEMPLATE_SLOT_CAPACITY := 65536
static var _key: RegEx = RegEx.create_from_string("^[a-z][a-z0-9_]{0,63}\\z")
static var _uuid: RegEx = RegEx.create_from_string("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\\z")
# Consume ordinary string runs as one possessive chunk: a legal large opaque
# state must not exhaust PCRE's per-character backtracking/match budget.
static var _tokens: RegEx = RegEx.create_from_string('"(?:[^"\\\\]++|\\\\.)*+"|[{}\\[\\]:,]|true|false|null|-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?')
static var _integer: RegEx = RegEx.create_from_string("^-?(0|[1-9][0-9]*)\\z")
static var _hex: RegEx = RegEx.create_from_string("^[0-9a-fA-F]{4}\\z")

static func key(value: Variant) -> bool: return value is String and _key.search(value) != null
static func uuid(value: Variant) -> bool: return value is String and _uuid.search(value) != null
static func integer(value: Variant, minimum: int = 0) -> bool: return typeof(value) == TYPE_INT and value >= minimum and value <= MAX
static func time(value: Variant) -> bool: return value is String and HorizonPlayerValues._timeMillis(value) >= 0

## All numeric fields in Items are integers. Parse before native JSON can round or coerce them.
static func parse(json: String, max_bytes: int = 1048576) -> Dictionary:
	if max_bytes < 1 or max_bytes > 2097152 or json.to_utf8_buffer().size() > max_bytes: return {}
	return parseTransport(json)

## Lossless grammar without importing an unrelated feature's response-byte frame.
## Callers still enforce their own field/encoding contracts; HTTP owns the received body.
static func parseTransport(json: String) -> Dictionary:
	var tokens: Array[RegExMatch] = _tokens.search_all(json)
	var end: int = 0
	for token: RegExMatch in tokens:
		if not _space(json.substr(end, token.get_start() - end)): return {}
		end = token.get_end()
	if not _space(json.substr(end)): return {}
	var position: Array[int] = [0]
	var valid: Array[bool] = [true]
	var value: Variant = _read(tokens, position, valid, 0)
	return value if valid[0] and position[0] == tokens.size() and value is Dictionary else {}

static func _space(text: String) -> bool: return text.replace(" ", "").replace("\t", "").replace("\r", "").replace("\n", "").is_empty()
static func _read(tokens: Array[RegExMatch], position: Array[int], valid: Array[bool], depth: int) -> Variant:
	if depth > 16 or position[0] >= tokens.size(): valid[0] = false; return null
	var text: String = tokens[position[0]].get_string()
	position[0] += 1
	if text in ["{", "["]:
		var object: bool = text == "{"
		var result: Variant = {} if object else []
		var close: String = "}" if object else "]"
		if position[0] < tokens.size() and tokens[position[0]].get_string() == close: position[0] += 1; return result
		while position[0] < tokens.size():
			var name: String = ""
			if object:
				var decoded: Variant = _string(tokens[position[0]].get_string())
				position[0] += 1
				if not decoded is String or result.has(decoded) or position[0] >= tokens.size() or tokens[position[0]].get_string() != ":": valid[0] = false; return null
				name = decoded
				position[0] += 1
			var child: Variant = _read(tokens, position, valid, depth + 1)
			if not valid[0]: return null
			if object: result[name] = child
			else: result.append(child)
			if position[0] >= tokens.size(): break
			var separator: String = tokens[position[0]].get_string()
			position[0] += 1
			if separator == close: return result
			if separator != ",": break
		valid[0] = false
		return null
	if text.begins_with('"'):
		var decoded: Variant = _string(text)
		if not decoded is String and not decoded is HorizonItemStringData: valid[0] = false
		return decoded
	if text == "true": return true
	if text == "false": return false
	if text == "null": return null
	if _integer.search(text) != null and text.length() <= 17 and integer(int(text), -MAX): return int(text)
	valid[0] = false
	return null

static func _string(text: String) -> Variant:
	if not text.begins_with('"') or not text.ends_with('"'): return null
	var index: int = 1
	var cuts: Array[int] = []
	while index < text.length() - 1:
		var code: int = text.unicode_at(index)
		if code < 32 or (code >= 0xd800 and code <= 0xdfff): return null
		if code == 92:
			index += 1
			if index >= text.length() - 1: return null
			var escape: String = text.substr(index, 1)
			if escape == "u":
				var digits: String = text.substr(index + 1, 4)
				if _hex.search(digits) == null: return null
				var unit: int = digits.hex_to_int()
				# Godot cannot hold NUL. Decode its surrounding valid segments separately.
				if unit == 0: cuts.append(index - 1)
				if unit >= 0xd800 and unit <= 0xdbff:
					var low: String = text.substr(index + 7, 4)
					if text.substr(index + 5, 2) != "\\u" or _hex.search(low) == null or low.hex_to_int() < 0xdc00 or low.hex_to_int() > 0xdfff: return null
					index += 10
				elif unit >= 0xdc00 and unit <= 0xdfff: return null
				else: index += 4
			elif not escape in ['"', "\\", "/", "b", "f", "n", "r", "t"]: return null
		index += 1
	if cuts.is_empty(): return JSON.parse_string(text)
	var parts: PackedStringArray = []
	var start: int = 1
	for cut: int in cuts:
		parts.append(JSON.parse_string('"' + text.substr(start, cut - start) + '"'))
		start = cut + 6
	parts.append(JSON.parse_string('"' + text.substr(start, text.length() - start - 1) + '"'))
	return HorizonItemStringData._fromParts(parts, text)

static func quote(value: String) -> String:
	var result: String = '"'
	for character: String in value:
		var code: int = character.unicode_at(0)
		match code:
			34: result += '\\"'
			92: result += "\\\\"
			8: result += "\\b"
			9: result += "\\t"
			10: result += "\\n"
			12: result += "\\f"
			13: result += "\\r"
			_: result += ("\\u%04x" % code) if code < 32 else character
	return result + '"'

static func canonical(value: Variant) -> String:
	if value is HorizonItemStringData: return value.getJson()
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var fields: PackedStringArray = []
		for name: String in keys: fields.append(quote(name) + ":" + canonical(value[name]))
		return "{" + ",".join(fields) + "}"
	if value is Array:
		var entries: PackedStringArray = []
		for child: Variant in value: entries.append(canonical(child))
		return "[" + ",".join(entries) + "]"
	if value is String: return quote(value)
	if value is bool: return "true" if value else "false"
	return str(value)

static func properties(raw: Variant) -> Variant:
	if not raw is Dictionary or raw.size() > 16: return null
	for name: Variant in raw:
		var value: Variant = raw[name]
		if not key(String(name)) or (not value is String and not value is HorizonItemStringData and not value is bool and not integer(value, -MAX)): return null
	if canonical(raw).to_utf8_buffer().size() > 256: return null
	return raw.duplicate(true)

static func limits(raw: Variant) -> Dictionary:
	if not raw is Dictionary: return {}
	for field: String in ["catalog", "inventory", "receipts"]:
		if not integer(raw.get(field), 1) or raw[field] > INT32_MAX: return {}
	return {"catalog": raw.catalog, "inventory": raw.inventory, "receipts": raw.receipts}

static func references(raw: Variant) -> Variant:
	if not raw is Array or raw.size() > 4: return null
	var ids: Dictionary = {}
	var result: Array = []
	for entry: Variant in raw:
		if not entry is Dictionary or not uuid(entry.get("instanceId")) or not key(entry.get("itemKey")) or ids.has(entry.instanceId.to_lower()): return null
		ids[entry.instanceId.to_lower()] = true
		result.append({"instanceId": entry.instanceId, "itemKey": entry.itemKey})
	return result

## PV receives native parsed numbers; its original wire quantity tokens are checked first.
static func rewards(raw: Variant) -> Variant:
	if not raw is Array or raw.size() > 4: return null
	var result: Array = []
	var seen: Dictionary = {}
	var total: int = 0
	for entry: Variant in raw:
		if not entry is Dictionary or not key(entry.get("itemKey")) or not HorizonPlayerValues._safeNumber(entry.get("quantity")) or entry.quantity < 1 or entry.quantity > 4 or seen.has(entry.itemKey): return null
		seen[entry.itemKey] = true
		total += int(entry.quantity)
		result.append({"itemKey": entry.itemKey, "quantity": int(entry.quantity)})
	return result if total <= 4 else null

static func inventory(raw: Dictionary, user: String) -> Dictionary:
	if raw.get("userId") != user or not integer(raw.get("revision")) or not time(raw.get("serverTime")): return {}
	var cap: Dictionary = limits(raw.get("limits"))
	var instances: Variant = raw.get("instances")
	if cap.is_empty() or not instances is Array: return {}
	var seen: Dictionary = {}
	var rows: Array = []
	for item: Variant in instances:
		if not item is Dictionary or not uuid(item.get("instanceId")) or seen.has(item.instanceId.to_lower()) or not key(item.get("itemKey")) or not item.get("equipped") is bool or not time(item.get("createdAt")): return {}
		var props: Variant = properties(item.get("properties"))
		if props == null: return {}
		seen[item.instanceId.to_lower()] = true
		rows.append({"instanceId": item.instanceId, "itemKey": item.itemKey, "properties": props, "equipped": item.equipped, "createdAt": item.createdAt})
	return {"userId": user, "revision": raw.revision, "instances": rows, "limits": cap, "serverTime": raw.serverTime}

static func _name(value: Variant) -> bool:
	if value is HorizonItemStringData: return value.getUtf8ByteCount() <= 120
	return value is String and not value.strip_edges().is_empty() and value.to_utf8_buffer().size() <= 120

static func template(raw: Variant) -> Dictionary:
	if not raw is Dictionary or not key(raw.get("key")) or not _name(raw.get("name")) or not key(raw.get("type")) or not key(raw.get("rarity")) or not raw.get("active") is bool: return {}
	var props: Variant = properties(raw.get("baseProperties"))
	var rules: Variant = raw.get("propertyRules")
	if props == null or not rules is Array or rules.size() > 16: return {}
	var seen: Dictionary = {}
	var entries: Array = []
	for rule: Variant in rules:
		if not rule is Dictionary or not key(rule.get("key")) or seen.has(rule.key) or not integer(rule.get("min"), -MAX) or not integer(rule.get("max"), -MAX) or not integer(rule.get("maxChangePerCall"), 1) or rule.min > rule.max or not integer(props.get(rule.key), -MAX) or props[rule.key] < rule.min or props[rule.key] > rule.max: return {}
		seen[rule.key] = true
		entries.append({"key": rule.key, "min": rule.min, "max": rule.max, "maxChangePerCall": rule.maxChangePerCall})
	var result: Dictionary = {"key": raw.key, "name": raw.name, "type": raw.type, "rarity": raw.rarity, "active": raw.active, "baseProperties": props, "propertyRules": entries}
	return result if canonical(result).to_utf8_buffer().size() <= 2048 else {}

static func page(raw: Dictionary, after: String, limit: int) -> Dictionary:
	if not integer(raw.get("revision")) or not integer(raw.get("total")) or raw.total > TEMPLATE_SLOT_CAPACITY or not time(raw.get("serverTime")) or not raw.has("nextAfterKey"): return {}
	var cap: Dictionary = limits(raw.get("limits"))
	var definitions: Variant = raw.get("definitions")
	if cap.is_empty() or not definitions is Array or definitions.size() > limit or raw.total < definitions.size(): return {}
	var previous: String = after
	var rows: Array = []
	for definition: Variant in definitions:
		var row: Dictionary = template(definition)
		if row.is_empty() or row.key <= previous: return {}
		previous = row.key
		rows.append(row)
	if raw.nextAfterKey != null and (not key(raw.nextAfterKey) or rows.size() != limit or raw.nextAfterKey != previous): return {}
	return {"revision": raw.revision, "definitions": rows, "nextAfterKey": raw.nextAfterKey, "total": raw.total, "limits": cap, "serverTime": raw.serverTime}

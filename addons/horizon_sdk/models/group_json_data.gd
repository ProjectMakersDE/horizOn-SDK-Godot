class_name HorizonGroupJsonData
extends RefCounted
## Original JSON object. Keep this value when changing other group metadata.
## getPreview() uses Godot numbers for display only and may round large numbers.
# Godot Variant/JSON engine serialization boundary, not GROUP_DATA_MAX_DEPTH.
# https://github.com/godotengine/godot/blob/master/core/variant/variant.h
const ENGINE_JSON_DEPTH: int = 1024
static var _raw_controls: RegEx = RegEx.create_from_string("[\\x00-\\x1f]")
var _json: String = ""
var _bytes: int = 0
var _comparison: String = ""
func getJson() -> String: return _json
func getPreview() -> Dictionary:
	var value: Variant = JSON.parse_string(_json)
	return value if value is Dictionary else {}
func isValid() -> bool: return not _json.is_empty()

static func fromJson(json: String) -> HorizonGroupJsonData:
	var tokens: Array[Token] = tokenize(json)
	if tokens.is_empty() or tokens[0].get_string() != "{": return null
	var previous: int = 0
	var lexemes: PackedStringArray = []
	for token: Token in tokens:
		if not _whitespace(json.substr(previous, token.get_start() - previous)): return null
		var text: String = token.get_string()
		if text.begins_with('"') and _raw_controls.search(text) != null: return null
		lexemes.append(text)
		previous = token.get_end()
	if not _whitespace(json.substr(previous)): return null
	var position: Array[int] = [0]
	var canonical: Variant = _canonical(tokens, position, 0)
	if not canonical is String or position[0] != tokens.size(): return null
	var parsed: Variant = JSON.parse_string(json)
	if not parsed is Dictionary or not isJsonValue(parsed, 0): return null
	var data := HorizonGroupJsonData.new()
	data._json = "".join(lexemes)
	data._bytes = canonical.to_utf8_buffer().size()
	data._comparison = canonical
	return data

static func _whitespace(text: String) -> bool:
	return text.replace(" ", "").replace("\t", "").replace("\r", "").replace("\n", "").is_empty()

## Strict grammar before Godot's permissive parser. The comparison sorts object
## keys and normalizes string escapes, preserving exact number lexemes and arrays.
static func _canonical(tokens: Array[Token], position: Array[int], depth: int) -> Variant:
	# Iterative grammar/tree walk: configurable nesting must not overflow the GDScript call stack.
	var frames: Array[Dictionary] = []
	var root: Dictionary = {}
	while position[0] < tokens.size():
		var text: String = tokens[position[0]].get_string()
		if frames.is_empty():
			if not root.is_empty() or text not in ["{", "["]: return null
			frames.append(_frame(text)); position[0] += 1; continue
		var frame: Dictionary = frames.back()
		var close: String = "}" if frame.kind == "{" else "]"
		if text == close and frame.state in ["separator", "key_or_end", "value_or_end"]:
			frames.pop_back(); position[0] += 1
			if frames.is_empty(): root = frame; break
			_put(frames.back(), frame); continue
		if frame.state == "separator":
			if text != ",": return null
			frame.state = "key" if frame.kind == "{" else "value"
			position[0] += 1; continue
		if frame.state in ["key", "key_or_end"]:
			if not text.begins_with('"'): return null
			var key: Variant = JSON.parse_string(text)
			if not key is String or frame.entries.has(key): return null
			frame.key = key; frame.state = "colon"; position[0] += 1; continue
		if frame.state == "colon":
			if text != ":": return null
			frame.state = "value"; position[0] += 1; continue
		if frame.state not in ["value", "value_or_end"]: return null
		if text in ["{", "["]:
			if frames.size() + depth >= ENGINE_JSON_DEPTH: return null
			frames.append(_frame(text)); position[0] += 1; continue
		var leaf: Variant = _leaf(text)
		if not leaf is String: return null
		_put(frame, leaf); position[0] += 1
	if root.is_empty() or not frames.is_empty(): return null
	var output: PackedStringArray = []
	var nodes: Array = [root]
	while not nodes.is_empty():
		var node: Variant = nodes.pop_back()
		if node is String: output.append(node); continue
		if node.kind == "{":
			output.append("{"); nodes.append("}")
			var keys: Array = node.entries.keys(); keys.sort()
			for index: int in range(keys.size() - 1, -1, -1):
				nodes.append(node.entries[keys[index]])
				nodes.append(("," if index > 0 else "") + JSON.stringify(keys[index]) + ":")
		else:
			output.append("["); nodes.append("]")
			for index: int in range(node.values.size() - 1, -1, -1):
				nodes.append(node.values[index])
				if index > 0: nodes.append(",")
	return "".join(output)

static func _frame(kind: String) -> Dictionary:
	return {"kind": kind, "state": "key_or_end" if kind == "{" else "value_or_end", "entries": {}, "values": [], "key": ""}
static func _put(frame: Dictionary, node: Variant) -> void:
	if frame.kind == "{": frame.entries[frame.key] = node
	else: frame.values.append(node)
	frame.state = "separator"
static func _leaf(text: String) -> Variant:
	if text.begins_with('"'):
		var value: Variant = JSON.parse_string(text)
		return JSON.stringify(value) if value is String else null
	if text in ["null", "true", "false"]: return text
	return text if RegEx.create_from_string("^-?(0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\\z").search(text) != null else null

static func fromDictionary(data: Dictionary) -> HorizonGroupJsonData:
	if not isJsonValue(data, 0): return null
	return fromJson(JSON.stringify(data, "", true, true))

static func isJsonValue(value: Variant, depth: int) -> bool:
	var pending: Array[Dictionary] = [{"value": value, "depth": depth}]
	var active: Array = []
	while not pending.is_empty():
		var entry: Dictionary = pending.pop_back()
		if entry.has("exit"): active.pop_back(); continue
		if entry.depth > ENGINE_JSON_DEPTH: return false
		var item: Variant = entry.value
		match typeof(item):
			TYPE_NIL, TYPE_BOOL, TYPE_STRING, TYPE_INT: continue
			TYPE_FLOAT:
				if not is_finite(item): return false
			TYPE_ARRAY, TYPE_DICTIONARY:
				for parent: Variant in active:
					if is_same(parent, item): return false
				active.append(item); pending.append({"exit": true})
				if item is Dictionary:
					for key: Variant in item:
						if not key is String and not key is StringName: return false
				var children: Array = item.values() if item is Dictionary else item
				for child: Variant in children: pending.append({"value": child, "depth": entry.depth + 1})
			_: return false
	return true

# The received Groups envelope may contain millions of escaped characters.
# PCRE's fixed match budget is not a product quota: find complete strings with
# native String.find, then keep the existing strict grammar/token validation.
class Token:
	var text: String
	var start: int
	var end: int
	func _init(value: String, first: int, last: int) -> void: text = value; start = first; end = last
	func get_string() -> String: return text
	func get_start() -> int: return start
	func get_end() -> int: return end
static var _plain_token: RegEx = RegEx.create_from_string('[ \t\r\n]++|[{}\\[\\]:,]|true|false|null|-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?')
static func tokenize(json: String) -> Array[Token]:
	var result: Array[Token] = []
	var position: int = 0
	while position < json.length():
		var end: int
		if json.unicode_at(position) == 34:
			end = json.find('"', position + 1)
			while end >= 0:
				var slash: int = end - 1
				while slash > position and json.unicode_at(slash) == 92: slash -= 1
				if (end - slash - 1) % 2 == 0: break
				end = json.find('"', end + 1)
			if end < 0: return []
			end += 1
		else:
			var found: RegExMatch = _plain_token.search(json, position)
			if found == null or found.get_start() != position: return []
			end = found.get_end()
			if _whitespace(found.get_string()): position = end; continue
		var text: String = json.substr(position, end - position)
		if text.begins_with('"') and _raw_controls.search(text) != null: return []
		result.append(Token.new(text, position, end))
		position = end
	return result

## Match original data to its enclosing GroupView ID, skipping complete inner data
## objects so arbitrary nested id/data keys cannot impersonate another GroupView.
static func extract(json: String) -> Dictionary:
	var matches: Array[Token] = tokenize(json)
	var stack: Array = []
	var result: Dictionary = {}
	var comparisons: Dictionary = {}
	var metadata: Dictionary = {}
	var index: int = 0
	while index < matches.size():
		var text: String = matches[index].get_string()
		if text == "{" and not stack.is_empty() and stack.back() is Dictionary and stack.back().get("key") == "data":
			var start: int = matches[index].get_start()
			var depth: int = 1
			index += 1
			while index < matches.size() and depth > 0:
				var next: String = matches[index].get_string()
				if next in ["{", "["]: depth += 1
				elif next in ["}", "]"]: depth -= 1
				index += 1
			if depth != 0: return {"_invalid": true}
			stack.back()["dataJson"] = json.substr(start, matches[index - 1].get_end() - start)
			stack.back()["key"] = ""
			continue
		if text == "{": stack.append({"key": ""})
		elif text == "[": stack.append(null)
		elif text in ["}", "]"]:
			if stack.is_empty(): return {"_invalid": true}
			var frame: Variant = stack.pop_back()
			if frame is Dictionary and frame.get("id") is String:
				var id: String = frame.id.to_lower()
				if frame.has("nameJson") and frame.has("descriptionJson"):
					var original: Dictionary = {"name": frame.nameJson, "description": frame.descriptionJson}
					if metadata.has(id):
						for field: String in original:
							if not _sameMetadata(metadata[id][field], original[field]): return {"_invalid": true}
					else: metadata[id] = original
				if frame.has("dataJson"):
					var data: HorizonGroupJsonData = fromJson(frame.dataJson)
					if data == null or (comparisons.has(id) and comparisons[id] != data._comparison): return {"_invalid": true}
					comparisons[id] = data._comparison
					if not result.has(id): result[id] = data.getJson()
		elif text.begins_with('"') and not stack.is_empty() and stack.back() is Dictionary:
			if index + 1 < matches.size() and matches[index + 1].get_string() == ":": stack.back()["key"] = JSON.parse_string(text)
			else:
				if stack.back().get("key") == "id": stack.back()["id"] = JSON.parse_string(text)
				elif stack.back().get("key") in ["name", "description"]: stack.back()[stack.back().key + "Json"] = text
				stack.back()["key"] = ""
		index += 1
	if not stack.is_empty() or matches.is_empty(): return {"_invalid": true}
	result["_metadata"] = metadata
	return result

static func _sameMetadata(left: String, right: String) -> bool:
	var a: Variant = metadataString(left)
	var b: Variant = metadataString(right)
	if a is String and b is String: return a == b
	return a is HorizonItemStringData and b is HorizonItemStringData and a.getJson() == b.getJson()

## Native JSON.stringify emits some control characters literally. Native replace
## also avoids allocating one RegExMatch per character in large escaped metadata.
static func quoteMetadata(value: String) -> String:
	var text: String = value.replace("\\", "\\\\").replace('"', '\\"')
	for code: int in range(1, 32):
		var escaped: String
		match code:
			8: escaped = "\\b"
			9: escaped = "\\t"
			10: escaped = "\\n"
			12: escaped = "\\f"
			13: escaped = "\\r"
			_: escaped = "\\u%04x" % code
		text = text.replace(String.chr(code), escaped)
	return '"' + text + '"'

## Ordinary metadata remains String. Only NUL needs the existing lossless carrier.
static func metadataString(token: String) -> Variant:
	return HorizonItemModels._string(token) if token.contains("\\u0000") else JSON.parse_string(token)

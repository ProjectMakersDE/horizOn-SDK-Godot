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
	var tokens: Array[RegExMatch] = _tokens().search_all(json)
	if tokens.is_empty() or tokens[0].get_string() != "{": return null
	var previous: int = 0
	var lexemes: PackedStringArray = []
	for token: RegExMatch in tokens:
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
static func _canonical(tokens: Array[RegExMatch], position: Array[int], depth: int) -> Variant:
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

static func _tokens() -> RegEx:
	return RegEx.create_from_string('"(?:[^"\\\\]++|(?:\\\\(?:u[0-9a-fA-F]{4}|.))++)*+"|[{}\\[\\]:,]|true|false|null|-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?')

## Match original data to its enclosing GroupView ID, skipping complete inner data
## objects so arbitrary nested id/data keys cannot impersonate another GroupView.
static func extract(json: String) -> Dictionary:
	var matches: Array[RegExMatch] = _tokens().search_all(json)
	var stack: Array = []
	var result: Dictionary = {}
	var comparisons: Dictionary = {}
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
			if frame is Dictionary and frame.get("id") is String and frame.has("dataJson"):
				var id: String = frame.id.to_lower()
				var data: HorizonGroupJsonData = fromJson(frame.dataJson)
				if data == null or (comparisons.has(id) and comparisons[id] != data._comparison): return {"_invalid": true}
				comparisons[id] = data._comparison
				if not result.has(id): result[id] = data.getJson()
		elif text.begins_with('"') and not stack.is_empty() and stack.back() is Dictionary:
			if index + 1 < matches.size() and matches[index + 1].get_string() == ":": stack.back()["key"] = JSON.parse_string(text)
			else:
				if stack.back().get("key") == "id": stack.back()["id"] = JSON.parse_string(text)
				stack.back()["key"] = ""
		index += 1
	return result if stack.is_empty() else {"_invalid": true}

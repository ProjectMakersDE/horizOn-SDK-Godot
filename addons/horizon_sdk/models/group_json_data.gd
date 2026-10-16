class_name HorizonGroupJsonData
extends RefCounted
## Original JSON object. Keep this value when changing other group metadata.
## getPreview() uses Godot numbers for display only and may round large numbers.
var _json: String = ""
var _bytes: int = 0
var _comparison: String = ""
func getJson() -> String: return _json
func getPreview() -> Dictionary:
	var value: Variant = JSON.parse_string(_json)
	return value if value is Dictionary else {}
func isValid() -> bool: return not _json.is_empty() and _bytes <= 2048

static func fromJson(json: String) -> HorizonGroupJsonData:
	var tokens: Array[RegExMatch] = _tokens().search_all(json)
	if tokens.is_empty() or tokens[0].get_string() != "{": return null
	var previous: int = 0
	var lexemes: PackedStringArray = []
	for token: RegExMatch in tokens:
		if not _whitespace(json.substr(previous, token.get_start() - previous)): return null
		var text: String = token.get_string()
		if text.begins_with('"'):
			for character: int in range(1, text.length() - 1):
				if text.unicode_at(character) < 32: return null
		lexemes.append(text)
		previous = token.get_end()
	if not _whitespace(json.substr(previous)): return null
	var position: Array[int] = [0]
	var canonical: Variant = _canonical(tokens, position, 0)
	if not canonical is String or position[0] != tokens.size() or canonical.to_utf8_buffer().size() > 2048: return null
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
	if depth > 16 or position[0] >= tokens.size(): return null
	var text: String = tokens[position[0]].get_string()
	position[0] += 1
	if text == "{":
		var entries: Dictionary = {}
		if position[0] < tokens.size() and tokens[position[0]].get_string() == "}":
			position[0] += 1
			return "{}"
		while position[0] < tokens.size():
			var key_token: String = tokens[position[0]].get_string()
			if not key_token.begins_with('"'): return null
			var key: Variant = JSON.parse_string(key_token)
			position[0] += 1
			if not key is String or entries.has(key) or position[0] >= tokens.size() or tokens[position[0]].get_string() != ":": return null
			position[0] += 1
			var value: Variant = _canonical(tokens, position, depth + 1)
			if not value is String: return null
			entries[key] = value
			if position[0] >= tokens.size(): return null
			var separator: String = tokens[position[0]].get_string()
			position[0] += 1
			if separator == "}":
				var keys: Array = entries.keys()
				keys.sort()
				var fields: PackedStringArray = []
				for name: String in keys: fields.append(JSON.stringify(name) + ":" + entries[name])
				return "{" + ",".join(fields) + "}"
			if separator != ",": return null
		return null
	if text == "[":
		var values: PackedStringArray = []
		if position[0] < tokens.size() and tokens[position[0]].get_string() == "]":
			position[0] += 1
			return "[]"
		while position[0] < tokens.size():
			var value: Variant = _canonical(tokens, position, depth + 1)
			if not value is String: return null
			values.append(value)
			if position[0] >= tokens.size(): return null
			var separator: String = tokens[position[0]].get_string()
			position[0] += 1
			if separator == "]": return "[" + ",".join(values) + "]"
			if separator != ",": return null
		return null
	if text.begins_with('"'):
		var value: Variant = JSON.parse_string(text)
		return JSON.stringify(value) if value is String else null
	if text in ["null", "true", "false"]: return text
	var number := RegEx.create_from_string("^-?(0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\\z")
	return text if number.search(text) != null else null

static func fromDictionary(data: Dictionary) -> HorizonGroupJsonData:
	if not isJsonValue(data, 0): return null
	return fromJson(JSON.stringify(data, "", true, true))

static func isJsonValue(value: Variant, depth: int) -> bool:
	if depth > 16: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING, TYPE_INT: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_ARRAY:
			for child: Variant in value:
				if not isJsonValue(child, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if (not key is String and not key is StringName) or not isJsonValue(value[key], depth + 1): return false
			return true
	return false

static func _tokens() -> RegEx:
	return RegEx.create_from_string('"(?:[^"\\\\]|\\\\.)*"|[{}\\[\\]:,]|true|false|null|-?[0-9]+(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?')

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

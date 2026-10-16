class_name HorizonItemStringData
extends RefCounted
## Godot cannot hold U+0000 in a String. Preserve those values without changing the wire bytes.
## Ordinary item strings remain String. Only strings containing NUL use this immutable value.
var _parts: PackedStringArray = []
var _original: String = ""

static func _fromParts(parts: PackedStringArray, original: String) -> HorizonItemStringData:
	var value := HorizonItemStringData.new()
	value._parts = parts.duplicate()
	value._original = original
	return value

## Complete original JSON string token, including quotes and original escape spellings.
func getOriginalJson() -> String: return _original
## Canonical JSON string: all original code points, including the escaped NUL, are preserved.
func getJson() -> String:
	var encoded: PackedStringArray = []
	for part: String in _parts:
		var quoted: String = HorizonItemModels.quote(part)
		encoded.append(quoted.substr(1, quoted.length() - 2))
	return '"' + "\\u0000".join(encoded) + '"'
## Display only: each NUL is visibly escaped. Never use this preview as an unchanged value.
func getDisplayPreview() -> String: return "\\u0000".join(_parts)
func hasEscapedNul() -> bool: return true
func getUtf8ByteCount() -> int:
	var count: int = _parts.size() - 1
	for part: String in _parts: count += part.to_utf8_buffer().size()
	return count

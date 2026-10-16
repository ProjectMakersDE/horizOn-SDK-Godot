extends VBoxContainer
## Attach to a configured signed-in project. This scene never creates/replaces an identity.
const Recipe = preload("res://addons/horizon_sdk/examples/features/chat_example.gd")
var _recipe: Node
var _kind: OptionButton
var _context: LineEdit
var _feed: RichTextLabel
var _compose: TextEdit
var _message: LineEdit
var _reason: LineEdit
var _status: Label
func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var title := Label.new(); title.text = "horizOn Chat · signed-in players"; add_child(title)
	_kind = OptionButton.new()
	for kind: String in ["project", "direct", "group"]: _kind.add_item(kind)
	add_child(_kind)
	_context = LineEdit.new(); _context.placeholder_text = "Friend player UUID or group UUID (project: empty)"; add_child(_context)
	_button("Open and subscribe", _open)
	_status = Label.new(); _status.text = "Sign in with the existing Horizon.auth session first."; _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(_status)
	_feed = RichTextLabel.new(); _feed.bbcode_enabled = false; _feed.custom_minimum_size = Vector2(320, 260); add_child(_feed)
	_compose = TextEdit.new(); _compose.placeholder_text = "Plain text, at most 500 characters"; _compose.custom_minimum_size.y = 90; add_child(_compose)
	_button("Send original", _send)
	_button("Inspect pending operation", _inspect)
	_button("Explicitly retry unchanged original", _retry)
	_message = LineEdit.new(); _message.placeholder_text = "Message UUID to report"; add_child(_message)
	_reason = LineEdit.new(); _reason.placeholder_text = "Original report reason"; add_child(_reason)
	_button("Report message", _report)
	_recipe = Recipe.new(); add_child(_recipe)
	_recipe.feed_changed.connect(_show_feed)
	_recipe.feed_hidden.connect(func(): _feed.text = ""; _status.text = "Feed hidden; waiting for a fresh authorized subscription and snapshot.")
func _button(text: String, action: Callable) -> void:
	var button := Button.new(); button.text = text; button.pressed.connect(action); add_child(button)
func _open() -> void:
	var kind: String = _kind.get_item_text(_kind.selected)
	_show(await _recipe.choose_channel(kind, _context.text if kind == "direct" else "", _context.text if kind == "group" else ""))
func _send() -> void: _show(await _recipe.send_text(_compose.text))
func _inspect() -> void: _show(await _recipe.inspect_pending())
func _retry() -> void: _show(await _recipe.retry_original())
func _report() -> void: _show(await _recipe.report(_message.text, _reason.text))
func _show(result: Dictionary) -> void:
	_status.text = "Confirmed. Original receipt saved." if result.success and result.data.has("receipt") else ("Subscribed; feed arrives through push." if result.success else "Action retained/refused: " + str(result.errorCode))
func _show_feed(_data: Dictionary) -> void:
	var data: Dictionary = _recipe.current_feed()
	if data.is_empty(): _feed.text = ""; return
	var lines: PackedStringArray = []
	for row: Dictionary in data.messages: lines.append(row.authorId + " · " + row.id + "\n" + row.text)
	_feed.text = "\n\n".join(lines)
	_status.text = "Live authorized snapshot · %d messages" % data.messages.size()

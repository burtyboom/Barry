class_name DevConsole
extends PanelContainer
## The ` console (drops down from the top). Commands:
##   admin <code>   unlock the admin menu (the code is 1234)
##   help, clear

const ADMIN_CODE := "1234"

var main: Node
var _log: RichTextLabel
var _line: LineEdit


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiTheme.panel(Color(0.02, 0.04, 0.08, 0.88), 0, 12))
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_bottom = 260
	var vb := VBoxContainer.new()
	add_child(vb)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.add_theme_font_size_override("normal_font_size", 15)
	vb.add_child(_log)
	_line = LineEdit.new()
	_line.placeholder_text = "type a command (help)"
	_line.text_submitted.connect(_run)
	vb.add_child(_line)
	_print("[color=#fc6]%s v%s console[/color] - type [b]help[/b]" % [GameVersion.TITLE, GameVersion.VERSION])


func toggle() -> void:
	visible = not visible
	if visible:
		_line.text = ""
		_line.grab_focus()
	else:
		_line.release_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_QUOTELEFT:
			toggle()
			get_viewport().set_input_as_handled()
		elif visible and event.keycode == KEY_ESCAPE:
			toggle()
			get_viewport().set_input_as_handled()


func _print(t: String) -> void:
	_log.append_text(t + "\n")


func _run(line: String) -> void:
	_line.text = ""
	line = line.strip_edges()
	if line == "":
		return
	_print("[color=#8af]> %s[/color]" % line.replace("[", "[lb]"))
	var parts := line.split(" ", false)
	match parts[0].to_lower():
		"help":
			_print("  admin <code>  - unlock the admin menu\n  clear  - clear this console")
		"clear":
			_log.clear()
		"admin":
			if parts.size() > 1 and parts[1] == ADMIN_CODE:
				main.admin_unlocked = true
				if main.hud:
					main.hud.set_admin_unlocked(true)
				_print("[color=#7e7]Admin menu unlocked - it's the Admin button by the map (or F2). Have fun![/color]")
			else:
				_print("[color=#f77]Nice try, mate.[/color]")
		_:
			_print("[color=#f77]Don't know that one. Try help.[/color]")

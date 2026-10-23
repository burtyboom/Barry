class_name ChatBox
extends PanelContainer
## Chat, bottom-left. Two tabs: Players (what people type - everyone on the server sees
## it) and Bots (what the bots are nattering about). Enter opens the box to type, Enter
## sends, Esc closes. When you're not typing it fades back to just the latest lines.

const MAX_LINES := 80

var input: LineEdit
var _logs := {}            ## tab -> RichTextLabel
var _tab_btns := {}
var _tab := "players"
var _unread := {"players": 0, "bots": 0}
var _idle := 99.0          ## seconds since anything happened
var _open := false
var send_cb: Callable      ## main's send function


func _ready() -> void:
	custom_minimum_size = Vector2(300, 190)
	add_theme_stylebox_override("panel", UiTheme.panel(Color(0.04, 0.08, 0.14, 0.62), 14, 10))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	vb.add_child(tabs)
	for t in [["players", "Players"], ["bots", "Bots"]]:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		b.custom_minimum_size = Vector2(90, 26)
		var id: String = t[0]
		b.pressed.connect(func() -> void: show_tab(id))
		tabs.add_child(b)
		_tab_btns[id] = b
		var log := RichTextLabel.new()
		log.bbcode_enabled = true
		log.scroll_following = true
		log.size_flags_vertical = Control.SIZE_EXPAND_FILL
		log.add_theme_font_size_override("normal_font_size", 15)
		log.add_theme_font_override("bold_font", UiTheme.font(true))
		log.add_theme_font_size_override("bold_font_size", 15)
		log.add_theme_constant_override("outline_size", 4)
		log.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		log.mouse_filter = Control.MOUSE_FILTER_PASS
		vb.add_child(log)
		_logs[id] = log
	var hint := Label.new()
	hint.text = "Enter to chat"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(1, 1, 1, 0.5)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tabs.add_child(hint)
	input = LineEdit.new()
	input.placeholder_text = "Say something... (Esc cancels)"
	input.max_length = 160
	input.visible = false
	input.text_submitted.connect(_submit)
	vb.add_child(input)
	show_tab("players")
	add_line("players", "", "[color=#9ad]Welcome! Press Enter to chat with everyone on the island.[/color]")


func show_tab(id: String) -> void:
	_tab = id
	_unread[id] = 0
	for k in _logs:
		(_logs[k] as Control).visible = k == id
		(_tab_btns[k] as Button).set_pressed_no_signal(k == id)
	_refresh_tab_names()
	_idle = 0.0


func _refresh_tab_names() -> void:
	for k in _tab_btns:
		var base: String = "Players" if k == "players" else "Bots"
		(_tab_btns[k] as Button).text = base + (" (%d)" % _unread[k] if _unread[k] > 0 else "")


## who = "" for system lines; text is plain (escaped here) unless who is "".
func add_line(tab: String, who: String, text: String, col := Color(0.55, 0.85, 1.0)) -> void:
	var log: RichTextLabel = _logs[tab]
	var line := text if who == "" else "[b][color=#%s]%s:[/color][/b] %s" % [col.to_html(false), _esc(who), _esc(text)]
	log.append_text(line + "\n")
	if log.get_paragraph_count() > MAX_LINES:
		log.remove_paragraph(0)
	if tab != _tab:
		_unread[tab] += 1
		_refresh_tab_names()
	if tab == _tab or tab == "players":
		_idle = 0.0


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func open() -> void:
	_open = true
	input.visible = true
	input.text = ""
	input.grab_focus()
	if _tab != "players":
		show_tab("players")
	_idle = 0.0


func close() -> void:
	_open = false
	input.release_focus()
	input.visible = false
	_idle = 0.0


func is_open() -> bool:
	return _open


func _submit(t: String) -> void:
	t = t.strip_edges()
	if t != "" and send_cb.is_valid():
		send_cb.call(t)
	close()


func _input(event: InputEvent) -> void:
	if _open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_idle += delta
	# fade out when nobody's said anything for a while (keeps the beach view clear)
	var a := 1.0 if _open or _idle < 10.0 else clampf(1.0 - (_idle - 10.0) / 2.0, 0.0, 1.0)
	modulate.a = move_toward(modulate.a, maxf(a, 0.0), delta * 3.0)

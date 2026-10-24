class_name PauseMenu
extends Control
## Esc in game: a little card over a dimmed screen - back to the game, controls,
## fullscreen, back to the main menu, quit. The game keeps running behind it (it's
## multiplayer - the beach doesn't stop for you). Esc again closes it.

var main: Node
var _leave_btn: Button
var _leave_armed := false
var _gfx_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.05, 0.10, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.panel(UiTheme.SAND, 22, 26, UiTheme.INK, 4))
	center.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.custom_minimum_size = Vector2(320, 0)
	card.add_child(vb)
	var t := Label.new()
	t.text = "Smoko"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", UiTheme.title_font())
	t.add_theme_font_size_override("font_size", 40)
	t.add_theme_color_override("font_color", UiTheme.ORANGE)
	t.add_theme_color_override("font_outline_color", UiTheme.INK)
	t.add_theme_constant_override("outline_size", 8)
	vb.add_child(t)
	_button(vb, "Back to the beach", UiTheme.GREEN, close)
	_button(vb, "Controls (F1)", UiTheme.SURF, func() -> void:
		close()
		var hp := get_parent().get_node_or_null("HelpPanel") as Control
		if hp:
			hp.visible = true)
	_button(vb, "Fullscreen (F11)", UiTheme.TEAL, func() -> void:
		if main:
			main._toggle_fullscreen())
	_gfx_btn = _button(vb, "", UiTheme.PURPLE, func() -> void:
		if main:
			main.set_graphics_low(not main.graphics_low)
			_gfx_btn.text = _gfx_text())
	_leave_btn = _button(vb, "Back to main menu", UiTheme.ORANGE, _on_leave)
	_button(vb, "Quit game", UiTheme.RED, func() -> void: get_tree().quit())


func _button(parent: Control, text: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 52)
	UiTheme.style_button(b, col, 22)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func open() -> void:
	# the HUD's root has no size of its own, so cover the screen by hand
	position = Vector2.ZERO
	size = get_viewport_rect().size
	visible = true
	_leave_armed = false
	_leave_btn.text = _leave_text()
	_gfx_btn.text = _gfx_text()


func _gfx_text() -> String:
	return "Graphics: Low (faster)" if main and main.graphics_low else "Graphics: High (prettier)"


func close() -> void:
	visible = false


func _leave_text() -> String:
	var net := get_node("/root/Net")
	if net.mode == "host":
		return "End the game (kicks everyone)"
	if net.mode == "client":
		return "Leave and go to main menu"
	return "Back to main menu"


func _on_leave() -> void:
	# hosting: leaving ends it for your mates too, so make sure
	if get_node("/root/Net").mode == "host" and not _leave_armed:
		_leave_armed = true
		_leave_btn.text = "Sure? Click again"
		return
	close()
	if main:
		main.back_to_menu()

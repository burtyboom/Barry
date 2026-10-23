class_name Hud
extends CanvasLayer

var car: SandVehicle
var player: PlayerCharacter
var _hotbar: HBoxContainer
var _slots: Array[PanelContainer] = []
var _prompt: Label
var _hint: Label
var _charge_bg: ColorRect
var _charge_bar: ColorRect
var island: IslandData
var cars_root: Node

var dash: Dash
var _pve_chip: Label
var _bogged: Label
var _debug: Label
var _map_tex: ImageTexture
var minimap: Minimap
var chat: ChatBox
var _admin_toggle: Button
var _helper_panel: PanelContainer
var _talk_chip: Label
var _toast: Label
var _toast_t := 0.0
var _admin: PanelContainer
var _tabs: Array[Control] = []
var _tab_buttons: Array[Button] = []
var _bot_count: Label
var _winch_box: VBoxContainer   ## big WINCH buttons while you're in the cab
var _winch_info: Label
var _winch_in_btn: Button
var _winch_out_btn: Button

const MAP_DIV := 2   # minimap = 1 pixel per 2 cells (5 m)


## True while you're typing in chat / the console (driving and walking keys are ignored).
static func typing() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	return tree != null and tree.root.gui_get_focus_owner() is LineEdit


func _ready() -> void:
	island = IslandData.instance
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	dash = Dash.new()
	dash.name = "Dash"
	dash.main = get_parent()
	dash.position = Vector2(16, 16)
	root.add_child(dash)
	# PvE on: a little shield chip beside the dashboard
	_pve_chip = Label.new()
	_pve_chip.text = "  PvE  "
	_pve_chip.tooltip_text = "PvE mode: no ute bonks or lassos with other players"
	_pve_chip.add_theme_font_override("font", UiTheme.font(true))
	_pve_chip.add_theme_font_size_override("font_size", 14)
	_pve_chip.add_theme_stylebox_override("normal", UiTheme.panel(Color(0.20, 0.62, 0.35, 0.9), 12, 5))
	_pve_chip.position = Vector2(16 + Dash.W + 8, 18)
	_pve_chip.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(_pve_chip)

	_bogged = Label.new()
	_bogged.text = "BOGGED!"
	_bogged.add_theme_font_size_override("font_size", 64)
	_bogged.add_theme_color_override("font_color", Color(1, 0.25, 0.15))
	_bogged.add_theme_color_override("font_outline_color", Color.BLACK)
	_bogged.add_theme_constant_override("outline_size", 12)
	_bogged.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_bogged.position = Vector2(-140, 60)
	_bogged.visible = false
	root.add_child(_bogged)

	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 8)
	# full-width strip above the hotbar: long messages stay centred and wrap upward
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_toast)
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_left = 220.0
	_toast.offset_right = -220.0
	_toast.offset_top = -330.0
	_toast.offset_bottom = -200.0

	var hp := HelpCard.new()
	hp.name = "HelpPanel"
	root.add_child(hp)
	hp.position = Vector2(16, 326)
	var f1 := Label.new()
	f1.text = "  F1  controls  "
	f1.add_theme_font_override("font", UiTheme.font(true))
	f1.add_theme_font_size_override("font_size", 13)
	f1.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	f1.add_theme_stylebox_override("normal", UiTheme.panel(Color(0.05, 0.10, 0.17, 0.6), 10, 5))
	f1.position = Vector2(16, 326)
	f1.visible = false
	root.add_child(f1)
	hp.visibility_changed.connect(func() -> void: f1.visible = not hp.visible)
	# tuck the help away after a while (F1 brings it back)
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		if is_instance_valid(hp):
			hp.visible = false)

	_build_admin(root)
	if "--ui-debug" in OS.get_cmdline_user_args():
		get_tree().create_timer(2.0).timeout.connect(_print_ui_rects)
	_build_hotbar(root)

	_debug = Label.new()
	_debug.add_theme_font_size_override("font_size", 14)
	_debug.position = Vector2(16, 330)
	_debug.visible = false
	var dbg_bg := _style(Color(0, 0, 0, 0.6))
	_debug.add_theme_stylebox_override("normal", dbg_bg)
	root.add_child(_debug)

	_build_maps(root)
	_build_winch_buttons(root)


## In the cab with the winch hooked on: big hold-down buttons (G / H do the same).
## Unhooking is still a job for outside, by hand.
func _build_winch_buttons(root: Control) -> void:
	_winch_box = VBoxContainer.new()
	_winch_box.name = "WinchButtons"
	_winch_box.add_theme_constant_override("separation", 8)
	_winch_box.visible = false
	root.add_child(_winch_box)
	_winch_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 30)
	_winch_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_winch_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_winch_box.offset_top -= 46.0   # leave room for the "[E] Get out" prompt underneath
	_winch_box.offset_bottom -= 46.0
	_winch_info = Label.new()
	_winch_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_winch_info.add_theme_font_size_override("font_size", 18)
	_winch_info.add_theme_color_override("font_outline_color", Color.BLACK)
	_winch_info.add_theme_constant_override("outline_size", 6)
	_winch_box.add_child(_winch_info)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_winch_box.add_child(row)
	_winch_in_btn = _big_button(row, "WINCH IN\n(hold, or G)", Color(0.15, 0.65, 0.25), Vector2(240, 96), 30)
	_winch_out_btn = _big_button(row, "LET OUT\n(hold, or H)", Color(0.75, 0.30, 0.15), Vector2(170, 96), 22)
	_winch_in_btn.button_down.connect(func() -> void: _ropes().cab_in = true)
	_winch_in_btn.button_up.connect(func() -> void: _ropes().cab_in = false)
	_winch_out_btn.button_down.connect(func() -> void: _ropes().cab_out = true)
	_winch_out_btn.button_up.connect(func() -> void: _ropes().cab_out = false)


func _big_button(parent: Control, text: String, col: Color, sz: Vector2, font: int) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = sz
	b.add_theme_font_size_override("font_size", font)
	for st in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col if st == "normal" else (col.lightened(0.15) if st == "hover" else col.darkened(0.25))
		sb.set_corner_radius_all(14)
		sb.border_color = Color(1, 1, 1, 0.85)
		sb.set_border_width_all(3)
		b.add_theme_stylebox_override(st, sb)
	parent.add_child(b)
	return b


func _ropes() -> Ropes:
	return get_parent().ropes


func _update_winch_buttons() -> void:
	var ropes := _ropes()
	var rid := ""
	var in_cab := player != null and is_instance_valid(player) and player.state == PlayerCharacter.State.IN_CAR
	if in_cab and car and is_instance_valid(car):
		rid = ropes.winch_rope_of(String(car.name))
	var show := rid != ""
	if _winch_box.visible != show:
		_winch_box.visible = show
		# messages sit above the big buttons while they're up
		_toast.offset_top = -470.0 if show else -330.0
		_toast.offset_bottom = -340.0 if show else -200.0
		if not show:
			ropes.cab_in = false
			ropes.cab_out = false
	if show:
		var r: Dictionary = ropes.ropes[rid]
		var kn := float(r["tension"]) / 1000.0
		_winch_info.text = "Winch hooked on: %.1f m of cable out   pull %.0f kN%s\n(get out and press E at the hook to unhook it)" % [
			float(r["rest"]), kn, "  - STALLED, too much load!" if kn > Ropes.WINCH_MAX / 1000.0 else ""]


## Hotbar slot background: like _style but with tight margins (13 slots have to fit).
func _slot_style(c: Color) -> StyleBoxFlat:
	var sb := _style(c)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(5)
	return sb


func _style(c: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _build_maps(root: Control) -> void:
	var w := island.cols / MAP_DIV
	var h := island.rows / MAP_DIV
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := (y * MAP_DIV) * island.cols + x * MAP_DIV
			var sf := island.surf[i]
			var hh := island.heights[i]
			var c: Color
			if hh < 0.0 and sf != IslandData.Surface.ROCK:
				c = Color(0.1, 0.35, 0.55).lerp(Color(0.3, 0.65, 0.75), clampf(1.0 + hh / 4.0, 0.0, 1.0))
			else:
				c = WorldBuilder.surface_color(sf, island.soft[i], hh)
				if island.track[i] > 0.4:
					c = Color(0.95, 0.85, 0.55)
			img.set_pixel(x, y, c)
	for l in island.lakes:
		var cx := int((float(l["x"]) - island.x_min) / IslandData.CELL / MAP_DIV)
		var cz := int((float(l["z"]) - island.z_min) / IslandData.CELL / MAP_DIV)
		var rr := int(float(l["r"]) / IslandData.CELL / MAP_DIV)
		for dy in range(-rr, rr + 1):
			for dx in range(-rr, rr + 1):
				if dx * dx + dy * dy <= rr * rr:
					var px := clampi(cx + dx, 0, w - 1)
					var py := clampi(cz + dy, 0, h - 1)
					img.set_pixel(px, py, (l["color"] as Color).lightened(0.1))
	_map_tex = ImageTexture.create_from_image(img)

	minimap = Minimap.new()
	minimap.name = "Minimap"
	root.add_child(minimap)
	minimap.setup(self, _map_tex)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(get_viewport().get_visible_rect().size.x - Minimap.SIZE - 18.0, 16.0)
	minimap.offset_left = -Minimap.SIZE - 18.0
	minimap.offset_right = -18.0
	root.add_child(minimap.big_map)
	minimap.big_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# under the minimap: [map] [Helper] [Admin]
	var row := HBoxContainer.new()
	row.name = "MapButtons"
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(row)
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.offset_right = -18.0
	row.offset_left = -18.0 - 340.0
	row.offset_top = 16.0 + Minimap.SIZE + 10.0
	row.offset_bottom = row.offset_top + 48.0
	_admin_toggle = Button.new()
	_admin_toggle.text = "Admin"
	_admin_toggle.focus_mode = Control.FOCUS_NONE
	_admin_toggle.custom_minimum_size = Vector2(0, 46)
	UiTheme.style_button(_admin_toggle, Color(0.35, 0.38, 0.45), 16, 12, 4)
	_admin_toggle.pressed.connect(func() -> void:
		_helper_panel.visible = false
		_admin.visible = not _admin.visible)
	_admin_toggle.visible = bool(get_parent().get("admin_unlocked"))
	row.add_child(_admin_toggle)
	var helper := Button.new()
	helper.text = "Helper"
	helper.focus_mode = Control.FOCUS_NONE
	helper.custom_minimum_size = Vector2(0, 46)
	helper.tooltip_text = "Your helper ute: follows you around and pulls (or nudges) you out when you bog"
	UiTheme.style_button(helper, UiTheme.GREEN, 16, 12, 4)
	helper.pressed.connect(func() -> void:
		_admin.visible = false
		_helper_panel.visible = not _helper_panel.visible)
	row.add_child(helper)
	var mapb := Button.new()
	mapb.focus_mode = Control.FOCUS_NONE
	mapb.custom_minimum_size = Vector2(64, 46)
	mapb.tooltip_text = "Island map (M)"
	UiTheme.style_button(mapb, UiTheme.SURF, 16, 12, 4)
	mapb.pressed.connect(func() -> void: minimap.big_map.visible = not minimap.big_map.visible)
	var icon := Control.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.draw.connect(func() -> void:
		# a little folded paper map with a red pin
		var c := icon.size * 0.5 + Vector2(0, -2)
		var pw := 11.0
		var ph := 13.0
		var cols := [Color(0.98, 0.93, 0.78), Color(0.85, 0.80, 0.66), Color(0.98, 0.93, 0.78)]
		for i in 3:
			var x0 := c.x - pw * 1.5 + i * pw
			var dy := -3.0 if i % 2 == 0 else 3.0
			icon.draw_colored_polygon(PackedVector2Array([Vector2(x0, c.y - ph + dy), Vector2(x0 + pw, c.y - ph - dy),
				Vector2(x0 + pw, c.y + ph - dy), Vector2(x0, c.y + ph + dy)]), cols[i])
		icon.draw_circle(c + Vector2(3, -3), 4.5, Color(0.9, 0.15, 0.1))
		icon.draw_circle(c + Vector2(3, -3), 1.8, Color.WHITE)
		icon.draw_string(UiTheme.font(true), Vector2(icon.size.x - 13, icon.size.y - 6), "M", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85)))
	mapb.add_child(icon)
	row.add_child(mapb)
	_build_helper_panel(root)

	# the "you're on the mic" chip
	_talk_chip = Label.new()
	_talk_chip.text = "  Talking...  "
	_talk_chip.add_theme_font_override("font", UiTheme.font(true))
	_talk_chip.add_theme_font_size_override("font_size", 18)
	_talk_chip.add_theme_stylebox_override("normal", UiTheme.panel(Color(0.85, 0.15, 0.2, 0.9), 14, 8))
	_talk_chip.visible = false
	root.add_child(_talk_chip)
	_talk_chip.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 14)

	chat = ChatBox.new()
	chat.name = "Chat"
	chat.main = get_parent()
	root.add_child(chat)
	var cv: Convoy = get_parent().get("convoy")
	if cv:
		cv.changed.connect(chat.convoy_changed)
		chat.convoy_changed()
	chat.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	chat.grow_vertical = Control.GROW_DIRECTION_BEGIN
	if get_parent().has_method("send_chat"):
		chat.send_cb = get_parent().send_chat


## Admin unlocked from the console: show its button.
func set_admin_unlocked(on: bool) -> void:
	_admin_toggle.visible = on
	if not on:
		_admin.visible = false


## The Helper panel (under the minimap): everything you can ask your helper ute to do.
func _build_helper_panel(root: Control) -> void:
	_helper_panel = PanelContainer.new()
	_helper_panel.name = "HelperPanel"
	_helper_panel.visible = false
	root.add_child(_helper_panel)
	_helper_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_helper_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_helper_panel.offset_right = -18.0
	_helper_panel.offset_left = -18.0 - 340.0
	_helper_panel.offset_top = 16.0 + Minimap.SIZE + 66.0
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_helper_panel.add_child(vb)
	var bots: Bots = get_parent().bots
	_section(vb, "Your helper (the green ute)")
	var g := GridContainer.new()
	g.columns = 2
	vb.add_child(g)
	var helper := func() -> HelperBot:
		return bots.helper if bots.helper and is_instance_valid(bots.helper) else null
	var need := func(fn: Callable) -> Callable:
		return func() -> void:
			var h: HelperBot = helper.call()
			if h == null:
				show_toast("Call your helper first (Spawn helper)")
			else:
				fn.call(h)
	_admin_button(g, "Spawn helper", func() -> void: bots.spawn("helper"))
	_admin_button(g, "Send helper home", bots.remove_helper)
	_admin_button(g, "Follow me", need.call(func(h: HelperBot) -> void: h.follow()))
	_admin_button(g, "Stay here", need.call(func(h: HelperBot) -> void: h.stay()))
	_admin_button(g, "Come to my rear", need.call(func(h: HelperBot) -> void: h.come("rear")))
	_admin_button(g, "Come to my front", need.call(func(h: HelperBot) -> void: h.come("front")))
	_admin_button(g, "Nudge me out!", need.call(func(h: HelperBot) -> void: h.nudge_me()))
	_admin_button(g, "Strap me out!", need.call(func(h: HelperBot) -> void: h.strap_me_out()))
	_admin_button(g, "Winch me out!", need.call(func(h: HelperBot) -> void: h.winch_me_out()))
	_admin_button(g, "Send it (pull now)", need.call(func(h: HelperBot) -> void: h.send_it()))
	_admin_button(g, "Bring helper to me", need.call(func(h: HelperBot) -> void: h.teleport_to_lead()))
	var btn: Array[Button] = []
	btn.append(_admin_button(g, "Follow distance 18 m", need.call(func(h: HelperBot) -> void:
		btn[0].text = "Follow distance %d m" % int(h.cycle_follow_dist()))))


func _world_to_map(p: Vector3, rect_size: Vector2, keep_aspect: bool) -> Vector2:
	var u := (p.x - island.x_min) / ((island.cols - 1) * IslandData.CELL)
	var v := (p.z - island.z_min) / ((island.rows - 1) * IslandData.CELL)
	if not keep_aspect:
		return Vector2(u * rect_size.x, v * rect_size.y)
	var tex_aspect := float(island.cols) / float(island.rows)
	var h := rect_size.y
	var w := h * tex_aspect
	if w > rect_size.x:
		w = rect_size.x
		h = w / tex_aspect
	var off := (rect_size - Vector2(w, h)) * 0.5
	return off + Vector2(u * w, v * h)


## Is this bot ute bogged and waiting for help? (Shown as a pulsing ring on the map.)
func _bot_stuck(v: SandVehicle) -> bool:
	var p := get_parent().players.get_node_or_null("BotP_" + String(v.name).trim_prefix("Bot_")) as PlayerCharacter
	return p != null and p._icon != null


func show_toast(text: String) -> void:
	_toast.text = text
	# longer messages stay up longer so there's time to read them
	_toast_t = clampf(2.0 + text.length() * 0.035, 2.5, 6.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("help"):
		var hp := get_child(0).get_node("HelpPanel") as Control
		hp.visible = not hp.visible
	elif event.is_action_pressed("debug"):
		_debug.visible = not _debug.visible
	elif event.is_action_pressed("admin"):
		if _admin_toggle.visible:
			_admin.visible = not _admin.visible
	elif event.is_action_pressed("map"):
		minimap.big_map.visible = not minimap.big_map.visible
	elif event.is_action_pressed("chat") and not (event as InputEventKey).alt_pressed:
		chat.open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("wave"):
		if player and is_instance_valid(player):
			player.wave()
			get_parent().on_wave()


# ------------------------------------------------------------- admin menu (top right)
## A clickable "Admin" button next to the minimap opens a list of every place on
## the island (click to teleport there) plus a fullscreen toggle. F2 also opens it.
func _build_admin(root: Control) -> void:
	var anchor := VBoxContainer.new()
	anchor.name = "AdminMenu"
	anchor.add_theme_constant_override("separation", 6)
	root.add_child(anchor)
	anchor.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	anchor.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	# under the minimap and its buttons
	anchor.offset_right = -18.0
	anchor.offset_left = anchor.offset_right - 340.0
	anchor.offset_top = 16.0 + Minimap.SIZE + 66.0

	_admin = PanelContainer.new()
	_admin.add_theme_stylebox_override("panel", _style(Color(0, 0, 0, 0.6)))
	_admin.visible = false
	anchor.add_child(_admin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	_admin.add_child(outer)
	var tab_row := HBoxContainer.new()
	outer.add_child(tab_row)
	for k in 3:
		var tb := Button.new()
		tb.text = ["World", "Teleport", "Bots"][k]
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.button_down.connect(_show_tab.bind(k))
		tab_row.add_child(tb)
		_tab_buttons.append(tb)
		var sec := VBoxContainer.new()
		sec.add_theme_constant_override("separation", 4)
		outer.add_child(sec)
		_tabs.append(sec)
	var vb := _tabs[0]

	var full := Button.new()
	full.text = "Fullscreen"
	full.focus_mode = Control.FOCUS_NONE
	full.pressed.connect(func() -> void:
		var main := get_parent()
		if main.has_method("_toggle_fullscreen"):
			main._toggle_fullscreen())
	vb.add_child(full)

	var ach := Button.new()
	ach.text = "Achievements"
	ach.focus_mode = Control.FOCUS_NONE
	ach.button_down.connect(_toggle_achievement_list)
	vb.add_child(ach)

	var main0 := get_parent()
	var mb: Array[Button] = []
	mb.append(_admin_button(vb, "Music: %s  (N)" % ("ON" if main0.music.enabled else "OFF"), func() -> void:
		main0.toggle_music()
		mb[0].text = "Music: %s  (N)" % ("ON" if main0.music.enabled else "OFF")))
	var sfx_levels := [0.0, -6.0, -14.0, -80.0]
	var sfx_names := ["loud", "normal", "quiet", "off"]
	var sfx_bus := AudioServer.get_bus_index("SFX")
	var cur := 0
	for k in sfx_levels.size():
		if absf(AudioServer.get_bus_volume_db(sfx_bus) - float(sfx_levels[k])) < 0.5:
			cur = k
	mb.append(_admin_button(vb, "Sound effects: %s" % sfx_names[cur], func() -> void:
		var now := 0
		for k in sfx_levels.size():
			if absf(AudioServer.get_bus_volume_db(sfx_bus) - float(sfx_levels[k])) < 0.5:
				now = k
		var nxt := (now + 1) % sfx_levels.size()
		AudioServer.set_bus_volume_db(sfx_bus, sfx_levels[nxt])
		AudioServer.set_bus_mute(sfx_bus, nxt == sfx_levels.size() - 1)
		mb[1].text = "Sound effects: %s" % sfx_names[nxt]
		main0.save_settings()))

	var spare := Button.new()
	spare.text = "Spawn a parked ute"
	spare.focus_mode = Control.FOCUS_NONE
	spare.button_down.connect(func() -> void:
		var main := get_parent()
		if main.has_method("spawn_spare_ute"):
			main.spawn_spare_ute())
	vb.add_child(spare)

	var tide_head := Label.new()
	tide_head.text = "Tide"
	tide_head.add_theme_font_size_override("font_size", 14)
	tide_head.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(tide_head)
	var tides := GridContainer.new()
	tides.columns = 2
	vb.add_child(tides)
	for t in [["High", 0.0], ["Low", 0.5], ["Falling", 0.25], ["Rising", 0.75], ["Real time", -1.0]]:
		var tb := Button.new()
		tb.text = t[0]
		tb.focus_mode = Control.FOCUS_NONE
		tb.add_theme_font_size_override("font_size", 13)
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.button_down.connect(func() -> void:
			var main := get_parent()
			if main.has_method("set_tide"):
				main.set_tide(t[1]))
		tides.add_child(tb)

	vb = _tabs[1]
	var head := Label.new()
	head.text = "Teleport to"
	head.add_theme_font_size_override("font_size", 14)
	head.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(head)
	# plain grid (no ScrollContainer: its drag-to-scroll can swallow button clicks)
	var list := GridContainer.new()
	list.name = "TeleportGrid"
	list.columns = 2
	list.add_theme_constant_override("h_separation", 2)
	list.add_theme_constant_override("v_separation", 1)
	vb.add_child(list)
	for p in island.places:
		var b := Button.new()
		b.text = p["name"]
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 12)
		b.custom_minimum_size = Vector2(150, 22)
		b.clip_text = true
		b.button_down.connect(_teleport_to.bind(p))   # fire on press, not release
		list.add_child(b)
	_build_bot_tab(_tabs[2])
	_show_tab(1)


func _show_tab(k: int) -> void:
	for i in _tabs.size():
		_tabs[i].visible = i == k
		_tab_buttons[i].set_pressed_no_signal(i == k)


func _admin_button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(140, 26)
	b.button_down.connect(action)
	b.button_down.connect(func() -> void: Sfx.play_ui(self, "click", -6.0))
	parent.add_child(b)
	return b


func _section(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.modulate = Color(1, 1, 1, 0.7)
	parent.add_child(l)
	return l


## Admin > Bots: your helper (with debug controls) and island bots.
func _build_bot_tab(vb: Control) -> void:
	var bots: Bots = get_parent().bots
	_section(vb, "Helper bot (debug)")
	var g := GridContainer.new()
	g.columns = 2
	vb.add_child(g)
	var helper := func() -> HelperBot:
		return bots.helper if bots.helper and is_instance_valid(bots.helper) else null
	# lambdas copy locals when they're made, so the buttons reach themselves through an array
	var btn: Array[Button] = []
	btn.append(_admin_button(g, "Helper can't bog: ON", func() -> void:
		bots.helper_bog_proof = not bots.helper_bog_proof
		btn[0].text = "Helper can't bog: %s" % ("ON" if bots.helper_bog_proof else "OFF")
		var h: HelperBot = helper.call()
		if h:
			h.car.bog_proof = bots.helper_bog_proof))
	btn.append(_admin_button(vb, "Bot debug view: OFF", func() -> void:
		bots.debug = not bots.debug
		btn[1].text = "Bot debug view: %s" % ("ON (labels, paths, trail)" if bots.debug else "OFF")))

	_bot_count = _section(vb, "Island bots")
	var g2 := GridContainer.new()
	g2.columns = 2
	vb.add_child(g2)
	for role in Bots.ROLES:
		_admin_button(g2, "+ " + String(Bots.ROLES[role]), func() -> void: bots.spawn(role))
	_admin_button(g2, "+ 5 random bots", func() -> void:
		for k in 5:
			bots.spawn(bots.random_role(false)))
	_admin_button(g2, "Remove all bots", bots.remove_all_ambient)
	_section(vb, "Bot debug")
	var g3 := GridContainer.new()
	g3.columns = 2
	vb.add_child(g3)
	btn.append(_admin_button(g3, "Emergency: COMMON", func() -> void:
		bots.emergency_common = not bots.emergency_common
		btn[2].text = "Emergency: %s" % ("COMMON" if bots.emergency_common else "RARE")))
	btn.append(_admin_button(g3, "Bots stop to help: 50%", func() -> void:
		bots.help_chance = {0.5: 1.0, 1.0: 0.0}.get(bots.help_chance, 0.5)
		btn[3].text = "Bots stop to help: %s" % {0.5: "50%", 1.0: "ALWAYS", 0.0: "NEVER"}[bots.help_chance]))
	_admin_button(g3, "Bog the nearest bot", bots.bog_nearest)
	_admin_button(g3, "Free all stuck bots", bots.free_stuck)
	var main: Node = get_parent()
	var bonk_btn: Array[Button] = []
	bonk_btn.append(_admin_button(g3, "Ute bonks: PLAYERS + BOTS", func() -> void:
		main.bonk_mode = (main.bonk_mode + 2) % 3
		bonk_btn[0].text = "Ute bonks: %s" % ["OFF", "PLAYERS ONLY", "PLAYERS + BOTS"][main.bonk_mode]))
	_admin_button(g3, "Heal me (full health)", func() -> void:
		if player and is_instance_valid(player):
			player.revive())
	var cd_btn: Array[Button] = []
	cd_btn.append(_admin_button(g3, "Lasso cooldown: ON", func() -> void:
		main.lasso_cooldown = not main.lasso_cooldown
		if not main.lasso_cooldown and player and is_instance_valid(player):
			player._lasso_cd = 0.0
		cd_btn[0].text = "Lasso cooldown: %s" % ("ON" if main.lasso_cooldown else "OFF")))


var _ach_panel: PanelContainer


func _toggle_achievement_list() -> void:
	if _ach_panel and is_instance_valid(_ach_panel):
		_ach_panel.queue_free()
		_ach_panel = null
		return
	var main := get_parent()
	var got: Dictionary = main.achievements.unlocked if main.get("achievements") else {}
	_ach_panel = PanelContainer.new()
	_ach_panel.add_theme_stylebox_override("panel", _style(Color(0.06, 0.08, 0.14, 0.92)))
	get_child(0).add_child(_ach_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_ach_panel.add_child(vb)
	var title := Label.new()
	title.text = "ACHIEVEMENTS  %d / %d" % [got.size(), Achievements.DEFS.size()]
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	vb.add_child(title)
	for id in Achievements.DEFS:
		var d: Array = Achievements.DEFS[id]
		var row := Label.new()
		var have := got.has(id)
		row.text = ("[x] " if have else "[  ] ") + d[0] + "  -  " + (d[1] if have else "???")
		row.add_theme_font_size_override("font_size", 16)
		row.modulate = Color(1, 1, 1) if have else Color(1, 1, 1, 0.45)
		vb.add_child(row)
	var close := Button.new()
	close.text = "Close"
	close.focus_mode = Control.FOCUS_NONE
	close.button_down.connect(_toggle_achievement_list)
	vb.add_child(close)
	# centre it once it knows how big it is
	await get_tree().process_frame
	if _ach_panel and is_instance_valid(_ach_panel):
		_ach_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)


## Dev: --ui-debug prints where the admin buttons are (for automated click tests).
func _print_ui_rects() -> void:
	print("UIRECT toggle ", _admin_toggle.get_global_rect())
	_admin.visible = true
	await get_tree().process_frame
	await get_tree().process_frame
	_show_tab(1)
	await get_tree().process_frame
	var grid := _admin.find_child("TeleportGrid", true, false) as Control
	print("UIRECT place2 ", grid.get_child(2).get_global_rect(), " ", (grid.get_child(2) as Button).text)
	_admin.visible = false


func _teleport_to(p: Dictionary) -> void:
	if car == null or not is_instance_valid(car):
		return
	var main := get_parent()
	if main.has_method("teleport_local"):
		main.teleport_local(p["pos"])
	else:
		car.teleport(p["pos"], Vector3.FORWARD)
	show_toast("Teleported: %s" % p["name"])


# ------------------------------------------------------------- hotbar (on foot)
func _build_hotbar(root: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "HotbarBox"
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 14)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN

	_prompt = Label.new()
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 24)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 8)
	box.add_child(_prompt)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 16)
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 6)
	_hint.modulate = Color(1, 1, 0.85)
	box.add_child(_hint)
	var bar_row := CenterContainer.new()
	box.add_child(bar_row)
	_charge_bg = ColorRect.new()
	_charge_bg.custom_minimum_size = Vector2(260, 12)
	_charge_bg.color = Color(0, 0, 0, 0.5)
	bar_row.add_child(_charge_bg)
	_charge_bar = ColorRect.new()
	_charge_bar.size = Vector2(0, 12)
	_charge_bg.add_child(_charge_bar)

	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 6)
	_hotbar.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_hotbar)
	for i in Items.LIST.size():
		var it: Dictionary = Items.LIST[i]
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(66, 86)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		p.add_child(vb)
		var key := Label.new()
		key.text = {Items.REMOTE: "-", Items.LASSO: "L", Items.PHONE: "P"}.get(i, str((i + 1) % 10))
		key.add_theme_font_size_override("font_size", 12)
		key.modulate = Color(1, 1, 1, 0.6)
		vb.add_child(key)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(56, 44)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture = _make_icon(it["id"])
		vb.add_child(icon)
		var nm := Label.new()
		nm.text = it["short"]
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.add_theme_font_size_override("font_size", 14)
		vb.add_child(nm)
		_hotbar.add_child(p)
		_slots.append(p)


## Renders an item's 3D model once into a little texture for its hotbar slot.
func _make_icon(id: String) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 96)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var model := Items.icon_model(id)
	vp.add_child(model)
	var aabb := _model_aabb(model)
	var centre := aabb.get_center()
	var radius := maxf(aabb.size.length() * 0.5, 0.2)
	var cam := Camera3D.new()
	cam.fov = 32.0
	vp.add_child(cam)
	var dir := Vector3(0.9, 0.55, 1.0).normalized()
	cam.position = centre + dir * radius / sin(deg_to_rad(cam.fov * 0.5)) * 0.62
	cam.look_at(centre, Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.2
	vp.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment.ambient_light_energy = 0.8
	vp.add_child(env)
	return vp.get_texture()


func _model_aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is VisualInstance3D and not (c is Light3D) and not (c is GPUParticles3D):
			var vi := c as VisualInstance3D
			var b := vi.global_transform * vi.get_aabb() if vi.is_inside_tree() else _local_xf(vi, n) * vi.get_aabb()
			box = b if first else box.merge(b)
			first = false
		for k in c.get_children():
			stack.append(k)
	return box


func _local_xf(node: Node3D, root: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


func _update_hotbar() -> void:
	var on_foot := player != null and is_instance_valid(player) and player.is_on_foot()
	_hotbar.visible = on_foot
	var t: PlayerTools = player.tools if player and is_instance_valid(player) else null
	_prompt.text = t.prompt if t else ""
	_hint.text = t.hint if t and on_foot else ""
	var alive := player != null and is_instance_valid(player)
	if alive:
		if player.is_down():
			_prompt.text = "Out cold! Seeing stars... the ambulance is on its way"
		elif player._bonk == 1:
			_prompt.text = "WHEEEEE!"
	var ch := t.charge if t and on_foot else -1.0
	_charge_bg.visible = ch >= 0.0
	if ch >= 0.0:
		_charge_bar.size = Vector2(260.0 * ch, 12)
		_charge_bar.color = Color(0.3, 0.9, 0.3).lerp(Color(1.0, 0.4, 0.1), ch)
	if on_foot:
		var winch_out := car != null and is_instance_valid(car) and _ropes().winch_rope_of(String(car.name)) != ""
		_slots[Items.REMOTE].visible = winch_out
		for i in _slots.size():
			var sel := i == t.slot
			_slots[i].add_theme_stylebox_override("panel", _slot_style(Color(0.95, 0.75, 0.2, 0.9) if sel else Color(0, 0, 0, 0.55)))
			_slots[i].modulate = Color(1, 1, 1) if sel else Color(1, 1, 1, 0.85)


func _process(delta: float) -> void:
	_update_hotbar()
	_update_winch_buttons()
	if _admin.visible and _bot_count:
		var bots: Bots = get_parent().bots
		_bot_count.text = "Island bots (%d out and about)" % bots.ambient_count()
	_toast_t -= delta
	_toast.visible = _toast_t > 0.0
	_pve_chip.visible = bool(get_parent().get("pve"))
	var v: Voice = get_parent().get("voice")
	_talk_chip.visible = v != null and v.talking_local
	dash.car = car if car and is_instance_valid(car) else null
	if car == null or not is_instance_valid(car):
		return
	_bogged.visible = car.is_bogged
	if _debug.visible:
		var t := ""
		for w in car.wheels:
			t += "%s load %5.0fN soft %.2f sink %.3f dig %.3f mu %.2f rr %.3f slip %.2f %s\n" % [
				w.name, w.load, w.soft, w.sink, w.dig, w.mu, w.rr, w.slip, "W" if w.in_water else ""]
		var p := car.global_position
		t += "pos %.0f, %.1f, %.0f  f=%.3f" % [p.x, p.y, p.z, island.z_to_f(p.z)]
		_debug.text = t

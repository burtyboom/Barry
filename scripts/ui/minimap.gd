class_name Minimap
extends Control
## Round minimap in the top-right corner (north up, follows you) and the full-island
## map (M or the map button). Both show every ute and everyone on foot: you as a big
## bright arrow with a pulsing ring, other players in their ute colour with their name,
## bots as small coloured dots, bogged bots with a flashing red ring.

const SIZE := 230.0
const VIEW_M := 230.0          ## metres from the centre to the edge of the minimap

var hud: Hud
var tex: Texture2D
var island: IslandData
var big_map: Control
var _small: Control
var _big_draw: Control
var _t := 0.0

const BOT_COLS := {"helper": Color(0.40, 1.0, 0.25), "police": Color(0.25, 0.45, 1.0), "ambulance": Color(1.0, 0.25, 0.25),
	"ranger": Color(0.20, 0.65, 0.30)}


func setup(h: Hud, map_tex: Texture2D) -> void:
	hud = h
	tex = map_tex
	island = IslandData.instance
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# --- the round minimap: a circle-shaped panel that clips the map drawn inside it
	var frame := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.42, 0.62)
	sb.set_corner_radius_all(int(SIZE / 2))
	sb.anti_aliasing = true
	frame.add_theme_stylebox_override("panel", sb)
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.size = Vector2(SIZE, SIZE)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_small = Control.new()
	_small.size = Vector2(SIZE, SIZE)
	_small.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_small.draw.connect(_draw_small)
	frame.add_child(_small)
	var ring := Control.new()
	ring.size = Vector2(SIZE, SIZE)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.draw.connect(func() -> void:
		var c := Vector2(SIZE, SIZE) * 0.5
		ring.draw_arc(c, SIZE * 0.5 - 3.0, 0, TAU, 72, Color(1, 1, 1, 0.95), 6.0, true)
		ring.draw_arc(c, SIZE * 0.5 - 7.0, 0, TAU, 72, Color(0, 0, 0, 0.25), 2.0, true)
		# north marker
		var n := c + Vector2(0, -SIZE * 0.5 + 4.0)
		ring.draw_circle(n, 13.0, UiTheme.ORANGE)
		ring.draw_string(UiTheme.font(true), n + Vector2(-6, 6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE))
	add_child(ring)
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = custom_minimum_size

	# --- the full map: a big overlay over a dimmed screen
	big_map = Control.new()
	big_map.visible = false
	big_map.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.06, 0.12, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	big_map.add_child(dim)
	_big_draw = Control.new()
	_big_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_big_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_big_draw.draw.connect(_draw_big)
	big_map.add_child(_big_draw)
	var close := Button.new()
	close.text = "Close map  (M)"
	close.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(close, UiTheme.ORANGE, 18)
	close.pressed.connect(func() -> void: big_map.visible = false)
	big_map.add_child(close)
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	big_map.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_RIGHT:
			big_map.visible = false)


func _process(delta: float) -> void:
	_t += delta
	if is_visible_in_tree():
		_small.queue_redraw()
	if big_map.visible:
		_big_draw.queue_redraw()


## Where the map should centre: you (on foot or in the ute).
func _me_pos() -> Vector3:
	if hud.player and is_instance_valid(hud.player) and hud.player.is_on_foot():
		return hud.player.global_position
	if hud.car and is_instance_valid(hud.car):
		return hud.car.global_position
	return Vector3.ZERO


## World position -> texture pixel.
func _tex_px(p: Vector3) -> Vector2:
	return Vector2((p.x - island.x_min) / IslandData.CELL / Hud.MAP_DIV, (p.z - island.z_min) / IslandData.CELL / Hud.MAP_DIV)


func _draw_small() -> void:
	var c := Vector2(SIZE, SIZE) * 0.5
	var me := _me_pos()
	var px_per_m := 1.0 / (IslandData.CELL * Hud.MAP_DIV)
	var half := VIEW_M * px_per_m
	var centre := _tex_px(me)
	_small.draw_texture_rect_region(tex, Rect2(Vector2.ZERO, Vector2(SIZE, SIZE)), Rect2(centre - Vector2(half, half), Vector2(half, half) * 2.0))
	var to_screen := func(p: Vector3) -> Vector2:
		return c + Vector2(p.x - me.x, p.z - me.z) / VIEW_M * (SIZE * 0.5)
	_draw_markers(_small, to_screen, false)


func _draw_big() -> void:
	var area := _big_draw.size
	var ts := tex.get_size()
	var scale_f := minf((area.x - 700.0) / ts.x, (area.y - 60.0) / ts.y)
	var dsize := ts * scale_f
	var origin := Vector2((area.x - dsize.x) * 0.5 - 200.0, (area.y - dsize.y) * 0.5)
	var frame := Rect2(origin - Vector2(8, 8), dsize + Vector2(16, 16))
	_big_draw.draw_rect(frame, Color(0.14, 0.42, 0.62))
	_big_draw.draw_texture_rect(tex, Rect2(origin, dsize), false)
	_big_draw.draw_rect(frame, Color.WHITE, false, 5.0)
	var font := UiTheme.font(true)
	var to_screen := func(p: Vector3) -> Vector2:
		return origin + _tex_px(p) * scale_f
	for pl in island.places:
		var mp: Vector2 = to_screen.call(pl["pos"])
		_big_draw.draw_circle(mp, 3.5, Color(0.1, 0.1, 0.1))
		_text(_big_draw, mp + Vector2(7, 5), String(pl["name"]), 13, Color(1, 1, 0.92), font)
	_draw_markers(_big_draw, to_screen, true)
	# title + legend to the right of the island
	var lx := origin.x + dsize.x + 190.0   # clear of the place names
	var ly := origin.y + 10.0
	_text(_big_draw, Vector2(lx, ly + 30), island.display_name, 34, Color(1.0, 0.85, 0.3), UiTheme.title_font())
	var rows := [["You", UiTheme.ORANGE, "arrow"], ["Other players", Color(0.3, 0.8, 1.0), "arrow"], ["Your helper", BOT_COLS["helper"], "dot"],
		["Police", BOT_COLS["police"], "dot"], ["Ambulance", BOT_COLS["ambulance"], "dot"], ["Other bots", Color(1.0, 0.85, 0.2), "dot"],
		["Bogged - needs a hand", Color(1, 0.2, 0.15), "ring"], ["On foot", Color.WHITE, "foot"]]
	for i in rows.size():
		var y := ly + 80.0 + i * 34.0
		var col: Color = rows[i][1]
		var at := Vector2(lx + 10, y)
		match rows[i][2]:
			"arrow":
				_arrow(_big_draw, at, Vector2(0, -1), 10.0, col)
			"dot":
				_big_draw.draw_circle(at, 6.0, Color(0, 0, 0, 0.6))
				_big_draw.draw_circle(at, 4.5, col)
			"ring":
				_big_draw.draw_arc(at, 8.0, 0, TAU, 20, col, 2.5)
			"foot":
				_big_draw.draw_circle(at, 5.0, Color(0, 0, 0, 0.7))
				_big_draw.draw_circle(at, 3.5, col)
		_text(_big_draw, at + Vector2(20, 6), rows[i][0], 17, Color.WHITE, font)


func _text(ctl: Control, at: Vector2, s: String, fsize: int, col: Color, font: Font) -> void:
	ctl.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 5, Color(0, 0, 0, 0.8))
	ctl.draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


func _arrow(ctl: Control, at: Vector2, dir: Vector2, r: float, col: Color) -> void:
	var o := dir.orthogonal()
	var pts := PackedVector2Array([at + dir * r * 1.5, at + o * r - dir * r * 0.8, at - dir * r * 0.25, at - o * r - dir * r * 0.8])
	var outline := PackedVector2Array()
	for p in pts:
		outline.append(at + (p - at) * 1.35)
	ctl.draw_colored_polygon(outline, Color.WHITE)
	ctl.draw_colored_polygon(pts, col)


func _draw_markers(ctl: Control, to_screen: Callable, big: bool) -> void:
	var main: Node = hud.get_parent()
	var font := UiTheme.font(true)
	var lim := SIZE * 0.5 - 6.0
	var centre := Vector2(SIZE, SIZE) * 0.5
	var visible_at := func(mp: Vector2) -> bool:
		return big or mp.distance_to(centre) < lim
	var my_car: SandVehicle = hud.car if hud.car and is_instance_valid(hud.car) else null
	var me_on_foot: bool = hud.player != null and is_instance_valid(hud.player) and hud.player.is_on_foot()
	var labels := []
	# utes
	if hud.cars_root:
		for c in hud.cars_root.get_children():
			if not c is SandVehicle:
				continue
			var v := c as SandVehicle
			var mp: Vector2 = to_screen.call(v.global_position)
			if not visible_at.call(mp):
				continue
			var fwd := -v.global_basis.z
			var dir := Vector2(fwd.x, fwd.z).normalized()
			if v.has_meta("bot"):
				var col: Color = BOT_COLS.get(String(v.get_meta("bot")), Color(1.0, 0.85, 0.2))
				if hud._bot_stuck(v):
					var r2 := (11.0 if big else 8.0) * (1.0 + 0.3 * sin(_t * 8.0))
					ctl.draw_arc(mp, r2, 0, TAU, 24, Color(1, 0.15, 0.1), 2.5)
				ctl.draw_circle(mp, 6.5 if big else 5.0, Color(0, 0, 0, 0.6))
				ctl.draw_circle(mp, 5.0 if big else 3.8, col)
			elif v == my_car and not me_on_foot:
				continue   # drawn last, on top
			else:
				var cv: Convoy = main.get("convoy")
				var n := String(v.name)
				if cv and n.begins_with("Car_") and not n.begins_with("Car_spare") and cv.in_my_convoy(int(n.trim_prefix("Car_"))):
					ctl.draw_arc(mp, 13.0 if big else 10.0, 0, TAU, 24, Color(0.45, 1.0, 0.5), 3.0)   # in your convoy
				_arrow(ctl, mp, dir, 8.0 if big else 6.5, v.body_color)
				var who := _owner_name(main, v)
				if who != "":
					labels.append([mp + Vector2(10, -8), who])
	# people on foot
	if main.get("players"):
		for p in main.players.get_children():
			var pc := p as PlayerCharacter
			if pc == null or not pc.is_on_foot() or pc == hud.player:
				continue
			var mp: Vector2 = to_screen.call(pc.global_position)
			if not visible_at.call(mp):
				continue
			var human := String(pc.name).begins_with("Player_")
			ctl.draw_circle(mp, (5.5 if human else 4.0), Color(0, 0, 0, 0.7))
			ctl.draw_circle(mp, (4.0 if human else 2.8), Color.WHITE if human else Color(1.0, 0.9, 0.6))
			if human and pc.tag_text != "":
				labels.append([mp + Vector2(8, -6), pc.tag_text])
	if big or true:
		for l in labels:
			_text(ctl, l[0], l[1], 14 if big else 12, Color.WHITE, font)
	# you: big orange arrow with a pulsing ring, always on top
	var me := _me_pos()
	var mpos: Vector2 = to_screen.call(me)
	var heading := Vector3.FORWARD
	if me_on_foot:
		heading = -hud.player.global_basis.z
	elif my_car:
		heading = -my_car.global_basis.z
	var hd := Vector2(heading.x, heading.z).normalized()
	var pulse := fmod(_t, 1.4) / 1.4
	ctl.draw_arc(mpos, 10.0 + pulse * (26.0 if big else 18.0), 0, TAU, 32, Color(1.0, 0.55, 0.1, 1.0 - pulse), 3.0)
	_arrow(ctl, mpos, hd, 11.0 if big else 9.0, UiTheme.ORANGE)
	if big:
		_text(ctl, mpos + Vector2(16, -12), "YOU", 18, UiTheme.ORANGE.lightened(0.3), font)


## "Car_5" -> that player's name; spare / unknown utes -> "".
func _owner_name(main: Node, v: SandVehicle) -> String:
	var n := String(v.name)
	if n.begins_with("Car_") and not n.begins_with("Car_spare"):
		var id := int(n.trim_prefix("Car_"))
		if id == main.multiplayer.get_unique_id():
			return ""
		return String(main.player_names.get(id, ""))
	return ""

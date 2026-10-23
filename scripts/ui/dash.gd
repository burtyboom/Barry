class_name Dash
extends Control
## The top-left dashboard card, all hand-drawn so it stays crisp and simple:
##   big speed + gear / range / locker chips
##   the sand you're on with a softness meter, where you are, the tide
##   a top-down ute with its four tyres: pressure next to each, tyre colour = how deep
##   it's sunk (green -> red), "~" = spinning, "!!" = sidewall folding, FLAT = rolled bead
##   little warning chips underneath only when something's up (deep water, rolled...)

const W := 300.0
const PAD := 16.0
const CARD := Color(0.05, 0.10, 0.17, 0.78)
const MUTED := Color(1, 1, 1, 0.62)

var car: SandVehicle
var main: Node
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 260)
	size = custom_minimum_size


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _chip(at: Vector2, text: String, bg: Color, fg := Color.WHITE, fsize := 15) -> float:
	var f := UiTheme.font(true)
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var r := Rect2(at, Vector2(tw + 16.0, fsize + 10.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(r.size.y * 0.5))
	draw_style_box(sb, r)
	draw_string(f, at + Vector2(8, fsize + 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, fg)
	return r.size.x + 6.0


func _draw() -> void:
	var f := UiTheme.font(false)
	var fb := UiTheme.font(true)
	var big := UiTheme.title_font()
	if car == null or not is_instance_valid(car):
		_card(Rect2(0, 0, W, 64))
		draw_string(fb, Vector2(PAD, 40), "Waiting for your ute...", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MUTED)
		return
	# warning chips at the bottom (worked out first so the card fits them)
	var warn := []
	if car.roll_state == 1:
		warn.append(["On its side! R to flip", UiTheme.RED])
	elif car.roll_state == 2:
		warn.append(["On its roof! R to flip", UiTheme.RED])
	if car.water_depth > 0.3:
		warn.append(["Water %.1f m deep" % car.water_depth, UiTheme.SURF])
	if car.is_bogged:
		warn.append(["Bogged - air down or R", UiTheme.ORANGE])
	var fines: int = main.fines_total if main else 0
	if fines > 0:
		warn.append(["Fines $%d" % fines, Color(0.25, 0.35, 0.8)])
	if IslandData.instance and IslandData.instance.softness_mult != 1.0:
		warn.append(["Sand x%.1f" % IslandData.instance.softness_mult, Color(0.45, 0.4, 0.35)])
	var h := 262.0 + (34.0 if not warn.is_empty() else 0.0)
	_card(Rect2(0, 0, W, h))

	# --- speed
	var spd := absi(roundi(car.speed_kmh))
	var too_fast := spd > 60
	draw_string(big, Vector2(PAD, 62), str(spd), HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color(1, 0.45, 0.35) if too_fast else Color.WHITE)
	var sw := big.get_string_size(str(spd), HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x
	draw_string(fb, Vector2(PAD + sw + 6, 60), "km/h", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, MUTED)
	# gear / range / lockers, right-aligned-ish
	var x := 168.0
	x += _chip(Vector2(x, 22), "R" if car.reversing else "D", Color(1, 1, 1, 0.16))
	x += _chip(Vector2(x, 22), "4L" if car.low_range else "4H", UiTheme.ORANGE if car.low_range else Color(1, 1, 1, 0.16))
	var lx := 168.0
	if car.front_locker:
		lx += _chip(Vector2(lx, 50), "F lock", UiTheme.PURPLE, Color.WHITE, 12)
	if car.rear_locker:
		_chip(Vector2(lx, 50), "R lock", UiTheme.PURPLE, Color.WHITE, 12)

	# --- sand + softness meter
	var y := 92.0
	draw_string(fb, Vector2(PAD, y), car.surface_name, HORIZONTAL_ALIGNMENT_LEFT, 150, 16, Color.WHITE)
	var bar := Rect2(170, y - 11, W - 170 - PAD, 9)
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color(1, 1, 1, 0.14)
	sbg.set_corner_radius_all(5)
	draw_style_box(sbg, bar)
	var soft := clampf(car.avg_soft, 0.0, 1.0)
	if soft > 0.02:
		var sfill := sbg.duplicate() as StyleBoxFlat
		sfill.bg_color = Color(0.35, 0.85, 0.4).lerp(Color(1.0, 0.6, 0.15), clampf(soft * 1.6, 0, 1)).lerp(Color(0.95, 0.25, 0.2), clampf(soft * 2.0 - 1.0, 0, 1))
		draw_style_box(sfill, Rect2(bar.position, Vector2(maxf(bar.size.x * soft, 9.0), bar.size.y)))
	draw_string(f, Vector2(170, y + 12), "soft" if soft > 0.45 else ("firm" if soft < 0.2 else "so-so"), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
	# --- where + tide
	var where := IslandData.instance.nearest_place(car.global_position) if IslandData.instance else ""
	_pin(Vector2(PAD + 5, y + 22))
	draw_string(f, Vector2(PAD + 16, y + 28), where if where != "" else IslandData.instance.display_name, HORIZONTAL_ALIGNMENT_LEFT, W - PAD * 2 - 16, 15, MUTED)
	var tide := Tide.describe().replace("  (pinned)", "")
	draw_string(f, Vector2(PAD, y + 50), "~ " + tide, HORIZONTAL_ALIGNMENT_LEFT, W - PAD * 2, 14, Color(0.6, 0.85, 1.0, 0.85))

	# --- the ute from above, with its tyres
	var c := Vector2(W * 0.5, 208)
	var body := Rect2(c - Vector2(30, 46), Vector2(60, 92))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = car.body_color.darkened(0.15)
	bsb.set_corner_radius_all(14)
	draw_style_box(bsb, body)
	var cab := StyleBoxFlat.new()
	cab.bg_color = Color(0.75, 0.9, 1.0, 0.55)
	cab.set_corner_radius_all(6)
	draw_style_box(cab, Rect2(c + Vector2(-22, -30), Vector2(44, 18)))   # windscreen (front = up)
	draw_rect(Rect2(c + Vector2(-22, 6), Vector2(44, 32)), Color(0, 0, 0, 0.18))   # tub
	var spots := [Vector2(-40, -30), Vector2(40, -30), Vector2(-40, 30), Vector2(40, 30)]
	for k in 4:
		var wh: SandVehicle.Wheel = car.wheels[k]
		var p: Vector2 = c + spots[k]
		var depth := clampf(wh.sink / car.max_sink, 0.0, 1.0)
		var tc := Color(0.30, 0.85, 0.40).lerp(Color(1.0, 0.6, 0.15), clampf(depth * 2.0, 0, 1)).lerp(Color(0.95, 0.2, 0.15), clampf(depth * 2.0 - 1.0, 0, 1))
		var squirm := wh.bead_risk > SandVehicle.BEAD_LIMIT * 0.3
		if wh.flat or squirm:
			tc = Color(0.95, 0.15, 0.15) if fmod(_t, 0.5) < 0.3 else Color(0.5, 0.05, 0.05)
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = tc
		tsb.set_corner_radius_all(5)
		tsb.border_color = Color(0.08, 0.08, 0.1)
		tsb.set_border_width_all(3)
		draw_style_box(tsb, Rect2(p - Vector2(9, 15), Vector2(18, 30)))
		# pressure label beside the tyre
		var left := k % 2 == 0
		var txt := "FLAT" if wh.flat else "%d" % roundi(wh.psi)
		var pc := Color.WHITE
		if not wh.flat and wh.psi <= 20.0:
			pc = Color(1.0, 0.85, 0.35)
		if absf(car.speed_kmh) > 60.0 and wh.psi < 22.0:
			pc = Color(1, 0.4, 0.35)   # too fast for aired-down tyres
		if wh.flat or squirm:
			pc = Color(1, 0.35, 0.3)
		var fs := 22
		var tw := fb.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var unit_w := 0.0 if wh.flat else f.get_string_size("psi", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 4.0
		var tx := p.x - 18.0 - tw - unit_w if left else p.x + 18.0
		draw_string(fb, Vector2(tx, p.y + 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, pc)
		if not wh.flat:
			draw_string(f, Vector2(tx + tw + 4.0, p.y + 5), "psi", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MUTED)
		var mark := "!!" if squirm else ("~" if wh.slip > 0.15 else "")
		if mark != "":
			draw_string(fb, Vector2(tx + (tw * 0.5) - 5.0, p.y + 24), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.8, 0.3))

	# --- warnings
	if not warn.is_empty():
		var wx := PAD
		for w in warn:
			if wx > W - 60.0:
				break
			wx += _chip(Vector2(wx, h - 36.0), w[0], w[1], Color.WHITE, 13)


func _card(r: Rect2) -> void:
	var sb := UiTheme.panel(CARD, 18, 0)
	draw_style_box(sb, r)


## A little map-pin icon.
func _pin(at: Vector2) -> void:
	draw_circle(at, 5.0, UiTheme.ORANGE)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-4, 2), at + Vector2(4, 2), at + Vector2(0, 9)]), UiTheme.ORANGE)
	draw_circle(at, 2.0, Color(0.05, 0.1, 0.17))

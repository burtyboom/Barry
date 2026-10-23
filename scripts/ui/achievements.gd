class_name Achievements
extends CanvasLayer
## Achievement pop-ups: a banner slides down from the top with a gold badge,
## a burst of sparkles and a little chime. Not saved locally - online, the server keeps them on your account.

const DEFS := {
	"forty_psi": ["40 PSI Club", "Drove off the barge onto the sand without airing down.", "40", Color(0.95, 0.55, 0.15)],
	"bogged": ["Can't Park There, Mate", "Got properly bogged.", "!!", Color(0.85, 0.25, 0.20)],
	"gone_fishing": ["Gone Fishin'", "Cast a line into the water.", "~", Color(0.20, 0.60, 0.95)],
	"happy_camper": ["Happy Camper", "Lit a campfire.", "*", Color(0.95, 0.40, 0.10)],
	"snatch": ["Snatch 'Em Out", "Pulled a bogged mate out with a recovery strap.", "S", Color(0.95, 0.80, 0.10)],
	"winch": ["Winch Wizard", "Winched a bogged car free.", "W", Color(0.55, 0.60, 0.70)],
	"deflators": ["Pressure Drop", "Let your tyres down with deflators.", "psi", Color(0.70, 0.45, 0.90)],
	"salty": ["Salty Undercarriage", "Drove into the sea up to the doors.", "~~", Color(0.10, 0.75, 0.80)],
	"lighthouse": ["Light Keeper", "Made it to a lighthouse.", "L", Color(0.95, 0.95, 0.85)],
	"ngkala": ["Ngkala Conqueror", "Made it over the Ngkala Rocks dune.", "N", Color(0.60, 0.40, 0.25)],
	"sit_down": ["Take a Load Off", "Sat down in a camp chair.", "h", Color(0.30, 0.70, 0.35)],
	"bead": ["Bead Roller", "Rolled a tyre off the rim. Too low, too fast!", "O", Color(0.25, 0.25, 0.28)],
	"reseat": ["Pump It Up", "Reseated a rolled bead with the inflator.", "+", Color(0.25, 0.75, 0.35)],
	"booked": ["Booked!", "Got pulled over for speeding on the beach. It's 60, mate!", "$", Color(0.15, 0.30, 0.80)],
	"samaritan": ["Good Samaritan", "Pulled a bogged stranger out of the sand.", "<3", Color(0.95, 0.35, 0.55)],
	"campfire_guest": ["Pull Up a Chair", "Sat down at a camper's fire for a yarn.", "~*", Color(0.90, 0.55, 0.15)],
	"winch_remote": ["Remote Control", "Used the winch remote from outside the ute.", "R", Color(0.85, 0.15, 0.10)],
	"skittled": ["Skittled!", "Sent someone flying with your ute. Sorry, mate!", "B!", Color(0.95, 0.60, 0.10)],
	"bonked": ["Human Cannonball", "Got sent flying by a ute.", "^", Color(0.40, 0.75, 0.95)],
	"air_time": ["Air Time", "Flew 20 m after a ute bump.", "20", Color(0.55, 0.85, 1.00)],
	"frequent_flyer": ["Frequent Flyer", "Got sent flying ten times. Maybe stay off the beach?", "10", Color(0.30, 0.45, 0.95)],
	"seeing_stars": ["Seeing Stars", "Got knocked out cold. Five bumps will do it.", "**", Color(1.00, 0.85, 0.20)],
	"ambo": ["Saved by the Ambos", "Got brought round by a paramedic.", "+", Color(0.90, 0.20, 0.20)],
	"thong": ["Thong Thief", "Chased down a dingo and got your thong back.", "Y", Color(0.20, 0.55, 0.95)],
	"rollover": ["Shiny Side Up", "Rolled your ute. Maybe sidle a little slower next time.", "@", Color(0.85, 0.35, 0.65)],
}

signal unlocked_one(id: String)

var unlocked := {}
var _queue: Array[String] = []
var _showing := false
var _chime: AudioStreamPlayer


func _ready() -> void:
	layer = 20
	_chime = AudioStreamPlayer.new()
	_chime.stream = _make_chime()
	_chime.volume_db = -8.0
	add_child(_chime)


func is_unlocked(id: String) -> bool:
	return unlocked.has(id)


func unlock(id: String) -> void:
	if unlocked.has(id) or not DEFS.has(id):
		return
	unlocked[id] = true
	unlocked_one.emit(id)
	_queue.append(id)
	if not _showing:
		_show_next()


## Already earned (restored from your online account): no banner.
func mark(id: String) -> void:
	if DEFS.has(id):
		unlocked[id] = true


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var id: String = _queue.pop_front()
	var d: Array = DEFS[id]
	var banner := _make_banner(d[0], d[1], d[2], d[3])
	add_child(banner)
	await get_tree().process_frame   # let it size itself
	var w := banner.size.x
	var vp := get_viewport().get_visible_rect().size
	banner.position = Vector2((vp.x - w) * 0.5, -banner.size.y - 20.0)
	banner.pivot_offset = banner.size * 0.5
	_chime.play()
	var tw := create_tween()
	tw.tween_property(banner, "position:y", 22.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _sparkle(banner))
	tw.tween_property(banner, "scale", Vector2(1.06, 1.06), 0.12)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.18)
	tw.tween_interval(3.6)
	tw.tween_property(banner, "position:y", -banner.size.y - 30.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		banner.queue_free()
		_show_next())


func _make_banner(title: String, desc: String, badge_text: String, colour: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.16, 0.94)
	sb.border_color = Color(1.0, 0.80, 0.25)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	p.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	p.add_child(hb)

	# round badge
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(76, 76)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = colour
	bsb.border_color = Color(1.0, 0.85, 0.35)
	bsb.set_border_width_all(4)
	bsb.set_corner_radius_all(38)
	badge.add_theme_stylebox_override("panel", bsb)
	var bl := Label.new()
	bl.text = badge_text
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.add_theme_font_size_override("font_size", 28 if badge_text.length() <= 2 else 20)
	bl.add_theme_color_override("font_color", Color.WHITE)
	bl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	bl.add_theme_constant_override("outline_size", 6)
	badge.add_child(bl)
	hb.add_child(badge)

	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_child(vb)
	var top := Label.new()
	top.text = "ACHIEVEMENT UNLOCKED"
	top.add_theme_font_size_override("font_size", 14)
	top.add_theme_color_override("font_color", Color(1.0, 0.80, 0.30))
	vb.add_child(top)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	t.add_theme_constant_override("outline_size", 6)
	vb.add_child(t)
	var dl := Label.new()
	dl.text = desc
	dl.add_theme_font_size_override("font_size", 16)
	dl.modulate = Color(1, 1, 1, 0.85)
	vb.add_child(dl)
	return p


## A short burst of gold sparkles from the badge.
func _sparkle(banner: Control) -> void:
	var c := CPUParticles2D.new()
	c.position = Vector2(52, banner.size.y * 0.5)
	c.amount = 40
	c.one_shot = true
	c.explosiveness = 0.9
	c.lifetime = 0.9
	c.direction = Vector2(0, -1)
	c.spread = 180.0
	c.initial_velocity_min = 120.0
	c.initial_velocity_max = 320.0
	c.gravity = Vector2(0, 420)
	c.scale_amount_min = 3.0
	c.scale_amount_max = 6.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.95, 0.5))
	g.set_color(1, Color(1.0, 0.6, 0.1, 0.0))
	c.color_ramp = g
	banner.add_child(c)
	c.emitting = true
	get_tree().create_timer(1.5).timeout.connect(c.queue_free)


## Three rising notes, synthesised so there's no audio file to manage.
func _make_chime() -> AudioStreamWAV:
	var rate := 22050
	var notes := [523.25, 659.25, 783.99, 1046.5]
	var note_len := int(rate * 0.11)
	var total := note_len * notes.size() + int(rate * 0.35)
	var data := PackedByteArray()
	data.resize(total * 2)
	for i in total:
		var v := 0.0
		for n in notes.size():
			var start: int = n * note_len
			if i >= start:
				var t := float(i - start) / rate
				v += sin(TAU * notes[n] * t) * exp(-t * 6.0) * 0.22
				v += sin(TAU * notes[n] * 2.0 * t) * exp(-t * 9.0) * 0.06
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w

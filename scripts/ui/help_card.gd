class_name HelpCard
extends PanelContainer
## The controls card (F1): three short columns of keycaps. Only the everyday stuff -
## the rest is left for people to stumble on.

const SECTIONS := [
	["Driving", [
		[["W", "A", "S", "D"], "Drive (hold S to reverse)"],
		[["Space"], "Handbrake"],
		[["1", "2", "3", "4"], "Tyres 32 / 18 / 15 / 12 psi"],
		[["[", "]"], "Tyres down / up 1 psi"],
		[["L"], "Low range (slow down first)"],
		[["X", "Z"], "Rear / front locker"],
		[["G", "H"], "Winch in / out"],
		[["F"], "Horn"],
		[["E"], "Get out"],
		[["R"], "Recover / flip it back"],
	]],
	["On foot", [
		[["W", "A", "S", "D"], "Walk"],
		[["Shift"], "Run"],
		[["Space"], "Jump"],
		[["E"], "Get in / sit / hook up"],
		[["1-0"], "Pick gear (again = put away)"],
		[["Click"], "Use / place"],
		[["Q"], "Pick up"],
		[["P"], "Phone - take a selfie"],
		[["-"], "Winch remote (Q in / E out)"],
	]],
	["Everything else", [
		[["M"], "Island map"],
		[["C"], "Camera"],
		[["Y"], "Wave"],
		[["B"], "Whistle (pets come back)"],
		[["Enter"], "Chat"],
		[["V"], "Hold to talk"],
		[["N"], "Music on / off"],
		[["Tab"], "Hold: who's on"],
		[["Esc"], "Menu / leave"],
		[["F1"], "Show / hide this"],
	]],
]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", UiTheme.panel(Color(0.05, 0.10, 0.17, 0.82), 18, 16))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 26)
	add_child(cols)
	for sec in SECTIONS:
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 5)
		cols.add_child(vb)
		var h := Label.new()
		h.text = sec[0]
		h.add_theme_font_override("font", UiTheme.title_font())
		h.add_theme_font_size_override("font_size", 20)
		h.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
		vb.add_child(h)
		for row in sec[1]:
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 3)
			vb.add_child(hb)
			for k in row[0]:
				hb.add_child(_cap(k))
			var d := Label.new()
			d.text = "  " + row[1]
			d.add_theme_font_size_override("font_size", 14)
			d.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
			hb.add_child(d)


## One key on the keyboard: a light cap with a darker lip.
func _cap(k: String) -> Label:
	var l := Label.new()
	l.text = k
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(24, 0)
	l.add_theme_font_override("font", UiTheme.font(true))
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UiTheme.INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.97, 0.95, 0.9)
	sb.set_corner_radius_all(6)
	sb.border_color = Color(0.7, 0.66, 0.58)
	sb.border_width_bottom = 3
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	l.add_theme_stylebox_override("normal", sb)
	return l

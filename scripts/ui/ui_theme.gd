class_name UiTheme
extends RefCounted
## The game's UI look: round friendly Fredoka type, chunky buttons with a darker "lip"
## underneath (they squash down when pressed), soft rounded panels.
##   make()       - dark glassy style for the in-game HUD (white text)
##   make_card()  - light sandy cards for the menus (dark text)

const SAND := Color(0.99, 0.96, 0.89)
const INK := Color(0.12, 0.16, 0.25)
const ORANGE := Color(0.98, 0.52, 0.13)
const SURF := Color(0.13, 0.58, 0.86)
const GREEN := Color(0.20, 0.68, 0.32)
const PURPLE := Color(0.55, 0.33, 0.85)
const TEAL := Color(0.10, 0.66, 0.66)
const RED := Color(0.88, 0.26, 0.24)

static var _font: Font
static var _bold: Font


static func font(bold := false) -> Font:
	if _font == null:
		var base: FontFile = load("res://assets/fonts/Fredoka.ttf")
		var ts := TextServerManager.get_primary_interface()
		_font = FontVariation.new()
		(_font as FontVariation).base_font = base
		(_font as FontVariation).variation_opentype = {ts.name_to_tag("weight"): 500}
		_bold = FontVariation.new()
		(_bold as FontVariation).base_font = base
		(_bold as FontVariation).variation_opentype = {ts.name_to_tag("weight"): 650}
	return _bold if bold else _font


static func title_font() -> Font:
	return load("res://assets/fonts/LuckiestGuy-Regular.ttf")


## A chunky button style: flat top colour with a darker lip along the bottom.
static func chunky(col: Color, radius := 14, lip := 5) -> Dictionary:
	var out := {}
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var s := StyleBoxFlat.new()
		var c := col
		match st:
			"hover":
				c = col.lightened(0.12)
			"pressed":
				c = col.darkened(0.08)
			"disabled":
				c = col.lerp(Color(0.6, 0.6, 0.6), 0.6)
		s.bg_color = c
		s.set_corner_radius_all(radius)
		s.border_color = col.darkened(0.35)
		var down: bool = st == "pressed"
		s.border_width_bottom = 1 if down else lip
		s.content_margin_left = 16
		s.content_margin_right = 16
		s.content_margin_top = 8 + (lip - 1 if down else 0)
		s.content_margin_bottom = 8
		if st == "focus":
			s.bg_color = Color(0, 0, 0, 0)
			s.border_color = Color(1, 1, 1, 0.0)
			s.set_border_width_all(0)
		out[st] = s
	return out


static func style_button(b: Button, col: Color, font_size := 20, radius := 14, lip := 5) -> void:
	var st := chunky(col, radius, lip)
	for k in st:
		b.add_theme_stylebox_override(k, st[k])
	var light := col.get_luminance() > 0.62
	var fc := INK if light else Color.WHITE
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, fc)
	b.add_theme_font_override("font", font(true))
	b.add_theme_font_size_override("font_size", font_size)
	if not light:
		b.add_theme_color_override("font_outline_color", col.darkened(0.5))
		b.add_theme_constant_override("outline_size", 4)


static func panel(bg: Color, radius := 22, margin := 22, border := Color(0, 0, 0, 0), border_w := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	if border_w > 0:
		s.border_color = border
		s.set_border_width_all(border_w)
	s.shadow_color = Color(0, 0, 0, 0.28)
	s.shadow_size = 14
	s.shadow_offset = Vector2(0, 6)
	return s


static func _common(t: Theme, text: Color, field_bg: Color, field_text: Color) -> void:
	t.default_font = font()
	t.default_font_size = 18
	t.set_color("font_color", "Label", text)
	var le := StyleBoxFlat.new()
	le.bg_color = field_bg
	le.set_corner_radius_all(10)
	le.set_content_margin_all(9)
	le.border_color = Color(0, 0, 0, 0.18)
	le.set_border_width_all(2)
	var lef := le.duplicate() as StyleBoxFlat
	lef.border_color = ORANGE
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", field_text)
	t.set_color("font_placeholder_color", "LineEdit", Color(field_text, 0.45))
	t.set_color("caret_color", "LineEdit", ORANGE)
	t.set_color("selection_color", "LineEdit", Color(ORANGE, 0.35))
	t.set_stylebox("normal", "TextEdit", le)
	t.set_stylebox("focus", "TextEdit", lef)
	# scrollbars: thin rounded
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(0.5, 0.5, 0.5, 0.6)
	grab.set_corner_radius_all(4)
	grab.content_margin_left = 4
	grab.content_margin_right = 4
	var track := StyleBoxEmpty.new()
	for sb in ["VScrollBar"]:
		t.set_stylebox("grabber", sb, grab)
		t.set_stylebox("grabber_highlight", sb, grab)
		t.set_stylebox("grabber_pressed", sb, grab)
		t.set_stylebox("scroll", sb, track)
	var tip := StyleBoxFlat.new()
	tip.bg_color = Color(0.08, 0.12, 0.20, 0.95)
	tip.set_corner_radius_all(8)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", Color.WHITE)


## In-game / default theme: dark glass, white text.
static func make() -> Theme:
	var t := Theme.new()
	_common(t, Color.WHITE, Color(1, 1, 1, 0.92), INK)
	var st := chunky(Color(0.16, 0.24, 0.36), 10, 3)
	for k in st:
		t.set_stylebox(k, "Button", st[k])
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(1.0, 0.85, 0.4))
	t.set_color("font_hover_pressed_color", "Button", Color(1.0, 0.85, 0.4))
	t.set_stylebox("panel", "PanelContainer", panel(Color(0.04, 0.08, 0.14, 0.72), 14, 12))
	return t


## Menu cards: warm sand, dark ink text, coloured buttons.
static func make_card() -> Theme:
	var t := Theme.new()
	_common(t, INK, Color(1, 1, 1), INK)
	var st := chunky(Color(0.93, 0.88, 0.78), 12, 4)
	for k in st:
		t.set_stylebox(k, "Button", st[k])
	var on := chunky(ORANGE, 12, 4)
	t.set_stylebox("pressed", "Button", on["normal"])
	t.set_stylebox("hover_pressed", "Button", on["hover"])
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_hover_pressed_color", "Button", Color.WHITE)
	t.set_color("font_color", "CheckBox", INK)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_hover_pressed_color", "CheckBox", INK)
	for k in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		t.set_stylebox(k, "CheckBox", StyleBoxEmpty.new())
	t.set_color("default_color", "RichTextLabel", INK)
	t.set_stylebox("panel", "PanelContainer", panel(SAND, 22, 22))
	return t

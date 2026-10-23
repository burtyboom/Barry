class_name Logo
extends Control
## The "That Ain't Living Barry!" title: chunky cartoon letters with a gradient fill, a fat
## outline and a white sticker edge, tilted every which way over a spinning sunburst.
## Used on the menu; tools/render_logo.gd saves it as a PNG for the website.

const FONT := "res://assets/fonts/LuckiestGuy-Regular.ttf"

## Fill gradient for the white parts of the text (the outline stays its own colour).
const GRADIENT_SHADER := """
shader_type canvas_item;
uniform vec4 top_col : source_color;
uniform vec4 bottom_col : source_color;
uniform float top_y;
uniform float bottom_y;
varying float ly;
void vertex() { ly = VERTEX.y; }
void fragment() {
	vec4 c = COLOR;
	float lum = dot(c.rgb, vec3(0.333));
	float t = clamp((ly - top_y) / max(bottom_y - top_y, 1.0), 0.0, 1.0);
	vec3 g = mix(top_col.rgb, bottom_col.rgb, t);
	if (lum > 0.9) { c.rgb = g; }
	COLOR = c;
}
"""

var animate := true
var draw_sun := true          ## false: the website draws its own animated sun behind the PNG
var _t := 0.0
var _words: Array[Control] = []
var _sun_angle := 0.0
var _ribbon: Control


func _ready() -> void:
	custom_minimum_size = Vector2(640, 350)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font: Font = load(FONT)
	# [text, size, position, tilt deg, top colour, bottom colour, outline colour]
	var parts := [
		["THAT AIN'T", 62, Vector2(70, 18), -5.0, Color(1, 1, 1), Color(0.65, 0.92, 1.0), Color(0.05, 0.22, 0.42)],
		["LIVING", 78, Vector2(150, 78), 3.0, Color(1, 1, 1), Color(0.65, 0.92, 1.0), Color(0.05, 0.22, 0.42)],
		["BARRY!", 150, Vector2(40, 140), -6.0, Color(1.0, 0.93, 0.35), Color(1.0, 0.45, 0.10), Color(0.42, 0.10, 0.03)],
	]
	for p in parts:
		var holder := Control.new()
		holder.position = p[2]
		holder.rotation_degrees = p[3]
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(holder)
		var size: int = p[1]
		# white sticker edge behind
		var back := _label(p[0], font, size, Color.WHITE, Color.WHITE, int(size * 0.34))
		back.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
		back.add_theme_constant_override("shadow_offset_x", 5)
		back.add_theme_constant_override("shadow_offset_y", 8)
		back.add_theme_constant_override("shadow_outline_size", int(size * 0.34))
		holder.add_child(back)
		var front := _label(p[0], font, size, Color.WHITE, p[6], int(size * 0.17))
		var mat := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = GRADIENT_SHADER
		mat.shader = sh
		mat.set_shader_parameter("top_col", p[4])
		mat.set_shader_parameter("bottom_col", p[5])
		mat.set_shader_parameter("top_y", size * 0.25)
		mat.set_shader_parameter("bottom_y", size * 1.05)
		front.material = mat
		holder.add_child(front)
		holder.pivot_offset = Vector2(size * 2.0, size * 0.6)
		_words.append(holder)
	_ribbon = _make_ribbon(font)


## The "AI SLOP SPECIAL EDITION" banner slapped across the bottom corner: a red ribbon
## with notched ends, a fat dark outline and a little fold under each end.
func _make_ribbon(font: Font) -> Control:
	var r := Control.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.position = Vector2(165, 270)
	r.size = Vector2(410, 56)
	r.pivot_offset = r.size * 0.5
	r.rotation_degrees = -7.0
	add_child(r)
	r.draw.connect(func() -> void:
		var w := r.size.x
		var h := r.size.y
		var ink := Color(0.30, 0.04, 0.04)
		# folded-back tails behind each end
		for side in [-1.0, 1.0]:
			var x0 := 0.0 if side < 0.0 else w
			var tail := PackedVector2Array([Vector2(x0 - side * 6.0, 12), Vector2(x0 + side * 34.0, 12), Vector2(x0 + side * 22.0, h * 0.5 + 12),
				Vector2(x0 + side * 34.0, h + 12), Vector2(x0 - side * 6.0, h + 12)])
			r.draw_colored_polygon(_grow(tail, 4.0), ink)
			r.draw_colored_polygon(tail, Color(0.62, 0.08, 0.08))
		var band := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
		r.draw_colored_polygon(_grow(band, 4.0), ink)
		r.draw_colored_polygon(band, Color(0.88, 0.14, 0.12))
		r.draw_rect(Rect2(6, 5, w - 12, 5), Color(1, 1, 1, 0.22))   # shine
		r.draw_dashed_line(Vector2(10, h - 7), Vector2(w - 10, h - 7), Color(1, 0.85, 0.6, 0.55), 2.0, 7.0))
	var l := _label("AI SLOP SPECIAL EDITION", font, 30, Color(1.0, 0.95, 0.75), Color(0.30, 0.04, 0.04), 9)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.35))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = r.size
	l.position = Vector2(0, -1)
	r.add_child(l)
	return r


## A polygon pushed out from its middle (for the outline behind a shape).
func _grow(pts: PackedVector2Array, by: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var out := PackedVector2Array()
	for p in pts:
		var d := p - c
		out.append(p + Vector2(signf(d.x), signf(d.y)) * by)
	return out


func _label(text: String, font: Font, size: int, col: Color, outline: Color, outline_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", outline_size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _process(delta: float) -> void:
	if not animate:
		return
	_t += delta
	_sun_angle += delta * 0.25
	# BARRY! does a little bounce every few seconds; the other words bob gently
	for i in _words.size():
		var w := _words[i]
		var bob := sin(_t * 1.6 + i * 1.3) * 3.0
		var sq := 1.0
		if i == 2:
			var k := fmod(_t, 4.0)
			if k < 0.5:
				sq = 1.0 + sin(k / 0.5 * PI) * 0.08
				bob -= sin(k / 0.5 * PI) * 14.0
		w.scale = Vector2(sq, 2.0 - sq)
		w.position.y = [18.0, 78.0, 140.0][i] + bob
	# the banner gives a cheeky little wiggle every so often
	var k2 := fmod(_t + 2.0, 6.0)
	_ribbon.rotation_degrees = -7.0 + (sin(k2 * 20.0) * 3.0 * (1.0 - k2 / 0.6) if k2 < 0.6 else 0.0)
	queue_redraw()


func _draw() -> void:
	# sunburst behind BARRY!
	if not draw_sun:
		return
	# turning slowly, each ray stretching and shrinking on its own beat, the middle
	# breathing in and out a little - a sun that's having a good time
	var c := Vector2(470, 180)
	var rays := 14
	for i in rays:
		var a0 := _sun_angle + TAU * i / rays
		var a1 := a0 + TAU / rays * (0.5 + 0.08 * sin(_t * 1.3 + i * 2.1))
		var r := 148.0 + 14.0 * sin(_t * 2.2 + i * 1.7)
		var tip := (a0 + a1) * 0.5
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r * 0.86,
			c + Vector2(cos(tip), sin(tip)) * r, c + Vector2(cos(a1), sin(a1)) * r * 0.86]), Color(1.0, 0.86, 0.45))
	var puff := 1.0 + 0.045 * sin(_t * 1.6)
	var squish := Vector2(1.0 + 0.035 * sin(_t * 2.3), 1.0 - 0.035 * sin(_t * 2.3))
	draw_set_transform(c, 0.0, squish * puff)
	draw_circle(Vector2.ZERO, 84.0, Color(1.0, 0.62, 0.15))
	draw_circle(Vector2.ZERO, 70.0, Color(1.0, 0.80, 0.30))
	draw_set_transform(Vector2.ZERO)

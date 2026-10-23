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
var _t := 0.0
var _words: Array[Control] = []
var _sun_angle := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(640, 300)
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
	_sun_angle += delta * 0.15
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
	queue_redraw()


func _draw() -> void:
	# sunburst behind BARRY!
	var c := Vector2(470, 180)
	var rays := 14
	for i in rays:
		var a0 := _sun_angle + TAU * i / rays
		var a1 := a0 + TAU / rays * 0.5
		var r := 148.0
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(cos(a0), sin(a0)) * r, c + Vector2(cos(a1), sin(a1)) * r]),
			Color(1.0, 0.86, 0.45))
	draw_circle(c, 84.0, Color(1.0, 0.62, 0.15))
	draw_circle(c, 70.0, Color(1.0, 0.80, 0.30))

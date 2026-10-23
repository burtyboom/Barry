class_name Avatar
extends Node3D
## Character model with simple procedural animation. Two styles:
##   "blocky" - Minecraft-ish: cube head, box body, swinging box limbs, a cap
##   "bean"   - squishy jellybean (Fall Guys-ish) with big eyes and a bucket hat
## Both share the same rig (pivot nodes) so animation code is shared.
## Origin is at the feet, facing -Z.

const STYLES := ["blocky", "bean"]
## Dress-ups (menu "Customise"). Keys go over the network inside the spec string.
const HATS := {"cap": "Cap", "bucket": "Bucket hat", "pirate": "Pirate", "corks": "Cork hat", "viking": "Viking",
	"propeller": "Propeller beanie", "chef": "Chef", "crown": "Crown", "party": "Party hat", "sombrero": "Sombrero", "none": "No hat"}
const SHIRTS := {"plain": "Plain tee", "hawaiian": "Hawaiian", "stripes": "Stripes", "flanno": "Flanno",
	"hivis": "Hi-vis", "singlet": "Singlet", "tux": "Tuxedo tee", "barry": "BARRY tee"}
const SHOES := {"sneakers": "Chunky sneakers", "thongs": "Thongs", "boots": "Big boots", "gumboots": "Gumboots",
	"clown": "Clown shoes", "flippers": "Flippers"}

var style := "blocky"
var shirt := Color(0.95, 0.45, 0.15)
var hat := ""                  ## "" = the style's usual (cap / bucket hat)
var shirt_kind := "plain"
var shoes := "sneakers"
var _propeller: Node3D
var _skin := Color(0.96, 0.78, 0.62)

var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hand_r: Node3D          ## things held in the right hand attach here

var _phase := 0.0
var _hop := 0.0
var _arm_l_x := 0.0
var _arm_r_x := 0.0
var _arm_l_z := 0.0
var _arm_r_z := 0.0
var _leg_l_x := 0.0
var _leg_r_x := 0.0
var _leg_l_z := 0.0
var _leg_r_z := 0.0
var _lean := 0.0
var _lift := 0.0           ## raises the body off the ground when lying prone (crawling)
## googly eyes: [{pupil, base (pupil rest spot), r (how far it can roll), off, vel, inner (+1/-1 toward the nose)}]
var _eyes: Array[Dictionary] = []
var _eye_last_pos := Vector3.ZERO
var _eye_last_vel := Vector3.ZERO
var _still_t := 0.0


## Height of the hips above the feet (for sitting in chairs).
func hip_height() -> float:
	return 0.36 if style == "bean" else 0.72


## style_name is either just the body ("blocky" / "bean") or a full spec from spec():
## "body;hat;shirt;shoes;rrggbb" (the colour in the spec wins over shirt_colour).
static func create(style_name: String, shirt_colour: Color) -> Avatar:
	var a := Avatar.new()
	var p := style_name.split(";")
	a.style = p[0] if p[0] in STYLES else "blocky"
	a.shirt = shirt_colour
	if p.size() >= 4:
		a.hat = p[1] if HATS.has(p[1]) else ""
		a.shirt_kind = p[2] if SHIRTS.has(p[2]) else "plain"
		a.shoes = p[3] if SHOES.has(p[3]) else "sneakers"
	if p.size() >= 5 and Color.html_is_valid(p[4]):
		a.shirt = Color.html(p[4])
	if a.hat == "":
		a.hat = "bucket" if a.style == "bean" else "cap"
	a._build()
	return a


## Everything about how this avatar looks, as one string (see create()).
static func make_spec(body: String, hat_id: String, shirt_id: String, shoes_id: String, col: Color) -> String:
	return "%s;%s;%s;%s;%s" % [body, hat_id, shirt_id, shoes_id, col.to_html(false)]


func spec() -> String:
	return make_spec(style, hat, shirt_kind, shoes, shirt)


## A random get-up for bots.
static func random_spec(body: String, col: Color) -> String:
	var h: Array = HATS.keys()
	var s: Array = SHIRTS.keys()
	var f: Array = SHOES.keys()
	return make_spec(body, h[randi() % h.size()], s[randi() % s.size()], f[randi() % f.size()], col)


func _build() -> void:
	torso = Node3D.new()
	add_child(torso)
	if style == "bean":
		_build_bean()
	else:
		_build_blocky()
	for n in [torso, head, arm_l, arm_r, leg_l, leg_r]:
		for c in n.get_children():
			if c is GeometryInstance3D:
				(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


# ------------------------------------------------------------- blocky
func _build_blocky() -> void:
	var skin := _skin
	var pants := Color(0.18, 0.30, 0.60)
	var hair := Color(0.40, 0.25, 0.12)
	# legs: pivot at the hip, hang down 0.72
	leg_l = _pivot(torso, Vector3(-0.12, 0.72, 0))
	leg_r = _pivot(torso, Vector3(0.12, 0.72, 0))
	for leg in [leg_l, leg_r]:
		Toon.box(leg, Vector3(0.23, 0.62, 0.24), Vector3(0, -0.31, 0), pants)
		_build_shoe(leg, -0.72, 0.24)
	# body
	var body := Toon.box(torso, Vector3(0.48, 0.70, 0.26), Vector3(0, 1.07, 0), shirt)
	body.material_override = _shirt_mat()
	Toon.box(torso, Vector3(0.50, 0.08, 0.28), Vector3(0, 0.74, 0), Color(0.15, 0.12, 0.10))   # belt
	_shirt_extras(torso, Vector3(0, 1.10, -0.135), 1.0)
	# arms: pivot at the shoulder
	arm_l = _pivot(torso, Vector3(-0.36, 1.36, 0))
	arm_r = _pivot(torso, Vector3(0.36, 1.36, 0))
	for arm in [arm_l, arm_r]:
		var sleeve := Toon.box(arm, Vector3(0.22, 0.30, 0.24), Vector3(0, -0.12, 0), skin if shirt_kind == "singlet" else shirt)
		if shirt_kind != "singlet":
			sleeve.material_override = _shirt_mat()
		Toon.box(arm, Vector3(0.20, 0.42, 0.22), Vector3(0, -0.46, 0), skin)
	hand_r = _pivot(arm_r, Vector3(0, -0.66, -0.02))
	# head
	head = _pivot(torso, Vector3(0, 1.42, 0))
	Toon.box(head, Vector3(0.46, 0.46, 0.46), Vector3(0, 0.23, 0), skin)
	Toon.box(head, Vector3(0.48, 0.12, 0.48), Vector3(0, 0.44, 0.0), hair)
	Toon.box(head, Vector3(0.48, 0.30, 0.10), Vector3(0, 0.32, 0.20), hair)
	# face
	for x in [-0.105, 0.105]:
		# googly eyes stuck on the front of the block head
		var white := _cyl(head, 0.085, 0.085, 0.03, Vector3(x, 0.28, -0.24), Color.WHITE)
		white.rotation_degrees.x = 90.0
		var pupil := _cyl(head, 0.04, 0.04, 0.02, Vector3(x, 0.28, -0.258), Color(0.06, 0.06, 0.08))
		pupil.rotation_degrees.x = 90.0
		_add_eye(pupil, 0.04, -signf(x))
	Toon.box(head, Vector3(0.16, 0.04, 0.02), Vector3(0, 0.13, -0.235), Color(0.55, 0.25, 0.20))
	_build_hat(head, Vector3(0, 0.50, 0), 0.85, Vector3(-0.105, 0.28, -0.26))


# ------------------------------------------------------------- bean
func _build_bean() -> void:
	var belly := shirt.lightened(0.45)
	# stubby legs
	leg_l = _pivot(torso, Vector3(-0.15, 0.36, 0))
	leg_r = _pivot(torso, Vector3(0.15, 0.36, 0))
	for leg in [leg_l, leg_r]:
		_capsule(leg, 0.11, 0.42, Vector3(0, -0.16, 0), shirt.darkened(0.15))
		_build_shoe(leg, -0.40, 0.24)
	# jellybean body
	var body := _capsule(torso, 0.40, 1.30, Vector3(0, 0.98, 0), shirt)
	body.material_override = _shirt_mat()
	if shirt_kind in ["plain", "singlet"]:
		_sphere(torso, Vector3(0.56, 0.62, 0.30), Vector3(0, 0.78, -0.18), belly)
	_shirt_extras(torso, Vector3(0, 0.98, -0.405), 1.1)
	# little arms
	arm_l = _pivot(torso, Vector3(-0.40, 1.12, 0))
	arm_r = _pivot(torso, Vector3(0.40, 1.12, 0))
	for arm in [arm_l, arm_r]:
		var a := _capsule(arm, 0.09, 0.50, Vector3(0, -0.20, 0), _skin if shirt_kind == "singlet" else shirt)
		if shirt_kind != "singlet":
			a.material_override = _shirt_mat()
		_sphere(arm, Vector3(0.18, 0.18, 0.18), Vector3(0, -0.44, 0), Color(0.98, 0.98, 0.98))   # gloves
	hand_r = _pivot(arm_r, Vector3(0, -0.46, -0.04))
	# head = the top of the bean; big googly eyes and whatever hat
	head = _pivot(torso, Vector3(0, 1.30, 0))
	for x in [-0.14, 0.14]:
		_sphere(head, Vector3(0.20, 0.24, 0.12), Vector3(x, 0.16, -0.33), Color.WHITE)
		var pupil := _sphere(head, Vector3(0.08, 0.10, 0.05), Vector3(x, 0.16, -0.39), Color(0.08, 0.08, 0.10))
		_add_eye(pupil, 0.055, -signf(x))
	_build_hat(head, Vector3(0, 0.40, 0), 1.13, Vector3(-0.14, 0.16, -0.40))


# ------------------------------------------------------------- dress-ups
## Shirt material: the colour, plus a print for the patterned shirts (box-mapped so it
## wraps any body shape).
func _shirt_mat() -> StandardMaterial3D:
	if shirt_kind in ["plain", "singlet", "barry"]:
		return Toon.mat(Color(0.97, 0.97, 0.95) if shirt_kind == "singlet" else shirt)
	var key := "%s_%s" % [shirt_kind, shirt.to_html()]
	if _shirt_mats.has(key):
		return _shirt_mats[key]
	var m := Toon.mat(Color.WHITE).duplicate() as StandardMaterial3D
	m.albedo_texture = _pattern(shirt_kind, shirt)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(2.2, 2.2, 2.2)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_shirt_mats[key] = m
	return m


static var _shirt_mats := {}


## 64x64 tileable prints, drawn by hand.
static func _pattern(kind: String, c: Color) -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	match kind:
		"hawaiian":
			img.fill(c)
			var rng := RandomNumberGenerator.new()
			rng.seed = 7
			for k in 7:
				var fc := [Color(1, 1, 1), Color(1.0, 0.85, 0.2), Color(1.0, 0.45, 0.6)][k % 3] as Color
				var cx := rng.randi_range(0, n - 1)
				var cy := rng.randi_range(0, n - 1)
				for petal in 5:
					var a := TAU * petal / 5.0 + k
					_blob(img, cx + int(cos(a) * 5), cy + int(sin(a) * 5), 4, fc)
				_blob(img, cx, cy, 2, Color(1.0, 0.6, 0.1))
			for k in 5:
				_blob(img, rng.randi_range(0, n - 1), rng.randi_range(0, n - 1), 3, Color(0.15, 0.55, 0.25))
		"stripes":
			for y in n:
				for x in n:
					img.set_pixel(x, y, c if (y / 8) % 2 == 0 else Color(0.97, 0.97, 0.95))
		"flanno":
			var dark := c.darkened(0.55)
			for y in n:
				for x in n:
					var bx := (x / 16) % 2 == 0
					var by := (y / 16) % 2 == 0
					var col := c
					if bx and by:
						col = dark
					elif bx or by:
						col = c.lerp(dark, 0.45)
					if x % 16 == 7 or y % 16 == 7:
						col = col.lerp(Color(1, 1, 0.9), 0.35)   # the thin light thread
					img.set_pixel(x, y, col)
		"hivis":
			var fl := Color(1.0, 0.55, 0.05) if c.r > c.g else Color(0.85, 1.0, 0.1)
			for y in n:
				for x in n:
					img.set_pixel(x, y, Color(0.85, 0.88, 0.9) if y % 32 >= 22 and y % 32 < 28 else fl)
		"tux":
			img.fill(Color(0.08, 0.08, 0.10))
		_:
			img.fill(c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _blob(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	var n := img.get_width()
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(posmod(cx + dx, n), posmod(cy + dy, n), c)


## Bits stuck on the front of the shirt: a painted-on tux, the BARRY print, hi-vis strips.
func _shirt_extras(parent: Node3D, front: Vector3, s: float) -> void:
	match shirt_kind:
		"tux":
			Toon.box(parent, Vector3(0.20, 0.50, 0.02) * s, front + Vector3(0, 0, -0.005), Color(0.97, 0.97, 0.97))
			Toon.box(parent, Vector3(0.18, 0.07, 0.04) * s, front + Vector3(0, 0.22 * s, -0.02), Color(0.85, 0.1, 0.12))   # bow tie
			for k in 3:
				Toon.box(parent, Vector3(0.03, 0.03, 0.02) * s, front + Vector3(0, (0.08 - k * 0.12) * s, -0.02), Color(0.1, 0.1, 0.1))
		"barry":
			var l := Label3D.new()
			l.text = "BARRY"
			l.font = load("res://assets/fonts/LuckiestGuy-Regular.ttf")
			l.font_size = 64
			l.pixel_size = 0.0018 * s
			l.modulate = Color(1.0, 0.85, 0.15)
			l.outline_modulate = Color(0.45, 0.12, 0.05)
			l.outline_size = 14
			l.position = front + Vector3(0, 0.05, -0.012)
			l.rotation_degrees.y = 180.0   # faces -Z (forward)
			l.double_sided = false
			parent.add_child(l)


## Hats sit on top of the head. `top` = crown of the head, `s` scales to the head size,
## `eye` = where the left eye is (the pirate gets an eyepatch).
func _build_hat(h: Node3D, top: Vector3, s: float, eye: Vector3) -> void:
	var a := _pivot(h, top)
	a.scale = Vector3.ONE * s
	var dark := shirt.darkened(0.25)
	match hat:
		"cap":
			_cyl(a, 0.30, 0.31, 0.14, Vector3(0, 0.05, 0), dark)
			Toon.box(a, Vector3(0.34, 0.035, 0.24), Vector3(0, -0.01, -0.33), dark)
			_sphere(a, Vector3(0.06, 0.04, 0.06), Vector3(0, 0.13, 0), dark.lightened(0.3))
		"bucket":
			var hc := Color(0.78, 0.70, 0.48)
			_cyl(a, 0.42, 0.42, 0.045, Vector3(0, 0.0, 0), hc.darkened(0.08))
			_cyl(a, 0.27, 0.30, 0.22, Vector3(0, 0.12, 0), hc)
			_cyl(a, 0.305, 0.305, 0.055, Vector3(0, 0.04, 0), Color(0.20, 0.35, 0.20))
		"pirate":
			var blk := Color(0.10, 0.09, 0.10)
			_cyl(a, 0.28, 0.31, 0.20, Vector3(0, 0.10, 0), blk)
			for k in 3:
				var side := _pivot(a, Vector3.ZERO)
				side.rotation.y = TAU * k / 3.0
				var flap := Toon.box(side, Vector3(0.52, 0.22, 0.05), Vector3(0, 0.12, -0.30), blk)
				flap.rotation_degrees.x = -22.0
			_sphere(a, Vector3(0.10, 0.10, 0.04), Vector3(0, 0.16, -0.345), Color.WHITE)   # skull
			for r in [35.0, -35.0]:
				var bone := Toon.box(a, Vector3(0.20, 0.025, 0.02), Vector3(0, 0.08, -0.35), Color.WHITE)
				bone.rotation_degrees.z = r
			# eyepatch over the left eye (and that pupil is hidden)
			var patch := _cyl(h, 0.075, 0.075, 0.03, eye + Vector3(0, 0, -0.01), blk)
			patch.rotation_degrees.x = 90.0
			var hw := absf(eye.z) * 2.0 + 0.02
			var strap := Toon.box(h, Vector3(hw, 0.025, hw), Vector3(0, eye.y + 0.07, 0), blk)
			strap.rotation_degrees.z = -12.0
			for e in _eyes:
				if float(e["inner"]) > 0.0:   # the left eye
					(e["pupil"] as Node3D).visible = false
		"corks":
			var hc := Color(0.55, 0.38, 0.22)
			_cyl(a, 0.46, 0.46, 0.04, Vector3(0, 0.0, 0), hc.darkened(0.1))
			_cyl(a, 0.25, 0.29, 0.24, Vector3(0, 0.13, 0), hc)
			_cyl(a, 0.295, 0.295, 0.05, Vector3(0, 0.04, 0), Color(0.3, 0.2, 0.1))
			for k in 8:
				var ang := TAU * (k + 0.5) / 8.0
				var p := Vector3(sin(ang) * 0.42, 0, cos(ang) * 0.42)
				Toon.box(a, Vector3(0.008, 0.14, 0.008), p + Vector3(0, -0.07, 0), Color(0.3, 0.25, 0.2))
				_cyl(a, 0.03, 0.025, 0.07, p + Vector3(0, -0.17, 0), Color(0.80, 0.62, 0.40))
		"viking":
			var steel := Color(0.65, 0.67, 0.72)
			_sphere(a, Vector3(0.62, 0.42, 0.62), Vector3(0, 0.0, 0), steel)
			_cyl(a, 0.315, 0.315, 0.06, Vector3(0, -0.03, 0), Color(0.55, 0.40, 0.18))
			for sx in [-1.0, 1.0]:
				var horn := _cyl(a, 0.0, 0.07, 0.34, Vector3(sx * 0.36, 0.14, 0), Color(0.96, 0.92, 0.80))
				horn.rotation_degrees.z = -sx * 55.0
		"propeller":
			for k in 4:
				var seg := _sphere(a, Vector3(0.60, 0.40, 0.60), Vector3(0, 0.0, 0), [Color(0.9, 0.2, 0.2), Color(0.2, 0.5, 0.95), Color(1.0, 0.85, 0.15), Color(0.2, 0.75, 0.3)][k])
				seg.scale = Vector3(0.60 - k * 0.002, 0.40, 0.60 - k * 0.002)
				seg.rotation.y = k * PI * 0.5
			_cyl(a, 0.015, 0.015, 0.14, Vector3(0, 0.25, 0), Color(0.2, 0.2, 0.2))
			_propeller = _pivot(a, Vector3(0, 0.32, 0))
			Toon.box(_propeller, Vector3(0.46, 0.015, 0.07), Vector3.ZERO, Color(1.0, 0.85, 0.15))
			Toon.box(_propeller, Vector3(0.07, 0.016, 0.46), Vector3.ZERO, Color(0.9, 0.2, 0.2))
		"chef":
			_cyl(a, 0.28, 0.28, 0.24, Vector3(0, 0.12, 0), Color(0.98, 0.98, 0.98))
			_sphere(a, Vector3(0.70, 0.40, 0.70), Vector3(0, 0.36, 0), Color(1, 1, 1))
		"crown":
			var gold := Color(1.0, 0.78, 0.15)
			_cyl(a, 0.27, 0.27, 0.14, Vector3(0, 0.06, 0), gold)
			for k in 6:
				var ang := TAU * k / 6.0
				_cyl(a, 0.0, 0.06, 0.14, Vector3(sin(ang) * 0.24, 0.20, cos(ang) * 0.24), gold)
			_sphere(a, Vector3(0.07, 0.07, 0.03), Vector3(0, 0.07, -0.275), Color(0.9, 0.1, 0.2))
		"party":
			var cone := _cyl(a, 0.0, 0.22, 0.48, Vector3(0, 0.22, 0), Color(0.95, 0.35, 0.75))
			cone.material_override = _party_mat()
			_sphere(a, Vector3(0.12, 0.12, 0.12), Vector3(0, 0.48, 0), Color(1.0, 0.9, 0.2))
			a.rotation_degrees.z = 12.0
		"sombrero":
			var straw := Color(0.92, 0.78, 0.45)
			_cyl(a, 0.80, 0.80, 0.04, Vector3(0, 0.0, 0), straw)
			_cyl(a, 0.82, 0.82, 0.05, Vector3(0, 0.03, 0), Color(0.85, 0.2, 0.2))
			_cyl(a, 0.14, 0.27, 0.36, Vector3(0, 0.18, 0), straw)
			_cyl(a, 0.275, 0.275, 0.06, Vector3(0, 0.05, 0), Color(0.2, 0.6, 0.3))


static var _party: StandardMaterial3D


static func _party_mat() -> StandardMaterial3D:
	if _party == null:
		_party = Toon.mat(Color.WHITE).duplicate() as StandardMaterial3D
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				img.set_pixel(x, y, Color(0.95, 0.35, 0.75) if ((x + y) / 4) % 2 == 0 else Color(0.35, 0.8, 1.0))
		_party.albedo_texture = ImageTexture.create_from_image(img)
		_party.uv1_triplanar = true
		_party.uv1_scale = Vector3(3, 3, 3)
	return _party


## Slightly-too-big shoes. `foot` = the sole's height below the hip pivot, `w` = leg width.
func _build_shoe(leg: Node3D, foot: float, w: float) -> void:
	var f := _pivot(leg, Vector3(0, foot, 0))
	match shoes:
		"thongs":
			Toon.box(f, Vector3(w * 1.15, 0.03, 0.40), Vector3(0, 0.015, -0.06), Color(0.2, 0.55, 0.95))
			Toon.box(f, Vector3(w * 0.95, 0.08, 0.32), Vector3(0, 0.07, -0.05), _skin)           # bare feet
			Toon.box(f, Vector3(w * 1.0, 0.03, 0.03), Vector3(0, 0.10, -0.12), Color(0.95, 0.85, 0.2))   # strap
		"boots":
			var tan := Color(0.55, 0.36, 0.18)
			Toon.box(f, Vector3(w * 1.35, 0.20, 0.44), Vector3(0, 0.10, -0.07), tan)
			Toon.box(f, Vector3(w * 1.37, 0.06, 0.46), Vector3(0, 0.03, -0.07), Color(0.15, 0.12, 0.1))
			Toon.box(f, Vector3(w * 1.2, 0.10, 0.14), Vector3(0, 0.12, -0.24), Color(0.62, 0.62, 0.65))   # steel cap
		"gumboots":
			var g := Color(0.12, 0.30, 0.18)
			Toon.box(f, Vector3(w * 1.25, 0.42, 0.28), Vector3(0, 0.21, 0.0), g)
			Toon.box(f, Vector3(w * 1.25, 0.14, 0.42), Vector3(0, 0.07, -0.07), g)
			Toon.box(f, Vector3(w * 1.3, 0.04, 0.30), Vector3(0, 0.40, 0.0), Color(0.85, 0.25, 0.1))
		"clown":
			Toon.box(f, Vector3(w * 1.6, 0.18, 0.66), Vector3(0, 0.09, -0.20), Color(0.92, 0.12, 0.12))
			Toon.box(f, Vector3(w * 1.65, 0.05, 0.68), Vector3(0, 0.02, -0.20), Color(1.0, 0.9, 0.2))
			_sphere(f, Vector3(0.10, 0.08, 0.10), Vector3(0, 0.20, -0.06), Color(1.0, 0.9, 0.2))   # pom pom
		"flippers":
			Toon.box(f, Vector3(w * 1.1, 0.14, 0.26), Vector3(0, 0.07, 0.0), Color(0.15, 0.15, 0.18))
			var fin := Toon.box(f, Vector3(w * 1.8, 0.03, 0.62), Vector3(0, 0.02, -0.38), Color(1.0, 0.85, 0.1))
			fin.rotation_degrees.x = 4.0
		_:   # chunky sneakers
			Toon.box(f, Vector3(w * 1.3, 0.16, 0.44), Vector3(0, 0.10, -0.07), Color(0.97, 0.97, 0.97))
			Toon.box(f, Vector3(w * 1.34, 0.07, 0.46), Vector3(0, 0.035, -0.07), shirt.darkened(0.1))
			Toon.box(f, Vector3(w * 1.32, 0.03, 0.20), Vector3(0, 0.12, -0.02), shirt)


func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 6
	mi.mesh = cm
	mi.material_override = Toon.mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 14
	sm.rings = 7
	mi.mesh = sm
	mi.material_override = Toon.mat(c)
	mi.scale = size
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = 20
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = Toon.mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _add_eye(pupil: MeshInstance3D, r: float, inner: float) -> void:
	_eyes.append({"pupil": pupil, "base": pupil.position, "r": r, "off": Vector2.ZERO, "vel": Vector2.ZERO, "inner": inner})


## Pupils rattle round inside the eyes as the head moves (they lag behind, gravity pulls
## them down, every footstep jiggles them); stand still for a moment and they drift
## back to a cross-eyed resting look.
func _wobble_eyes(delta: float, speed: float) -> void:
	if _eyes.is_empty() or delta <= 0.0 or not is_inside_tree() or not visible:
		return
	if _propeller:   # the propeller beanie spins up as you get going
		_propeller.rotation.y += delta * (2.0 + speed * 6.0)
	var p := head.global_position
	var vel := (p - _eye_last_pos) / delta
	var acc := (vel - _eye_last_vel) / delta
	_eye_last_pos = p
	_eye_last_vel = vel
	if acc.length() > 400.0:   # teleported / respawned
		acc = Vector3.ZERO
	var inv := head.global_basis.inverse()
	var a_local := inv * (Vector3(0, -9.8, 0) - acc)   # what the pupil "feels" in the eye's plane
	var moving := speed > 0.3 or acc.length() > 3.0
	_still_t = 0.0 if moving else _still_t + delta
	for e in _eyes:
		var off: Vector2 = e["off"]
		var v: Vector2 = e["vel"]
		var r: float = e["r"]
		if _still_t > 0.5:
			# settle cross-eyed: both pupils toward the nose
			var want := Vector2(float(e["inner"]) * r * 0.85, -r * 0.1)
			v += ((want - off) * 120.0 - v * 14.0) * delta
		else:
			v += Vector2(a_local.x, a_local.y) * 0.06 * delta
			if speed > 0.3:
				v += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * speed * 0.08 * delta * 60.0 * 0.05
			v -= v * 1.5 * delta
		off += v * delta
		if off.length() > r:
			var n := off.normalized()
			off = n * r
			var vn := v.dot(n)
			if vn > 0.0:
				v -= n * vn * 1.6   # bounce off the rim
		e["off"] = off
		e["vel"] = v
		var pupil: MeshInstance3D = e["pupil"]
		pupil.position = (e["base"] as Vector3) + Vector3(off.x, off.y, 0.0)


# ------------------------------------------------------------- animation
## pose: idle / walk / run / jump / sit / drive / swim / wind / throw / hold / dig / reel /
##       walk_hold / run_hold (moving with something up in the right hand) / wave / radar /
##       flail (sent flying by a ute) / flat (lying on your back, seeing stars) / cpr /
##       climb_out (hauling yourself out the top of a ute on its side) / crawl (belly-crawl
##       out from under a ute on its roof) / getup (on one knee, pushing up off the sand)
## speed: horizontal speed (m/s) drives the walk cycle.
func animate(delta: float, pose: String, speed: float) -> void:
	var sw := 0.0       # leg / arm swing amplitude (rad)
	var bob := 0.0
	var ta_l := 0.0     # arm targets (x = forward swing, z = out to the side)
	var ta_r := 0.0
	var tz_l := 0.08
	var tz_r := -0.08
	var tl_l := 0.0
	var tl_r := 0.0
	var lean := 0.0
	var lift := 0.0
	var sl_l := 0.0     # legs out to the side (riding astride)
	var sl_r := 0.0
	match pose:
		"walk", "run", "swim", "walk_hold", "run_hold":
			var running := pose == "run" or pose == "run_hold"
			var rate := 9.0 if running else 6.5
			_phase += delta * rate * clampf(speed / 3.0, 0.6, 1.6)
			sw = 0.95 if running else 0.6
			if pose == "swim":
				sw = 0.4
			var s := sin(_phase)
			tl_l = s * sw
			tl_r = -s * sw
			ta_l = -s * sw * 0.9
			ta_r = s * sw * 0.9
			if pose.ends_with("_hold"):
				# rod / tool held up in front, bouncing with each step
				ta_r = 0.9 + absf(cos(_phase)) * (0.15 if running else 0.07)
			bob = absf(cos(_phase)) * (0.08 if running else 0.045)
			lean = 0.18 if running else 0.05
		"wave":
			_phase += delta * 9.0
			ta_r = -2.7
			tz_r = -0.35 + sin(_phase) * 0.45
			ta_l = sin(_phase * 0.5) * 0.05
		"selfie":
			# phone up at arm's length, out front and a bit to the right, cheesy grin
			ta_r = 2.05
			tz_r = -0.32
			ta_l = 0.1
			tz_l = 0.25
			lean = -0.05
		"radar":
			# speed gun held out at arm's length, aimed up the beach
			ta_r = 1.45
			ta_l = 0.9
			tz_l = -0.35
		"flail":
			# arms windmilling, legs kicking - all very undignified
			_phase += delta * 17.0
			ta_l = -1.6 + sin(_phase) * 1.4
			ta_r = -1.6 - sin(_phase) * 1.4
			tz_l = 0.7
			tz_r = -0.7
			tl_l = sin(_phase * 1.3) * 0.9
			tl_r = -sin(_phase * 1.3) * 0.9
		"flat":
			# spread-eagled on the sand, the odd twitch
			_phase += delta * 3.0
			tz_l = 1.35
			tz_r = -1.35
			tl_l = 0.25 + maxf(sin(_phase * 1.7), 0.0) * 0.15
			tl_r = -0.25
		"tied":
			# lassoed: arms pinned to your sides, legs kicking about
			_phase += delta * 9.0
			tz_l = 0.12
			tz_r = -0.12
			tl_l = sin(_phase) * 0.45
			tl_r = -sin(_phase) * 0.45
		"cpr":
			# down on one knee, pumping away on the chest
			_phase += delta * 11.0
			ta_l = 1.25 + sin(_phase) * 0.22
			ta_r = 1.25 + sin(_phase) * 0.22
			tz_l = -0.2
			tz_r = 0.2
			tl_l = 1.2
			tl_r = -0.6
			lean = 0.55 + sin(_phase) * 0.06
		"climb_out":
			# hauling up hand over hand, one knee up, the other leg scrabbling
			_phase += delta * 7.0
			ta_l = -2.7 + sin(_phase) * 0.45
			ta_r = -2.7 - sin(_phase) * 0.45
			tz_l = 0.25
			tz_r = -0.25
			tl_l = 1.1 + sin(_phase) * 0.35
			tl_r = 0.2 - sin(_phase) * 0.35
			lean = 0.12
		"crawl":
			# flat on your belly, arms reaching out ahead and dragging you along
			_phase += delta * 6.0 * clampf(speed, 0.4, 1.6)
			lean = PI * 0.5
			lift = 0.40 if style == "bean" else 0.16
			ta_l = 2.55 + sin(_phase) * 0.5
			ta_r = 2.55 - sin(_phase) * 0.5
			tz_l = 0.35
			tz_r = -0.35
			tl_l = 0.15 + sin(_phase) * 0.25
			tl_r = 0.15 - sin(_phase) * 0.25
		"getup":
			# on one knee, pushing up off the sand
			lean = 0.75
			lift = 0.05
			tl_l = 1.45
			tl_r = 0.35
			ta_l = 0.9
			ta_r = 0.9
		"jump":
			tl_l = 0.5
			tl_r = -0.2
			ta_l = -2.6
			ta_r = -2.6
			tz_l = 0.4
			tz_r = -0.4
		"ride":
			# astride a quad / dirt bike: knees forward and out, hands on the bars
			tl_l = 0.6
			tl_r = 0.6
			sl_l = 0.28
			sl_r = -0.28
			ta_l = 1.25
			ta_r = 1.25
			tz_l = -0.18
			tz_r = 0.18
			lean = 0.22
		"sit", "drive":
			tl_l = PI * 0.5
			tl_r = PI * 0.5
			if pose == "drive":
				ta_l = 1.15
				ta_r = 1.15
				tz_l = -0.25
				tz_r = 0.25
			else:
				ta_l = 0.35
				ta_r = 0.35
		"wind":   # rod back over the shoulder
			ta_r = -2.6
			ta_l = 0.3
			lean = -0.12
		"throw":
			ta_r = 1.4
			ta_l = 0.2
			lean = 0.18
		"hold", "reel":
			ta_r = 0.9
			ta_l = 0.5 if pose == "reel" else 0.0
			if pose == "reel":
				_phase += delta * 10.0
				ta_l += sin(_phase) * 0.25
		"dig":
			_phase += delta * 6.0
			ta_r = 0.8 + sin(_phase) * 0.6
			ta_l = 0.8 + sin(_phase) * 0.6
			lean = 0.25 + sin(_phase) * 0.1
		_:   # idle: gentle breathing
			_phase += delta * 1.6
			ta_l = sin(_phase) * 0.04
			ta_r = -sin(_phase) * 0.04
			bob = sin(_phase) * 0.008
	var k := minf(1.0, delta * 14.0)
	_arm_l_x = lerpf(_arm_l_x, ta_l, k)
	_arm_r_x = lerpf(_arm_r_x, ta_r, k)
	_arm_l_z = lerpf(_arm_l_z, tz_l, k)
	_arm_r_z = lerpf(_arm_r_z, tz_r, k)
	_leg_l_x = lerpf(_leg_l_x, tl_l, k)
	_leg_r_x = lerpf(_leg_r_x, tl_r, k)
	_lean = lerpf(_lean, lean, k)
	_lift = lerpf(_lift, lift, k)
	arm_l.rotation = Vector3(_arm_l_x, 0, _arm_l_z)
	arm_r.rotation = Vector3(_arm_r_x, 0, _arm_r_z)
	leg_l.rotation.x = _leg_l_x
	leg_r.rotation.x = _leg_r_x
	_leg_l_z = lerpf(_leg_l_z, sl_l, k)
	_leg_r_z = lerpf(_leg_r_z, sl_r, k)
	leg_l.rotation.z = _leg_l_z
	leg_r.rotation.z = _leg_r_z
	torso.rotation.x = -_lean
	torso.position.y = bob + _lift
	_wobble_eyes(delta, speed if pose != "flail" else 6.0)
	# bean squash and stretch while bouncing along
	if style == "bean":
		var sq := 1.0 + bob * 1.5
		torso.scale = Vector3(1.0 / sqrt(sq), sq, 1.0 / sqrt(sq))

class_name Pet
extends Node3D
## A player's pet: a cat, or a dog (cavoodle, greyhound or border collie).
## Rides along while you drive - in the ute it picks, each time, either the tray or the back
## seat with its head out the window (ears flapping, tongue out); on the buggy, quad or
## dirt bike it sits on its spot - hops down when you get out and follows you
## around (with a bit of sniffing about), comes running when you whistle (B).
## Dogs play with other dogs - a run-up and a barrel roll - and chase cats that get too
## close; cats are chill: they wander over to other cats and bolt from dogs.
##
## The owner's machine decides what the pet does and streams it to everyone else at
## 10 Hz (pets are named Pet_<peer id> under Main/Pets, authority = that peer).

const KINDS := {
	"cat": {"name": "Cat", "dog": false, "cols": [
		["Ginger", Color(0.93, 0.55, 0.22), Color(1.0, 0.86, 0.68)],
		["Black", Color(0.13, 0.13, 0.15), Color(0.30, 0.30, 0.33)],
		["Tabby", Color(0.55, 0.53, 0.50), Color(0.82, 0.80, 0.76)],
		["Patchy", Color(0.97, 0.96, 0.93), Color(0.88, 0.52, 0.20)]]},
	"cavoodle": {"name": "Cavoodle", "dog": true, "cols": [
		["Apricot", Color(0.92, 0.66, 0.40), Color(0.98, 0.80, 0.60)],
		["Cream", Color(0.96, 0.90, 0.78), Color(1.0, 0.96, 0.90)],
		["Black", Color(0.14, 0.13, 0.13), Color(0.28, 0.26, 0.26)]]},
	"greyhound": {"name": "Greyhound", "dog": true, "cols": [
		["Grey", Color(0.55, 0.58, 0.62), Color(0.85, 0.86, 0.88)],
		["Fawn", Color(0.86, 0.70, 0.50), Color(0.95, 0.88, 0.76)],
		["Black", Color(0.14, 0.14, 0.15), Color(0.95, 0.95, 0.95)],
		["Brindle", Color(0.48, 0.34, 0.22), Color(0.28, 0.18, 0.12)]]},
	"collie": {"name": "Border Collie", "dog": true, "cols": [
		["Black & white", Color(0.10, 0.10, 0.11), Color(0.97, 0.97, 0.96)],
		["Red & white", Color(0.62, 0.32, 0.16), Color(0.97, 0.96, 0.94)],
		["Merle", Color(0.55, 0.58, 0.66), Color(0.97, 0.97, 0.96)]]},
}
## For the menu: id -> label (none first).
const MENU := {"none": "No pet", "cat": "Cat", "cavoodle": "Cavoodle", "greyhound": "Greyhound", "collie": "Border Collie"}

## Where the pet sits in the tray (ute-local): between the jerry cans and the tailgate,
## looking out over the driver's-side wall.
const TRAY_XF := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-0.42, 0.70, 1.96))
## The ute's rear passenger-side window (glass from y 1.13 to 1.53, z 0.42 to 0.98, side at
## x -0.95): the pet sits on the back seat and leans out of it - see _window_xf().
const WINDOW_SILL := Vector3(-0.99, 1.21, 0.72)
const FAR := 200.0
const WINDOW_PITCH := 0.30

## (new values only ever go on the end: they're sent over the network as ints)
enum Anim { IDLE, WALK, RUN, SIT, ROLL, HOP, TRAY, LIE, WINDOW, PERCH }

var kind := "collie"
var col_i := 0
var is_dog := true
var player: PlayerCharacter        ## who it belongs to
var preview := false               ## menu preview: just sits there looking cute
var force_anim := -1               ## dev: preview holds this pose (Anim) at force_speed
var force_speed := 0.0

var state := "follow"              ## (owner) follow / wander / sit / come / play / roll / chase / flee / visit / tray / hop
var anim := Anim.IDLE
var _t := 0.0                      ## time in this state
var _phase := 0.0                  ## walk cycle
var _speed := 0.0                  ## current ground speed (for the walk cycle)
var _yaw := 0.0
var _target := Vector3.ZERO
var _friend: Pet                   ## the dog we're playing with / cat we're chasing / visiting
var _cool := {"play": 6.0, "chase": 0.0, "visit": 4.0, "wander": 3.0, "voice": 2.0}
var _hop_a := Vector3.ZERO
var _hop_b := Vector3.ZERO
var _hop_dur := 0.6
var _hop_then := "follow"
var _roll_a := 0.0                 ## barrel-roll angle
var _flee_dir := Vector3.ZERO
var _net_t := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_has := false
var _net_vel := Vector3.ZERO       ## remote: how fast the owner says it's going
var _net_at := 0                   ## remote: when the last update came in (ms)

# rig: the body pivots at the hips (so sitting drops the rump, not the middle) and each
# leg is two bones solved with a little IK, so the paws land where we put them
var _root: Node3D                  ## everything; rolls for barrel rolls
var _body: Node3D                  ## pivot at the hip joint, torso runs forward (-Z) to the shoulders
var _legs: Array[Dictionary] = []  ## {hip, knee, paw, front, x, u, l, anchor}
var _neck: Node3D
var _head: Node3D
var _tail: Node3D
var _tail_segs: Array[Node3D] = []
var _ears: Array[Node3D] = []
var _tongue: Node3D
var _hip_h := 0.3                  ## standing hip height
var _len := 0.5                    ## hip to shoulder
var _br := 0.12                    ## torso radius
var _paw := 0.03                   ## paw radius (feet sit this far above the sand)
var _pose := {}                    ## the blended pose (see _pose_for)
var _gait_w := 0.0                 ## 0 = standing still, 1 = legs fully in the walk / run cycle
var _run_w := 0.0                  ## 0 = walk, 1 = gallop
var _slope := Vector2.ZERO         ## ground under the hind / front feet, relative to us
var _ride := Anim.TRAY             ## how we're riding this time: TRAY / WINDOW (ute) or PERCH
var _wind := 0.0                   ## 0..1 how hard the wind's blowing our ears back (window)


## Breed shapes: torso radius, hip-to-shoulder length, upper + lower leg, leg radius,
## head radius, neck length.
const SHAPE := {
	"cavoodle": {"br": 0.125, "bl": 0.25, "u": 0.115, "l": 0.115, "lr": 0.042, "hr": 0.115, "neck": 0.07},
	"greyhound": {"br": 0.085, "bl": 0.46, "u": 0.25, "l": 0.26, "lr": 0.028, "hr": 0.08, "neck": 0.15},
	"collie": {"br": 0.13, "bl": 0.40, "u": 0.165, "l": 0.165, "lr": 0.036, "hr": 0.105, "neck": 0.10},
	"cat": {"br": 0.085, "bl": 0.30, "u": 0.125, "l": 0.13, "lr": 0.024, "hr": 0.085, "neck": 0.045},
}


static func spec_of(k: String, i: int) -> String:
	return "" if k == "none" or not KINDS.has(k) else "%s:%d" % [k, i]


## "collie:1" -> a new pet (or null for "" / unknown).
static func create(spec: String) -> Pet:
	var p := spec.split(":")
	if p.size() < 1 or not KINDS.has(p[0]):
		return null
	var pet := Pet.new()
	pet.kind = p[0]
	pet.col_i = clampi(int(p[1]) if p.size() > 1 else 0, 0, (KINDS[p[0]]["cols"] as Array).size() - 1)
	pet.is_dog = bool(KINDS[p[0]]["dog"])
	pet._build()
	return pet


func spec() -> String:
	return spec_of(kind, col_i)


static func colour_of(k: String, i: int) -> Color:
	if not KINDS.has(k):
		return Color.WHITE
	var cols: Array = KINDS[k]["cols"]
	return (cols[clampi(i, 0, cols.size() - 1)] as Array)[1]


# ------------------------------------------------------------- building
func _build() -> void:
	var c: Array = (KINDS[kind]["cols"] as Array)[col_i]
	var main_c: Color = c[1]
	var acc: Color = c[2]
	var s: Dictionary = SHAPE[kind]
	var br: float = s["br"]
	var bl: float = s["bl"]
	var u: float = s["u"]
	var l: float = s["l"]
	var lr: float = s["lr"]
	var hr: float = s["hr"]
	_br = br
	_len = bl
	_paw = lr * 0.85
	_hip_h = (u + l) * (0.95 if kind != "cat" else 0.91) + _paw * 0.4
	_root = Node3D.new()
	add_child(_root)
	_body = Node3D.new()
	_body.position = Vector3(0, _hip_h, bl * 0.5)
	_root.add_child(_body)
	var fluffy := kind == "cavoodle"
	var white := Color(0.97, 0.97, 0.96)
	# ---- torso
	match kind:
		"cavoodle":
			# a cloud of curls
			_sphere(_body, Vector3(br * 2.3, br * 2.1, br * 2.2), Vector3(0, 0.0, -0.01), main_c)
			_sphere(_body, Vector3(br * 2.3, br * 2.2, br * 2.3), Vector3(0, 0.01, -bl * 0.55), main_c)
			_sphere(_body, Vector3(br * 2.1, br * 2.0, br * 2.0), Vector3(0, 0.02, -bl), main_c)
			_curls(_body, main_c.lightened(0.06), br, Vector3(0, 0, -bl * 0.5), bl * 0.6, 26)
		"greyhound":
			# deep chest up front, tucked-up waist, small rump
			_sphere(_body, Vector3(br * 2.3, br * 3.3, br * 3.0), Vector3(0, -br * 0.45, -bl * 0.84), main_c)
			_capsule(_body, br * 0.82, bl * 0.75, Vector3(0, br * 0.25, -bl * 0.42), main_c, Vector3(84, 0, 0))
			_sphere(_body, Vector3(br * 1.9, br * 1.8, br * 2.0), Vector3(0, br * 0.15, 0.0), main_c)
		"collie":
			_capsule(_body, br, bl + br * 1.4, Vector3(0, 0, -bl * 0.5), main_c, Vector3(90, 0, 0))
			_sphere(_body, Vector3(br * 2.2, br * 2.2, br * 2.0), Vector3(0, 0.0, 0.0), main_c)   # rump
			# the white ruff: chest bib + collar
			_sphere(_body, Vector3(br * 1.9, br * 2.3, br * 1.6), Vector3(0, -br * 0.15, -bl - br * 0.25), acc)
			_sphere(_body, Vector3(br * 2.25, br * 1.5, br * 1.2), Vector3(0, br * 0.45, -bl - br * 0.05), acc)
			_sphere(_body, Vector3(br * 1.2, br * 0.8, bl * 0.9), Vector3(0, -br * 0.65, -bl * 0.55), acc)   # white belly
		_:
			# slinky cat
			_capsule(_body, br, bl + br * 1.6, Vector3(0, 0, -bl * 0.5), main_c, Vector3(90, 0, 0))
			_sphere(_body, Vector3(br * 2.15, br * 2.1, br * 2.2), Vector3(0, 0.005, 0.0), main_c)
			_sphere(_body, Vector3(br * 1.5, br * 1.0, bl * 0.8), Vector3(0, -br * 0.55, -bl * 0.55), acc)   # tummy
	if kind == "cat" and col_i == 3:
		_sphere(_body, Vector3(br * 1.7, br * 1.3, br * 2.4), Vector3(0.03, br * 0.55, -bl * 0.25), acc)   # big ginger patch
		_sphere(_body, Vector3(br * 1.4, br * 1.2, br * 1.6), Vector3(-0.03, br * 0.5, 0.0), Color(0.15, 0.14, 0.15))
	if kind == "cat" and col_i == 2:
		for k in 4:   # tabby stripes over the back
			_sphere(_body, Vector3(br * 2.06, br * 0.9, 0.035), Vector3(0, br * 0.25, -bl * 0.85 + k * bl * 0.27), main_c.darkened(0.35))
	if kind == "greyhound" and col_i == 3:
		for k in 5:   # brindle stripes
			var stripe := _sphere(_body, Vector3(br * 2.0, br * 2.4, 0.03), Vector3(0, -br * 0.1, -bl * 0.95 + k * bl * 0.22), acc)
			stripe.rotation_degrees.x = 12.0
	if kind == "greyhound" and col_i == 2:
		_sphere(_body, Vector3(br * 1.6, br * 1.6, br * 1.4), Vector3(0, -br * 0.9, -bl * 0.9), acc)   # white chest
	if kind == "collie" and col_i == 2:
		for k in 4:   # merle splodges
			_sphere(_body, Vector3.ONE * br * 0.8, Vector3((k % 2 - 0.5) * br * 0.9, br * 0.7, -bl * 0.15 - k * bl * 0.22), Color(0.16, 0.17, 0.22))
	# ---- legs (0 left hind, 1 right hind, 2 left front, 3 right front)
	for front in [false, true]:
		for side in [-1.0, 1.0]:
			var leg := {"front": front, "x": side * br * (0.55 if kind != "greyhound" else 0.7), "u": u, "l": l}
			leg["anchor"] = Vector3(leg["x"], -br * (0.15 if front else 0.05), -bl if front else 0.0)
			var hip := Node3D.new()
			_root.add_child(hip)
			var knee := Node3D.new()
			knee.position = Vector3(0, -u, 0)
			hip.add_child(knee)
			var paw := Node3D.new()
			paw.position = Vector3(0, -l, 0)
			knee.add_child(paw)
			var low_c := main_c
			if kind == "collie" or (kind == "cat" and col_i == 3) or (kind == "greyhound" and col_i == 2):
				low_c = acc   # white socks
			if fluffy:
				_sphere(hip, Vector3(lr * 2.9, u * 1.5, lr * 2.9), Vector3(0, -u * 0.45, 0), main_c)
				_sphere(knee, Vector3(lr * 2.6, l * 1.45, lr * 2.6), Vector3(0, -l * 0.5, 0), low_c)
				_sphere(paw, Vector3(lr * 2.6, lr * 1.7, lr * 3.0), Vector3(0, 0, -lr * 0.3), low_c)
			else:
				var thigh := lr * (1.9 if not front else 1.35)
				if kind == "greyhound" and not front:
					thigh = lr * 2.6   # muscly
				_capsule(hip, thigh, u + thigh, Vector3(0, -u * 0.5, 0), main_c, Vector3.ZERO)
				var shin := lr * (1.3 if kind == "greyhound" and front else 1.0)   # the greyhound's forelegs need to read
				_capsule(knee, shin, l + shin, Vector3(0, -l * 0.5, 0), low_c, Vector3.ZERO)
				_sphere(paw, Vector3(lr * 2.5, lr * 1.7, lr * 3.2), Vector3(0, 0, -lr * 0.6), low_c)
			if not front:
				# haunch: a round thigh muscle so the folded leg reads when sitting
				_sphere(hip, Vector3(br * 0.75, u * 1.15, u * 0.95) * (1.25 if fluffy else 1.0), Vector3(side * br * 0.05, -u * 0.3, 0.0), main_c)
			leg["hip"] = hip
			leg["knee"] = knee
			leg["paw"] = paw
			_legs.append(leg)
	# ---- neck + head
	var neck_len: float = s["neck"]
	_neck = Node3D.new()
	_neck.position = Vector3(0, br * 0.35, -bl - br * 0.35)
	_body.add_child(_neck)
	var neck_dir := Vector3(0, 0.82, -0.57).normalized()
	if fluffy:
		_sphere(_neck, Vector3.ONE * br * 1.5, neck_dir * neck_len * 0.5, main_c)
	elif kind == "greyhound":
		# a long arched sighthound neck: thick where it leaves the chest, slimming to the
		# head, with the crest bowed up and forward (a curve of overlapping beads, not a pipe)
		var ctrl := neck_dir * neck_len * 0.5 + Vector3(0, neck_len * 0.12, -neck_len * 0.22)
		for k in 9:
			var t := float(k) / 8.0
			var p := ctrl * (2.0 * t * (1.0 - t)) + neck_dir * neck_len * (t * t)
			var r := lerpf(br * 0.95, br * 0.5, t)
			_sphere(_neck, Vector3(r * 2.0, r * 2.15, r * 2.1), p, main_c)
	else:
		var neck_r := br * 0.62
		var nm := _capsule(_neck, neck_r, neck_len + neck_r * 2.0, neck_dir * neck_len * 0.5, main_c, Vector3.ZERO)
		nm.rotation.x = -acos(neck_dir.y)   # lie the capsule along the neck
	_head = Node3D.new()
	_head.position = neck_dir * neck_len
	_neck.add_child(_head)
	var face_z := -hr * 0.95
	match kind:
		"cavoodle":
			_sphere(_head, Vector3(hr * 2.2, hr * 2.05, hr * 2.1), Vector3.ZERO, main_c)
			_curls(_head, main_c.lightened(0.06), hr * 0.95, Vector3(0, hr * 0.1, 0.0), hr * 0.3, 12)   # curly mop
			_sphere(_head, Vector3(hr * 1.15, hr * 0.95, hr * 1.1), Vector3(0, -hr * 0.35, -hr * 0.85), acc)   # short fluffy muzzle
			for x in [-1.0, 1.0]:
				var ear := Node3D.new()
				ear.position = Vector3(x * hr * 0.88, hr * 0.25, 0.0)
				_head.add_child(ear)
				_sphere(ear, Vector3(hr * 0.75, hr * 1.7, hr * 0.85), Vector3(x * hr * 0.12, -hr * 0.75, 0), main_c.darkened(0.06))
				_curls(ear, main_c.darkened(0.03), hr * 0.35, Vector3(x * hr * 0.12, -hr * 1.3, 0), hr * 0.2, 3)
				ear.set_meta("side", x)
				ear.set_meta("floppy", true)
				_ears.append(ear)
			face_z = -hr * 1.35
		"greyhound":
			# long wedge head: skull + long tapering muzzle
			_sphere(_head, Vector3(hr * 2.1, hr * 2.0, hr * 2.5), Vector3.ZERO, main_c)
			var muz := _capsule(_head, hr * 0.58, hr * 3.0, Vector3(0, -hr * 0.3, -hr * 1.45), main_c, Vector3(100, 0, 0))
			muz.scale = Vector3(1.0, 1.0, 0.85)
			for x in [-1.0, 1.0]:
				# rose ears: small and folded back along the skull
				var ear := Node3D.new()
				ear.position = Vector3(x * hr * 0.65, hr * 0.7, hr * 0.55)
				_head.add_child(ear)
				var e := _sphere(ear, Vector3(hr * 0.35, hr * 0.65, hr * 1.05), Vector3(0, 0, hr * 0.3), main_c.darkened(0.2))
				e.rotation_degrees = Vector3(-35, 0, x * 20.0)
				ear.set_meta("side", x)
				_ears.append(ear)
			face_z = -hr * 2.95
		"collie":
			_sphere(_head, Vector3(hr * 2.05, hr * 1.95, hr * 2.15), Vector3.ZERO, main_c)
			_sphere(_head, Vector3(hr * 0.95, hr * 0.85, hr * 1.55), Vector3(0, -hr * 0.35, -hr * 1.05), acc)   # white muzzle
			var blaze := _sphere(_head, Vector3(hr * 0.42, hr * 1.5, hr * 1.2), Vector3(0, hr * 0.2, -hr * 0.62), acc)   # white blaze
			blaze.rotation_degrees.x = 30.0
			for x in [-1.0, 1.0]:
				# semi-pricked ears: a flat triangle standing up off the skull, the top third
				# folded forward over the front (reads as an ear from the side and 3/4)
				var ear := Node3D.new()
				ear.position = Vector3(x * hr * 0.6, hr * 0.7, hr * 0.12)
				_head.add_child(ear)
				var lean := Node3D.new()
				lean.rotation_degrees = Vector3(10.0, 0.0, -x * 18.0)
				ear.add_child(lean)
				var base_h := hr * 0.72
				var flap := _frustum(lean, hr * 0.52, hr * 0.22, base_h, Vector3.ZERO, main_c)
				flap.scale = Vector3(1.0, 1.0, 0.42)
				# the pale inside of the ear, on the front face
				var inner := _frustum(lean, hr * 0.3, hr * 0.13, base_h * 0.85, Vector3(0, hr * 0.04, -hr * 0.1), Color(0.78, 0.62, 0.62))
				inner.scale = Vector3(1.0, 1.0, 0.25)
				var fold := Node3D.new()
				fold.position = Vector3(0, base_h * 0.96, 0)
				fold.rotation_degrees.x = -78.0
				lean.add_child(fold)
				var tip := _cone(fold, hr * 0.22, hr * 0.38, Vector3.ZERO, main_c)
				tip.scale = Vector3(1.0, 1.0, 0.42)
				ear.set_meta("side", x)
				_ears.append(ear)
			face_z = -hr * 1.75
		_:   # cat
			_sphere(_head, Vector3(hr * 2.3, hr * 2.0, hr * 2.0), Vector3.ZERO, main_c)
			for x in [-1.0, 1.0]:
				_sphere(_head, Vector3(hr * 0.75, hr * 0.62, hr * 0.62), Vector3(x * hr * 0.33, -hr * 0.4, -hr * 0.78), acc)   # whisker pads
			for x in [-1.0, 1.0]:
				var ear := Node3D.new()
				ear.position = Vector3(x * hr * 0.62, hr * 0.7, 0.0)
				_head.add_child(ear)
				var e := _cone(ear, hr * 0.48, hr * 0.85, Vector3.ZERO, main_c)
				e.scale = Vector3(1.0, 1.0, 0.55)
				e.rotation_degrees.z = -x * 12.0
				ear.set_meta("side", x)
				_ears.append(ear)
			for x in [-1.0, 1.0]:   # whiskers
				for k in 2:
					var w := Toon.box(_head, Vector3(0.12, 0.004, 0.004), Vector3(x * hr * 0.95, -hr * 0.38 + k * 0.02, -hr * 0.75), Color(0.95, 0.95, 0.95))
					w.rotation_degrees.z = x * (8.0 - k * 16.0)
	# eyes (with a little shine) + nose
	var eye_z := -hr * (0.78 if kind != "greyhound" else 0.95)
	var eye_y := hr * 0.18
	var eye_x := hr * (0.42 if kind != "greyhound" else 0.5)
	for x in [-1.0, 1.0]:
		var ec := Color(0.95, 0.85, 0.3) if kind == "cat" else Color(0.07, 0.05, 0.04)
		_sphere(_head, Vector3.ONE * hr * 0.42, Vector3(x * eye_x, eye_y, eye_z), ec)
		if kind == "cat":
			_sphere(_head, Vector3(hr * 0.12, hr * 0.34, hr * 0.1), Vector3(x * eye_x, eye_y, eye_z - hr * 0.17), Color(0.05, 0.05, 0.05))
		_sphere(_head, Vector3.ONE * hr * 0.12, Vector3(x * eye_x + hr * 0.07, eye_y + hr * 0.08, eye_z - hr * 0.18), Color(1, 1, 1))
	var nose_c := Color(0.9, 0.5, 0.55) if kind == "cat" and col_i != 1 else Color(0.08, 0.06, 0.06)
	_sphere(_head, Vector3(hr * 0.42, hr * 0.3, hr * 0.3) * (0.7 if kind == "cat" else 1.0), Vector3(0, -hr * (0.2 if kind != "greyhound" else 0.25), face_z), nose_c)
	if is_dog:
		_tongue = Node3D.new()
		_tongue.position = Vector3(0, -hr * 0.65, face_z + hr * 0.35)
		_head.add_child(_tongue)
		var tg := _sphere(_tongue, Vector3(hr * 0.42, hr * 0.12, hr * 0.75), Vector3(0, -hr * 0.12, -hr * 0.2), Color(0.95, 0.42, 0.52))
		tg.rotation_degrees.x = -35.0
		_tongue.visible = false
	# ---- tail: a short chain of bones so it can curve, wag and curl
	_tail = Node3D.new()
	_tail.position = Vector3(0, br * 0.55, br * 0.75)
	_body.add_child(_tail)
	var segs: int = {"cavoodle": 2, "greyhound": 4, "collie": 4, "cat": 5}[kind]
	var tl: float = {"cavoodle": 0.05, "greyhound": 0.1, "collie": 0.075, "cat": 0.065}[kind]
	var tr: float = {"cavoodle": 0.05, "greyhound": 0.019, "collie": 0.042, "cat": 0.022}[kind]
	var parent := _tail
	for k in segs:
		var seg := Node3D.new()
		if k > 0:
			seg.position = Vector3(0, 0, tl)
		parent.add_child(seg)
		var col := main_c
		if k == segs - 1 and (kind == "collie" or (kind == "cat" and col_i == 3)):
			col = acc
		var r := tr * (1.0 - 0.12 * k) if kind != "collie" else tr * (1.0 + 0.2 * sin(float(k) / segs * PI))
		if fluffy:
			_sphere(seg, Vector3(r * 2.5, r * 2.5, tl * 2.1), Vector3(0, 0, tl * 0.55), col)
		elif kind == "collie":
			# feathery brush: fat overlapping capsules
			_capsule(seg, r * 1.15, tl + r * 2.6, Vector3(0, -r * 0.2, tl * 0.5), col, Vector3(90, 0, 0))
		else:
			_capsule(seg, r, tl + r * 2.0, Vector3(0, 0, tl * 0.5), col, Vector3(90, 0, 0))
		_tail_segs.append(seg)
		parent = seg
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_pose = _pose_for(Anim.IDLE)
	_animate(0.0, Anim.IDLE, 0.0)


## A scatter of little balls over a surface: curly cavoodle fur.
func _curls(parent: Node3D, c: Color, r: float, centre: Vector3, spread: float, n: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind + str(n) + str(centre))
	for k in n:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1), rng.randf_range(-1, 1)).normalized()
		var p := centre + Vector3(dir.x * r * 0.92, dir.y * r * 0.92, dir.z * (r * 0.92 + spread * 0.5))
		_sphere(parent, Vector3.ONE * r * rng.randf_range(0.28, 0.4), p, c)


func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, c: Color, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = maxf(h, r * 2.0)
	cm.radial_segments = 10
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = Toon.mat(c)
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, size: Vector3, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 12
	sm.rings = 6
	mi.mesh = sm
	mi.scale = size
	mi.material_override = Toon.mat(c)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _cone(parent: Node3D, r: float, h: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 8
	mi.mesh = cm
	mi.material_override = Toon.mat(c)
	mi.position = pos + Vector3(0, h * 0.5, 0)
	parent.add_child(mi)
	return mi


## A cone with its top cut off (bottom radius r, top radius tr), sitting on pos.
func _frustum(parent: Node3D, r: float, tr: float, h: float, pos: Vector3, c: Color) -> MeshInstance3D:
	var mi := _cone(parent, r, h, pos, c)
	(mi.mesh as CylinderMesh).top_radius = tr
	return mi


# ------------------------------------------------------------- per frame
func _ready() -> void:
	_yaw = rotation.y
	_net_pos = global_position


func _owner_local() -> bool:
	return not preview and is_multiplayer_authority()


func _physics_process(delta: float) -> void:
	if preview and force_anim >= 0:
		if force_anim == Anim.ROLL:
			_roll_a = clampf(fmod(Time.get_ticks_msec() / 1000.0, 1.6) / 0.9, 0.0, 1.0) * TAU
		_animate(delta, force_anim, force_speed)
		return
	if preview:
		_animate(delta, Anim.SIT if fmod(Time.get_ticks_msec() / 1000.0, 9.0) < 6.0 else Anim.IDLE, 0.0)
		return
	if player == null or not is_instance_valid(player):
		return
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_to(global_position) > FAR
	visible = not far
	if not _owner_local():
		_remote(delta)
		return
	for k in _cool:
		_cool[k] = float(_cool[k]) - delta
	_t += delta
	_think(delta)
	if not far:
		_animate(delta, anim, _speed)
	_net_t += delta
	if _net_t > 0.1 and _online():
		_net_t = 0.0
		_st.rpc(global_position, _yaw, anim, _roll_a)


## The owner decides what the pet does.
func _think(delta: float) -> void:
	var car := player.car if player.car and is_instance_valid(player.car) else null
	var in_car := not player.is_on_foot() and car != null
	var me := global_position
	# --- riding along: hop in / out as you get in / out ("tray" = riding, whichever spot)
	if in_car and state != "tray" and state != "hop":
		# the ute: tray or back seat, a coin toss every time; the rest have one spot
		if car.kind == "ute":
			_ride = Anim.TRAY if randf() < 0.5 else Anim.WINDOW
		else:
			_ride = Anim.PERCH
		var spot := _ride_xf(car, _ride)
		if me.distance_to(spot.origin) > 25.0:
			state = "tray"   # too far to run: just turns up in its spot
		else:
			_hop(me, spot.origin, 0.55, "tray")
			_say("woof" if is_dog else "meow")
	if state == "tray":
		if not in_car:
			var out := car.global_transform * Vector3(-1.6, 0, float(car.spec["z"]) + 1.15) if car else player.global_position
			out.y = _ground(out)
			global_transform = _ride_xf(car, _ride) if car else global_transform
			_hop(global_position, out, 0.5, "follow")
			return
		if (car.kind == "ute") == (_ride == Anim.PERCH):
			_ride = Anim.TRAY if car.kind == "ute" else Anim.PERCH   # (arrived on the barge / machine swapped)
		global_transform = _ride_xf(car, _ride)
		_yaw = global_rotation.y
		_speed = 0.0
		_wind = clampf(absf(car.speed_kmh) / 60.0, 0.0, 1.0)
		anim = _ride
		return
	if state == "hop":
		var k := clampf(_t / _hop_dur, 0.0, 1.0)
		var p := _hop_a.lerp(_hop_b, k)
		p.y += sin(k * PI) * 0.9
		global_position = p
		var d := _hop_b - _hop_a
		if Vector2(d.x, d.z).length() > 0.1:
			_yaw = atan2(-d.x, -d.z)
		rotation = Vector3(0, _yaw, 0)
		anim = Anim.HOP
		if k >= 1.0:
			_go(_hop_then)
		return
	# --- on foot from here on
	var owner_pos := player.global_position
	var dist_owner := _flat(me, owner_pos)
	if dist_owner > 70.0:
		# you teleported or drove off without us: catch up
		var p := owner_pos + Vector3(1.2, 0, 1.2)
		p.y = _ground(p)
		global_position = p
		_go("follow")
	var others := _others()
	match state:
		"follow":
			var spot := owner_pos + (me - owner_pos).normalized() * (2.0 if is_dog else 3.5) if dist_owner > 0.1 else owner_pos
			if dist_owner > (3.0 if is_dog else 6.0):
				_move(spot, 6.5 if dist_owner > 10.0 else 3.0, delta)
			else:
				_stop(delta)
				# stand about, sit, and eventually flop down (cats go into a loaf sooner)
				anim = Anim.IDLE if _t < 4.0 else (Anim.SIT if _t < (14.0 if is_dog else 9.0) else Anim.LIE)
				if float(_cool["wander"]) <= 0.0 and randf() < delta * (0.25 if is_dog else 0.12):
					_go("wander")
					var a := randf() * TAU
					_target = owner_pos + Vector3(cos(a), 0, sin(a)) * randf_range(4.0, 10.0)
			_social(others, delta)
		"wander":
			# sniffing about near you
			if _flat(me, _target) < 0.6 or _t > 8.0 or dist_owner > 14.0:
				_cool["wander"] = randf_range(4.0, 12.0)
				_go("follow")
			else:
				_move(_target, 2.0 if not is_dog else 2.6, delta)
			_social(others, delta)
		"come":
			if dist_owner < 2.2 or _t > 15.0:
				_go("sit")
			else:
				_move(owner_pos, _top_speed(), delta)
		"sit":
			_stop(delta)
			anim = Anim.SIT
			if _t > 2.5:
				_go("follow")
		"play":
			if _friend == null or not is_instance_valid(_friend) or _t > 6.0 or dist_owner > 25.0:
				_go("follow")
			else:
				_move(_friend.global_position, _top_speed() * 0.85, delta)
				if _flat(me, _friend.global_position) < _len * 0.9 + 0.3:
					_start_roll()
					_friend.got_rolled(self)
					_say("woof")
		"roll":
			_stop(delta)
			_roll_a = minf(_t / 0.9, 1.0) * TAU
			anim = Anim.ROLL
			if _t > 1.1:
				_roll_a = 0.0
				_cool["play"] = randf_range(8.0, 18.0)
				# go round again sometimes
				_go("play" if _friend and is_instance_valid(_friend) and randf() < 0.35 else "follow")
		"chase":
			if _friend == null or not is_instance_valid(_friend) or _t > 6.0 or dist_owner > 30.0:
				_cool["chase"] = randf_range(12.0, 25.0)
				_go("follow")
			else:
				_move(_friend.global_position, _top_speed(), delta)
				if float(_cool["voice"]) <= 0.0:
					_say("woof")
					_cool["voice"] = randf_range(0.8, 1.6)
		"flee":
			var p := me + _flee_dir * 4.0
			_move(p, _top_speed(), delta)
			if _t > 3.0:
				_go("follow")
		"visit":
			if _friend == null or not is_instance_valid(_friend) or _t > 12.0 or dist_owner > 20.0:
				_cool["visit"] = randf_range(15.0, 30.0)
				_go("follow")
			elif _flat(me, _friend.global_position) > 1.0:
				_move(_friend.global_position, 1.6, delta)
			else:
				_stop(delta)
				anim = Anim.SIT
		_:
			_go("follow")


## Other pets about: dogs play with dogs and chase cats, cats visit cats and run from dogs.
func _social(others: Array, delta: float) -> void:
	for n in others:
		var o := n as Pet
		var od := _flat(global_position, o.global_position)
		if is_dog:
			if not o.is_dog and od < 9.0 and float(_cool["chase"]) <= 0.0:
				_friend = o
				_go("chase")
				_say("woof")
				return
			if o.is_dog and od < 14.0 and float(_cool["play"]) <= 0.0 and randf() < delta * 0.5:
				_friend = o
				_go("play")
				return
		else:
			if o.is_dog and od < 7.0:
				var away := global_position - o.global_position
				away.y = 0.0
				_flee_dir = away.normalized() if away.length() > 0.05 else Vector3.FORWARD
				_go("flee")
				_say("meow")
				return
			if not o.is_dog and od < 15.0 and od > 1.5 and float(_cool["visit"]) <= 0.0 and randf() < delta * 0.3:
				_friend = o
				_go("visit")
				return


func _others() -> Array:
	var out := []
	var parent := get_parent()
	if parent == null:
		return out
	for n in parent.get_children():
		if n is Pet and n != self and (n as Pet).visible_on_foot():
			out.append(n)
	return out


## Out on the sand (not riding along in someone's machine).
func visible_on_foot() -> bool:
	return not _riding(anim) and anim != Anim.HOP


static func _riding(a: int) -> bool:
	return a == Anim.TRAY or a == Anim.WINDOW or a == Anim.PERCH


## Where we ride (world): the tray, leaning out the back window, or the machine's pet spot.
func _ride_xf(car: SandVehicle, how: int) -> Transform3D:
	if car.kind != "ute" or how == Anim.PERCH:
		return car.global_transform * car.pet_spot()
	if how == Anim.WINDOW:
		return car.global_transform * _window_xf()
	return car.global_transform * TRAY_XF


## Back seat, ute-local: facing out of the left-hand side, shoulders just inside the glass
## so the neck, head and front paws stick out of the window and the rest stays in the cab.
func _window_xf() -> Transform3D:
	var pitch := WINDOW_PITCH
	var hz := _len * 0.5
	var shoulder_z := hz - _len * cos(pitch)          # (root space, nose to -Z)
	var shoulder_y := _hip_h + _len * sin(pitch)
	# nose -Z turned to -X: root +Z ends up along ute +X
	var o := WINDOW_SILL - Vector3(shoulder_z, shoulder_y, 0)
	return Transform3D(Basis(Vector3.UP, PI * 0.5), o)


## Another dog barrelled into us: tumble too (runs on our owner's machine).
func got_rolled(by: Pet) -> void:
	if _owner_local():
		_friend = by
		_start_roll()
	else:
		_rpc_rolled.rpc_id(get_multiplayer_authority())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rolled() -> void:
	if _owner_local() and state != "tray" and state != "hop":
		_start_roll()


func _start_roll() -> void:
	_go("roll")


## B: come here! (Also used when you jump in the ute.)
func whistle() -> void:
	if not _owner_local():
		return
	Sfx.play_at(self, "whistle", player.global_position + Vector3.UP * 1.6, -2.0)
	if _online():
		_rpc_whistle.rpc(player.global_position + Vector3.UP * 1.6)
	if state != "tray" and state != "hop":
		_friend = null
		_cool["chase"] = 10.0
		_cool["play"] = 10.0
		_go("come")
		get_tree().create_timer(0.6).timeout.connect(func() -> void: _say("woof" if is_dog else "meow"))


@rpc("any_peer", "call_remote", "reliable")
func _rpc_whistle(at: Vector3) -> void:
	Sfx.play_at(self, "whistle", at, -2.0)


func _say(what: String) -> void:
	if visible:
		Sfx.play_at(self, what, global_position + Vector3.UP * 0.5, -8.0, randf_range(0.9, 1.15) * (1.3 if kind == "cavoodle" else 1.0))


func _go(s: String) -> void:
	state = s
	_t = 0.0


func _hop(a: Vector3, b: Vector3, dur: float, then: String) -> void:
	_hop_a = a
	_hop_b = b
	_hop_dur = dur
	_hop_then = then
	_go("hop")


func _top_speed() -> float:
	return {"greyhound": 11.0, "collie": 8.5, "cavoodle": 6.0, "cat": 7.5}.get(kind, 7.0)


func _move(to: Vector3, spd: float, delta: float) -> void:
	var d := Vector3(to.x - global_position.x, 0, to.z - global_position.z)
	var island := IslandData.instance
	var p := global_position
	var water := island.water_level_at(p.x, p.z) - island.height_at(p.x, p.z) if island else 0.0
	if water > 0.4:
		spd *= 0.45   # paddling
	if d.length() < 0.05:
		_stop(delta)
		return
	var want := atan2(-d.x, -d.z)
	_yaw = lerp_angle(_yaw, want, minf(1.0, 8.0 * delta))
	_speed = move_toward(_speed, spd, 14.0 * delta)
	p += Vector3(-sin(_yaw), 0, -cos(_yaw)) * minf(_speed * delta, d.length())
	p.y = _ground(p)
	global_position = p
	rotation = Vector3(0, _yaw, 0)
	anim = Anim.RUN if _speed > 4.0 else Anim.WALK


func _stop(delta: float) -> void:
	_speed = move_toward(_speed, 0.0, 10.0 * delta)
	var p := global_position
	p.y = _ground(p)
	global_position = p
	rotation = Vector3(0, _yaw, 0)
	if _speed < 0.2:
		anim = Anim.IDLE


func _ground(p: Vector3) -> float:
	var island := IslandData.instance
	if island == null:
		return p.y
	var h := island.height_at(p.x, p.z)
	var w := island.water_level_at(p.x, p.z)
	return maxf(h, w - _hip_h * 0.9)   # swimming: head above water


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ------------------------------------------------------------- animation
## The still pose for an animation, in _root space (nose to -Z, paws at y = 0):
## body pitch (+ = nose up), hip height, where the hind / front paws go (z, y), head nod,
## tail droop (+ = down) and curl, tail sweep round to the side, ears back.
func _pose_for(a: int) -> Dictionary:
	var bl := _len
	var hz := bl * 0.5
	var leg_l: float = _legs[0]["u"] + _legs[0]["l"] if not _legs.is_empty() else _hip_h
	var cat := kind == "cat"
	var p := {"pitch": 0.0, "hip_y": _hip_h, "hind": Vector2(hz + 0.01, _paw), "front": Vector2(-hz, _paw),
		"head": 0.0, "tail": 0.0, "curl": 0.0, "sweep": 0.0}
	match kind:
		"cavoodle":
			p["tail"] = -0.9
			p["curl"] = -0.35
		"greyhound":
			p["tail"] = 1.05
			p["curl"] = -0.12
		"collie":
			p["tail"] = 0.95
			p["curl"] = -0.22
		_:
			p["tail"] = -1.2
			p["curl"] = -0.22
	match a:
		Anim.WALK, Anim.RUN:
			if cat:
				p["hip_y"] = _hip_h * 0.94   # slinky: a touch low
				p["head"] = -0.12
			elif kind == "greyhound" or kind == "collie":
				p["tail"] = float(p["tail"]) - 0.45   # tail comes up a bit on the move
			if a == Anim.RUN:
				p["head"] = -0.2
		Anim.SIT, Anim.PERCH:
			# rump on the sand (or the seat), front legs straight, hind legs folded up beside the body
			var hy := _br * (0.95 if kind != "greyhound" else 1.25)
			# tip up until the front legs are straight under the shoulders
			var shoulder := leg_l * 0.97 + _paw + _br * 0.15
			var pitch := asin(clampf((shoulder - hy) / bl, 0.5, 0.97))
			# long-legged dogs would sit bolt upright like a meerkat: lean them back to a
			# sighthound sit and plant the (still straight) front legs a little forward instead
			pitch = minf(pitch, 1.02 if kind == "greyhound" else 1.2)
			p["hip_y"] = hy
			p["pitch"] = pitch
			var sh_y := hy + bl * sin(pitch) - _br * 0.15 - _paw
			var reach := sqrt(maxf(0.0, pow(leg_l * 0.97, 2.0) - sh_y * sh_y))
			p["front"] = Vector2(hz - bl * cos(pitch) - 0.01 - reach, _paw)
			p["hind"] = Vector2(hz - leg_l * 0.55, _paw)
			p["head"] = 0.08
			if cat:
				p["tail"] = 1.2
				p["curl"] = 0.05
				p["sweep"] = 0.42   # wrapped round the paws
			else:
				p["tail"] = minf(float(p["tail"]), 0.0) + 1.0
				p["curl"] = 0.0
		Anim.LIE:
			p["hip_y"] = _br * 0.92
			p["pitch"] = 0.0
			if cat:
				# loaf: every paw tucked away under
				p["front"] = Vector2(-hz + _br * 0.4, _paw)
				p["hind"] = Vector2(hz - _br * 0.6, _paw)
				p["tail"] = 1.3
				p["curl"] = 0.0
				p["sweep"] = 0.45
			else:
				# flopped down: front paws out in front, back legs tucked along the tummy
				p["front"] = Vector2(-hz - leg_l * (0.5 if kind != "greyhound" else 1.05), _paw)   # greyhound: long forelegs stretched right out (any less and the elbows fold under the sand)
				p["hind"] = Vector2(hz - leg_l * 0.9, _paw)
				p["head"] = 0.05
				p["tail"] = 1.35
				p["curl"] = 0.0
				p["sweep"] = 0.15
		Anim.TRAY:
			# up on the side of the tray, looking out
			var pitch := 0.32
			p["pitch"] = pitch
			p["front"] = Vector2(hz - bl * cos(pitch) - 0.03, _hip_h + bl * sin(pitch) - leg_l * 0.88)
			p["head"] = -0.15
			if is_dog:
				p["tail"] = float(p["tail"]) - 0.4
		Anim.WINDOW:
			# leaning out the back window: chest on the sill, front paws hooked over it,
			# head up into the wind
			var pitch := WINDOW_PITCH
			p["pitch"] = pitch
			p["front"] = Vector2(hz - bl * cos(pitch) - leg_l * 0.42, _hip_h + bl * sin(pitch) - leg_l * 0.22)
			p["hind"] = Vector2(hz + 0.02, _paw)
			p["head"] = -0.25
			if is_dog:
				p["tail"] = float(p["tail"]) - 0.4
		Anim.HOP:
			p["pitch"] = 0.12
			p["front"] = Vector2(-hz - leg_l * 0.55, _hip_h - leg_l * 0.55)
			p["hind"] = Vector2(hz + leg_l * 0.65, _hip_h - leg_l * 0.6)
			p["head"] = -0.1
		Anim.ROLL:
			# paws tucked up, belly to the sky on the way round
			p["hip_y"] = _hip_h * 0.75
			p["front"] = Vector2(-hz + 0.02, _hip_h * 0.75 - leg_l * 0.5)
			p["hind"] = Vector2(hz - 0.02, _hip_h * 0.75 - leg_l * 0.5)
	return p


func _animate(delta: float, a: int, spd: float) -> void:
	var k := minf(1.0, 7.0 * delta) if delta > 0.0 else 1.0
	var want := _pose_for(a)
	for key in want:
		_pose[key] = lerp(_pose[key], want[key], k) if _pose.has(key) else want[key]
	var moving := (a == Anim.WALK or a == Anim.RUN or (a == Anim.IDLE and spd > 0.4))
	_gait_w = move_toward(_gait_w, 1.0 if moving else 0.0, delta * 5.0)
	_run_w = move_toward(_run_w, 1.0 if a == Anim.RUN else 0.0, delta * 3.0)
	var leg_l: float = _legs[0]["u"] + _legs[0]["l"]
	var stride := leg_l * (0.3 + 0.28 * _run_w)
	if _gait_w > 0.01:
		# the feet sweep 2 * stride per half cycle: match that to the ground speed so they don't skate
		_phase += delta * maxf(PI * spd / (2.0 * stride), 4.0)
	var hz := _len * 0.5
	# the sand under the hind and front feet (on the island, out on foot)
	var on_ground := is_inside_tree() and not preview and IslandData.instance != null and (a == Anim.IDLE or a == Anim.WALK or a == Anim.RUN or a == Anim.SIT or a == Anim.LIE)
	var slope := Vector2.ZERO
	if on_ground:
		var b := global_transform.basis
		var gh := _ground(global_position + b * Vector3(0, 0, hz)) - global_position.y
		var gf := _ground(global_position + b * Vector3(0, 0, -hz)) - global_position.y
		slope = Vector2(clampf(gh, -0.3, 0.3), clampf(gf, -0.3, 0.3))
	_slope = _slope.lerp(slope, minf(1.0, 10.0 * delta) if delta > 0.0 else 1.0)
	# body: gallop rocks nose up / down, walking bobs a little
	var ph := _phase
	var rock := sin(ph) * 0.1 * _run_w * _gait_w
	var bob := (cos(ph * 2.0) * leg_l * 0.025 * (1.0 - _run_w) + sin(ph + 0.6) * leg_l * 0.06 * _run_w) * _gait_w
	var pitch := float(_pose["pitch"]) + rock + atan2(_slope.y - _slope.x, _len)
	_body.position = Vector3(0, float(_pose["hip_y"]) + bob + _slope.x, hz)
	_body.rotation = Vector3(pitch, 0, 0)
	# legs: walk = one foot at a time (hind, front, other hind, other front); gallop = pairs
	var walk_off := [0.0, PI, PI * 0.5, PI * 1.5]
	var run_off := [0.0, 0.45, PI, PI + 0.45]
	var lift := leg_l * (0.16 + 0.14 * _run_w)
	for i in _legs.size():
		var leg: Dictionary = _legs[i]
		var front: bool = leg["front"]
		var base: Vector2 = _pose["front"] if front else _pose["hind"]
		var off := lerpf(walk_off[i], run_off[i], _run_w)
		var f := Vector3(leg["x"], base.y + (_slope.y if front else _slope.x), base.x)
		if _gait_w > 0.0:
			f.z += -stride * sin(ph + off) * _gait_w
			f.y += lift * maxf(0.0, cos(ph + off)) * _gait_w
		_solve(leg, _body.transform * (leg["anchor"] as Vector3), f)
	# neck keeps the head level whatever the body's doing; head looks about when idle
	_neck.rotation.x = -pitch * 0.85 + float(_pose["head"])
	var look := sin(Time.get_ticks_msec() * 0.0011 + col_i * 1.7) * 0.5 if _gait_w < 0.5 and a != Anim.ROLL else 0.0
	if a == Anim.WINDOW:
		look = -0.45 + sin(Time.get_ticks_msec() * 0.0009 + col_i) * 0.15   # nose into the wind (toward the front)
	_head.rotation.y = lerp_angle(_head.rotation.y, look, minf(1.0, 4.0 * delta))
	_head.rotation.z = sin(Time.get_ticks_msec() * 0.0007 + col_i) * 0.12 * (1.0 - _gait_w) if is_dog else 0.0   # the head tilt
	# ears: floppy ones bounce, pricked ones flick back when running
	var now := Time.get_ticks_msec() * 0.001
	for e in _ears:
		var side: float = e.get_meta("side")
		if a == Anim.WINDOW:
			# head out the window: ears streaming back and flapping, more the faster we go
			var flap := sin(now * (16.0 + 10.0 * _wind) + side * 1.3) * (0.15 + 0.4 * _wind)
			if e.has_meta("floppy"):
				e.rotation.z = side * (0.35 + 0.55 * _wind + flap)
				e.rotation.x = -0.4 - 0.9 * _wind + flap * 0.5
			else:
				e.rotation.x = -0.35 - 0.6 * _wind + flap * 0.3
			continue
		if e.has_meta("floppy"):
			e.rotation.z = side * (0.15 + sin(ph * 2.0) * 0.25 * _gait_w + _run_w * 0.35)
			e.rotation.x = -0.5 * _run_w
		else:
			var twitch := maxf(0.0, sin(now * 1.3 + side * 2.0) - 0.96) * 6.0
			e.rotation.x = -0.55 * _run_w * _gait_w - twitch * 0.3
	# tail: dogs wag (harder when happy), cats swish the tip slowly
	var happy := a == Anim.RUN or a == Anim.TRAY or a == Anim.WINDOW or a == Anim.HOP or (state == "come" and _owner_local())
	var wag := sin(now * (13.0 if is_dog else 1.8)) * (0.45 if happy else 0.22)
	if not is_dog:
		wag = sin(now * 1.8) * 0.25
	_tail.rotation = Vector3(float(_pose["tail"]), wag if is_dog else wag * 0.4, 0)
	for j in _tail_segs.size():
		if j == 0:
			continue
		var seg := _tail_segs[j]
		var lag := sin(now * (13.0 if is_dog else 1.8) - j * 0.8) * (0.12 if is_dog else 0.18)
		seg.rotation = Vector3(float(_pose["curl"]), float(_pose["sweep"]) + lag, 0)
	if _tongue:
		_tongue.visible = a == Anim.RUN or a == Anim.TRAY or a == Anim.WINDOW or a == Anim.ROLL or ((a == Anim.SIT or a == Anim.PERCH) and fmod(now + col_i, 7.0) < 4.0)
	# barrel roll: the whole pet spins round its nose-to-tail axis
	_root.position.y = 0.0
	if a == Anim.ROLL:
		_root.rotation.z = _roll_a
		_root.position.y = absf(sin(_roll_a * 0.5)) * _hip_h * 0.6
	else:
		_root.rotation.z = lerp_angle(_root.rotation.z, 0.0, minf(1.0, 10.0 * delta))


## Two-bone leg: put the paw at `foot` (in _root space) from the joint at `at`.
## Front legs bend at the back (elbow), hind legs at the front (stifle), like the real thing.
func _solve(leg: Dictionary, at: Vector3, foot: Vector3) -> void:
	var hip: Node3D = leg["hip"]
	var u: float = leg["u"]
	var l: float = leg["l"]
	hip.position = at
	var dy := foot.y - at.y
	var dz := foot.z - at.z
	var d := clampf(sqrt(dy * dy + dz * dz), absf(u - l) + 0.01, u + l - 0.001)
	var aim := atan2(-dz, -dy)   # rotation.x that points a bone straight at the foot
	var alpha := acos(clampf((u * u + d * d - l * l) / (2.0 * u * d), -1.0, 1.0))
	var bend := PI - acos(clampf((u * u + l * l - d * d) / (2.0 * u * l), -1.0, 1.0))
	var upper: float
	var lower: float
	if leg["front"]:
		upper = aim - alpha
		lower = upper + bend
	else:
		upper = aim + alpha
		lower = upper - bend
	hip.rotation.x = upper
	(leg["knee"] as Node3D).rotation.x = lower - upper
	(leg["paw"] as Node3D).rotation.x = -lower   # paw stays flat on the ground


# ------------------------------------------------------------- network
func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


@rpc("authority", "call_remote", "unreliable_ordered")
func _st(pos: Vector3, yaw: float, a: int, roll: float) -> void:
	var now := Time.get_ticks_msec()
	if not _net_has:
		global_position = pos
	elif now > _net_at:
		var v := (pos - _net_pos) / maxf((now - _net_at) / 1000.0, 0.05)
		_net_vel = v if v.length() < 20.0 else Vector3.ZERO   # a teleport, not a sprint
	_net_at = now
	_net_pos = pos
	_net_yaw = yaw
	anim = a as Anim
	_roll_a = roll
	_net_has = true


## Someone else's pet: glide to where its owner says it is (in the tray it rides the ute itself).
func _remote(delta: float) -> void:
	var car := player.car if player.car and is_instance_valid(player.car) else null
	if _riding(anim) and car:
		global_transform = _ride_xf(car, anim)
		_wind = clampf(absf(car.speed_kmh) / 60.0, 0.0, 1.0)
	elif _net_has:
		# updates come 10 times a second: run on a little where it was heading, and ease in
		var age := minf((Time.get_ticks_msec() - _net_at) / 1000.0, 0.2)
		var target := _net_pos + _net_vel * age
		if global_position.distance_to(target) > 6.0:
			global_position = target
		global_position = global_position.lerp(target, minf(1.0, 12.0 * delta))
		rotation = Vector3(0, lerp_angle(rotation.y, _net_yaw, minf(1.0, 10.0 * delta)), 0)
		_speed = lerpf(_speed, Vector2(_net_vel.x, _net_vel.z).length(), minf(1.0, 6.0 * delta))
	if visible:
		_animate(delta, anim, _speed)

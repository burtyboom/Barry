class_name Pet
extends Node3D
## A player's pet: a cat, or a dog (cavoodle, greyhound or border collie).
## Rides in the ute's tray while you drive, hops down when you get out and follows you
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
const FAR := 200.0

enum Anim { IDLE, WALK, RUN, SIT, ROLL, HOP, TRAY }

var kind := "collie"
var col_i := 0
var is_dog := true
var player: PlayerCharacter        ## who it belongs to
var preview := false               ## menu preview: just sits there looking cute

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

# rig
var _root: Node3D                  ## everything; rolls for barrel rolls
var _body: Node3D
var _legs: Array[Node3D] = []
var _head: Node3D
var _tail: Node3D
var _tongue: Node3D
var _hip_h := 0.3                  ## leg length (body sits this high)
var _len := 0.5                    ## body length


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
	_root = Node3D.new()
	add_child(_root)
	_body = Node3D.new()
	_root.add_child(_body)
	# per-breed proportions: body radius, body length, leg length, leg radius, head radius
	var br := 0.11
	var bl := 0.42
	var ll := 0.20
	var lr := 0.035
	var hr := 0.10
	match kind:
		"cavoodle":
			br = 0.14; bl = 0.36; ll = 0.17; lr = 0.05; hr = 0.13
		"greyhound":
			br = 0.12; bl = 0.62; ll = 0.46; lr = 0.03; hr = 0.09
		"collie":
			br = 0.15; bl = 0.55; ll = 0.30; lr = 0.045; hr = 0.12
	_hip_h = ll
	_len = bl
	_body.position = Vector3(0, ll + br * 0.6, 0)
	# body
	if kind == "cavoodle":
		for k in 3:   # fluffy: a row of fuzzy balls
			_sphere(_body, Vector3.ONE * br * 2.3, Vector3(0, 0.02 * sin(k), -bl * 0.5 + k * bl * 0.5), main_c)
	else:
		_capsule(_body, br, bl + br * 2.0, Vector3.ZERO, main_c, Vector3(90, 0, 0))
	if kind == "greyhound":
		_sphere(_body, Vector3(br * 2.2, br * 2.6, br * 2.4), Vector3(0, -0.03, -bl * 0.3), main_c)   # deep chest
	if kind == "collie":
		_sphere(_body, Vector3(br * 1.9, br * 1.9, br * 1.4), Vector3(0, -0.02, -bl * 0.5 - 0.02), acc)   # white chest ruff
	if kind == "cat" and col_i == 3:
		_sphere(_body, Vector3(br * 1.6, br * 1.2, br * 2.2), Vector3(0.04, br * 0.5, 0.05), acc)   # a big ginger patch
	if kind == "greyhound" and col_i == 3:
		for k in 4:   # brindle stripes
			var stripe := Toon.box(_body, Vector3(br * 2.05, 0.03, 0.05), Vector3(0, 0.0, -bl * 0.3 + k * bl * 0.22), acc)
			stripe.rotation_degrees.z = 90.0
	if kind == "collie" and col_i == 2:
		for k in 3:   # merle splodges
			_sphere(_body, Vector3.ONE * br * 0.9, Vector3((k - 1) * 0.08, br * 0.7, -bl * 0.25 + k * bl * 0.25), Color(0.15, 0.16, 0.2))
	# legs
	for z in [-bl * 0.5, bl * 0.5]:
		for x in [-br * 0.6, br * 0.6]:
			var leg := Node3D.new()
			leg.position = Vector3(x, _body.position.y - br * 0.3, z)
			_root.add_child(leg)
			var leg_c := main_c
			if kind == "collie" or (kind == "cat" and col_i == 3):
				leg_c = acc   # white socks / legs
			if kind == "cavoodle":
				_sphere(leg, Vector3(lr * 2.6, ll * 1.25, lr * 2.6), Vector3(0, -ll * 0.5, 0), main_c)
			else:
				_capsule(leg, lr, ll + 0.04, Vector3(0, -ll * 0.5, 0), main_c, Vector3.ZERO)
				_sphere(leg, Vector3(lr * 2.4, lr * 1.6, lr * 3.0), Vector3(0, -ll + lr * 0.5, -lr * 0.6), leg_c)   # paw
			_legs.append(leg)
	# head
	_head = Node3D.new()
	_head.position = Vector3(0, br * 0.9, -bl * 0.5 - br * 0.6)
	_body.add_child(_head)
	match kind:
		"cavoodle":
			_sphere(_head, Vector3.ONE * hr * 2.2, Vector3.ZERO, main_c)
			_sphere(_head, Vector3(hr, hr * 0.9, hr * 1.2), Vector3(0, -hr * 0.3, -hr * 0.9), acc)   # snout
			for x in [-1.0, 1.0]:
				_sphere(_head, Vector3(hr * 0.8, hr * 1.6, hr * 0.7), Vector3(x * hr * 0.95, -hr * 0.35, 0), main_c.darkened(0.08))   # floppy ears
		"greyhound":
			_capsule(_head, hr, hr * 4.2, Vector3(0, 0, -hr * 0.9), main_c, Vector3(90, 0, 0))   # long narrow head
			for x in [-1.0, 1.0]:
				var ear := Toon.box(_head, Vector3(0.03, 0.07, 0.09), Vector3(x * hr * 0.6, hr * 0.8, hr * 0.5), main_c.darkened(0.15))
				ear.rotation_degrees = Vector3(-30, 0, x * 40.0)
		"collie":
			_sphere(_head, Vector3(hr * 2.1, hr * 2.0, hr * 2.1), Vector3.ZERO, main_c)
			_sphere(_head, Vector3(hr * 0.9, hr * 0.8, hr * 1.5), Vector3(0, -hr * 0.3, -hr * 1.0), acc)   # white muzzle
			Toon.box(_head, Vector3(hr * 0.35, hr * 1.4, 0.02), Vector3(0, hr * 0.3, -hr * 1.0), acc)   # white blaze
			for x in [-1.0, 1.0]:
				var ear := _cone(_head, hr * 0.45, hr * 1.1, Vector3(x * hr * 0.6, hr * 1.05, 0), main_c)
				ear.rotation_degrees = Vector3(-15, 0, -x * 15.0)
				var tip := _sphere(_head, Vector3.ONE * hr * 0.3, Vector3(x * hr * 0.75, hr * 1.4, -0.03), main_c)
				tip.scale = Vector3(hr * 0.5, hr * 0.3, hr * 0.4)   # tipped-over ear ends
		_:   # cat
			_sphere(_head, Vector3(hr * 2.3, hr * 2.0, hr * 2.0), Vector3.ZERO, main_c)
			_sphere(_head, Vector3(hr * 1.0, hr * 0.7, hr * 0.7), Vector3(0, -hr * 0.35, -hr * 0.8), acc)
			for x in [-1.0, 1.0]:
				_cone(_head, hr * 0.5, hr * 0.9, Vector3(x * hr * 0.65, hr * 1.0, 0), main_c)
			for x in [-1.0, 1.0]:   # whiskers
				for k in 2:
					var w := Toon.box(_head, Vector3(0.12, 0.004, 0.004), Vector3(x * hr * 0.9, -hr * 0.3 + k * 0.02, -hr * 0.85), Color(0.95, 0.95, 0.95))
					w.rotation_degrees.z = x * (8.0 - k * 16.0)
	# eyes + nose
	var face_z := -hr * (2.0 if kind == "greyhound" else 0.95)
	for x in [-1.0, 1.0]:
		_sphere(_head, Vector3.ONE * hr * 0.42, Vector3(x * hr * 0.42, hr * 0.2, face_z + hr * (1.1 if kind == "greyhound" else 0.05)),
			Color(0.95, 0.85, 0.3) if kind == "cat" else Color(0.06, 0.05, 0.05))
	_sphere(_head, Vector3.ONE * hr * 0.35, Vector3(0, -hr * 0.15, face_z - hr * (1.2 if kind == "greyhound" else 0.55)), Color(0.08, 0.06, 0.06))
	if is_dog:
		_tongue = Node3D.new()
		_tongue.position = Vector3(0, -hr * 0.6, face_z - hr * 0.3)
		_head.add_child(_tongue)
		Toon.box(_tongue, Vector3(hr * 0.45, 0.02, hr * 0.8), Vector3(0, -0.02, -hr * 0.3), Color(0.95, 0.4, 0.5))
		_tongue.visible = false
	# tail
	_tail = Node3D.new()
	_tail.position = Vector3(0, br * 0.4, bl * 0.5 + br * 0.5)
	_body.add_child(_tail)
	match kind:
		"cavoodle":
			_sphere(_tail, Vector3.ONE * 0.13, Vector3(0, 0.06, 0.03), main_c)
		"greyhound":
			_capsule(_tail, 0.018, 0.45, Vector3(0, -0.12, 0.12), main_c, Vector3(-30, 0, 0))
		"collie":
			_capsule(_tail, 0.05, 0.38, Vector3(0, -0.06, 0.15), main_c, Vector3(-55, 0, 0))
			_sphere(_tail, Vector3.ONE * 0.09, Vector3(0, -0.15, 0.3), acc)   # white tail tip
		_:
			_capsule(_tail, 0.03, 0.42, Vector3(0, 0.16, 0.06), main_c, Vector3(-15, 0, 0))   # cat tail, up
	for n in find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON


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


# ------------------------------------------------------------- per frame
func _ready() -> void:
	_yaw = rotation.y
	_net_pos = global_position


func _owner_local() -> bool:
	return not preview and is_multiplayer_authority()


func _physics_process(delta: float) -> void:
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
	# --- the ute: in the tray while you drive, hop in / out as you get in / out
	if in_car and state != "tray" and state != "hop":
		var tray := car.global_transform * TRAY_XF
		if me.distance_to(tray.origin) > 25.0:
			state = "tray"   # too far to run: just turns up in the back
		else:
			_hop(me, tray.origin, 0.55, "tray")
			_say("woof" if is_dog else "meow")
	if state == "tray":
		if not in_car:
			var out := car.global_transform * Vector3(-1.6, 0, 2.6) if car else player.global_position
			out.y = _ground(out)
			global_transform = car.global_transform * TRAY_XF if car else global_transform
			_hop(global_position, out, 0.5, "follow")
			return
		global_transform = car.global_transform * TRAY_XF
		_yaw = global_rotation.y
		_speed = 0.0
		anim = Anim.TRAY
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
				anim = Anim.IDLE if _t < 4.0 else Anim.SIT
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


## Out on the sand (not sitting in someone's tray).
func visible_on_foot() -> bool:
	return anim != Anim.TRAY and anim != Anim.HOP


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
func _animate(delta: float, a: int, spd: float) -> void:
	var walking := a == Anim.WALK or a == Anim.RUN
	var rate := 7.0 + spd * (1.6 if kind != "greyhound" else 1.1)
	if walking:
		_phase += delta * rate
	var amp := 0.0
	if a == Anim.WALK:
		amp = 0.45
	elif a == Anim.RUN:
		amp = 0.85
	for i in _legs.size():
		var leg := _legs[i]
		var front := i < 2
		var gait := 0.0 if a != Anim.RUN else (0.0 if front else PI)   # gallop: front pair together
		var side := 0.0 if a == Anim.RUN else (0.0 if (i % 2 == 0) == front else PI)   # walk: diagonal pairs
		leg.rotation.x = sin(_phase + gait + side) * amp
		if a == Anim.SIT:
			leg.rotation.x = 1.1 if not front else 0.0   # back legs folded under
		elif a == Anim.TRAY:
			leg.rotation.x = 0.25 if not front else -0.2   # standing, leaning on the side
		if a == Anim.HOP:
			leg.rotation.x = 0.9 if front else -0.9
	# body: sit = rear down, run = bounce
	# body pitch: + = nose up (sitting: rear down; in the tray: up on the side looking out)
	var sit := a == Anim.SIT
	var pitch := 0.5 if sit else (0.3 if a == Anim.TRAY else 0.0)
	_body.rotation.x = lerpf(_body.rotation.x, pitch, minf(1.0, 8.0 * delta))
	var base_y := _hip_h * (0.6 if sit else 1.0)
	_body.position.y = lerpf(_body.position.y, base_y + 0.06 + (absf(sin(_phase)) * 0.05 if a == Anim.RUN else 0.0), minf(1.0, 10.0 * delta))
	# head looks about a bit when idle
	_head.rotation.y = sin(Time.get_ticks_msec() * 0.0011 + col_i) * 0.5 if not walking else 0.0
	# tail: dogs wag (more when excited), cats swish slowly
	var wag_speed := 14.0 if is_dog else 2.0
	var wag_amp := 0.35 if is_dog else 0.4
	if a == Anim.RUN or a == Anim.TRAY:
		wag_amp *= 1.6
	_tail.rotation.y = sin(Time.get_ticks_msec() * 0.001 * wag_speed) * wag_amp
	if _tongue:
		_tongue.visible = a == Anim.RUN or a == Anim.TRAY or a == Anim.ROLL
	# barrel roll: the whole pet spins round its nose-to-tail axis
	_root.position.y = 0.0
	if a == Anim.ROLL:
		_root.rotation.z = _roll_a
		_root.position.y = absf(sin(_roll_a * 0.5)) * 0.25
	else:
		_root.rotation.z = lerp_angle(_root.rotation.z, 0.0, minf(1.0, 10.0 * delta))


# ------------------------------------------------------------- network
func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


@rpc("authority", "call_remote", "unreliable_ordered")
func _st(pos: Vector3, yaw: float, a: int, roll: float) -> void:
	if not _net_has:
		global_position = pos
	_net_pos = pos
	_net_yaw = yaw
	anim = a as Anim
	_roll_a = roll
	_net_has = true


## Someone else's pet: glide to where its owner says it is (in the tray it rides the ute itself).
func _remote(delta: float) -> void:
	var car := player.car if player.car and is_instance_valid(player.car) else null
	if anim == Anim.TRAY and car:
		global_transform = car.global_transform * TRAY_XF
	elif _net_has:
		var prev := global_position
		global_position = global_position.lerp(_net_pos, minf(1.0, 10.0 * delta))
		rotation = Vector3(0, lerp_angle(rotation.y, _net_yaw, minf(1.0, 10.0 * delta)), 0)
		_speed = (global_position - prev).length() / maxf(delta, 0.001)
	if visible:
		_animate(delta, anim, _speed)

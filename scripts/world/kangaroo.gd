class_name Kangaroo
extends Node3D
## A cartoon eastern grey. Grazes hunched over on its forearms, now and then shuffles a
## few metres, sits up tall with its ears swivelling when something comes near, and
## bounds off - big two-footed hops with the tail swinging for balance - when a ute or
## a person gets too close. No collision, so nobody gets stuck on one.
## Shared in multiplayer: the host / online server runs the brains (logic = true) and
## Wildlife sends everyone where each roo is; other machines just follow along
## (logic = false) and animate. The online server has no meshes at all (show = false).

const FAR := 240.0           ## past this from the camera: hidden, no thinking
const SCARE_PERSON := 13.0
const SCARE_CAR := 30.0
const HOP_LEN := 0.58        ## seconds per bound
const STATES := ["graze", "shuffle", "alert", "flee"]

var island: IslandData
var mob_center := Vector3.ZERO   ## where the mob hangs out (Wildlife moves it)
var logic := true            ## this machine decides what it does (host / server / solo)
var show := true             ## build the model and animate (false on the online server)
var wild: Node               ## the Wildlife manager (threat list)
var _main: Node
var _net_pos := Vector3.INF  ## follower: where the host says it is
var _net_yaw := 0.0
var _net_speed := 0.0
var _net_at := 0
var _state := "graze"        ## graze / shuffle / alert / flee
var _t := 0.0
var _wait := 3.0
var _yaw := 0.0
var _target := Vector3.ZERO
var _flee_dir := Vector3.ZERO
var _hop := 0.0              ## 0..1 through the current bound
var _hopping := false
var _speed := 0.0
var _look_at := Vector3.INF
var _ear_t := 1.0
var _pose := 0.0             ## 0 = grazing hunch, 1 = sitting up tall
var _root: Node3D            ## everything; lifted during hops
var _torso: Node3D
var _head: Node3D
var _ears: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _legs: Array[Node3D] = []    ## hip pivots
var _knees: Array[Node3D] = []
var _tail: Node3D
var _tail_tip: Node3D
var _size := 1.0


func _ready() -> void:
	if island == null:
		island = IslandData.instance
	_main = get_tree().root.get_node_or_null("Main")
	add_to_group("roos")
	if logic:
		_size = randf_range(0.85, 1.12)
	if show:
		_build()
		Birds.bake_tree(self, true)
	_yaw = randf() * TAU
	global_basis = Basis(Vector3.UP, _yaw) * Basis.from_scale(Vector3.ONE * _size)
	_wait = randf_range(2.0, 7.0)
	_t = randf() * 3.0


# ------------------------------------------------------------- model
func _build() -> void:
	var fur := Color(0.60, 0.50, 0.42)
	var pale := Color(0.90, 0.84, 0.74)
	var dark := Color(0.22, 0.17, 0.15)
	_root = Node3D.new()
	add_child(_root)
	var hip := Node3D.new()
	hip.position = Vector3(0, 0.46, 0)
	_root.add_child(hip)
	# big rump
	_ball(hip, 0.24, 0.42, Vector3(0, 0.02, 0.03), fur, Vector3(70, 0, 0))
	# torso leans from the hips
	_torso = Node3D.new()
	hip.add_child(_torso)
	_limb(_torso, Vector3(0, 0.0, 0.0), Vector3(0, 0.50, -0.08), 0.19, fur)
	_limb(_torso, Vector3(0, 0.08, -0.08), Vector3(0, 0.42, -0.14), 0.13, pale)    # pale chest
	for x in [-0.1, 0.1]:
		var arm := Node3D.new()
		arm.position = Vector3(x, 0.40, -0.14)
		_torso.add_child(arm)
		_limb(arm, Vector3.ZERO, Vector3(0, -0.22, -0.08), 0.035, fur)
		_ball(arm, 0.04, 0.09, Vector3(0, -0.24, -0.09), dark, Vector3(90, 0, 0))   # paws
		_arms.append(arm)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.60, -0.10)
	_torso.add_child(_head)
	_ball(_head, 0.11, 0.30, Vector3(0, 0.0, -0.04), fur, Vector3(90, 0, 0))       # skull
	_ball(_head, 0.07, 0.20, Vector3(0, -0.035, -0.17), fur, Vector3(100, 0, 0))   # long muzzle
	Toon.box(_head, Vector3(0.07, 0.05, 0.04), Vector3(0, -0.03, -0.27), dark)       # nose
	for x in [-0.06, 0.06]:
		Toon.box(_head, Vector3(0.03, 0.035, 0.02), Vector3(x, 0.035, -0.12), dark)  # eyes
		var ear := Node3D.new()
		ear.position = Vector3(x * 0.9, 0.08, 0.03)
		ear.rotation_degrees = Vector3(-8, 0, x * 370.0)
		_head.add_child(ear)
		Toon.box(ear, Vector3(0.095, 0.24, 0.03), Vector3(0, 0.12, 0), fur)
		Toon.box(ear, Vector3(0.055, 0.17, 0.012), Vector3(0, 0.12, -0.016), pale)
		_ears.append(ear)
	# hind legs: thigh forward-down to the knee, shin back-down to the heel, long foot flat
	for x in [-0.13, 0.13]:
		var leg := Node3D.new()
		leg.position = Vector3(x, 0.0, -0.02)
		hip.add_child(leg)
		var knee_at := Vector3(0, -0.20, -0.17)
		_limb(leg, Vector3.ZERO, knee_at, 0.10, fur)
		var knee := Node3D.new()
		knee.position = knee_at
		leg.add_child(knee)
		var heel_at := Vector3(0, -0.20, 0.27)
		_limb(knee, Vector3.ZERO, heel_at, 0.055, fur)
		# the long foot (part of the shin piece - it never bends on its own)
		_limb(knee, heel_at + Vector3(0, -0.02, 0.02), heel_at + Vector3(0, -0.03, -0.34), 0.045, fur)
		Toon.box(knee, Vector3(0.07, 0.03, 0.08), heel_at + Vector3(0, -0.035, -0.36), dark)   # toes
		_legs.append(leg)
		_knees.append(knee)
	# thick tail, resting on the ground behind
	_tail = Node3D.new()
	_tail.position = Vector3(0, -0.02, 0.18)
	hip.add_child(_tail)
	_limb(_tail, Vector3.ZERO, Vector3(0, -0.20, 0.38), 0.085, fur)
	_tail_tip = Node3D.new()
	_tail_tip.position = Vector3(0, -0.20, 0.38)
	_tail.add_child(_tail_tip)
	_limb(_tail_tip, Vector3.ZERO, Vector3(0, -0.20, 0.36), 0.05, fur)
	_ball(_tail_tip, 0.045, 0.1, Vector3(0, -0.2, 0.37), dark, Vector3(60, 0, 0))


func _ball(parent: Node3D, r: float, h: float, pos: Vector3, c: Color, rot: Vector3) -> void:
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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if r < 0.06 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)


## A capsule spanning a -> b (in the parent's frame).
func _limb(parent: Node3D, a: Vector3, b: Vector3, r: float, c: Color) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	var len := a.distance_to(b)
	cm.radius = r
	cm.height = len + r * 2.0
	cm.radial_segments = 10
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = Toon.mat(c)
	var up := (b - a).normalized()
	var side := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := side.cross(up).normalized()
	var x := up.cross(z).normalized()
	mi.transform = Transform3D(Basis(x, up, z), (a + b) * 0.5)
	parent.add_child(mi)


# ------------------------------------------------------------- brains
func _dry(p: Vector3) -> bool:
	return island.water_level_at(p.x, p.z) < island.height_at(p.x, p.z) - 0.1


## Something scary nearby: which way to run, or ZERO. Also notes what to stare at.
func _threat() -> Vector3:
	_look_at = Vector3.INF
	var me := global_position
	var worst := Vector3.ZERO
	if wild:
		# everyone's utes and people, with speeds worked out by Wildlife (remote utes on
		# the server don't have a physics velocity of their own)
		for t in wild.threats:
			var rel: Vector3 = me - (t["pos"] as Vector3)
			rel.y = 0.0
			var d := rel.length()
			if t["car"]:
				if d > SCARE_CAR + 20.0:
					continue
				if d < 50.0:
					_look_at = t["pos"]
				if (d < SCARE_CAR and t["speed"] > 2.0) or d < 8.0 or (t["horn"] and d < 40.0):
					worst = rel.normalized() if d > 0.1 else Vector3.FORWARD
			else:
				if d < 26.0 and _look_at == Vector3.INF:
					_look_at = t["pos"]
				if d < SCARE_PERSON and worst == Vector3.ZERO:
					worst = rel.normalized() if d > 0.1 else Vector3.FORWARD
		return worst
	if _main == null:
		return Vector3.ZERO
	if _main.get("cars"):
		for c in _main.cars.get_children():
			var car := c as SandVehicle
			if car == null:
				continue
			var rel := me - car.global_position
			rel.y = 0.0
			var d := rel.length()
			if d > SCARE_CAR + 20.0:
				continue
			var sp := car.linear_velocity.length()
			if d < 50.0:
				_look_at = car.global_position
			if (d < SCARE_CAR and sp > 2.0) or d < 8.0 or (car.horn_on and d < 40.0):
				worst = rel.normalized() if d > 0.1 else Vector3.FORWARD
	if worst == Vector3.ZERO and _main.get("players"):
		for p in _main.players.get_children():
			var pc := p as PlayerCharacter
			if pc == null or not pc.is_on_foot():
				continue
			var rel := me - pc.global_position
			rel.y = 0.0
			var d := rel.length()
			if d < 26.0:
				_look_at = pc.global_position
			if d < SCARE_PERSON:
				worst = rel.normalized() if d > 0.1 else Vector3.FORWARD
	return worst


func scare(from: Vector3) -> void:
	var away := global_position - from
	away.y = 0.0
	_flee_dir = away.normalized() if away.length() > 0.1 else -global_basis.z
	if _state != "flee":
		_set_state("flee")


func _process(delta: float) -> void:
	if island == null:
		return
	var far := true
	if show:
		var cam := get_viewport().get_camera_3d()
		far = cam != null and cam.global_position.distance_to(global_position) > FAR
		visible = not far
	if not logic:
		_follow(delta, far)
		return
	if far and wild == null:
		return   # ambient only (no manager): nothing to do out of sight
	_think(delta, far)


## Follower: glide to where the host says it is, hopping when it's moving.
func _follow(delta: float, far: bool) -> void:
	if _net_pos == Vector3.INF:
		return
	_t += delta
	var age := minf((Time.get_ticks_msec() - _net_at) / 1000.0, 0.6)
	var want := _net_pos
	if _net_speed > 0.3:
		want += Vector3(-sin(_net_yaw), 0, -cos(_net_yaw)) * _net_speed * age
	var pos := global_position
	if Vector2(want.x - pos.x, want.z - pos.z).length() > 12.0:
		pos = want   # way off (just placed / relocated): jump there
	else:
		pos = pos.lerp(want, minf(1.0, delta * 6.0))
	pos.y = island.height_at(pos.x, pos.z)
	global_position = pos
	_yaw = lerp_angle(_yaw, _net_yaw, minf(1.0, delta * 8.0))
	global_basis = Basis(Vector3.UP, _yaw) * Basis.from_scale(Vector3.ONE * _size)
	_speed = move_toward(_speed, _net_speed, delta * 12.0)
	if _speed > 0.3 or _hopping:
		if not _hopping:
			_hopping = true
			_hop = 0.0
		_hop += delta / (HOP_LEN * (1.25 if _speed < 4.0 else 1.0))
		if _hop >= 1.0:
			if _speed > 0.3:
				_hop -= 1.0
			else:
				_hop = 0.0
				_hopping = false
	if not far:
		_animate(delta)


## Follower: the host's latest word on this roo.
func net_update(pos: Vector3, yaw: float, state: int, speed: float, size: float) -> void:
	var first := _net_pos == Vector3.INF
	_net_pos = pos
	_net_yaw = yaw
	_net_speed = speed
	_net_at = Time.get_ticks_msec()
	var st: String = STATES[clampi(state, 0, STATES.size() - 1)]
	if st != _state:
		_set_state(st)
	if absf(size - _size) > 0.001:
		_size = size
	if first:
		_yaw = yaw
		global_position = Vector3(pos.x, island.height_at(pos.x, pos.z), pos.z)
		global_basis = Basis(Vector3.UP, _yaw) * Basis.from_scale(Vector3.ONE * _size)


func state_code() -> int:
	return maxi(STATES.find(_state), 0)


func _think(delta: float, far: bool) -> void:
	_t += delta
	var pos := global_position
	var threat := _threat()
	if threat != Vector3.ZERO:
		if _state != "flee":
			# the mob goes together
			for k in get_tree().get_nodes_in_group("roos"):
				var other := k as Kangaroo
				if other != self and other.global_position.distance_to(pos) < 25.0:
					other.scare(pos - threat * 5.0)
		_flee_dir = _flee_dir.lerp(threat, minf(1.0, delta * 2.0)).normalized() if _state == "flee" else threat
		if _state != "flee":
			_set_state("flee")
	var want_speed := 0.0
	match _state:
		"graze":
			if _look_at != Vector3.INF:
				_set_state("alert")
			elif _t > _wait:
				_pick_target()
				_set_state("shuffle")
		"shuffle":
			var to := Vector3(_target.x - pos.x, 0, _target.z - pos.z)
			if to.length() < 0.6 or _t > 8.0:
				_set_state("graze")
				_wait = randf_range(3.0, 9.0)
			else:
				want_speed = 2.6
				_face(to, delta * 0.8)
		"alert":
			if _look_at == Vector3.INF and _t > 3.0:
				_set_state("graze")
				_wait = randf_range(2.0, 5.0)
			elif _look_at != Vector3.INF:
				_face(_look_at - pos, delta * 0.6)
		"flee":
			want_speed = 9.5
			var ahead := pos + _flee_dir * 6.0
			if not _dry(ahead):
				_flee_dir = _flee_dir.rotated(Vector3.UP, PI * 0.5 * (1.0 if randf() < 0.5 else -1.0))
			_face(_flee_dir, delta * 2.5)
			if _t > 5.0 and threat == Vector3.ZERO:
				_set_state("alert")
				mob_center = pos
	# move only in bounds: hops carry it forward, nothing slides
	_speed = move_toward(_speed, want_speed, delta * 12.0)
	if _speed > 0.3 or _hopping:
		if not _hopping:
			_hopping = true
			_hop = 0.0
		_hop += delta / (HOP_LEN * (1.25 if _speed < 4.0 else 1.0))
		if _hop >= 1.0:
			if _speed > 0.3:
				_hop -= 1.0
			else:
				_hop = 0.0
				_hopping = false
		if _hopping and _dry(pos - global_basis.z * 1.0):
			pos += -global_basis.z * maxf(_speed, 1.5) * delta
	pos.y = island.height_at(pos.x, pos.z)
	global_position = pos
	if show and not far:
		_animate(delta)


func _set_state(s: String) -> void:
	_state = s
	_t = 0.0


func _pick_target() -> void:
	for tries in 6:
		var a := randf() * TAU
		var d := randf_range(3.0, 12.0)
		var p := mob_center + Vector3(cos(a) * d, 0, sin(a) * d)
		if _dry(p):
			_target = p
			return
	_target = global_position


func _face(dir: Vector3, rate: float) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var want := atan2(-dir.x, -dir.z)
	_yaw = lerp_angle(_yaw, want, minf(1.0, 6.0 * rate))
	global_basis = Basis(Vector3.UP, _yaw) * Basis.from_scale(Vector3.ONE * _size)


# ------------------------------------------------------------- animation
func _animate(delta: float) -> void:
	var k := minf(1.0, delta * 8.0)
	# sitting up tall when alert, hunched over grazing, leaning right forward in a bound
	var tall := 1.0 if _state == "alert" else 0.0
	_pose = lerpf(_pose, tall, minf(1.0, delta * 4.0))
	var lift := 0.0
	var leg_swing := 0.0
	var knee_bend := 0.0
	var tail_pitch := 0.0
	var lean := lerpf(-1.15, -0.18, _pose)       # torso pitch (negative = forward)
	var head_pitch := lerpf(-0.2, 0.15, _pose)    # grazing: nose down in the grass
	var arm_pitch := lerpf(0.35, -0.2, _pose)
	if _hopping:
		var s := _hop
		var big := clampf(_speed / 9.5, 0.35, 1.0)
		# up and over: a parabola, feet off the ground most of the bound
		lift = 4.0 * s * (1.0 - s) * lerpf(0.25, 0.75, big)
		# legs: crouched on landing/take-off, stretched out behind in the air
		var air := sin(s * PI)
		leg_swing = -air * 0.9 * big
		knee_bend = air * 0.8 * big
		lean = lerpf(-0.75, -1.0, air * big)
		head_pitch = -lean - 0.25    # keep the head looking ahead
		arm_pitch = 0.6
		# tail counter-swings: low on the push, up in the air
		tail_pitch = lerpf(0.25, -0.35, air) * big
	else:
		# small breathing / chewing
		head_pitch += sin(_t * 3.0) * 0.04 * (1.0 - _pose)
		if _state == "alert":
			head_pitch = -lean + 0.05
	_root.position.y = lerpf(_root.position.y, lift, minf(1.0, delta * 25.0))
	_torso.rotation.x = lerp_angle(_torso.rotation.x, lean, k)
	_head.rotation.x = lerp_angle(_head.rotation.x, head_pitch, k)
	for a in _arms:
		a.rotation.x = lerp_angle(a.rotation.x, arm_pitch, k)
	for i in _legs.size():
		_legs[i].rotation.x = lerp_angle(_legs[i].rotation.x, leg_swing, minf(1.0, delta * 18.0))
		_knees[i].rotation.x = lerp_angle(_knees[i].rotation.x, knee_bend, minf(1.0, delta * 18.0))
	_tail.rotation.x = lerp_angle(_tail.rotation.x, tail_pitch, minf(1.0, delta * 14.0))
	_tail_tip.rotation.x = lerp_angle(_tail_tip.rotation.x, tail_pitch * 0.6, minf(1.0, delta * 10.0))
	# ears swivel now and then (always when alert)
	_ear_t -= delta
	if _ear_t <= 0.0:
		_ear_t = randf_range(0.4, 1.2) if _state == "alert" else randf_range(1.5, 5.0)
		for i in _ears.size():
			if randf() < 0.7:
				_ears[i].set_meta("yaw", randf_range(-0.7, 0.7))
	for i in _ears.size():
		var want: float = _ears[i].get_meta("yaw", 0.0)
		_ears[i].rotation.y = lerp_angle(_ears[i].rotation.y, want, minf(1.0, delta * 10.0))

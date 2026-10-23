class_name Dingo
extends Node3D
## A cartoon dingo (Fraser / K'gari only) that wanders around a home spot: trots to random
## points, sits and scratches, howls (and the pack joins in), and comes over (stopping at a
## polite distance) to look at people who get close. Scatters out of the way of utes and horns.
## Every now and then one sneaks up, pinches your thong and makes you chase it down.
## Ambient only - each machine runs its own.

const RANGE := 34.0
const FAR := 220.0            ## past this from the camera we stop thinking (and hide)
const THEFT_GAP_MS := 100000  ## at most one thong theft every so often, across all dingoes

static var _next_theft_ms := 30000

var home := Vector3.ZERO
var island: IslandData
var steal_chance := 0.35      ## per close look at you
var _main: Node
var _target := Vector3.ZERO
var _state := "idle"          ## idle / walk / sit / curious / flee / howl / steal / carry / tease
var _t := 0.0
var _wait := 2.0
var _phase := 0.0
var _yaw := 0.0
var _body: Node3D
var _legs: Array[Node3D] = []
var _head: Node3D
var _tail: Node3D
var _flee_dir := Vector3.ZERO
var _howl_t := 0.0
var _curious_t := 0.0
var _rolled := false          ## already decided whether to pinch something this visit
var _victim: PlayerCharacter
var _bursts := 0
var _escaped := false         ## got clear after the grab (only then can you catch it)
var _thong: Node3D            ## in our mouth
var _dropped: Node3D          ## lying on the sand, waiting to be picked up


func _ready() -> void:
	island = IslandData.instance
	_main = get_tree().root.get_node_or_null("Main")
	add_to_group("dingoes")
	_build()
	global_position = home
	_howl_t = randf_range(25.0, 140.0)
	_pick_target()


func _exit_tree() -> void:
	if _dropped and is_instance_valid(_dropped):
		_dropped.queue_free()


func _build() -> void:
	var fur := Color(0.86, 0.62, 0.32)
	var light := Color(0.98, 0.90, 0.75)
	_body = Node3D.new()
	add_child(_body)
	_capsule(_body, 0.17, 0.85, Vector3(0, 0.55, 0), fur, Vector3(90, 0, 0))
	_capsule(_body, 0.12, 0.55, Vector3(0, 0.48, -0.05), light, Vector3(90, 0, 0))   # pale belly
	for x in [-0.1, 0.1]:
		for z in [-0.28, 0.28]:
			var leg := Node3D.new()
			leg.position = Vector3(x, 0.5, z)
			_body.add_child(leg)
			_capsule(leg, 0.05, 0.45, Vector3(0, -0.22, 0), fur, Vector3.ZERO)
			_capsule(leg, 0.055, 0.12, Vector3(0, -0.44, -0.02), light, Vector3(90, 0, 0))   # white socks
			_legs.append(leg)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.75, -0.45)
	_body.add_child(_head)
	_capsule(_head, 0.13, 0.32, Vector3(0, 0, 0), fur, Vector3(90, 0, 0))
	_capsule(_head, 0.07, 0.22, Vector3(0, -0.04, -0.2), light, Vector3(90, 0, 0))    # snout
	Toon.box(_head, Vector3(0.05, 0.04, 0.04), Vector3(0, -0.02, -0.32), Color(0.1, 0.08, 0.08))   # nose
	for x in [-0.08, 0.08]:
		Toon.box(_head, Vector3(0.07, 0.12, 0.03), Vector3(x, 0.15, 0.02), fur, true, Vector3(0, 0, x * 120.0))   # ears
		Toon.box(_head, Vector3(0.03, 0.03, 0.02), Vector3(x * 0.8, 0.05, -0.11), Color(0.1, 0.08, 0.08))      # eyes
	_tail = Node3D.new()
	_tail.position = Vector3(0, 0.62, 0.42)
	_body.add_child(_tail)
	_capsule(_tail, 0.05, 0.4, Vector3(0, 0.1, 0.12), fur, Vector3(-55, 0, 0))
	_thong = _make_thong()
	_thong.position = Vector3(0.06, -0.1, -0.33)
	_thong.rotation_degrees = Vector3(0, 75, 70)
	_thong.scale = Vector3.ONE * 1.6
	_thong.visible = false
	_head.add_child(_thong)


## A blue thong (flip-flop): sole plus the white Y strap.
static func _make_thong() -> Node3D:
	var n := Node3D.new()
	Toon.box(n, Vector3(0.11, 0.025, 0.27), Vector3.ZERO, Color(0.15, 0.45, 0.95))
	Toon.box(n, Vector3(0.012, 0.035, 0.11), Vector3(0.03, 0.03, 0.0), Color(0.97, 0.97, 0.97), true, Vector3(0, 25, 0))
	Toon.box(n, Vector3(0.012, 0.035, 0.11), Vector3(-0.03, 0.03, 0.0), Color(0.97, 0.97, 0.97), true, Vector3(0, -25, 0))
	return n


func _capsule(parent: Node3D, r: float, h: float, pos: Vector3, c: Color, rot: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	cm.radial_segments = 10
	cm.rings = 4
	mi.mesh = cm
	mi.material_override = Toon.mat(c)
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)


func _dry(p: Vector3) -> bool:
	return island.water_level_at(p.x, p.z) < island.height_at(p.x, p.z) - 0.05


func _pick_target() -> void:
	for tries in 8:
		var a := randf() * TAU
		var d := randf_range(6.0, RANGE)
		var p := home + Vector3(cos(a) * d, 0, sin(a) * d)
		if _dry(p):
			_target = p
			return
	_target = home


func _nearest_person() -> PlayerCharacter:
	if _main == null or _main.players == null:
		return null
	var best: PlayerCharacter = null
	var bd := 9.0
	for p in _main.players.get_children():
		var pc := p as PlayerCharacter
		if pc == null or not pc.is_on_foot() or pc._bonk != 0:
			continue
		var d := pc.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = pc
	return best


## A ute about to run us over (or honking nearby): which way to bolt, or ZERO.
func _car_threat() -> Vector3:
	if _main == null or _main.cars == null:
		return Vector3.ZERO
	var me := global_position
	for c in _main.cars.get_children():
		var car := c as SandVehicle
		if car == null:
			continue
		var rel := me - car.global_position
		rel.y = 0.0
		if rel.length() > 22.0:
			continue
		if car.horn_on and rel.length() < 16.0:
			return rel.normalized()
		var v := car.linear_velocity
		v.y = 0.0
		if v.length() < 3.0:
			continue
		# closest we'll get over the next couple of seconds
		var tc := clampf(rel.dot(v) / v.length_squared(), 0.0, 2.2)
		if (rel - v * tc).length() < 4.0:
			var side := rel - v.normalized() * rel.dot(v.normalized())
			if side.length() < 0.3:
				side = Vector3(-v.z, 0, v.x) * (1.0 if randf() < 0.5 else -1.0)
			return side.normalized()
	return Vector3.ZERO


func _process(delta: float) -> void:
	_t += delta
	_check_pickup()
	var cam := get_viewport().get_camera_3d()
	var far := cam != null and cam.global_position.distance_to(global_position) > FAR
	visible = not far
	if far and _state != "carry" and _state != "tease":
		return
	var pos := global_position
	var threat := _car_threat()
	if threat != Vector3.ZERO and _state != "flee":
		if _state != "carry" and _state != "tease":
			_set_state("flee")
		_flee_dir = threat
		Sfx.play_at(self, "yip", pos + Vector3.UP * 0.6, -6.0, randf_range(0.95, 1.2))
	_howl_t -= delta
	var person := _nearest_person()
	var speed := 0.0
	match _state:
		"idle", "sit":
			if person:
				_set_state("curious")
			elif _howl_t <= 0.0:
				_start_howl()
			elif _t > _wait:
				if _state == "sit":
					_set_state("idle")
				else:
					_set_state("walk" if randf() < 0.7 else "sit")
					_wait = randf_range(2.0, 6.0)
					_pick_target()
		"walk":
			if person:
				_set_state("curious")
			var to := Vector3(_target.x - pos.x, 0, _target.z - pos.z)
			if to.length() < 0.8:
				_set_state("idle")
			else:
				speed = 2.2
				_face(to, delta)
		"curious":
			if person == null:
				_set_state("idle")
				_rolled = false
				_curious_t = 0.0
			else:
				var to := Vector3(person.global_position.x - pos.x, 0, person.global_position.z - pos.z)
				_face(to, delta)
				if to.length() > 3.0:
					speed = 3.0
				_curious_t += delta
				if _curious_t > 3.0 and not _rolled and person.local_control:
					_rolled = true
					if Time.get_ticks_msec() > _next_theft_ms and randf() < steal_chance:
						steal_from(person)
		"flee":
			speed = 8.0
			_face(_flee_dir, delta * 3.0)
			if not _dry(pos + _flee_dir * 2.0):
				_flee_dir = Vector3(-_flee_dir.z, 0, _flee_dir.x)
			if _t > 1.3:
				_set_state("idle")
		"howl":
			if _t > 2.9:
				_set_state("sit")
				_wait = randf_range(1.0, 3.0)
		"steal":
			speed = _steal(delta)
		"carry", "tease":
			speed = _carry(delta)
	if speed > 0.0:
		pos += -global_basis.z * speed * delta
	pos.y = island.height_at(pos.x, pos.z)
	global_position = pos
	_animate(delta, speed)


func _set_state(s: String) -> void:
	_state = s
	_t = 0.0


func _start_howl() -> void:
	_set_state("howl")
	_howl_t = randf_range(60.0, 180.0)
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(global_position) < 140.0:
		Sfx.play_at(self, "howl", global_position + Vector3.UP * 0.8, -3.0, randf_range(0.88, 1.15))
	# the rest of the pack joins in
	for d in get_tree().get_nodes_in_group("dingoes"):
		var other := d as Dingo
		if other and other != self and other.global_position.distance_to(global_position) < 40.0 \
				and (other._state == "idle" or other._state == "sit" or other._state == "walk"):
			other._howl_t = randf_range(0.4, 1.6)


# ------------------------------------------------------------- thong thief
## Dash in and pinch this person's thong (only ever the player on this machine).
func steal_from(pc: PlayerCharacter) -> void:
	_victim = pc
	_bursts = 0
	_escaped = false
	_next_theft_ms = Time.get_ticks_msec() + THEFT_GAP_MS
	_set_state("steal")


func _who() -> String:
	return String(_main.player_name) if _main else "mate"


func _steal(delta: float) -> float:
	if _victim == null or not is_instance_valid(_victim) or not _victim.is_on_foot() or _t > 12.0:
		_set_state("idle")
		return 0.0
	var to := _victim.global_position - global_position
	to.y = 0.0
	_face(to, delta * 2.0)
	if to.length() < 0.9:
		_thong.visible = true
		Sfx.play_at(self, "yip", global_position + Vector3.UP * 0.6, 0.0, 1.25)
		_toast("Oi! A dingo just pinched your thong, %s! Chase it down!" % _who())
		_set_state("carry")
		return 0.0
	return 6.5


## Running off with it in short bursts, stopping to sit and tease; you get it back by
## getting close enough (it drops it) - or it gets bored and leaves it somewhere.
func _carry(delta: float) -> float:
	if _victim == null or not is_instance_valid(_victim):
		_drop()
		return 0.0
	var to_me := global_position - _victim.global_position
	to_me.y = 0.0
	var d := to_me.length()
	_escaped = _escaped or d > 4.0
	if _escaped and _victim.is_on_foot() and d < 1.7:
		_drop()
		_toast("Got it! It dropped your thong - grab it.")
		return 0.0
	if _state == "tease":
		# sit facing them, tail going like mad
		_face(-to_me, delta)
		if d < 6.0:
			_bursts += 1
			if _bursts >= 4:
				_drop()
				_toast("The dingo's had its fun - it dropped your thong.")
				return 0.0
			_set_state("carry")
			Sfx.play_at(self, "yip", global_position + Vector3.UP * 0.6, -3.0, 1.3)
		elif _t > 25.0:
			_drop()
		return 0.0
	# zig-zag away from them, steering round the water
	var away := to_me.normalized() if d > 0.1 else -global_basis.z
	var dir := away.rotated(Vector3.UP, sin(_t * 2.2) * 0.6)
	if not _dry(global_position + dir * 3.0):
		dir = Vector3(-away.z, 0, away.x)
		if not _dry(global_position + dir * 3.0):
			dir = -dir
	_face(dir, delta * 2.0)
	if _t > 3.5 or d > 20.0:
		_set_state("tease")
	return 4.6


func _drop() -> void:
	_thong.visible = false
	if _victim != null and is_instance_valid(_victim) and _victim.local_control:
		if _dropped and is_instance_valid(_dropped):
			_dropped.queue_free()
		_dropped = _make_thong()
		_dropped.top_level = true
		add_child(_dropped)
		var p := global_position - global_basis.z * 0.5
		_dropped.global_position = Vector3(p.x, island.height_at(p.x, p.z) + 0.03, p.z)
		_dropped.rotation.y = randf() * TAU
		Sfx.play_at(self, "pop", p, -6.0)
	_victim = null
	_target = home
	_set_state("walk")


func _check_pickup() -> void:
	if _dropped == null or not is_instance_valid(_dropped) or _main == null:
		return
	var me: PlayerCharacter = _main.local_player
	if me == null or not is_instance_valid(me) or not me.is_on_foot():
		return
	if me.global_position.distance_to(_dropped.global_position) < 1.4:
		_dropped.queue_free()
		_dropped = null
		Sfx.play_ui(self, "pop", -2.0, 1.3)
		_toast("Got your thong back, %s! Cheeky dingo." % _who())
		_main.achievements.unlock("thong")


func _toast(msg: String) -> void:
	if _main and _main.hud:
		_main.hud.show_toast(msg)


# ------------------------------------------------------------- looks
func _face(dir: Vector3, delta: float) -> void:
	if dir.length() < 0.01:
		return
	var want := atan2(-dir.x, -dir.z)
	_yaw = lerp_angle(_yaw, want, minf(1.0, 6.0 * delta))
	global_basis = Basis(Vector3.UP, _yaw)


func _animate(delta: float, speed: float) -> void:
	var rate := 9.0 + speed * 1.5 if speed > 0.1 else 2.0
	_phase += delta * rate
	var sw := clampf(0.4 + speed * 0.07, 0.0, 0.95) if speed > 0.1 else 0.0
	for i in _legs.size():
		var off := 0.0 if i == 0 or i == 3 else PI
		if speed > 5.0:
			off = 0.0 if i < 2 else PI   # flat-out gallop: front pair, back pair
		_legs[i].rotation.x = lerpf(_legs[i].rotation.x, sin(_phase + off) * sw, minf(1.0, delta * 12.0))
	# sitting (or howling, or teasing): back end down
	var sit := 1.0 if _state == "sit" or _state == "howl" or _state == "tease" else 0.0
	_body.rotation.x = lerpf(_body.rotation.x, sit * 0.45, minf(1.0, delta * 5.0))
	_body.position.y = lerpf(_body.position.y, -sit * 0.15 + absf(sin(_phase)) * 0.03 * sw, minf(1.0, delta * 8.0))
	var wag := 3.0 if _state == "curious" else (6.0 if _state == "tease" else 1.0)
	_tail.rotation.y = sin(_phase * wag) * 0.5
	if _state == "howl":
		_head.rotation.x = lerpf(_head.rotation.x, 0.9, minf(1.0, delta * 6.0))   # nose to the sky
	else:
		_head.rotation.x = lerpf(_head.rotation.x, 0.0, minf(1.0, delta * 6.0))
	_head.rotation.y = sin(_t * 0.7) * 0.4 if _state == "idle" else 0.0

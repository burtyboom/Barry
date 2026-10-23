class_name Barge
extends AnimatableBody3D
## Vehicle barge from the mainland. Each new car starts on one: it motors in from
## offshore, beaches where the island says (IslandData.barge_*), drops its bow ramp
## so you can drive off, then raises the ramp, backs out and leaves.
##
## The timeline runs locally on every machine from the moment the car spawns, so
## other players see your barge too. Only the owner's car is actually carried;
## remote cars are positioned by the network as usual.
##
## Local space: bow (ramp end) is -Z, deck top is y = DECK_Y, origin at waterline.

signal ramp_down
signal departed

const LENGTH := 24.0
const WIDTH := 9.0
const DECK_Y := 0.6
const RAMP_LEN := 5.5
const RAMP_W := 6.0
const RAMP_UP := deg_to_rad(80.0)
const SAIL_DIST := 110.0
const SAIL_TIME := 14.0
const RAMP_TIME := 3.0
const LEAVE_TIME := 26.0
const BOW_DEPTH := -0.35         ## sea floor depth below the tide where the bow grounds (runs right up the beach)
## side-by-side landing spots, metres sideways from the island's barge anchor
const LANES := [0.0, 25.0, -25.0, 50.0, -50.0]

enum State { SAILING, LOWERING, UNLOADING, RAISING, LEAVING }

var state := State.SAILING
var car: SandVehicle
var _t := 0.0
var _clear_t := 0.0
var _carrying := false
var _car_local := Transform3D.IDENTITY
var _land := Vector3.ZERO
var _dir := Vector3.FORWARD      ## direction of travel toward the beach
var _side := Vector3.RIGHT
var _yaw := 0.0
var _start := Vector3.ZERO
var _ramp_down_angle := 0.3
var _hinge: Node3D
var _ramp_shape: CollisionShape3D   ## lives on the barge body itself so it moves with it
var _wake: MeshInstance3D


## Lane is picked from the player id so every machine puts a player's barge in the same place.
static func lane_for(peer_id: int) -> int:
	return 0 if peer_id == 1 else 1 + peer_id % (LANES.size() - 1)


func setup(lane: int) -> void:
	var island := IslandData.instance
	_dir = island.barge_dir.normalized()
	_side = _dir.cross(Vector3.UP)
	_yaw = atan2(-_dir.x, -_dir.z)
	# walk in from the sea until the bow would touch bottom
	var bow := island.barge_anchor + _side * float(LANES[lane % LANES.size()])
	var walked := 0.0
	while walked < 2000.0 and island.height_at(bow.x, bow.z) < Tide.level + BOW_DEPTH:
		bow += _dir * 0.5
		walked += 0.5
	bow.y = 0.0
	_land = bow - _dir * LENGTH * 0.5
	_start = _land - _dir * SAIL_DIST
	# lower the ramp until its tip rests on the beach
	var tip := bow + _dir * RAMP_LEN * 0.9
	var drop := DECK_Y + Tide.level - (island.height_at(tip.x, tip.z) + 0.1)
	_ramp_down_angle = clampf(asin(clampf(drop / RAMP_LEN, -1.0, 1.0)), deg_to_rad(4.0), deg_to_rad(35.0))
	sync_to_physics = true
	collision_layer = WorldBuilder.TERRAIN_LAYER
	collision_mask = 0
	set_meta("deck", true)
	_build()
	transform = Transform3D(Basis(Vector3.UP, _yaw), _start)


## Where a car sits on the deck, in world space (call after setup + add_child).
func car_spot() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0, DECK_Y + 1.4, -3.0))


## Locks the (local) car to the deck until the ramp is down.
func carry(c: SandVehicle) -> void:
	car = c
	if c.local_control:
		_carrying = true
		_car_local = Transform3D(Basis.IDENTITY, Vector3(0, DECK_Y + 1.4, -3.0))
		c.set_carried(self)
		c.global_transform = global_transform * _car_local


func _physics_process(delta: float) -> void:
	_t += delta
	match state:
		State.SAILING:
			var k := clampf(_t / SAIL_TIME, 0.0, 1.0)
			var e := 1.0 - pow(1.0 - k, 3.0)
			var bob := 1.0 - e
			var pos := _start.lerp(_land, e)
			pos.y = Tide.level + sin(_t * 1.3) * 0.08 * bob
			var sway := Basis.from_euler(Vector3(sin(_t * 0.9) * 0.012 * bob, 0, sin(_t * 1.1) * 0.02 * bob))
			global_transform = Transform3D(Basis(Vector3.UP, _yaw) * sway, pos)
			_wake.scale = Vector3(1, 1, maxf(0.05, (1.0 - k) * 1.3))
			_wake.visible = k < 0.97
			# a remote player who already drove off long ago: no barge needed
			if not _carrying and is_instance_valid(car) and car._net_has_state \
					and car.global_position.distance_to(car_spot().origin) > 30.0:
				queue_free()
				return
			if k >= 1.0:
				_next(State.LOWERING)
		State.LOWERING:
			var k := clampf(_t / RAMP_TIME, 0.0, 1.0)
			_hinge.rotation.x = lerpf(RAMP_UP, -_ramp_down_angle, k * k * (3.0 - 2.0 * k))
			_sync_ramp_shape()
			if k >= 1.0:
				if _carrying and is_instance_valid(car) and car.carrier == self:
					car.release_from_carrier()
				_carrying = false
				ramp_down.emit()
				_next(State.UNLOADING)
		State.UNLOADING:
			var gone := not is_instance_valid(car) or car.global_position.distance_to(global_position) > LENGTH * 0.5 + 18.0
			_clear_t = _clear_t + delta if gone else 0.0
			if _clear_t > 2.0:
				_next(State.RAISING)
		State.RAISING:
			var k := clampf(_t / RAMP_TIME, 0.0, 1.0)
			_hinge.rotation.x = lerpf(-_ramp_down_angle, RAMP_UP, k * k * (3.0 - 2.0 * k))
			_sync_ramp_shape()
			if k >= 1.0:
				_next(State.LEAVING)
		State.LEAVING:
			var k := clampf(_t / LEAVE_TIME, 0.0, 1.0)
			var e := k * k
			var pos := _land.lerp(_land - _dir * SAIL_DIST * 1.6 - _side * 40.0, e)
			pos.y = Tide.level + sin(_t * 1.3) * 0.08 * e
			global_transform = Transform3D(Basis(Vector3.UP, _yaw - 0.5 * e), pos)
			_wake.visible = k > 0.1
			_wake.scale = Vector3(1, 1, clampf(k * 2.0, 0.05, 1.0))
			if k >= 1.0:
				departed.emit()
				queue_free()
	if _carrying:
		if is_instance_valid(car) and car.carrier == self:
			car.global_transform = global_transform * _car_local
		else:
			_carrying = false   # teleported / recovered off the barge


## Puts the ramp's collision box where the ramp is drawn (hinge angle).
func _sync_ramp_shape() -> void:
	_ramp_shape.transform = _hinge.transform * Transform3D(Basis.IDENTITY, Vector3(0, -0.12, -RAMP_LEN * 0.5))


func _next(s: State) -> void:
	state = s
	_t = 0.0


# ------------------------------------------------------------- looks
func _build() -> void:
	var hull := Color(0.16, 0.38, 0.72)
	var white := Color(0.95, 0.95, 0.92)
	var deck := Color(0.42, 0.45, 0.48)
	var stripe := Color(0.95, 0.55, 0.12)
	var glass := Color(0.35, 0.65, 0.90)
	var black := Color(0.12, 0.12, 0.13)
	var half_l := LENGTH * 0.5
	# hull, deck plate, orange rub stripe
	_solid(Vector3(WIDTH, 2.0, LENGTH), Vector3(0, DECK_Y - 1.0, 0), hull)
	Toon.box(self, Vector3(WIDTH - 0.9, 0.06, LENGTH - 0.6), Vector3(0, DECK_Y + 0.03, 0), deck, false)
	Toon.box(self, Vector3(WIDTH + 0.08, 0.22, LENGTH + 0.08), Vector3(0, DECK_Y - 0.25, 0), stripe, false)
	# side walls + stern wall
	for sx in [-1.0, 1.0]:
		_solid(Vector3(0.4, 1.2, LENGTH), Vector3(sx * (WIDTH * 0.5 - 0.2), DECK_Y + 0.6, 0), white)
	_solid(Vector3(WIDTH, 1.2, 0.4), Vector3(0, DECK_Y + 0.6, half_l - 0.2), white)
	# deck tie-down lines
	for z in [-6.0, 0.0, 6.0]:
		Toon.box(self, Vector3(WIDTH - 1.2, 0.02, 0.12), Vector3(0, DECK_Y + 0.07, z), Color(0.95, 0.85, 0.2), false)
	# wheelhouse up on stilts over the starboard wall, out of the way of cars
	var wh := Vector3(WIDTH * 0.5 - 1.1, DECK_Y + 3.3, half_l - 3.0)
	for px in [-0.8, 0.8]:
		for pz in [-1.3, 1.3]:
			Toon.box(self, Vector3(0.18, 2.3, 0.18), wh + Vector3(px, -2.15, pz), black)
	Toon.box(self, Vector3(2.4, 2.0, 3.4), wh, white)
	Toon.box(self, Vector3(2.46, 0.6, 3.0), wh + Vector3(0, 0.3, 0), glass, false)
	Toon.box(self, Vector3(2.8, 0.2, 3.8), wh + Vector3(0, 1.1, 0), hull)
	Toon.box(self, Vector3(0.12, 1.4, 0.12), wh + Vector3(0, 1.9, 1.0), black)
	Toon.box(self, Vector3(0.05, 0.5, 0.8), wh + Vector3(0, 2.35, 1.4), Color(0.9, 0.15, 0.1), false)
	# bow ramp on a hinge at the front edge of the deck
	_hinge = Node3D.new()
	_hinge.position = Vector3(0, DECK_Y, -half_l)
	_hinge.rotation.x = RAMP_UP
	add_child(_hinge)
	# Visuals hang off the hinge. The collision box is a shape on the barge body
	# itself (a separate nested body would not follow the barge / hinge motion).
	var ramp := Node3D.new()
	_hinge.add_child(ramp)
	var rp := Vector3(0, -0.12, -RAMP_LEN * 0.5)
	_ramp_shape = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(RAMP_W, 0.25, RAMP_LEN)
	_ramp_shape.shape = bs
	add_child(_ramp_shape)
	_sync_ramp_shape()
	Toon.box(ramp, Vector3(RAMP_W, 0.25, RAMP_LEN), rp, deck)
	for k in 6:
		Toon.box(ramp, Vector3(RAMP_W - 0.4, 0.06, 0.12), Vector3(0, 0.03, -0.5 - k * 0.85), Color(0.3, 0.32, 0.34), false)
	for sx in [-1.0, 1.0]:
		Toon.box(ramp, Vector3(0.2, 0.35, RAMP_LEN), Vector3(sx * (RAMP_W * 0.5 - 0.1), 0.05, -RAMP_LEN * 0.5), stripe, false)
	# white wash pushed out by the bow while moving
	_wake = MeshInstance3D.new()
	var wm := BoxMesh.new()
	wm.size = Vector3(WIDTH + 3.0, 0.05, 14.0)
	_wake.mesh = wm
	_wake.material_override = Toon.mat(Color(1, 1, 1, 0.55))
	_wake.position = Vector3(0, 0.05, half_l + 6.0)
	_wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wake)


## Box that is both seen and solid.
func _solid(size: Vector3, pos: Vector3, c: Color) -> void:
	Toon.box(self, size, pos, c)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	add_child(cs)

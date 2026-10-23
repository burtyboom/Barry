class_name SoccerBall
extends RigidBody3D
## A beach soccer ball. Run into it to kick it (running kicks harder), or belt it with
## the ute. The server (or you, solo) runs the physics and sends it to everyone else
## 15 times a second; everyone else just shows where it is. It floats in the surf and
## goes back to its starting spot if it gets lost.

const RADIUS := 0.36

var home := Vector3.ZERO
var _last := {}          ## node -> [position, kick cooldown]
var _net_t := 0.0
var _net_pos := Vector3.ZERO
var _net_vel := Vector3.ZERO
var _net_has := false
var _lost_t := 0.0
static var _tex: ImageTexture


func _ready() -> void:
	mass = 0.45
	collision_layer = 8          # its own layer: utes don't crash into it, we kick it in code
	collision_mask = 1
	linear_damp = 0.25
	angular_damp = 1.2
	continuous_cd = true
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.55
	pm.friction = 0.7
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = RADIUS
	cs.shape = sh
	add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS
	sm.height = RADIUS * 2.0
	mi.mesh = sm
	var m := Toon.mat(Color.WHITE).duplicate() as StandardMaterial3D
	m.albedo_texture = _pattern()
	mi.material_override = m
	add_child(mi)
	if not is_multiplayer_authority():
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


## White ball, black patches (a soccer ball from far enough away).
static func _pattern() -> ImageTexture:
	if _tex == null:
		var img := Image.create(128, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.98, 0.98, 0.96))
		for k in 10:
			var cx := (k % 5) * 26 + (13 if k >= 5 else 0)
			var cy := 18 if k < 5 else 46
			for dy in range(-7, 8):
				for dx in range(-8, 9):
					if dx * dx + dy * dy * 1.3 < 52:
						img.set_pixel(posmod(cx + dx, 128), clampi(cy + dy, 0, 63), Color(0.08, 0.08, 0.1))
		_tex = ImageTexture.create_from_image(img)
	return _tex


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority():
		if _net_has:
			global_position = global_position.lerp(_net_pos + _net_vel * 0.05, minf(1.0, 12.0 * delta))
			rotate(Vector3(_net_vel.z, 0, -_net_vel.x).normalized() if Vector2(_net_vel.x, _net_vel.z).length() > 0.05 else Vector3.UP,
				Vector2(_net_vel.x, _net_vel.z).length() / RADIUS * delta)
		return
	var island := IslandData.instance
	if island == null:
		return
	var p := global_position
	# floats in the water
	var water := island.water_level_at(p.x, p.z) - p.y
	if water > -RADIUS * 0.5:
		apply_central_force(Vector3.UP * mass * 9.8 * clampf((water + RADIUS) / RADIUS, 0.0, 2.2))
		linear_velocity *= 1.0 - 0.8 * delta
	# lost (rolled out to sea / under the sand / miles away from anyone)? back home it goes
	if p.y < island.height_at(p.x, p.z) - 2.0 or p.distance_to(home) > 600.0:
		_lost_t += delta
	else:
		_lost_t = 0.0
	if _lost_t > 4.0:
		reset_home()
	_kicks()
	_net_t += delta
	if _net_t > 0.066 and _online():
		_net_t = 0.0
		_state.rpc(global_position, linear_velocity)


func reset_home() -> void:
	_lost_t = 0.0
	global_position = home + Vector3.UP * 0.6
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO


## Anyone walking / running into the ball kicks it; utes bowl it along.
func _kicks() -> void:
	var main := get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var bp := global_position
	var now := Time.get_ticks_msec() / 1000.0
	var movers: Array = []
	for pc in main.players.get_children():
		if pc is PlayerCharacter and (pc as PlayerCharacter).is_on_foot():
			movers.append([pc, 0.55, false])
	for c in main.cars.get_children():
		if c is SandVehicle:
			movers.append([c, 2.4, true])
	for m in movers:
		var n: Node3D = m[0]
		var pos := n.global_position
		var rec: Array = _last.get(n, [pos, 0.0])
		var vel := (pos - (rec[0] as Vector3)) * Engine.physics_ticks_per_second
		_last[n] = [pos, rec[1]]
		var reach: float = m[1] + RADIUS
		var flat := Vector3(bp.x - pos.x, 0, bp.z - pos.z)
		if flat.length() > reach or absf(bp.y - (pos.y + (0.6 if m[2] else 0.4))) > 1.4 or now < float(rec[1]):
			continue
		var hv := Vector3(vel.x, 0, vel.z)
		var spd := hv.length()
		if spd < 0.4 or hv.dot(flat) <= 0.0:
			continue
		var dir := (flat.normalized() * 0.6 + hv.normalized() * 0.4).normalized()
		if m[2]:
			linear_velocity = dir * (spd * 1.25 + 2.0) + Vector3.UP * (2.0 + spd * 0.25)
		else:
			var run := spd > 4.6
			linear_velocity = dir * (spd * 1.5 + (5.0 if run else 2.5)) + Vector3.UP * (3.5 if run else 1.5)
			Sfx.play_at(self, "thunk", bp, -6.0, 1.6)
		_last[n] = [pos, now + 0.35]


func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


@rpc("authority", "call_remote", "unreliable_ordered")
func _state(pos: Vector3, vel: Vector3) -> void:
	if not _net_has:
		global_position = pos
	elif (vel - _net_vel).length() > 3.0:
		Sfx.play_at(self, "thunk", pos, -6.0, 1.6)   # someone kicked it
	_net_pos = pos
	_net_vel = vel
	_net_has = true

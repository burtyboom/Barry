class_name Props
extends Node3D
## Placed camping gear (chairs, campfires, tents, eskies, umbrellas).
## Placing / picking up is broadcast to everyone; the host replays the lot to late joiners.

var props := {}          ## id -> StaticBody3D
var _counter := 0


func clear_all() -> void:
	for id in props:
		(props[id] as Node).queue_free()
	props.clear()


func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func place(kind: String, xf: Transform3D) -> String:
	_counter += 1
	var id := "%d_%d" % [multiplayer.get_unique_id(), _counter]
	if _online():
		_rpc_spawn.rpc(id, kind, xf)
	else:
		_rpc_spawn(id, kind, xf)
	return id


func remove(id: String) -> void:
	if _online():
		_rpc_remove.rpc(id)
	else:
		_rpc_remove(id)


## Host: send everything already placed to a player who just joined.
func sync_to(peer: int) -> void:
	for id in props:
		var n: Node3D = props[id]
		_rpc_spawn.rpc_id(peer, id, n.get_meta("kind"), n.global_transform)


@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn(id: String, kind: String, xf: Transform3D) -> void:
	if props.has(id):
		return
	var body := Props.build(kind, false)
	body.name = "Prop_" + id
	body.set_meta("id", id)
	add_child(body)
	body.global_transform = xf
	props[id] = body
	Sfx.play_at(self, "pop", xf.origin, -4.0)


@rpc("any_peer", "call_local", "reliable")
func _rpc_remove(id: String) -> void:
	if props.has(id):
		(props[id] as Node).queue_free()
		props.erase(id)


## Nearest prop within max_dist of pos (optionally of one kind): {"id", "node", "kind", "dist"} or {}.
func nearest(pos: Vector3, max_dist: float, kind := "") -> Dictionary:
	var best := {}
	var bd := max_dist
	for id in props:
		var n: Node3D = props[id]
		if kind != "" and n.get_meta("kind") != kind:
			continue
		var d := Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length()
		if d < bd:
			bd = d
			best = {"id": id, "node": n, "kind": n.get_meta("kind"), "dist": d}
	return best


# ------------------------------------------------------------- models
## Builds a prop. ghost = see-through preview with no collision.
static func build(kind: String, ghost: bool) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.set_meta("kind", kind)
	b.collision_layer = 4      # same layer as trees: cars bump into them
	b.collision_mask = 0
	var v := Node3D.new()
	v.name = "Visual"
	b.add_child(v)
	match kind:
		"chair":
			_chair(b, v)
		"fire":
			_fire(b, v, ghost)
		"tent":
			_tent(b, v)
		"esky":
			_esky(b, v)
		"umbrella":
			_umbrella(b, v)
	if ghost:
		for c in b.get_children():
			if c is CollisionShape3D:
				c.queue_free()
		_ghostify(v)
	return b


static func _ghostify(n: Node) -> void:
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.5, 1.0, 0.6, 0.45)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for c in n.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).material_override = gm
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if c is Light3D or c is GPUParticles3D:
			c.visible = false
		_ghostify(c)


static func _col(b: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = pos
	b.add_child(cs)


static func _cyl(parent: Node3D, top: float, bottom: float, h: float, pos: Vector3, c: Color, rot := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top
	cm.bottom_radius = bottom
	cm.height = h
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = Toon.mat(c, emissive)
	mi.position = pos
	mi.rotation_degrees = rot
	parent.add_child(mi)
	return mi


## Folding camp chair, facing -Z. Seat at y ~0.46.
static func _chair(b: StaticBody3D, v: Node3D) -> void:
	var frame := Color(0.15, 0.15, 0.17)
	var fabric := Color(0.18, 0.50, 0.85)
	for x in [-0.24, 0.24]:
		for z in [-0.2, 0.2]:
			Toon.box(v, Vector3(0.035, 0.5, 0.035), Vector3(x, 0.24, z), frame, true, Vector3(z * 40.0, 0, 0))
	Toon.box(v, Vector3(0.52, 0.06, 0.46), Vector3(0, 0.46, 0), fabric)                       # seat
	Toon.box(v, Vector3(0.52, 0.55, 0.06), Vector3(0, 0.74, 0.24), fabric, true, Vector3(-12, 0, 0))   # back
	for x in [-0.29, 0.29]:
		Toon.box(v, Vector3(0.08, 0.04, 0.44), Vector3(x, 0.64, 0.02), frame)                  # arm rests
	_cyl(v, 0.045, 0.04, 0.1, Vector3(0.29, 0.69, -0.14), Color(0.15, 0.15, 0.17))             # cup holder
	_cyl(v, 0.035, 0.035, 0.12, Vector3(0.29, 0.73, -0.14), Color(0.95, 0.85, 0.15))            # a can
	_col(b, Vector3(0.55, 0.9, 0.5), Vector3(0, 0.45, 0))
	b.set_meta("seat", Transform3D(Basis.IDENTITY, Vector3(0, 0.48, 0.02)))


static func _fire(b: StaticBody3D, v: Node3D, ghost: bool) -> void:
	var stone := Color(0.52, 0.50, 0.48)
	for k in 9:
		var a := TAU * k / 9.0
		Toon.box(v, Vector3(0.24, 0.18, 0.2), Vector3(cos(a) * 0.55, 0.08, sin(a) * 0.55), stone.darkened(0.1 * (k % 3)), true, Vector3(0, -rad_to_deg(a), 0))
	for k in 4:
		var log_n := _cyl(v, 0.07, 0.07, 0.8, Vector3(0, 0.12, 0), Color(0.45, 0.28, 0.15), Vector3(70, k * 45.0, 0))
		log_n.position = Vector3(0, 0.14, 0)
	var flames := Node3D.new()
	flames.name = "Flames"
	v.add_child(flames)
	_cyl(flames, 0.0, 0.32, 0.9, Vector3(0, 0.55, 0), Color(1.0, 0.45, 0.08), Vector3.ZERO, true)
	_cyl(flames, 0.0, 0.22, 0.7, Vector3(0.1, 0.5, 0.06), Color(1.0, 0.75, 0.15), Vector3(0, 0, -8), true)
	_cyl(flames, 0.0, 0.18, 0.55, Vector3(-0.1, 0.45, -0.05), Color(1.0, 0.92, 0.45), Vector3(6, 0, 6), true)
	if not ghost:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.25)
		light.light_energy = 2.2
		light.omni_range = 9.0
		light.position = Vector3(0, 0.9, 0)
		v.add_child(light)
		var embers := GPUParticles3D.new()
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 20.0
		pm.initial_velocity_min = 0.8
		pm.initial_velocity_max = 1.8
		pm.gravity = Vector3(0, 0.3, 0)
		pm.scale_min = 0.03
		pm.scale_max = 0.06
		pm.color = Color(1.0, 0.6, 0.2)
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 0.25
		embers.process_material = pm
		var em := SphereMesh.new()
		em.radius = 0.5
		em.height = 1.0
		em.radial_segments = 6
		em.rings = 3
		em.material = Toon.mat(Color(1.0, 0.6, 0.2), true)
		embers.draw_pass_1 = em
		embers.amount = 24
		embers.lifetime = 1.6
		embers.position = Vector3(0, 0.6, 0)
		v.add_child(embers)
		var flick := FlameFlicker.new()
		flick.flames = flames
		flick.light = light
		v.add_child(flick)
	_col(b, Vector3(1.2, 0.3, 1.2), Vector3(0, 0.15, 0))


## Dome tent with a fly and a zipped door, facing -Z.
static func _tent(b: StaticBody3D, v: Node3D) -> void:
	var fly := Color(0.30, 0.72, 0.30)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 0.5
	sm.is_hemisphere = true
	sm.radial_segments = 20
	sm.rings = 8
	dome.mesh = sm
	dome.material_override = Toon.mat(fly)
	dome.scale = Vector3(2.4, 2.7, 2.2)
	v.add_child(dome)
	# darker door arch on the front
	var door := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.5
	dm.height = 0.5
	dm.is_hemisphere = true
	dm.radial_segments = 16
	dm.rings = 6
	door.mesh = dm
	door.material_override = Toon.mat(Color(0.95, 0.60, 0.15))
	door.scale = Vector3(1.0, 2.0, 0.25)
	door.position = Vector3(0, 0, -1.02)
	v.add_child(door)
	Toon.box(v, Vector3(0.03, 0.9, 0.03), Vector3(0, 0.45, -1.16), Color(0.15, 0.15, 0.16))   # zip
	# pole arcs over the top
	for a in [45.0, -45.0]:
		var arc := Props._cyl(v, 1.22, 1.22, 0.04, Vector3(0, 0.02, 0), Color(0.2, 0.2, 0.22), Vector3(90, a, 0))
		arc.scale = Vector3(1.0, 1.0, 1.12)
	# guy ropes and pegs
	for k in 4:
		var ang := TAU * (k + 0.5) / 4.0
		var peg := Vector3(cos(ang) * 1.9, 0.05, sin(ang) * 1.75)
		Toon.box(v, Vector3(0.05, 0.12, 0.05), peg, Color(0.75, 0.75, 0.78))
	_col(b, Vector3(2.3, 1.3, 2.1), Vector3(0, 0.65, 0))


static func _esky(b: StaticBody3D, v: Node3D) -> void:
	Toon.box(v, Vector3(0.72, 0.42, 0.44), Vector3(0, 0.22, 0), Color(0.95, 0.95, 0.95))
	Toon.box(v, Vector3(0.75, 0.1, 0.47), Vector3(0, 0.47, 0), Color(0.15, 0.40, 0.85))
	for x in [-0.39, 0.39]:
		Toon.box(v, Vector3(0.05, 0.08, 0.2), Vector3(x, 0.38, 0), Color(0.15, 0.40, 0.85))
	_col(b, Vector3(0.75, 0.55, 0.47), Vector3(0, 0.27, 0))


static func _umbrella(b: StaticBody3D, v: Node3D) -> void:
	var tilt := Node3D.new()
	tilt.rotation_degrees = Vector3(8, 0, 0)
	v.add_child(tilt)
	_cyl(tilt, 0.03, 0.03, 2.3, Vector3(0, 1.1, 0), Color(0.9, 0.9, 0.92))
	_cyl(tilt, 0.04, 1.25, 0.45, Vector3(0, 2.1, 0), Color(0.92, 0.22, 0.28))
	_cyl(tilt, 0.04, 0.7, 0.26, Vector3(0, 2.2, 0), Color(1.0, 1.0, 1.0))
	_cyl(tilt, 0.06, 0.06, 0.08, Vector3(0, 2.36, 0), Color(0.92, 0.22, 0.28))
	_col(b, Vector3(0.2, 2.2, 0.2), Vector3(0, 1.1, 0))

class_name Birds
extends RefCounted
## Birds: a flock of seagulls loafing on the beach (they all lift off and wheel around
## when a ute or a person barges through, then settle again a bit further along), and
## big birds of prey soaring in lazy circles high overhead. Ambient only - each machine
## runs its own; no collision.

const GULL_GREY := Color(0.70, 0.74, 0.80)
const WHITE := Color(0.97, 0.97, 0.96)
const BLACK := Color(0.12, 0.12, 0.14)


static func _cap(parent: Node3D, r: float, h: float, pos: Vector3, c: Color, rot := Vector3(90, 0, 0)) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = maxf(h, r * 2.0)
	cm.radial_segments = 8
	cm.rings = 3
	mi.mesh = cm
	mi.material_override = Toon.mat(c)
	mi.position = pos
	mi.rotation_degrees = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func _flat(parent: Node3D, size: Vector3, pos: Vector3, c: Color, rot := Vector3.ZERO) -> void:
	var mi := Toon.box(parent, size, pos, c, false, rot)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Fewer draw calls: every node in the tree that holds several meshes gets them merged
## into one vertex-coloured mesh (the parts that move together stay one piece).
static func bake_tree(root: Node3D, shadows: bool) -> void:
	var nodes: Array[Node3D] = [root]
	for n in root.find_children("*", "Node3D", true, false):
		if not (n is MeshInstance3D):
			nodes.append(n as Node3D)
	for n in nodes:
		_bake(n, shadows)


static func _bake(n: Node3D, shadows: bool) -> void:
	var parts: Array[MeshInstance3D] = []
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			parts.append(c)
	if parts.is_empty():
		return
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for mi in parts:
		var col := Color.WHITE
		var m := mi.material_override as StandardMaterial3D
		if m:
			col = m.albedo_color.srgb_to_linear()   # vertex colours are taken as linear
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var ii: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var base := verts.size()
		var xf := mi.transform
		for k in v.size():
			verts.append(xf * v[k])
			norms.append((xf.basis * nn[k]).normalized() if k < nn.size() else Vector3.UP)
			cols.append(col)
		if ii.is_empty():
			for k in v.size():
				idx.append(base + k)
		else:
			for k in ii.size():
				idx.append(base + ii[k])
		mi.free()
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = norms
	a[Mesh.ARRAY_COLOR] = cols
	a[Mesh.ARRAY_INDEX] = idx
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var out := MeshInstance3D.new()
	out.mesh = am
	out.material_override = Toon.vcol_mat()
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(out)
	n.move_child(out, 0)


## Point a bird node along its velocity, banked into the turn (wings tilt the way a
## real bird's do: "up" leans toward the sideways pull).
static func _orient(n: Node3D, vel: Vector3, accel: Vector3, s: float) -> void:
	var fwd := vel.normalized()
	if fwd.length() < 0.01:
		return
	var side := accel - fwd * accel.dot(fwd)
	side.y = 0.0
	side = side.limit_length(7.0)
	var up := (Vector3.UP * 9.8 + side).normalized()
	if absf(up.dot(fwd)) > 0.98:
		up = Vector3.UP
	n.global_basis = Basis.looking_at(fwd, up) * Basis.from_scale(Vector3.ONE * s)


# =============================================================== seagulls
class Gull extends Node3D:
	var body: Node3D
	var wings: Array[Node3D] = []
	var folded: Array[Node3D] = []
	var legs: Node3D
	var head: Node3D
	var vel := Vector3.ZERO
	var flying := false
	var phase := 0.0
	var ang := 0.0          ## where it is on the flock's circle
	var rad := 10.0
	var alt := 10.0
	var spot := Vector3.ZERO ## landing / standing spot
	var peck_t := 0.0
	var flap := 0.0         ## seconds of flapping left
	var acc := Vector3.ZERO
	const S := 1.35

	func _ready() -> void:
		body = Node3D.new()
		body.position = Vector3(0, 0.15, 0)
		add_child(body)
		Birds._cap(body, 0.075, 0.36, Vector3.ZERO, Birds.WHITE)
		Birds._flat(body, Vector3(0.11, 0.04, 0.20), Vector3(0, 0.055, 0.03), Birds.GULL_GREY)
		Birds._flat(body, Vector3(0.09, 0.02, 0.12), Vector3(0, 0.02, 0.22), Birds.WHITE)          # tail
		head = Node3D.new()
		head.position = Vector3(0, 0.08, -0.15)
		body.add_child(head)
		Birds._cap(head, 0.058, 0.13, Vector3(0, 0, -0.01), Birds.WHITE)
		Birds._flat(head, Vector3(0.025, 0.03, 0.08), Vector3(0, -0.01, -0.1), Color(1.0, 0.82, 0.15))
		for x in [-1.0, 1.0]:
			Birds._flat(head, Vector3(0.02, 0.022, 0.02), Vector3(x * 0.045, 0.02, -0.03), Birds.BLACK)
			# spread wings (flying): pivot at the shoulder
			var w := Node3D.new()
			w.position = Vector3(x * 0.06, 0.04, -0.03)
			body.add_child(w)
			Birds._flat(w, Vector3(0.26, 0.018, 0.15), Vector3(x * 0.13, 0, 0), Birds.GULL_GREY)
			var tip := Node3D.new()
			tip.position = Vector3(x * 0.26, 0, 0)
			w.add_child(tip)
			Birds._flat(tip, Vector3(0.2, 0.016, 0.11), Vector3(x * 0.09, 0, 0.02), Birds.GULL_GREY)
			Birds._flat(tip, Vector3(0.09, 0.018, 0.10), Vector3(x * 0.16, 0, 0.025), Birds.BLACK)
			w.set_meta("tip", tip)
			w.visible = false
			wings.append(w)
		# folded wings (standing)
		var f := Node3D.new()
		body.add_child(f)
		for x in [-1.0, 1.0]:
			Birds._flat(f, Vector3(0.035, 0.07, 0.30), Vector3(x * 0.07, 0.035, 0.06), Birds.GULL_GREY)
			Birds._flat(f, Vector3(0.036, 0.05, 0.08), Vector3(x * 0.07, 0.04, 0.24), Birds.BLACK)
		folded.append(f)
		legs = Node3D.new()
		body.add_child(legs)
		for x in [-0.03, 0.03]:
			Birds._flat(legs, Vector3(0.018, 0.12, 0.018), Vector3(x, -0.1, 0.0), Color(0.95, 0.55, 0.2))
		Birds.bake_tree(self, false)
		scale = Vector3.ONE * S

	func set_flying(on: bool) -> void:
		flying = on
		for w in wings:
			w.visible = on
		for f in folded:
			f.visible = not on
		legs.visible = not on
		body.position.y = 0.0 if on else 0.15
		if not on:
			head.rotation.x = 0.0
			var yaw := randf() * TAU
			global_basis = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3.ONE * S)

	func animate_wings(delta: float, flapping: bool) -> void:
		phase += delta * (13.0 if flapping else 2.0)
		var a := sin(phase) * 0.75 if flapping else 0.12 + sin(phase) * 0.04
		for i in wings.size():
			var sgn := -1.0 if i == 0 else 1.0
			wings[i].rotation.z = -sgn * a
			(wings[i].get_meta("tip") as Node3D).rotation.z = -sgn * (sin(phase - 0.6) * 0.35 if flapping else -0.05)


class GullFlock extends Node3D:
	var island: IslandData
	var spot := Vector3.ZERO     ## middle of where they're sitting
	var count := 6
	var placed := false
	var gulls: Array[Gull] = []
	var _main: Node
	var _air := false
	var _air_t := 0.0
	var _air_for := 10.0
	var _center := Vector3.ZERO  ## circling centre while up
	var _landing := false
	var _call_t := 0.0

	func _ready() -> void:
		_main = get_tree().root.get_node_or_null("Main")
		for i in count:
			var g := Gull.new()
			add_child(g)
			g.set_flying(false)
			gulls.append(g)
		visible = false

	## Sit the whole flock down at p (no flying; used when it's out of sight).
	func place_at(p: Vector3) -> void:
		spot = p
		placed = true
		_air = false
		_landing = false
		for g in gulls:
			g.spot = _scatter_spot(p)
			g.global_position = g.spot
			g.vel = Vector3.ZERO
			g.set_flying(false)
		visible = true

	func _scatter_spot(p: Vector3) -> Vector3:
		for tries in 6:
			var q := p + Vector3(randf_range(-4.5, 4.5), 0, randf_range(-4.5, 4.5))
			if _sand(q):
				return Vector3(q.x, island.height_at(q.x, q.z), q.z)
		return Vector3(p.x, island.height_at(p.x, p.z), p.z)

	func _sand(p: Vector3) -> bool:
		var s := island.surface_at(p.x, p.z)
		var on := s == IslandData.Surface.WET_SAND or s == IslandData.Surface.DRY_SAND or s == IslandData.Surface.WEST_FLATS
		return on and island.water_level_at(p.x, p.z) < island.height_at(p.x, p.z) - 0.15

	func _scared() -> bool:
		if _main == null:
			return false
		if _main.get("cars"):
			for c in _main.cars.get_children():
				var car := c as SandVehicle
				if car == null:
					continue
				var d := Vector2(car.global_position.x - spot.x, car.global_position.z - spot.z).length()
				if (d < 18.0 and car.linear_velocity.length() > 1.5) or d < 7.0 or (car.horn_on and d < 35.0):
					return true
		if _main.get("players"):
			for p in _main.players.get_children():
				var pc := p as PlayerCharacter
				if pc and pc.is_on_foot() and Vector2(pc.global_position.x - spot.x, pc.global_position.z - spot.z).length() < 7.5:
					return true
		return false

	func take_off() -> void:
		_air = true
		_landing = false
		_air_t = 0.0
		_air_for = randf_range(9.0, 16.0)
		_center = spot + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		for g in gulls:
			g.set_flying(true)
			g.ang = randf() * TAU
			g.rad = randf_range(7.0, 15.0)
			g.alt = randf_range(7.0, 15.0)
			g.flap = randf_range(1.2, 2.2)
			g.vel = Vector3(randf_range(-1, 1), 4.0, randf_range(-1, 1))
		var cam := get_viewport().get_camera_3d()
		if cam and cam.global_position.distance_to(spot) < 90.0:
			for k in 3:
				Sfx.play_at(self, "gull", spot + Vector3(randf_range(-4, 4), 3, randf_range(-4, 4)), -4.0 - k * 2.0, randf_range(0.9, 1.25))

	## Somewhere new along the sand to settle: a bit further on, out of the way.
	func _new_spot() -> Vector3:
		for tries in 12:
			var a := randf() * TAU
			var d := randf_range(25.0, 70.0)
			var q := spot + Vector3(cos(a) * d * 0.4, 0, sin(a) * d)
			if _sand(q):
				return Vector3(q.x, island.height_at(q.x, q.z), q.z)
		return spot

	func _process(delta: float) -> void:
		if not placed or island == null:
			return
		var cam := get_viewport().get_camera_3d()
		var far := cam != null and cam.global_position.distance_to(spot) > 260.0
		visible = not far
		if far:
			return
		if not _air:
			# the tide coming in, or something charging through: everyone up
			if _scared() or not _sand(spot):
				take_off()
			else:
				_ground(delta)
			return
		_air_t += delta
		if not _landing and _air_t > _air_for and not _scared():
			var ns := _new_spot()
			if _sand(ns):
				spot = ns
				_landing = true
				for g in gulls:
					g.spot = _scatter_spot(ns)
		_call_t -= delta
		if _call_t <= 0.0:
			_call_t = randf_range(2.0, 6.0)
			if cam and cam.global_position.distance_to(_center) < 70.0:
				Sfx.play_at(self, "gull", _center + Vector3(0, 10, 0), -8.0, randf_range(0.9, 1.25))
		var down := 0
		for g in gulls:
			if not g.flying:
				down += 1
				continue
			var gh := island.height_at(_center.x, _center.z)
			var target: Vector3
			var spd := 7.5
			if _landing:
				target = g.spot + Vector3(0, 0.02, 0)
				var dist := g.global_position.distance_to(target)
				spd = clampf(dist * 0.9, 2.2, 8.0)
				if dist < 0.5:
					g.global_position = g.spot
					g.set_flying(false)
					continue
			else:
				g.ang += delta * spd / g.rad
				target = _center + Vector3(cos(g.ang) * g.rad, 0, sin(g.ang) * g.rad)
				target.y = maxf(gh, Tide.level) + g.alt + sin(g.ang * 2.0) * 1.5
			var want := (target - g.global_position)
			var wl := want.length()
			if wl > 0.01:
				want = want / wl * spd
			var before := g.vel
			g.vel = g.vel.lerp(want, minf(1.0, delta * 2.2))
			g.global_position += g.vel * delta
			g.acc = g.acc.lerp((g.vel - before) / maxf(delta, 0.001), minf(1.0, delta * 5.0))
			Birds._orient(g, g.vel, g.acc, Gull.S)
			g.flap -= delta
			if g.flap <= 0.0 and randf() < delta * 0.25:
				g.flap = randf_range(0.6, 1.4)
			g.animate_wings(delta, g.flap > 0.0 or g.vel.y > 1.0 or _landing)
		if down == gulls.size():
			_air = false
			_landing = false

	## Standing around: the odd peck, a few steps, turning about.
	func _ground(delta: float) -> void:
		for g in gulls:
			g.peck_t -= delta
			if g.peck_t <= 0.0:
				g.peck_t = randf_range(1.0, 5.0)
				if randf() < 0.4:
					g.global_basis = Basis(Vector3.UP, randf() * TAU) * Basis.from_scale(Vector3.ONE * Gull.S)
			# peck: head dips for a moment
			var pecking := g.peck_t < 0.35
			g.head.rotation.x = lerpf(g.head.rotation.x, 0.9 if pecking else 0.0, minf(1.0, delta * 14.0))


# =============================================================== birds of prey
## A big bird circling high up: a white-bellied sea eagle or a brahminy kite.
class Soarer extends Node3D:
	var island: IslandData
	var center := Vector3.ZERO
	var kind := "eagle"
	var _ang := 0.0
	var _rad := 45.0
	var _alt := 55.0
	var _wings: Array[Node3D] = []
	var _phase := 0.0
	var _flap_t := 5.0
	var _flap := 0.0
	var _vel := Vector3.FORWARD

	func _ready() -> void:
		var body_c := Birds.WHITE if kind == "eagle" else Color(0.62, 0.30, 0.15)
		var head_c := Birds.WHITE
		var wing_c := Color(0.42, 0.44, 0.48) if kind == "eagle" else Color(0.60, 0.29, 0.14)
		var tip_c := Color(0.12, 0.12, 0.14) if kind == "eagle" else Color(0.25, 0.13, 0.08)
		var b := Node3D.new()
		add_child(b)
		Birds._cap(b, 0.16, 0.85, Vector3.ZERO, body_c)
		Birds._cap(b, 0.12, 0.26, Vector3(0, 0.03, -0.48), head_c)
		Birds._flat(b, Vector3(0.07, 0.07, 0.12), Vector3(0, 0.0, -0.64), Color(0.95, 0.8, 0.3))   # beak
		Birds._flat(b, Vector3(0.36, 0.04, 0.30), Vector3(0, 0, 0.5), body_c if kind == "eagle" else wing_c)   # tail
		for x in [-1.0, 1.0]:
			var w := Node3D.new()
			w.position = Vector3(x * 0.12, 0.04, -0.05)
			b.add_child(w)
			Birds._flat(w, Vector3(0.75, 0.04, 0.48), Vector3(x * 0.37, 0, 0.02), wing_c)
			var tip := Node3D.new()
			tip.position = Vector3(x * 0.74, 0, 0)
			w.add_child(tip)
			Birds._flat(tip, Vector3(0.55, 0.035, 0.40), Vector3(x * 0.26, 0, 0.04), wing_c)
			# splayed "fingers" at the tip
			for k in 4:
				Birds._flat(tip, Vector3(0.22, 0.03, 0.06), Vector3(x * 0.6, 0, -0.1 + k * 0.1), tip_c, Vector3(0, x * (k - 1.5) * 6.0, 0))
			w.set_meta("tip", tip)
			_wings.append(w)
		Birds.bake_tree(self, false)
		_ang = randf() * TAU
		_rad = randf_range(35.0, 60.0)
		_alt = randf_range(45.0, 70.0)
		scale = Vector3.ONE * (1.25 if kind == "eagle" else 1.0)

	func _process(delta: float) -> void:
		if island == null:
			return
		var spd := 11.0
		_ang += delta * spd / _rad
		var ground := maxf(island.height_at(center.x, center.z), Tide.level)
		var p := center + Vector3(cos(_ang) * _rad, 0, sin(_ang) * _rad)
		p.y = ground + _alt + sin(_ang * 0.7) * 6.0
		var before := global_position
		global_position = p
		if delta > 0.0:
			var v := (p - before) / delta
			if v.length() > 0.5:
				_vel = v
		# circling: lean in toward the centre
		var inward := center - p
		inward.y = 0.0
		Birds._orient(self, _vel, inward.normalized() * spd * spd / _rad, scale.x)
		_flap_t -= delta
		if _flap_t <= 0.0:
			_flap_t = randf_range(6.0, 14.0)
			_flap = randf_range(1.0, 2.0)
		_flap -= delta
		var flapping := _flap > 0.0
		_phase += delta * (6.0 if flapping else 1.0)
		var a := sin(_phase) * 0.45 if flapping else 0.08 + sin(_phase) * 0.03
		for i in _wings.size():
			var sgn := -1.0 if i == 0 else 1.0
			_wings[i].rotation.z = -sgn * a
			(_wings[i].get_meta("tip") as Node3D).rotation.z = -sgn * (sin(_phase - 0.7) * 0.25 if flapping else 0.06)

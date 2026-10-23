class_name WorldBuilder
extends Node3D
## Turns IslandData into visible meshes, collision, water, vegetation and landmarks.

const CHUNK := 64
const TERRAIN_LAYER := 1
const COVER_CHUNK := 32          ## ground cover chunk size in cells (80 m)
const COVER_RANGE := 150.0       ## grass tufts fade out beyond this distance

var data: IslandData
var _tree_body: RID
var _tree_shape: CylinderShape3D
var _sea: MeshInstance3D
var _surf: MeshInstance3D


func build(d: IslandData) -> void:
	data = d
	_build_terrain()
	_build_collision()
	_build_water()
	_build_vegetation()
	_build_ground_cover()
	_build_wrecks()
	_build_lighthouses()
	_build_jetties()
	_build_structures()
	for h in data.dingo_homes:
		var dog := Dingo.new()
		dog.home = h
		add_child(dog)
	# roos and birds around wherever people are (the online server runs them without
	# meshes and tells everyone where they are; it lives at World/Wildlife everywhere)
	var wild := Wildlife.new()
	wild.name = "Wildlife"
	wild.island = data
	add_child(wild)
	if data.plane_f >= 0.0:
		var plane := Ambient.BeachPlane.new()
		plane.island = data
		var z := data.f_to_z(data.plane_f)
		var x := data.east_base(data.plane_f) - 12.0
		plane.touchdown = Vector3(x, data.height_at(x, z), z)
		plane.dir = Vector3(0, 0, -1)
		add_child(plane)
	if not data.dolphin_spot.is_empty():
		var dol := Ambient.Dolphins.new()
		dol.island = data
		var f: float = data.dolphin_spot[0]
		dol.position = Vector3(data.resolve_x(f, data.dolphin_spot[1], int(data.dolphin_spot[2])), 0, data.f_to_z(f))
		add_child(dol)
	_build_signs()
	_build_clouds()


## Moves the sea and surf foam to the current tide level.
func set_sea_level(y: float) -> void:
	if _sea:
		_sea.position.y = y
	if _surf:
		# the waterline creeps up / down the beach (slope ~1 in 30) as the tide moves
		_surf.position = Vector3(-y / 0.034, y, 0.0)


func _exit_tree() -> void:
	if _tree_body.is_valid():
		PhysicsServer3D.free_rid(_tree_body)


# ------------------------------------------------------------- colours
## Bright cartoon palette.
static func surface_color(sf: int, s: float, h: float) -> Color:
	match sf:
		IslandData.Surface.OCEAN:
			return Color(0.95, 0.88, 0.62)
		IslandData.Surface.WET_SAND:
			return Color(0.82, 0.72, 0.55).lerp(Color(0.93, 0.84, 0.66), clampf(s * 2.0, 0.0, 1.0))
		IslandData.Surface.DRY_SAND:
			return Color(0.98, 0.90, 0.70).lerp(Color(1.0, 0.97, 0.86), clampf((s - 0.5) * 2.5, 0.0, 1.0))
		IslandData.Surface.SOFT_DUNE:
			return Color(1.0, 0.97, 0.86)
		IslandData.Surface.TRACK:
			# softer = paler and fluffier; firmer = darker and packed
			return Color(0.80, 0.62, 0.40).lerp(Color(1.0, 0.92, 0.74), clampf(s, 0.0, 1.0))
		IslandData.Surface.FOREST:
			return Color(0.40, 0.70, 0.28).lerp(Color(0.30, 0.58, 0.24), clampf(fmod(h * 0.21, 1.0), 0.0, 1.0))
		IslandData.Surface.ROCK:
			# low beach rock is dark coffee rock; high headlands go reddish
			return Color(0.30, 0.21, 0.16).lerp(Color(0.62, 0.42, 0.36), clampf((h - 3.0) / 8.0, 0.0, 1.0))
		IslandData.Surface.LAKE_BED:
			return Color(0.96, 0.96, 0.90)
		IslandData.Surface.LAKE_SAND:
			return Color(1.0, 1.0, 0.97)
		IslandData.Surface.WEST_FLATS:
			return Color(0.72, 0.68, 0.48)
		IslandData.Surface.COLOURED_SAND:
			# stripy cartoon cliffs
			var bands := [Color(0.95, 0.45, 0.25), Color(1.0, 0.75, 0.40), Color(0.85, 0.30, 0.25), Color(1.0, 0.90, 0.60)]
			return bands[int(floor(h * 0.9)) % bands.size()]
	return Color.MAGENTA


func _vertex_color(i: int) -> Color:
	var sf := data.surf[i]
	var col := surface_color(sf, data.soft[i], data.heights[i])
	var t := data.track[i]
	if t > 0.02 and sf != IslandData.Surface.TRACK and sf != IslandData.Surface.ROCK:
		col = col.lerp(surface_color(IslandData.Surface.TRACK, data.soft[i], 0.0), t * 0.85)
	var hsh := float((i * 73856093) & 0xffff) / 65535.0
	return col * (0.96 + hsh * 0.06)


## Shader detail weights per vertex: x = sand grain amount, y = wind ripple amount.
func _vertex_detail(i: int) -> Vector2:
	var sf := data.surf[i]
	var s := data.soft[i]
	var t := data.track[i]
	var grain := 0.0
	var ripple := 0.0
	match sf:
		IslandData.Surface.WET_SAND, IslandData.Surface.OCEAN, IslandData.Surface.WEST_FLATS:
			grain = 0.45   # packed and smooth
		IslandData.Surface.DRY_SAND, IslandData.Surface.SOFT_DUNE:
			grain = 1.0
			ripple = smoothstep(0.35, 0.8, s)
		IslandData.Surface.TRACK, IslandData.Surface.LAKE_SAND, IslandData.Surface.LAKE_BED:
			grain = 1.0
		IslandData.Surface.COLOURED_SAND:
			grain = 0.5
	if sf != IslandData.Surface.ROCK:
		grain = maxf(grain, t)   # sand tracks through the bush
	ripple *= 1.0 - clampf(t * 1.5, 0.0, 1.0)   # tracks are churned, no ripples
	return Vector2(grain, ripple)


# ------------------------------------------------------------- terrain
func _make_terrain_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/terrain_toon.gdshader")
	return m


func _build_terrain() -> void:
	var mat := _make_terrain_material()
	var cols := data.cols
	var rows := data.rows
	var cell := IslandData.CELL
	var h := data.heights
	for r0 in range(0, rows - 1, CHUNK):
		for c0 in range(0, cols - 1, CHUNK):
			var c1 := mini(c0 + CHUNK, cols - 1)
			var r1 := mini(r0 + CHUNK, rows - 1)
			var w := c1 - c0 + 1
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			var colors := PackedColorArray()
			var detail := PackedVector2Array()
			var detail2 := PackedVector2Array()
			var indices := PackedInt32Array()
			for r in range(r0, r1 + 1):
				for c in range(c0, c1 + 1):
					var i := r * cols + c
					verts.append(Vector3(data.x_min + c * cell, h[i], data.z_min + r * cell))
					var hl := h[i - 1] if c > 0 else h[i]
					var hr := h[i + 1] if c < cols - 1 else h[i]
					var hu := h[i - cols] if r > 0 else h[i]
					var hd := h[i + cols] if r < rows - 1 else h[i]
					norms.append(Vector3(hl - hr, 2.0 * cell, hu - hd).normalized())
					colors.append(_vertex_color(i))
					detail.append(_vertex_detail(i))
					var grassy := 1.0 if data.surf[i] == IslandData.Surface.FOREST else 0.0
					detail2.append(Vector2(grassy * (1.0 - clampf(data.track[i] * 1.5, 0.0, 1.0)), 0.0))
			for r in range(r1 - r0):
				for c in range(c1 - c0):
					var a := r * w + c
					indices.append(a)
					indices.append(a + 1)
					indices.append(a + w)
					indices.append(a + 1)
					indices.append(a + w + 1)
					indices.append(a + w)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = colors
			arrays[Mesh.ARRAY_TEX_UV] = detail
			arrays[Mesh.ARRAY_TEX_UV2] = detail2
			arrays[Mesh.ARRAY_INDEX] = indices
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, mat)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.name = "Terrain_%d_%d" % [c0, r0]
			add_child(mi)


func _build_collision() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = data.cols
	shape.map_depth = data.rows
	shape.map_data = data.heights
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = TERRAIN_LAYER
	body.collision_mask = 0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	body.physics_material_override = pm
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(IslandData.CELL, 1.0, IslandData.CELL)
	cs.position = Vector3(
		data.x_min + (data.cols - 1) * IslandData.CELL * 0.5,
		0.0,
		data.z_min + (data.rows - 1) * IslandData.CELL * 0.5)
	body.add_child(cs)
	add_child(body)


# ------------------------------------------------------------- water
func _build_water() -> void:
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(9000, 9000)
	sea.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.72, 0.85, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mat.roughness = 0.12
	mat.metallic_specular = 0.7
	sea.material_override = mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	_sea = sea
	_build_surf()

	for l in data.lakes:
		var mi := MeshInstance3D.new()
		mi.name = String(l["name"]).replace(" ", "")
		var cm := CylinderMesh.new()
		cm.top_radius = float(l["r"]) + 0.5
		cm.bottom_radius = cm.top_radius
		cm.height = 0.02
		cm.radial_segments = 48
		mi.mesh = cm
		var c: Color = l["color"]
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(c.r, c.g, c.b, 0.8).lightened(0.15)
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lm.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
		lm.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		lm.roughness = 0.12
		lm.metallic_specular = 0.7
		mi.material_override = lm
		mi.position = Vector3(l["x"], l["level"], l["z"])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


## White cartoon foam lines along the surf beach.
func _build_surf() -> void:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var lines := [[-1.5, 2.5, 0.9], [-9.0, -6.5, 0.6], [-18.0, -16.0, 0.45]]
	for ln in lines:
		var a: float = ln[0]
		var b: float = ln[1]
		var alpha: float = ln[2]
		var step := 0.004
		var f := 0.03
		while f < 0.97:
			var f2 := f + step
			var z1 := data.f_to_z(f)
			var z2 := data.f_to_z(f2)
			var x1 := data.east_x(f)
			var x2 := data.east_x(f2)
			var wob1 := sin(f * 900.0) * 1.2
			var wob2 := sin(f2 * 900.0) * 1.2
			var p1 := Vector3(x1 + a + wob1, 0.03, z1)
			var p2 := Vector3(x1 + b + wob1, 0.03, z1)
			var p3 := Vector3(x2 + a + wob2, 0.03, z2)
			var p4 := Vector3(x2 + b + wob2, 0.03, z2)
			verts.append_array([p1, p3, p2, p2, p3, p4])
			var c := Color(1, 1, 1, alpha)
			cols.append_array([c, c, c, c, c, c])
			f = f2
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "SurfFoam"
	_surf = mi
	mi.mesh = am
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ------------------------------------------------------------- vegetation
## Cartoon trees: tapered trunks with puffy round canopies, or stacked cone pines.
## Visuals are MultiMeshes (unit meshes, scaled + coloured per instance).
## Collision uses raw PhysicsServer shapes on one static body (fast).
func _build_vegetation() -> void:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.32
	trunk_mesh.bottom_radius = 0.5
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 10
	trunk_mesh.rings = 1
	var puff := _puff_mesh()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.5
	cone.height = 1.0
	cone.radial_segments = 14
	cone.rings = 2
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed + 7

	var trunks: Array[Transform3D] = []
	var trunk_cols: Array[Color] = []
	var leaves: Array[Transform3D] = []
	var leaf_cols: Array[Color] = []
	var pines: Array[Transform3D] = []
	var pine_cols: Array[Color] = []
	var greens := [Color(0.30, 0.70, 0.20), Color(0.42, 0.80, 0.25), Color(0.20, 0.56, 0.24), Color(0.56, 0.84, 0.28)]

	_tree_shape = CylinderShape3D.new()
	_tree_shape.radius = 0.4
	_tree_shape.height = 6.0
	_tree_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_tree_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_space(_tree_body, get_world_3d().space)
	PhysicsServer3D.body_set_collision_layer(_tree_body, 4)
	PhysicsServer3D.body_set_collision_mask(_tree_body, 0)

	for t in data.trees:
		var sc := t.w
		var base := Vector3(t.x, t.y - 0.4, t.z)
		var yaw := rng.randf() * TAU
		var kind := rng.randi() % 3
		var trunk_h := (5.0 + rng.randf() * 4.0) * sc
		var tw := 0.55 * sc
		var by := Basis(Vector3.UP, yaw)
		trunks.append(Transform3D(by.scaled(Vector3(tw, trunk_h, tw)), base + Vector3.UP * trunk_h * 0.5))
		trunk_cols.append(Color(0.55, 0.40, 0.28) if kind != 1 else Color(0.85, 0.82, 0.75))  # brown, or white gum
		var top := base + Vector3.UP * trunk_h
		var g: Color = greens[rng.randi() % greens.size()]
		match kind:
			0:  # stacked cone "pine" / kauri
				var sizes := [3.8, 2.9, 1.9]
				var y := top.y - 0.6
				for k in sizes.size():
					var s2: float = sizes[k] * sc
					pines.append(Transform3D(by.scaled(Vector3(s2, s2 * 0.95, s2)), Vector3(top.x, y, top.z)))
					pine_cols.append(g.darkened(0.12).lightened(0.07 * k))
					y += s2 * 0.5
			_:  # puffy gum / satinay: a big round canopy of overlapping blobs
				for k in 4 + rng.randi() % 3:
					var s3 := (2.2 + rng.randf() * 1.8) * sc
					var off := Vector3(rng.randf_range(-1.5, 1.5), rng.randf_range(-0.3, 1.6), rng.randf_range(-1.5, 1.5)) * sc
					var yb := Basis(Vector3.UP, rng.randf() * TAU)
					leaves.append(Transform3D(yb.scaled(Vector3(s3, s3 * 0.85, s3)), top + off))
					# higher blobs catch more sun
					leaf_cols.append(g.lightened(0.04 + rng.randf() * 0.08 + off.y / sc * 0.04))
		PhysicsServer3D.body_add_shape(_tree_body, _tree_shape.get_rid(), Transform3D(Basis.IDENTITY, base + Vector3.UP * 3.0))

	_add_multimesh("TreeTrunks", trunk_mesh, trunks, trunk_cols)
	_add_multimesh("TreeLeaves", puff, leaves, leaf_cols)
	_add_multimesh("TreePines", cone, pines, pine_cols)

	# dune scrub / pandanus-ish clumps (no collision)
	var sx: Array[Transform3D] = []
	var scol: Array[Color] = []
	for s in data.scrub:
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		var w := s.w * 1.3
		sx.append(Transform3D(b.scaled(Vector3(w, w * 0.6, w)), Vector3(s.x, s.y + w * 0.15, s.z)))
		scol.append(Color(0.52, 0.76, 0.26).lerp(Color(0.78, 0.84, 0.32), rng.randf()))
	_add_multimesh("Scrub", puff, sx, scol)
	# chunky dark boulders on the coffee-rock bars
	var rx: Array[Transform3D] = []
	var rcol: Array[Color] = []
	for rp in data.rock_pieces:
		var b := Basis.from_euler(Vector3(rng.randf() * 0.6, rng.randf() * TAU, rng.randf() * 0.6))
		var sz := rp.w
		rx.append(Transform3D(b.scaled(Vector3(sz * 1.2, sz * 0.9, sz)), Vector3(rp.x, rp.y + sz * 0.1, rp.z)))
		rcol.append(Color(0.28, 0.19, 0.14).lerp(Color(0.42, 0.30, 0.22), rng.randf()))
	if not rx.is_empty():
		_add_multimesh("CoffeeRocks", Toon.rounded_box(Vector3.ONE), rx, rcol)
	_build_palms(rng)


## Piccabeen palms in the rainforest: a slim trunk and a crown of drooping fronds.
func _build_palms(rng: RandomNumberGenerator) -> void:
	if data.palms.is_empty():
		return
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.35
	trunk.bottom_radius = 0.5
	trunk.height = 1.0
	trunk.radial_segments = 8
	trunk.rings = 1
	var frond := _puff_mesh()
	var tx: Array[Transform3D] = []
	var tc: Array[Color] = []
	var fx: Array[Transform3D] = []
	var fc: Array[Color] = []
	for p in data.palms:
		var h := (7.0 + rng.randf() * 4.0) * p.w
		var lean := Basis(Vector3.RIGHT, rng.randf_range(-0.08, 0.08)) * Basis(Vector3.FORWARD, rng.randf_range(-0.08, 0.08))
		var base := Vector3(p.x, p.y - 0.3, p.z)
		tx.append(Transform3D(lean.scaled(Vector3(0.32, h, 0.32)), base + lean * Vector3.UP * h * 0.5))
		tc.append(Color(0.52, 0.48, 0.40))
		var top := base + lean * Vector3.UP * h
		var n := 8
		var spin := rng.randf() * TAU
		for k in n:
			var a := spin + TAU * k / n
			var droop := 0.35 + rng.randf() * 0.25
			var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -droop)
			var len := 2.6 * p.w
			fx.append(Transform3D(b.scaled(Vector3(0.55, 0.10, len)), top + b * Vector3(0, 0, -len * 0.45)))
			fc.append(Color(0.24, 0.58, 0.20).lerp(Color(0.40, 0.70, 0.22), rng.randf()))
	_add_multimesh("PalmTrunks", trunk, tx, tc)
	_add_multimesh("PalmFronds", frond, fx, fc)


## Timber jetties out into the bay. Solid, so you can walk - or drive - out on them.
func _build_jetties() -> void:
	var wood := Color(0.62, 0.45, 0.30)
	var post := Color(0.42, 0.30, 0.20)
	for j in data.jetty_list:
		var start: Vector3 = j["start"]
		var dir: Vector3 = j["dir"]
		var length: float = j["length"]
		var deck_y := 1.6
		var ramp_len := 7.0
		var yaw := atan2(-dir.x, -dir.z)        # local -Z points out to sea
		var body := StaticBody3D.new()
		body.name = "Jetty"
		body.collision_layer = TERRAIN_LAYER
		add_child(body)
		var mid := start + dir * (ramp_len + length * 0.5)
		body.position = Vector3(mid.x, deck_y, mid.z)
		body.rotation.y = yaw
		Toon.box(body, Vector3(3.0, 0.2, length), Vector3(0, -0.1, 0), wood)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(3.0, 0.2, length)
		cs.shape = bs
		cs.position = Vector3(0, -0.1, 0)
		body.add_child(cs)
		for k in int(length / 3.0) + 1:
			var z := -length * 0.5 + k * 3.0
			for x in [-1.35, 1.35]:
				Props._cyl(body, 0.13, 0.13, 6.0, Vector3(x, -3.0, z), post)
				Toon.box(body, Vector3(0.1, 0.9, 0.1), Vector3(x, 0.45, z), post)
		for x in [-1.42, 1.42]:
			Toon.box(body, Vector3(0.08, 0.08, length), Vector3(x, 0.92, 0), wood.lightened(0.1))
		# ramp up from the sand to the deck
		var drop := deck_y - start.y
		var rl := sqrt(drop * drop + ramp_len * ramp_len)
		var ramp := StaticBody3D.new()
		ramp.collision_layer = TERRAIN_LAYER
		add_child(ramp)
		var rc := start + dir * ramp_len * 0.5
		ramp.position = Vector3(rc.x, (deck_y + start.y) * 0.5 - 0.1, rc.z)
		ramp.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, atan2(drop, ramp_len))
		Toon.box(ramp, Vector3(3.0, 0.2, rl), Vector3.ZERO, wood)
		var rcs := CollisionShape3D.new()
		var rbs := BoxShape3D.new()
		rbs.size = Vector3(3.0, 0.2, rl)
		rcs.shape = rbs
		ramp.add_child(rcs)


## Little buildings: WWII bunkers, beach huts, township shops.
func _build_structures() -> void:
	for st in data.structure_list:
		var body := StaticBody3D.new()
		body.collision_layer = 4
		add_child(body)
		body.position = st["pos"] + Vector3(0, -0.3, 0)
		body.rotation.y = st["yaw"]
		var size := Vector3.ONE
		match st["kind"]:
			"bunker":
				var con := Color(0.66, 0.65, 0.60)
				size = Vector3(6.0, 2.4, 5.0)
				Toon.box(body, size, Vector3(0, 1.2, 0), con)
				Toon.box(body, Vector3(3.6, 0.35, 0.3), Vector3(0, 1.75, -2.52), Color(0.12, 0.12, 0.12))   # gun slit
				Props._cyl(body, 2.2, 2.4, 0.9, Vector3(0, 0.45, -5.5), con.darkened(0.08))                  # gun pit ring
				Props._cyl(body, 1.7, 1.7, 0.95, Vector3(0, 0.5, -5.5), Color(0.45, 0.42, 0.38))
			"hut":
				var wall := Color(0.95, 0.88, 0.70)
				size = Vector3(5.0, 2.6, 4.0)
				Toon.box(body, size, Vector3(0, 1.3, 0), wall)
				var roof := Node3D.new()
				roof.position = Vector3(0, 2.6, 0)
				body.add_child(roof)
				Toon.prism_x(roof, 5.6, PackedVector2Array([Vector2(-2.4, 0.0), Vector2(2.4, 0.0), Vector2(0.0, 1.4)]), Color(0.75, 0.25, 0.20))
				Toon.box(body, Vector3(1.0, 1.9, 0.08), Vector3(0, 0.95, -2.02), Color(0.35, 0.55, 0.75))
				for x in [-1.6, 1.6]:
					Toon.box(body, Vector3(0.9, 0.8, 0.08), Vector3(x, 1.55, -2.02), Color(0.55, 0.80, 0.95))
			"shop":
				var wall := Color(0.98, 0.95, 0.90)
				size = Vector3(9.0, 3.2, 6.0)
				Toon.box(body, size, Vector3(0, 1.6, 0), wall)
				Toon.box(body, Vector3(9.4, 0.25, 7.0), Vector3(0, 3.3, -0.4), Color(0.20, 0.45, 0.65))   # flat roof
				Toon.box(body, Vector3(9.0, 0.12, 2.2), Vector3(0, 2.7, -4.0), Color(0.95, 0.75, 0.15))    # awning
				for x in [-4.2, 4.2]:
					Toon.box(body, Vector3(0.15, 2.7, 0.15), Vector3(x, 1.35, -5.0), Color(0.5, 0.4, 0.3))
				Toon.box(body, Vector3(4.0, 0.7, 0.1), Vector3(0, 2.7, -3.06), Color(0.85, 0.20, 0.15))   # sign board
				for x in [-2.6, 2.6]:
					Toon.box(body, Vector3(2.0, 1.4, 0.08), Vector3(x, 1.4, -3.02), Color(0.55, 0.80, 0.95))
				Toon.box(body, Vector3(1.4, 2.1, 0.08), Vector3(0, 1.05, -3.02), Color(0.35, 0.55, 0.75))
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = Vector3(0, size.y * 0.5, 0)
		body.add_child(cs)


## Unit-diameter blob for canopies, bushes and clouds.
func _puff_mesh() -> SphereMesh:
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 14
	sm.rings = 7
	return sm


## Grass tufts and wildflowers on the bush floor. Purely visual (no collision),
## split into chunks so each one is culled and faded out with distance.
func _build_ground_cover() -> void:
	var tuft := _make_tuft_mesh()
	var flower := SphereMesh.new()
	flower.radius = 0.5
	flower.height = 1.0
	flower.radial_segments = 8
	flower.rings = 4
	var grass_mat := StandardMaterial3D.new()
	grass_mat.vertex_color_use_as_albedo = true
	grass_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	grass_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	grass_mat.roughness = 1.0
	grass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var flower_cols := [Color(1.0, 1.0, 0.95), Color(1.0, 0.85, 0.15), Color(0.75, 0.45, 0.95), Color(1.0, 0.55, 0.70)]
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed + 11
	var cols := data.cols
	var cell := IslandData.CELL
	var root := Node3D.new()
	root.name = "GroundCover"
	add_child(root)
	for r0 in range(0, data.rows - 1, COVER_CHUNK):
		for c0 in range(0, cols - 1, COVER_CHUNK):
			var tx: Array[Transform3D] = []
			var tc: Array[Color] = []
			var fx: Array[Transform3D] = []
			var fc: Array[Color] = []
			for r in range(r0, mini(r0 + COVER_CHUNK, data.rows - 1)):
				for c in range(c0, mini(c0 + COVER_CHUNK, cols - 1)):
					var i := r * cols + c
					if data.surf[i] != IslandData.Surface.FOREST or data.track[i] > 0.05:
						continue
					var base := surface_color(IslandData.Surface.FOREST, data.soft[i], data.heights[i])
					for k in rng.randi_range(0, 2):
						var x := data.x_min + (c + rng.randf()) * cell
						var z := data.z_min + (r + rng.randf()) * cell
						var w := rng.randf_range(0.45, 0.8)
						var h := rng.randf_range(0.45, 0.95)
						var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w))
						tx.append(Transform3D(b, Vector3(x, data.height_at(x, z) - 0.05, z)))
						tc.append(base.lerp(Color(0.28, 0.62, 0.16), 0.35 + rng.randf() * 0.4).lerp(Color(0.70, 0.80, 0.30), rng.randf() * 0.2))
						if rng.randf() < 0.12:
							var fs := rng.randf_range(0.13, 0.2)
							var fp := Vector3(x + rng.randf_range(-0.1, 0.1), 0.0, z + rng.randf_range(-0.1, 0.1))
							fp.y = data.height_at(fp.x, fp.z) + h * 0.75
							fx.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(fs, fs * 0.6, fs)), fp))
							fc.append(flower_cols[rng.randi() % flower_cols.size()])
			if tx.is_empty():
				continue
			var mi := _cover_multimesh(root, "Grass_%d_%d" % [c0, r0], tuft, tx, tc)
			mi.material_override = grass_mat
			if not fx.is_empty():
				_cover_multimesh(root, "Flowers_%d_%d" % [c0, r0], flower, fx, fc).material_override = Toon.vcol_mat()


func _cover_multimesh(parent: Node3D, nm: String, mesh: Mesh, xforms: Array[Transform3D], cols: Array[Color]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_color(k, cols[k])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = COVER_RANGE
	mi.visibility_range_end_margin = 30.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(mi)
	return mi


## A cartoon clump of 6 pointy blades, 1 m tall / 1 m wide before scaling.
## Normals all point up so the clump is lit like the ground it sits on;
## vertex colours darken the roots so clumps read against the floor.
func _make_tuft_mesh() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var root_col := Color(0.55, 0.55, 0.55)
	var tip_col := Color(1.0, 1.0, 1.0)
	for k in 6:
		var a := TAU * k / 6.0 + (0.3 if k % 2 else 0.0)
		var out := Vector3(cos(a), 0.0, sin(a))
		var side := out.cross(Vector3.UP) * 0.15
		var lean := 0.2 + 0.25 * float(k % 3)
		var foot := out * 0.12
		var tip := out * lean + Vector3.UP * (0.75 + 0.25 * float((k * 7) % 3) / 2.0)
		verts.append_array([foot - side, foot + side, tip])
		norms.append_array([Vector3.UP, Vector3.UP, Vector3.UP])
		colors.append_array([root_col, root_col, tip_col])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _add_multimesh(nm: String, mesh: Mesh, xforms: Array[Transform3D], cols: Array[Color]) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for k in xforms.size():
		mm.set_instance_transform(k, xforms[k])
		mm.set_instance_color(k, cols[k])
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.material_override = Toon.vcol_mat()
	add_child(mi)


# ------------------------------------------------------------- landmarks
## Cartoon rusty hulls (SS Maheno on Fraser, Tangalooma / Bulwer wrecks on Moreton).
func _build_wrecks() -> void:
	var rust := Color(0.72, 0.32, 0.15)
	var dark := Color(0.30, 0.14, 0.08)
	# solid pieces (with collision): hull with a pointed bow, broken deck house, funnel stump
	var parts := [
		[Vector3(0, 2.2, 1.5), Vector3(5.5, 4.4, 27.0), rust],
		[Vector3(0, 2.0, -13.0), Vector3(3.6, 4.0, 3.0), rust.darkened(0.08)],     # bow taper
		[Vector3(0, 1.8, -15.3), Vector3(1.8, 3.6, 2.0), rust.darkened(0.12)],
		[Vector3(0, 4.9, -2.0), Vector3(3.8, 1.4, 10.0), rust.darkened(0.15)],     # deck house
		[Vector3(-0.8, 6.0, -4.5), Vector3(1.6, 0.9, 3.0), rust.lightened(0.05)],  # broken upper level
		[Vector3(0, 6.1, 6.5), Vector3(1.8, 2.6, 1.8), rust.lightened(0.1)],       # funnel stump
		[Vector3(0, 4.7, 12.0), Vector3(4.6, 1.0, 4.0), rust.darkened(0.2)],       # stern deck
	]
	for k in data.wrecks.size():
		var w: Dictionary = data.wrecks[k]
		var sc: float = w["scale"]
		var root := StaticBody3D.new()
		root.name = "Wreck_%d" % k
		root.collision_layer = TERRAIN_LAYER
		root.position = w["pos"]
		root.rotation = Vector3(0, w["yaw"], w["roll"])
		for p in parts:
			var size: Vector3 = p[1] * sc
			var pos: Vector3 = p[0] * sc
			Toon.box(root, size, pos, p[2])
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = size
			cs.shape = bs
			cs.position = pos
			root.add_child(cs)
		# detail (no collision): rows of portholes, rust streaks, holes torn in the plates
		for side in [-1.0, 1.0]:
			for row in [3.3, 2.3]:
				for i in 11:
					var z := -10.0 + i * 2.3
					var port := Props._cyl(root, 0.22 * sc, 0.22 * sc, 0.12 * sc, Vector3(side * 2.76 * sc, row * sc, z * sc), dark, Vector3(0, 0, 90))
					port.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for i in 6:
				var z := -9.0 + i * 4.1
				Toon.box(root, Vector3(0.06, 1.6, 0.35) * sc, Vector3(side * 2.77, 1.6, z) * sc, Color(0.55, 0.22, 0.10), false)
			Toon.box(root, Vector3(0.08, 1.6, 4.0) * sc, Vector3(side * 2.78, 1.4, 5.0 - side * 6.0) * sc, Color(0.18, 0.09, 0.05), false)
		# jagged broken plates along the top edge
		for i in 9:
			var z := -11.0 + i * 3.0
			var hgt := 0.4 + float((i * 37) % 7) * 0.12
			for side in [-1.0, 1.0]:
				Toon.box(root, Vector3(0.12, hgt, 1.4) * sc, Vector3(side * 2.68, 4.4 + hgt * 0.5, z) * sc, rust.darkened(0.05 * (i % 3)), false, Vector3(0, 0, side * 8.0))
		add_child(root)


## Chunky white lighthouse with a red cap and a glowing lamp.
func _build_lighthouses() -> void:
	for lp in data.lighthouses:
		var root := StaticBody3D.new()
		root.name = "Lighthouse"
		root.collision_layer = TERRAIN_LAYER
		root.position = lp + Vector3(0, -0.5, 0)
		add_child(root)
		var white := Color(0.97, 0.96, 0.92)
		var tiers := [[3.6, 5.0], [3.0, 5.0], [2.5, 4.5]]
		var y := 0.0
		for t in tiers:
			var w: float = t[0]
			var h: float = t[1]
			Toon.box(root, Vector3(w, h, w), Vector3(0, y + h * 0.5, 0), white)
			y += h
		Toon.box(root, Vector3(3.2, 0.3, 3.2), Vector3(0, y + 0.15, 0), Color(0.15, 0.15, 0.16))   # gallery
		Toon.box(root, Vector3(1.8, 1.6, 1.8), Vector3(0, y + 1.1, 0), Color(1.0, 0.95, 0.6), true, Vector3.ZERO, true)
		Toon.box(root, Vector3(2.3, 1.0, 2.3), Vector3(0, y + 2.4, 0), Color(0.85, 0.15, 0.12))
		Toon.box(root, Vector3(0.3, 0.8, 0.3), Vector3(0, y + 3.3, 0), Color(0.15, 0.15, 0.16))
		Toon.box(root, Vector3(1.4, 2.0, 0.12), Vector3(0, 1.0, 1.82), Color(0.2, 0.45, 0.75), false)   # door
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(3.6, y, 3.6)
		cs.shape = bs
		cs.position = Vector3(0, y * 0.5, 0)
		root.add_child(cs)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0, y + 1.1, 0)
		lamp.light_color = Color(1.0, 0.9, 0.6)
		lamp.light_energy = 2.0
		lamp.omni_range = 18.0
		root.add_child(lamp)


func _build_signs() -> void:
	for p in data.places:
		var pos: Vector3 = p["pos"]
		var sign := Node3D.new()
		sign.position = pos + Vector3(-3.0, -0.2, 0.0)
		add_child(sign)
		Toon.box(sign, Vector3(0.25, 3.0, 0.25), Vector3(0, 1.5, 0), Color(0.50, 0.33, 0.20))
		Toon.box(sign, Vector3(0.18, 1.0, 2.6), Vector3(0, 2.7, 0), Color(0.80, 0.58, 0.35))
		var l := Label3D.new()
		l.text = p["name"]
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font_size = 72
		l.pixel_size = 0.011
		l.outline_size = 26
		l.outline_modulate = Color(0.15, 0.10, 0.05)
		l.modulate = Color(1, 0.95, 0.75)
		l.visibility_range_end = 450.0
		l.position = Vector3(0, 4.6, 0)
		sign.add_child(l)


func _build_clouds() -> void:
	var clouds := Node3D.new()
	clouds.name = "Clouds"
	clouds.set_script(preload("res://scripts/world/cloud_drift.gd"))
	add_child(clouds)
	var rng := RandomNumberGenerator.new()
	rng.seed = data.seed + 11
	var puff := _puff_mesh()
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(1, 1, 1)
	cloud_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	cloud_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	cloud_mat.emission_enabled = true
	cloud_mat.emission = Color(0.55, 0.62, 0.75)   # bright, slightly blue undersides
	cloud_mat.rim_enabled = true
	cloud_mat.rim = 0.6
	for i in 45:
		var c := Node3D.new()
		c.position = Vector3(rng.randf_range(-900, 900), rng.randf_range(110, 170), rng.randf_range(-2300, 2300))
		clouds.add_child(c)
		for k in 3 + rng.randi() % 4:
			var d := rng.randf_range(16, 30)
			var b := MeshInstance3D.new()
			b.mesh = puff
			b.material_override = cloud_mat
			b.scale = Vector3(d * 1.3, d * 0.75, d)
			b.position = Vector3(rng.randf_range(-18, 18), rng.randf_range(-1, 5), rng.randf_range(-12, 12))
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			c.add_child(b)

class_name Toon
extends RefCounted
## Shared cartoon look (Fortnite-ish): soft wrapped lighting, a bright rim light,
## gentle specular sheen and chunky rounded-edge shapes. No black outlines.
## Everything visual in the game should come through here so the style stays consistent.

const ROUND_MAX := 0.10    ## largest corner radius on rounded boxes (m) - big panels stay crisp
const ROUND_FRAC := 0.22   ## corner radius as a fraction of the box's thinnest side

static var _mats := {}
static var _box_meshes := {}
static var _vcol_mat: StandardMaterial3D


static func _style(m: StandardMaterial3D) -> void:
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.roughness = 0.6
	m.metallic_specular = 0.35
	m.rim_enabled = true
	m.rim = 0.3
	m.rim_tint = 0.6


## Cartoon material for a colour (cached, so the same colour = same material).
static func mat(c: Color, emissive := false) -> StandardMaterial3D:
	var key := "%s_%s" % [c.to_html(), emissive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	_style(m)
	m.albedo_color = c
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 1.5
	_mats[key] = m
	return m


## Cartoon material that takes its colour from vertex / MultiMesh instance colours.
static func vcol_mat() -> StandardMaterial3D:
	if _vcol_mat == null:
		_vcol_mat = StandardMaterial3D.new()
		_style(_vcol_mat)
		_vcol_mat.vertex_color_use_as_albedo = true
		_vcol_mat.metallic_specular = 0.2
	return _vcol_mat


## Adds a rounded-edge box. `outline` is kept for older call sites and ignored.
static func box(parent: Node3D, size: Vector3, pos: Vector3, c: Color, _outline := true, rot_deg := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = rounded_box(size)
	mi.material_override = mat(c, emissive)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


## Solid prism: a convex side profile (z, y) extruded across `width` along X.
## Good for wedges like the space under a raked windscreen. Flat shaded.
static func prism_x(parent: Node3D, width: float, profile: PackedVector2Array, c: Color) -> MeshInstance3D:
	var hw := width * 0.5
	var n := profile.size()
	var centre := Vector2.ZERO
	for p in profile:
		centre += p
	centre /= n
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var add_tri := func(a: Vector3, b: Vector3, d: Vector3, out: Vector3) -> void:
		# Godot front faces wind clockwise seen from outside
		if (b - a).cross(d - a).dot(out) > 0.0:
			verts.append_array([a, d, b])
		else:
			verts.append_array([a, b, d])
		norms.append_array([out, out, out])
	# end caps (fan)
	for sx in [-1.0, 1.0]:
		var out := Vector3(sx, 0, 0)
		for i in range(1, n - 1):
			add_tri.call(Vector3(sx * hw, profile[0].y, profile[0].x), Vector3(sx * hw, profile[i].y, profile[i].x),
				Vector3(sx * hw, profile[i + 1].y, profile[i + 1].x), out)
	# sides along each profile edge
	for i in n:
		var p0 := profile[i]
		var p1 := profile[(i + 1) % n]
		var e := p1 - p0
		var nrm := Vector2(-e.y, e.x).normalized()
		if nrm.dot((p0 + p1) * 0.5 - centre) < 0.0:
			nrm = -nrm
		var out := Vector3(0, nrm.y, nrm.x)
		var a := Vector3(-hw, p0.y, p0.x)
		var b := Vector3(hw, p0.y, p0.x)
		var cc := Vector3(hw, p1.y, p1.x)
		var d := Vector3(-hw, p1.y, p1.x)
		add_tri.call(a, b, cc, out)
		add_tri.call(a, cc, d, out)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c)
	parent.add_child(mi)
	return mi


## Smooth cylinder (e.g. a wheel) lying along X. `sides` is a minimum; `outline` is ignored.
static func cyl_x(parent: Node3D, radius: float, width: float, sides: int, pos: Vector3, c: Color, _outline := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = width
	cm.radial_segments = maxi(sides, 24)
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat(c)
	mi.rotation_degrees = Vector3(0, 0, 90)
	mi.position = pos
	parent.add_child(mi)
	return mi


## Box with rounded edges and corners, centred on the origin (cached per size).
## Built by projecting a box surface onto an inner box grown by the corner radius,
## with extra rows of vertices around the edges so the bevels come out round.
static func rounded_box(size: Vector3) -> ArrayMesh:
	var key := "%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if _box_meshes.has(key):
		return _box_meshes[key]
	var h := size * 0.5
	var r := minf(minf(size.x, minf(size.y, size.z)) * ROUND_FRAC, ROUND_MAX)
	var inner := h - Vector3(r, r, r)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	# 6 faces: (normal axis, u axis, v axis)
	var faces := [[0, 1, 2], [1, 2, 0], [2, 0, 1]]
	for f in faces:
		for sgn in [-1.0, 1.0]:
			var a: int = f[0]
			var ua: int = f[1]
			var va: int = f[2]
			var us := _axis_steps(h[ua], inner[ua])
			var vs := _axis_steps(h[va], inner[va])
			var base := verts.size()
			for v in vs:
				for u in us:
					var p := Vector3.ZERO
					p[a] = h[a] * sgn
					p[ua] = u
					p[va] = v
					var cp := p.clamp(-inner, inner)
					var d := p - cp
					var n := d.normalized() if d.length_squared() > 1e-10 else Vector3.ZERO
					if n == Vector3.ZERO:
						n[a] = sgn
					verts.append(cp + n * r)
					norms.append(n)
			var nu := us.size()
			for j in vs.size() - 1:
				for i in nu - 1:
					var i0 := base + j * nu + i
					var quad := [i0, i0 + 1, i0 + nu, i0 + 1, i0 + nu + 1, i0 + nu]
					for t in 2:
						var t0: int = quad[t * 3]
						var t1: int = quad[t * 3 + 1]
						var t2: int = quad[t * 3 + 2]
						# Godot front faces wind clockwise seen from outside
						var fn := (verts[t1] - verts[t0]).cross(verts[t2] - verts[t0])
						if fn.dot(norms[t0] + norms[t1] + norms[t2]) > 0.0:
							idx.append_array([t0, t2, t1])
						else:
							idx.append_array([t0, t1, t2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_box_meshes[key] = mesh
	return mesh


## Vertex positions along one face axis: dense across the rounded edges, sparse in the flat middle.
static func _axis_steps(half: float, inner: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	const K := 4
	for k in K + 1:
		out.append(lerpf(-half, -inner, float(k) / K))
	if inner > 0.001:
		for k in K + 1:
			out.append(lerpf(inner, half, float(k) / K))
	return out

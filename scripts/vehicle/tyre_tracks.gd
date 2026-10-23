class_name TyreTracks
extends MeshInstance3D
## Draws a ribbon behind each wheel. Darker and wider the deeper the tyre sinks,
## so you can see where you dug in. Lives in world space (top_level).

const MAX_POINTS := 260
const MIN_STEP := 0.6
const WIDTH := 0.30

var _pts: Array = []        # per wheel: Array of [pos, right, depth] or null (gap)
var _last: Array = []       # last added position per wheel
var _dirty := false
var _rebuild_t := 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	mesh = ArrayMesh.new()
	for i in 4:
		_pts.append([])
		_last.append(null)


func clear() -> void:
	for i in 4:
		_pts[i] = []
		_last[i] = null
	_dirty = true


func update_from(car: SandVehicle, delta: float) -> void:
	for i in car.wheels.size():
		var w: SandVehicle.Wheel = car.wheels[i]
		var list: Array = _pts[i]
		if not w.grounded or w.surface == IslandData.Surface.ROCK or w.in_water:
			if list.size() > 0 and list[list.size() - 1] != null:
				list.append(null)
			_last[i] = null
			continue
		var p := w.contact + w.normal * 0.03
		if _last[i] != null and (p - (_last[i] as Vector3)).length() < MIN_STEP:
			continue
		var right := w.fwd.cross(w.normal).normalized()
		var depth := clampf(w.sink / 0.3 + w.soft * 0.25, 0.08, 1.0)
		list.append([p, right, depth])
		_last[i] = p
		while list.size() > MAX_POINTS:
			list.pop_front()
		_dirty = true
	_rebuild_t += delta
	if _dirty and _rebuild_t > 0.12:
		_rebuild()


func _rebuild() -> void:
	_rebuild_t = 0.0
	_dirty = false
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for list in _pts:
		var prev = null
		for e in list:
			if e == null:
				prev = null
				continue
			if prev != null:
				var p0: Vector3 = prev[0]
				var p1: Vector3 = e[0]
				var r0: Vector3 = prev[1]
				var r1: Vector3 = e[1]
				var d0: float = prev[2]
				var d1: float = e[2]
				var w0 := WIDTH * (0.8 + d0 * 0.6)
				var w1 := WIDTH * (0.8 + d1 * 0.6)
				var c0 := Color(0.25, 0.20, 0.13, 0.25 + d0 * 0.45)
				var c1 := Color(0.25, 0.20, 0.13, 0.25 + d1 * 0.45)
				var a := p0 - r0 * w0
				var b := p0 + r0 * w0
				var c := p1 - r1 * w1
				var d := p1 + r1 * w1
				verts.append_array([a, b, c, b, d, c])
				cols.append_array([c0, c0, c1, c0, c1, c1])
			prev = e
	var am := mesh as ArrayMesh
	am.clear_surfaces()
	if verts.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

class_name Wildlife
extends Node3D
## Keeps a little bit of life around wherever you are, without filling the island:
## three small mobs of kangaroos on the grassy flats and bush edges, two flocks of
## seagulls on the beach, and a sea eagle and a brahminy kite circling high up.
## Anything that ends up far behind gets quietly moved to somewhere new ahead of you,
## out of sight. Ambient only - each machine has its own; the online server has none.

const MOBS := [2, 3, 2]          ## kangaroos per mob
const FLOCKS := [6, 5]           ## gulls per flock
const FAR := 380.0               ## past this from the camera: move it somewhere nearer

var island: IslandData
var _mobs: Array = []            ## [{roos: [Kangaroo], center: Vector3, placed: bool}]
var _flocks: Array[Birds.GullFlock] = []
var _soarers: Array[Birds.Soarer] = []
var _tick := 0.0
var _first := true


func _ready() -> void:
	if island == null:
		island = IslandData.instance
	for n in MOBS:
		var mob := {"roos": [], "center": Vector3.ZERO, "placed": false}
		for k in n:
			var r := Kangaroo.new()
			r.island = island
			r.visible = false
			r.set_process(false)
			add_child(r)
			mob["roos"].append(r)
		_mobs.append(mob)
	for n in FLOCKS:
		var f := Birds.GullFlock.new()
		f.island = island
		f.count = n
		add_child(f)
		_flocks.append(f)
	for kind in ["eagle", "kite"]:
		var s := Birds.Soarer.new()
		s.island = island
		s.kind = kind
		s.visible = false
		s.set_process(false)
		add_child(s)
		_soarers.append(s)


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or island == null:
		return
	_tick = 1.5
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	# the first time, things can be a little closer (there's something to see straight away)
	var near := 60.0 if _first else 150.0
	_first = false
	for mob in _mobs:
		var c: Vector3 = mob["center"]
		if mob["placed"] and _flat_dist(c, at) < FAR and _any_near(mob["roos"], at):
			continue
		var p := _roo_spot(at, near, 230.0)
		if p == Vector3.INF:
			continue
		_place_mob(mob, p)
	for f in _flocks:
		if f.placed and (_flat_dist(f.spot, at) < FAR or f._air):
			continue
		var p := _beach_spot(at, near, 220.0)
		if p != Vector3.INF:
			f.place_at(p)
	for s in _soarers:
		if s.is_processing() and _flat_dist(s.center, at) < 450.0:
			continue
		var a := randf() * TAU
		s.center = at + Vector3(cos(a), 0, sin(a)) * randf_range(60.0, 160.0)
		s.visible = true
		s.set_process(true)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _any_near(roos: Array, at: Vector3) -> bool:
	for r in roos:
		if _flat_dist((r as Node3D).global_position, at) < FAR:
			return true
	return false


func _place_mob(mob: Dictionary, p: Vector3) -> void:
	mob["center"] = p
	mob["placed"] = true
	for r in mob["roos"]:
		var roo := r as Kangaroo
		var q := p
		for tries in 6:
			q = p + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
			if _dry(q, 0.2):
				break
		roo.mob_center = p
		roo.global_position = Vector3(q.x, island.height_at(q.x, q.z), q.z)
		roo._set_state("graze")
		roo.visible = true
		roo.set_process(true)


func _dry(p: Vector3, margin: float) -> bool:
	return island.water_level_at(p.x, p.z) < island.height_at(p.x, p.z) - margin


## Grassy flats, bush edges and tracks: where roos would be. INF if nothing suits.
func _roo_spot(at: Vector3, dmin: float, dmax: float) -> Vector3:
	for tries in 40:
		var a := randf() * TAU
		var d := randf_range(dmin, dmax)
		var p := at + Vector3(cos(a) * d, 0, sin(a) * d)
		var f := island.z_to_f(p.z)
		if f < 0.02 or f > 0.98:
			continue
		var s := island.surface_at(p.x, p.z)
		if s != IslandData.Surface.FOREST and s != IslandData.Surface.WEST_FLATS \
				and s != IslandData.Surface.TRACK and s != IslandData.Surface.DRY_SAND:
			continue
		if not _dry(p, 1.0):
			continue
		var h := island.height_at(p.x, p.z)
		if absf(island.height_at(p.x + 4.0, p.z) - h) > 1.6 or absf(island.height_at(p.x, p.z + 4.0) - h) > 1.6:
			continue
		return Vector3(p.x, h, p.z)
	return Vector3.INF


## Open sand on either coast near `at` (gulls sit on the beach). INF if we're far inland.
func _beach_spot(at: Vector3, dmin: float, dmax: float) -> Vector3:
	for tries in 30:
		var dz := randf_range(dmin, dmax) * (1.0 if randf() < 0.5 else -1.0)
		var z := at.z + dz
		var ff := island.z_to_f(z)
		if ff < 0.01 or ff > 0.99:
			continue
		var x := island.east_x(ff) - randf_range(6.0, 40.0) if randf() < 0.75 else island.west_x(ff) + randf_range(6.0, 30.0)
		var p := Vector3(x, 0, z)
		if _flat_dist(p, at) > dmax + 60.0:
			continue
		var s := island.surface_at(p.x, p.z)
		if (s == IslandData.Surface.WET_SAND or s == IslandData.Surface.DRY_SAND) and _dry(p, 0.3):
			return Vector3(p.x, island.height_at(p.x, p.z), p.z)
	return Vector3.INF

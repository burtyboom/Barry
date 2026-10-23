class_name Wildlife
extends Node3D
## Keeps a little bit of life around wherever people are, without filling the island:
## a few small mobs of kangaroos on the grassy flats and bush edges and a couple of
## flocks of seagulls on the beach near each player (shared by players who are close
## together), plus a sea eagle and a brahminy kite circling high up. Anything that ends
## up far from everyone gets quietly moved to somewhere new near someone, out of sight.
##
## Multiplayer: the host / online server (multiplayer.is_server()) runs the roos and
## gulls and sends a compact snapshot to everyone a few times a second; everyone else
## follows (Kangaroo / GullFlock with logic = false). Joiners say hello once their island
## is built and start getting snapshots. The online server builds no meshes at all.
## The birds of prey are just for show: each machine circles its own above its camera.
## Lives at Main/World/Wildlife on every machine (RPC path).

const MOBS := [2, 3, 2]          ## kangaroos per mob, per player
const FLOCKS := [6, 5]           ## gulls per flock, per player
const MAX_MOBS := 9
const MAX_FLOCKS := 6
const FAR := 380.0               ## past this from everyone: move it somewhere nearer
const SEND_HZ := 4.0

var island: IslandData
var threats: Array = []          ## [{pos, speed, horn, car}] every ute and person on foot
var _mobs: Array = []            ## [{roos: [Kangaroo], center: Vector3, placed: bool}]
var _roos: Array[Kangaroo] = []  ## every roo, in a fixed order (snapshot index)
var _flocks: Array[Birds.GullFlock] = []
var _soarers: Array[Birds.Soarer] = []
var _show := true                ## build meshes (not on the online server)
var _main: Node
var _tick := 0.0
var _send_t := 0.0
var _seen := {}                  ## player ids we've already filled around (first fill is closer)
var _peers := {}                 ## host: peers whose island is ready for snapshots
var _last_pos := {}              ## threat speed estimates: node -> last position
var _speeds := {}


func _ready() -> void:
	if island == null:
		island = IslandData.instance
	_main = get_tree().root.get_node_or_null("Main")
	var net := get_node_or_null("/root/Net")
	_show = net == null or not net.dedicated
	if _show:
		for kind in ["eagle", "kite"]:
			var s := Birds.Soarer.new()
			s.island = island
			s.kind = kind
			s.visible = false
			s.set_process(false)
			add_child(s)
			_soarers.append(s)
	multiplayer.peer_disconnected.connect(func(id: int) -> void: _peers.erase(id))
	if not _auth() and _online():
		_hello.rpc_id(1)


func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) \
		and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Does this machine run the animals?
func _auth() -> bool:
	return not _online() or multiplayer.is_server()


# ------------------------------------------------------------- host: running it
func _process(delta: float) -> void:
	if island == null:
		return
	_soar()
	if not _auth():
		return
	_update_threats(delta)
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 1.0 / SEND_HZ
		if _online() and not _peers.is_empty():
			_broadcast()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.5
	_place()


## Where everyone is: each player (or their ute), or the camera on the menu backdrop.
func _anchors() -> Array:
	var out := []
	if _main and _main.get("players"):
		for p in _main.players.get_children():
			var pc := p as PlayerCharacter
			if pc == null:
				continue
			var at := pc.global_position
			if pc.state == PlayerCharacter.State.IN_CAR and pc.car and is_instance_valid(pc.car):
				at = pc.car.global_position
			out.append({"id": String(pc.name), "pos": at})
	if out.is_empty() and _show:
		var cam := get_viewport().get_camera_3d()
		if cam:
			out.append({"id": "cam", "pos": cam.global_position})
	return out


## Every ute and every person on foot, with a speed worked out from how far they moved
## (a remote ute on the server has no physics velocity of its own).
func _update_threats(delta: float) -> void:
	threats.clear()
	if _main == null or delta <= 0.0:
		return
	var alive := {}
	if _main.get("cars"):
		for c in _main.cars.get_children():
			var car := c as SandVehicle
			if car == null:
				continue
			threats.append({"pos": car.global_position, "speed": _speed_of(car, delta, alive), "horn": car.horn_on, "car": true})
	if _main.get("players"):
		for p in _main.players.get_children():
			var pc := p as PlayerCharacter
			if pc and pc.is_on_foot():
				threats.append({"pos": pc.global_position, "speed": 0.0, "horn": false, "car": false})
	for k in _last_pos.keys():
		if not alive.has(k):
			_last_pos.erase(k)
			_speeds.erase(k)


func _speed_of(n: Node3D, delta: float, alive: Dictionary) -> float:
	var id := n.get_instance_id()
	alive[id] = true
	var p := n.global_position
	var last: Vector3 = _last_pos.get(id, p)
	_last_pos[id] = p
	var s := minf(Vector2(p.x - last.x, p.z - last.z).length() / delta, 60.0)
	_speeds[id] = lerpf(float(_speeds.get(id, s)), s, minf(1.0, delta * 6.0))
	return _speeds[id]


## Keep a few mobs and flocks near each player; move the ones nobody's near.
func _place() -> void:
	var anchors := _anchors()
	if anchors.is_empty():
		return
	for a in anchors:
		var at: Vector3 = a["pos"]
		# the first time someone shows up, things can be a little closer (there's
		# something to see straight away)
		var near := 150.0 if _seen.has(a["id"]) else 60.0
		_seen[a["id"]] = true
		var have := 0
		for mob in _mobs:
			if mob["placed"] and _flat_dist(mob["center"], at) < FAR and _any_near(mob["roos"], at):
				have += 1
		while have < MOBS.size():
			var mob := _free_mob(anchors, MOBS[have])
			if mob.is_empty():
				break
			var p := _roo_spot(at, near, 230.0)
			if p == Vector3.INF:
				break
			_place_mob(mob, p)
			have += 1
		have = 0
		for f in _flocks:
			if f.placed and (_flat_dist(f.spot, at) < FAR or f._air):
				have += 1
		while have < FLOCKS.size():
			var f := _free_flock(anchors, FLOCKS[have])
			if f == null:
				break
			var p := _beach_spot(at, near, 220.0)
			if p == Vector3.INF:
				break
			f.place_at(p)
			have += 1


## A mob nobody is near (or a new one, under the cap), else {}.
func _free_mob(anchors: Array, n: int) -> Dictionary:
	for mob in _mobs:
		if not mob["placed"] or not _near_anyone(mob["center"], anchors):
			var near_roo := false
			for r in mob["roos"]:
				if _near_anyone((r as Node3D).global_position, anchors):
					near_roo = true
			if not near_roo:
				return mob
	if _mobs.size() >= MAX_MOBS:
		return {}
	var mob := {"roos": [], "center": Vector3.ZERO, "placed": false}
	for k in n:
		var r := _new_roo(true)
		mob["roos"].append(r)
	_mobs.append(mob)
	return mob


func _free_flock(anchors: Array, n: int) -> Birds.GullFlock:
	for f in _flocks:
		if not f.placed or (not f._air and not _near_anyone(f.spot, anchors)):
			return f
	if _flocks.size() >= MAX_FLOCKS:
		return null
	return _new_flock(n, true)


func _near_anyone(p: Vector3, anchors: Array) -> bool:
	for a in anchors:
		if _flat_dist(p, a["pos"]) < FAR:
			return true
	return false


func _new_roo(logic: bool) -> Kangaroo:
	var r := Kangaroo.new()
	r.island = island
	r.logic = logic
	r.show = _show
	r.wild = self if logic else null
	r.visible = false
	r.set_process(false)
	add_child(r)
	_roos.append(r)
	return r


func _new_flock(n: int, logic: bool) -> Birds.GullFlock:
	var f := Birds.GullFlock.new()
	f.island = island
	f.count = n
	f.logic = logic
	f.show = _show
	f.wild = self if logic else null
	add_child(f)
	_flocks.append(f)
	return f


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
		roo.visible = _show
		roo.set_process(true)


# ------------------------------------------------------------- snapshots
func _broadcast() -> void:
	var roos := PackedFloat32Array()
	for i in _roos.size():
		var r := _roos[i]
		if not r.is_processing():
			continue
		var p := r.global_position
		roos.append_array([i, p.x, p.z, r._yaw, r.state_code(), r._speed, r._size])
	var flocks := PackedFloat32Array()
	for i in _flocks.size():
		var f := _flocks[i]
		if not f.placed:
			continue
		flocks.append_array([i, f.count, f.spot.x, f.spot.y, f.spot.z, f._center.x, f._center.z,
			1.0 if f._air else 0.0, 1.0 if f._landing else 0.0])
	for id in _peers:
		_snap.rpc_id(id, roos, flocks)


## A joiner's island is built: start sending it snapshots.
@rpc("any_peer", "call_remote", "reliable")
func _hello() -> void:
	if multiplayer.is_server():
		_peers[multiplayer.get_remote_sender_id()] = true


@rpc("authority", "call_remote", "unreliable_ordered")
func _snap(roos: PackedFloat32Array, flocks: PackedFloat32Array) -> void:
	if _auth():
		return
	var live := {}
	var i := 0
	while i + 6 < roos.size():
		var k := int(roos[i])
		if k < 0 or k > 64:
			break
		while _roos.size() <= k:
			_new_roo(false)
		var r := _roos[k]
		r.net_update(Vector3(roos[i + 1], 0, roos[i + 2]), roos[i + 3], int(roos[i + 4]), roos[i + 5], roos[i + 6])
		if not r.is_processing():
			r.visible = _show
			r.set_process(true)
		live[k] = true
		i += 7
	for k in _roos.size():
		if not live.has(k) and _roos[k].is_processing():
			_roos[k].visible = false
			_roos[k].set_process(false)
	i = 0
	while i + 8 < flocks.size():
		var k := int(flocks[i])
		if k < 0 or k > 32:
			break
		while _flocks.size() <= k:
			_new_flock(int(flocks[i + 1]), false)
		_flocks[k].net_update(Vector3(flocks[i + 2], flocks[i + 3], flocks[i + 4]),
			Vector3(flocks[i + 5], 0, flocks[i + 6]), flocks[i + 7] > 0.5, flocks[i + 8] > 0.5)
		i += 9


# ------------------------------------------------------------- birds of prey (cosmetic)
func _soar() -> void:
	if _soarers.is_empty():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	for s in _soarers:
		if s.is_processing() and _flat_dist(s.center, at) < 450.0:
			continue
		var a := randf() * TAU
		s.center = at + Vector3(cos(a), 0, sin(a)) * randf_range(60.0, 160.0)
		s.visible = true
		s.set_process(true)


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

class_name Ropes
extends Node3D
## Snatch straps and winch cables between cars / trees.
##
## Each rope joins two anchors. An anchor is {"car": "Car_2", "p": local point}
## or {"world": Vector3} (a tree). Every machine knows every rope (create / remove /
## length changes are broadcast) and each machine applies the rope force only to the
## cars it owns, so two players' cars can tug on each other.
##
## strap - stretchy "rubber band": slack until it's taut, then stores energy as it
##         stretches (~30 %) and gives it back - the snatch that yanks a bogged car out.
## winch - stiff steel cable on the front of a ute; G winds it in, H lets it out - or the
##         winch remote on foot, or the big WINCH buttons on screen in the cab. It pulls
##         both ends together: whichever car is free to roll comes to the other.

signal rope_snapped(id: String)

const STRAP_LEN := 9.0
const STRAP_K := 15000.0        ## N per metre of stretch
const STRAP_DAMP := 2600.0      ## only while stretching, so the energy comes back as a snatch
const STRAP_BREAK := 0.75       ## snaps past 75 % stretch
const WINCH_K := 70000.0
const WINCH_DAMP := 7000.0
const WINCH_MAX := 85000.0      ## winch stalls above this pull (N)
const WINCH_IN := 0.6           ## m/s
const WINCH_OUT := 0.9
const WINCH_MAX_LEN := 35.0

var ropes := {}                 ## id -> Dictionary {kind, a, b, rest, tension, mesh}
var remote_in := false          ## winch remote (on foot) buttons held
var remote_out := false
var cab_in := false             ## on-screen winch buttons in the cab
var cab_out := false
var cars_root: Node
var _counter := 0
var _len_timer := 0.0
var _line_mat: StandardMaterial3D


func _ready() -> void:
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED


func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func clear_all() -> void:
	for id in ropes.keys():
		_rpc_remove(id)


# ------------------------------------------------------------- api
func create(kind: String, a: Dictionary, b: Dictionary, rest: float) -> String:
	_counter += 1
	var id := "%d_%d" % [multiplayer.get_unique_id(), _counter]
	if _online():
		_rpc_create.rpc(id, kind, a, b, rest)
	else:
		_rpc_create(id, kind, a, b, rest)
	return id


func remove(id: String) -> void:
	if _online():
		_rpc_remove.rpc(id)
	else:
		_rpc_remove(id)


func sync_to(peer: int) -> void:
	for id in ropes:
		var r: Dictionary = ropes[id]
		_rpc_create.rpc_id(peer, id, r["kind"], r["a"], r["b"], r["rest"])


## Anchor positions (world).
func anchor_pos(an: Dictionary) -> Vector3:
	if an.has("world"):
		return an["world"]
	var car := _car(an)
	if car == null:
		return Vector3.ZERO
	return car.global_transform * (an["p"] as Vector3)


## Ropes touching a given car (by node name).
func ropes_on(car_name: String) -> Array[String]:
	var out: Array[String] = []
	for id in ropes:
		var r: Dictionary = ropes[id]
		if r["a"].get("car", "") == car_name or r["b"].get("car", "") == car_name:
			out.append(id)
	return out


## Nearest rope end (within max_dist): {"id", "end": "a"/"b", "pos"} or {}.
func nearest_end(pos: Vector3, max_dist: float) -> Dictionary:
	var best := {}
	var bd := max_dist
	for id in ropes:
		for e in ["a", "b"]:
			var p := anchor_pos(ropes[id][e])
			var d := p.distance_to(pos)
			if d < bd:
				bd = d
				best = {"id": id, "end": e, "pos": p}
	return best


func winch_rope_of(car_name: String) -> String:
	for id in ropes:
		var r: Dictionary = ropes[id]
		if r["kind"] == "winch" and r["a"].get("car", "") == car_name:
			return id
	return ""


# ------------------------------------------------------------- network
@rpc("any_peer", "call_local", "reliable")
func _rpc_create(id: String, kind: String, a: Dictionary, b: Dictionary, rest: float) -> void:
	if ropes.has(id):
		return
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = _line_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.top_level = true
	add_child(mi)
	var whirr := Sfx.make_loop("winch", -8.0)
	add_child(whirr)
	ropes[id] = {"kind": kind, "a": a, "b": b, "rest": rest, "tension": 0.0, "mesh": mi, "peak": 0.0, "snd": whirr, "twanged": false, "last_rest": rest}
	Sfx.play_at(self, "pop", anchor_pos(a), -6.0, 0.7)


@rpc("any_peer", "call_local", "reliable")
func _rpc_remove(id: String) -> void:
	if ropes.has(id):
		(ropes[id]["mesh"] as Node).queue_free()
		(ropes[id]["snd"] as Node).queue_free()
		ropes.erase(id)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_length(id: String, rest: float) -> void:
	if ropes.has(id):
		ropes[id]["rest"] = rest


# ------------------------------------------------------------- physics
func _car(an: Dictionary) -> SandVehicle:
	if not an.has("car") or cars_root == null:
		return null
	var n := cars_root.get_node_or_null(String(an["car"]))
	return n as SandVehicle


func _anchor_vel(an: Dictionary, pos: Vector3) -> Vector3:
	var car := _car(an)
	if car == null:
		return Vector3.ZERO
	return car.linear_velocity + car.angular_velocity.cross(pos - car.global_position)


func _physics_process(delta: float) -> void:
	_len_timer += delta
	var send_len := _len_timer > 0.1
	if send_len:
		_len_timer = 0.0
	for id in ropes.keys():
		var r: Dictionary = ropes[id]
		var pa := anchor_pos(r["a"])
		var pb := anchor_pos(r["b"])
		var ab := pb - pa
		var d := ab.length()
		if d < 0.001:
			r["tension"] = 0.0
			continue
		var dir := ab / d
		var rest: float = r["rest"]
		var ext := d - rest
		var t := 0.0
		if ext > 0.0:
			var stretch_rate := (_anchor_vel(r["b"], pb) - _anchor_vel(r["a"], pa)).dot(dir)
			if r["kind"] == "strap":
				t = STRAP_K * ext
				if stretch_rate > 0.0:
					t += STRAP_DAMP * stretch_rate
				t = minf(t, 140000.0)
				if ext > rest * STRAP_BREAK:
					rope_snapped.emit(id)
					remove(id)
					continue
			else:
				t = WINCH_K * ext + WINCH_DAMP * stretch_rate
				t = clampf(t, 0.0, WINCH_MAX * 1.6)
		r["tension"] = t
		r["peak"] = maxf(float(r["peak"]) * 0.98, t)
		# the strap "twangs" as it snaps taut
		if r["kind"] == "strap":
			if t > 15000.0 and not r["twanged"]:
				r["twanged"] = true
				Sfx.play_at(self, "twang", pa.lerp(pb, 0.5), 0.0, randf_range(0.9, 1.1))
			elif t < 2000.0:
				r["twanged"] = false
		else:
			# winch whirr while the drum turns (on every machine, from the length changing)
			var snd: AudioStreamPlayer3D = r["snd"]
			var moving := absf(float(r["rest"]) - float(r["last_rest"])) > 0.0001
			r["last_rest"] = r["rest"]
			snd.global_position = pa
			if moving and not snd.playing:
				snd.play()
			elif not moving and snd.playing:
				snd.stop()
		if t > 0.0:
			var free_a := true
			var free_b := true
			if r["kind"] == "winch":
				# the winch pulls the stuck one in: whichever end is dug in lets its
				# brakes off and rolls; the other end holds still as the anchor
				var ca := _car(r["a"])
				var cb := _car(r["b"])
				var a_stuck := ca != null and ca.dug_in()
				var b_stuck := cb == null or cb.freeze or cb.dug_in()
				free_a = a_stuck or (cb == null or cb.freeze)
				free_b = b_stuck and cb != null or not a_stuck
			_apply(r["a"], pa, dir * t, free_a)
			_apply(r["b"], pb, -dir * t, free_b)
		# winch control belongs to whoever owns the winch car
		if r["kind"] == "winch":
			var wcar := _car(r["a"])
			if wcar and wcar.local_control and not wcar.has_meta("bot"):
				var changed := false
				var w_in := Input.is_action_pressed("winch_in") or remote_in or cab_in
				var w_out := Input.is_action_pressed("winch_out") or remote_out or cab_out
				if w_in and t < WINCH_MAX:
					r["rest"] = maxf(rest - WINCH_IN * delta, 1.0)
					changed = true
				elif w_out and not w_in:
					r["rest"] = minf(rest + WINCH_OUT * delta, WINCH_MAX_LEN)
					changed = true
				if changed and send_len and _online():
					_rpc_length.rpc(id, r["rest"])


func _apply(an: Dictionary, pos: Vector3, force: Vector3, release := true) -> void:
	var car := _car(an)
	if car and car.local_control and not car.freeze:
		car.apply_force(force, pos - car.global_position)
		if release and force.length() > 1500.0:
			car.note_towed()


# ------------------------------------------------------------- visuals
func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for id in ropes:
		var r: Dictionary = ropes[id]
		_draw(r, cam.global_position)


func _draw(r: Dictionary, eye: Vector3) -> void:
	var pa := anchor_pos(r["a"])
	var pb := anchor_pos(r["b"])
	var im: ImmediateMesh = (r["mesh"] as MeshInstance3D).mesh
	im.clear_surfaces()
	var d := pa.distance_to(pb)
	var rest: float = r["rest"]
	var strap: bool = r["kind"] == "strap"
	# slack hangs in a curve; taut is straight. Strap gets thinner and redder as it stretches.
	var sag := 0.0
	if d < rest:
		sag = sqrt(maxf(rest * rest - d * d, 0.0)) * 0.45
	var stretch := clampf((d - rest) / rest, 0.0, 0.6) if strap else 0.0
	var width := (0.09 * (1.0 - stretch * 0.9)) if strap else 0.025
	var col := Color(1.0, 0.82, 0.10).lerp(Color(1.0, 0.25, 0.10), stretch / 0.5) if strap else Color(0.16, 0.16, 0.18)
	var segs := 20
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in segs + 1:
		var k := float(i) / segs
		var p := pa.lerp(pb, k)
		p.y -= sag * 4.0 * k * (1.0 - k)
		# slack rope lies on the sand rather than sinking into it
		p.y = maxf(p.y, IslandData.instance.height_at(p.x, p.z) + 0.04)
		var tangent := (pb - pa).normalized()
		var side := tangent.cross(eye - p).normalized() * width
		im.surface_set_color(col)
		im.surface_add_vertex(p - side)
		im.surface_set_color(col)
		im.surface_add_vertex(p + side)
	im.surface_end()

class_name PlayerTools
extends Node3D
## The hotbar and everything you can hold / use while on foot.
##
##   (press the key of what you're holding again to put it away)
##   1 Fishing rod  - aim the ring at the water (green = in reach, red = no good), hold left
##                    click to wind up, release to cast there; click again to reel in
##   2 Snatch strap - click a car's bullbar or tow hitch, then another car's (within 9 m)
##   3 Inflator     - hose from the back of your tub; hold left click on a tyre to pump it up
##   4 Deflators    - [ / ] set the pressure, click a tyre to screw one on (click again to take it off)
##   5 Shovel       - click near a bogged wheel to dig it out
##   6-0 Camping gear - a ghost follows the mouse; hold right + drag (or R) to spin it,
##                      left click places, Q picks up
##   E - get in / out, sit, grab the winch hook from the bullbar and hook it to a tree or car
##   - Winch remote - shows up once your winch is hooked on: hold left click to winch in,
##                    right click to let out (G / H work anywhere too, even in the cab)

const REACH := 1.8
const HOSE_LEN := 11.0
const INFLATE_RATE := 2.5      ## psi per second
const PLACE_RANGE := 9.0       ## how far from you camping gear can be put down
const CAST_RANGE := 26.0       ## furthest you can cast (flat distance)

var player: PlayerCharacter
var slot := -1                 ## -1 = empty hands
var prompt := ""               ## e.g. "[E] Get in" - shown by the HUD
var hint := ""                 ## help line for the current item
var charge := -1.0             ## fishing wind-up 0..1 (HUD bar), -1 when not charging
var deflate_target := 18.0
var ghost_rot := 0.0           ## world yaw of the camping-gear ghost

var _main: Node
var _held: Node3D
var _held_id := ""
var _ghost: Node3D
var _ghost_ok := false
var _rotating := false         ## right mouse held: mouse X spins the ghost
var _ghost_lock := Vector3.ZERO
var _mouse_aim := true         ## false after gamepad input: ghost goes in front of you
var _action := Callable()      ## what E does right now
var _strap_a := {}             ## first end of the strap while you carry the other end
var _carrying_winch := false
var _inflating := -1
var _inflate_car: SandVehicle
var _inflate_send := 0.0
var _dig_t := -1.0
var _dig_car: SandVehicle
var _dig_wheel := -1
var _carry_mesh: MeshInstance3D
var _line_mat: StandardMaterial3D
# fishing
var _fish := "idle"            ## idle / charging / throw / flying / out / reeling
var _throw_t := 0.0
var _bobber: Node3D
var _bob_pos := Vector3.ZERO
var _bob_vel := Vector3.ZERO
var _bob_t := 0.0
var _bob_in_water := false
var _rod_tip: Node3D
var _rod: Node3D
var _rod_angle := -30.0        ## degrees: rod tilt relative to the body (+ = back over the shoulder)
var _fish_mesh: MeshInstance3D
var _compressor: AudioStreamPlayer3D
var _ratchet: AudioStreamPlayer3D
var _aim := Vector3.INF        ## where the cast will land (rod, local player)
var _aim_ok := false
var _aim_why := ""
var _aim_ring: MeshInstance3D
var _aim_mat: StandardMaterial3D
var _remote_in := false        ## winch remote buttons held
var _remote_out := false


func _ready() -> void:
	_main = get_tree().root.get_node_or_null("Main")
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_carry_mesh = _make_line_mesh()
	_compressor = Sfx.make_loop("compressor", -10.0)
	add_child(_compressor)
	_ratchet = Sfx.make_loop("ratchet", -12.0)
	add_child(_ratchet)
	_aim_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.38
	tm.outer_radius = 0.55
	tm.rings = 24
	tm.ring_segments = 6
	_aim_ring.mesh = tm
	_aim_mat = StandardMaterial3D.new()
	_aim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_aim_mat.albedo_color = Color(0.3, 1.0, 0.4)
	_aim_ring.material_override = _aim_mat
	_aim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aim_ring.top_level = true
	_aim_ring.visible = false
	add_child(_aim_ring)
	_fish_mesh = _make_line_mesh()
	_bobber = Node3D.new()
	_bobber.top_level = true
	_bobber.visible = false
	add_child(_bobber)
	var top := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	top.mesh = sm
	top.material_override = Toon.mat(Color(0.95, 0.15, 0.12))
	_bobber.add_child(top)
	var bot := MeshInstance3D.new()
	var sm2 := SphereMesh.new()
	sm2.radius = 0.09
	sm2.height = 0.09
	sm2.is_hemisphere = true
	bot.mesh = sm2
	bot.rotation_degrees = Vector3(180, 0, 0)
	bot.material_override = Toon.mat(Color(0.97, 0.97, 0.97))
	_bobber.add_child(bot)
	select(-1)


func _make_line_mesh() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = ImmediateMesh.new()
	mi.material_override = _line_mat
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func item() -> Dictionary:
	return Items.get_item(slot)


func slows_walking() -> bool:
	return _fish == "charging" or _dig_t >= 0.0


# ------------------------------------------------------------- selecting
func select(i: int) -> void:
	slot = clampi(i, -1, Items.LIST.size() - 1)
	if _fish != "idle":
		_end_fishing()
	_strap_a = {}
	_inflating = -1
	_rotating = false
	_remote_in = false
	_remote_out = false
	var it := item()
	if _held_id != it["id"]:
		_held_id = it["id"]
		if _held:
			_held.queue_free()
			_held = null
		_held = _build_held(it["id"])
		if _held and player and player.avatar:
			player.avatar.hand_r.add_child(_held)
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if it["kind"] == "prop" and player and player.local_control:
		ghost_rot = player._yaw + PI   # starts facing you
		_ghost = Props.build(it["id"], true)
		_ghost.top_level = true
		add_child(_ghost)


func _build_held(id: String) -> Node3D:
	var n := Node3D.new()
	match id:
		"rod":
			# rod points forward and up out of the fist
			var rod := Node3D.new()
			n.add_child(rod)
			_rod = rod
			Props._cyl(rod, 0.012, 0.03, 2.2, Vector3(0, 1.0, 0), Color(0.15, 0.15, 0.16))
			Props._cyl(rod, 0.035, 0.035, 0.3, Vector3(0, -0.05, 0), Color(0.55, 0.35, 0.2))
			Props._cyl(rod, 0.06, 0.06, 0.05, Vector3(0.05, 0.12, 0), Color(0.75, 0.75, 0.78), Vector3(0, 0, 90))
			_rod_tip = Node3D.new()
			_rod_tip.position = Vector3(0, 2.1, 0)
			rod.add_child(_rod_tip)
		"strap":
			Props._cyl(n, 0.16, 0.16, 0.1, Vector3(0, -0.05, -0.08), Color(0.98, 0.80, 0.10), Vector3(90, 0, 0))
		"inflator":
			Toon.box(n, Vector3(0.08, 0.16, 0.08), Vector3(0, -0.04, -0.04), Color(0.2, 0.2, 0.22))
			Toon.box(n, Vector3(0.06, 0.06, 0.22), Vector3(0, 0.03, -0.14), Color(0.85, 0.15, 0.12))
			Props._cyl(n, 0.035, 0.035, 0.05, Vector3(0, 0.03, -0.18), Color(0.8, 0.8, 0.3), Vector3(90, 0, 0))
		"deflators":
			for k in 4:
				Props._cyl(n, 0.03, 0.03, 0.09, Vector3(-0.06 + k * 0.04, -0.04, -0.06), Color(0.85, 0.65, 0.20), Vector3(90, 0, 0))
		"shovel":
			var sh := Node3D.new()
			sh.rotation_degrees = Vector3(-60, 0, 0)
			n.add_child(sh)
			Props._cyl(sh, 0.025, 0.025, 1.1, Vector3(0, -0.2, 0), Color(0.6, 0.42, 0.25))
			Toon.box(sh, Vector3(0.24, 0.3, 0.03), Vector3(0, -0.85, 0), Color(0.62, 0.64, 0.68))
		"remote":
			Toon.box(n, Vector3(0.07, 0.14, 0.04), Vector3(0, 0.0, -0.04), Color(0.15, 0.15, 0.17))
			Toon.box(n, Vector3(0.03, 0.03, 0.02), Vector3(0, 0.03, -0.065), Color(0.3, 0.85, 0.3))
			Toon.box(n, Vector3(0.03, 0.03, 0.02), Vector3(0, -0.03, -0.065), Color(0.9, 0.2, 0.15))
		"radar":
			# police hand-held speed gun
			Toon.box(n, Vector3(0.06, 0.14, 0.06), Vector3(0, -0.02, -0.02), Color(0.15, 0.15, 0.17))
			Toon.box(n, Vector3(0.10, 0.10, 0.22), Vector3(0, 0.07, -0.12), Color(0.95, 0.85, 0.15))
			Props._cyl(n, 0.045, 0.045, 0.03, Vector3(0, 0.07, -0.24), Color(0.2, 0.2, 0.25), Vector3(90, 0, 0))
		_:
			return null
	return n


# ------------------------------------------------------------- per frame
## Hold something that isn't on the hotbar (bots: the police radar gun).
func hold_extra(id: String) -> void:
	if _held:
		_held.queue_free()
		_held = null
	_held_id = id
	_held = _build_held(id)
	if _held and player and player.avatar:
		player.avatar.hand_r.add_child(_held)


func _process(delta: float) -> void:
	var reeling := _fish == "reeling"
	if reeling != _ratchet.playing:
		if reeling:
			_ratchet.play()
		else:
			_ratchet.stop()
	if reeling:
		_ratchet.global_position = _rod_tip_pos()
	var pumping := _inflating >= 0
	if pumping != _compressor.playing:
		if pumping:
			_compressor.play()
		else:
			_compressor.stop()
	if pumping and player and player.car:
		_compressor.global_position = player.car.global_transform * SandVehicle.HOSE_POINT
	if _held:
		_held.visible = player != null and player.is_on_foot()
	_aim_rod(delta)
	_update_fishing(delta)
	_draw_lines()
	_aim_ring.visible = false
	if player == null or not player.local_control:
		return
	prompt = ""
	hint = ""
	_action = Callable()
	_update_remote()
	if player.state == PlayerCharacter.State.IN_CAR:
		if player.car and player.car.carrier != null:
			prompt = ""
		elif player.car and absf(player.car.speed_kmh) < 6.0:
			prompt = "[E] Get out"
		_set_ghost_visible(false)
		return
	if player.state == PlayerCharacter.State.SITTING:
		prompt = "[E] / move to stand up"
		_set_ghost_visible(false)
		return
	if player.state != PlayerCharacter.State.ON_FOOT:
		_set_ghost_visible(false)
		return
	_find_interaction()
	_update_item(delta)


func _set_ghost_visible(v: bool) -> void:
	if _ghost:
		_ghost.visible = v


func _cars() -> Array:
	return _main.cars.get_children() if _main else []


## Bullbar and tow-hitch points of every car: [{car, p (local), pos (world), label}]
func _recovery_points() -> Array:
	var out := []
	for c in _cars():
		var car := c as SandVehicle
		if car == null:
			continue
		out.append({"car": car, "p": SandVehicle.FRONT_POINT, "pos": car.global_transform * SandVehicle.FRONT_POINT, "label": "bullbar"})
		out.append({"car": car, "p": SandVehicle.REAR_POINT, "pos": car.global_transform * SandVehicle.REAR_POINT, "label": "tow hitch"})
	return out


func _nearest_point(max_d: float, exclude: SandVehicle = null) -> Dictionary:
	var best := {}
	var bd := max_d
	for rp in _recovery_points():
		if rp["car"] == exclude:
			continue
		var d := (rp["pos"] as Vector3).distance_to(player.global_position + Vector3.UP * 0.6)
		if d < bd:
			bd = d
			best = rp
	return best


func _nearest_valve(max_d: float) -> Dictionary:
	var best := {}
	var bd := max_d
	for c in _cars():
		var car := c as SandVehicle
		if car == null:
			continue
		for i in car.wheels.size():
			var d := car.wheel_valve_world(i).distance_to(player.global_position + Vector3.UP * 0.5)
			if d < bd:
				bd = d
				best = {"car": car, "i": i}
	return best


func _nearest_tree(max_d: float) -> Vector3:
	var p := player.global_position
	var best := Vector3.INF
	var bd := max_d * max_d
	for t in player.island.trees:
		var dx := t.x - p.x
		var dz := t.z - p.z
		var d2 := dx * dx + dz * dz
		if d2 < bd:
			bd = d2
			best = Vector3(t.x, t.y + 0.9, t.z)
	return best


func _car_name(car: SandVehicle) -> String:
	return "your ute" if car == player.car else "their ute"


func _find_interaction() -> void:
	var own := player.car
	var pos := player.global_position
	var ropes: Ropes = _main.ropes
	if _carrying_winch:
		var winch_pos := own.global_transform * SandVehicle.FRONT_POINT
		if winch_pos.distance_to(pos) > Ropes.WINCH_MAX_LEN:
			_carrying_winch = false
			_toast("The winch cable is fully out - hook dropped back")
			return
		var tree := _nearest_tree(2.4)
		var rp := _nearest_point(REACH, own)
		if tree != Vector3.INF:
			prompt = "[E] Wrap the tree trunk protector and hook the winch on"
			_action = func() -> void: _attach_winch({"world": tree})
		elif not rp.is_empty():
			prompt = "[E] Hook the winch to %s %s" % [_car_name(rp["car"]), rp["label"]]
			_action = func() -> void: _attach_winch({"car": String(rp["car"].name), "p": rp["p"]})
		elif winch_pos.distance_to(pos + Vector3.UP * 0.6) < 2.2:
			prompt = "[E] Put the winch hook away"
			_action = func() -> void: _carrying_winch = false
		else:
			prompt = "Carrying the winch hook - walk it to a tree or another car (%.0f m out)" % winch_pos.distance_to(pos)
		return
	if own and player.door_spot().distance_to(pos) < 1.7:
		prompt = "[E] Get in"
		_action = player.get_in
		return
	for c in _cars():
		var other := c as SandVehicle
		if other == null or other == own or not other.local_control or other.driver_present or other.has_meta("bot"):
			continue
		var spot := other.global_transform * PlayerCharacter.OUTSIDE
		spot.y = player.island.height_at(spot.x, spot.z)
		if spot.distance_to(pos) < 1.7:
			prompt = "[E] Get in this ute"
			_action = func() -> void:
				if own:
					own.driver_present = false
				player.car = other
				player.get_in()
			return
	var end := ropes.nearest_end(pos + Vector3.UP * 0.6, 1.5)
	if not end.is_empty():
		var kind: String = ropes.ropes[end["id"]]["kind"]
		prompt = "[E] Unhook the %s" % ("strap" if kind == "strap" else "winch cable")
		_action = func() -> void: ropes.remove(end["id"])
		return
	if own and (own.global_transform * SandVehicle.FRONT_POINT).distance_to(pos + Vector3.UP * 0.6) < 2.0 \
			and ropes.winch_rope_of(String(own.name)) == "":
		prompt = "[E] Pull out the winch cable"
		_action = func() -> void:
			_carrying_winch = true
			_toast("Walk the winch hook to a tree or another car, then press E")
		return
	var chair: Dictionary = _main.props.nearest(pos, 1.4, "chair")
	if not chair.is_empty():
		prompt = "[E] Sit down"
		_action = func() -> void: _sit(chair)
		return
	var any: Dictionary = _main.props.nearest(pos, 2.0)
	if not any.is_empty():
		prompt = "[Q] Pick up the %s" % _prop_name(any["kind"])


func _prop_name(kind: String) -> String:
	for it in Items.LIST:
		if it["id"] == kind:
			return String(it["name"]).to_lower()
	return kind


func _sit(chair: Dictionary) -> void:
	var node: Node3D = chair["node"]
	var seat: Transform3D = node.global_transform * (node.get_meta("seat") as Transform3D)
	seat.origin.y -= player.avatar.hip_height() - 0.02
	player.sit(seat, chair["id"])
	_main.achievements.unlock("sit_down")


func _attach_winch(anchor: Dictionary) -> void:
	var own := player.car
	var wpos := own.global_transform * SandVehicle.FRONT_POINT
	var ropes: Ropes = _main.ropes
	var target := ropes.anchor_pos(anchor)
	ropes.create("winch", {"car": String(own.name), "p": SandVehicle.FRONT_POINT}, anchor, wpos.distance_to(target) + 0.3)
	_carrying_winch = false
	select(Items.REMOTE)
	_toast("Winch hooked on! Winch remote in hand: hold left click to winch in, right click to let out. In the cab: the big WINCH button or G / H")


# ------------------------------------------------------------- held items
func _update_item(delta: float) -> void:
	var it := item()
	match it["id"]:
		"rod":
			match _fish:
				"idle":
					hint = "Hold left click to wind up, let go to cast"
				"charging":
					charge = minf(charge + delta / 1.2, 1.0)
					hint = "Let go to cast!"
				"out", "flying":
					hint = "Left click to reel in"
			if _fish != "charging":
				charge = -1.0
			player.pose_override = {"charging": "wind", "throw": "throw", "reeling": "reel"}.get(_fish, "hold")
			if _fish == "idle" or _fish == "charging":
				_update_aim()
		"strap":
			player.pose_override = ""
			var rp := _nearest_point(REACH)
			if _strap_a.is_empty():
				hint = "Click a bullbar or tow hitch to hook the strap on"
				if not rp.is_empty():
					prompt = "[Click] Hook strap to %s %s" % [_car_name(rp["car"]), rp["label"]]
			else:
				var a_pos: Vector3 = (_strap_a["car"] as SandVehicle).global_transform * (_strap_a["p"] as Vector3)
				hint = "Now click another car's bullbar or tow hitch (the strap is %d m long)" % int(Ropes.STRAP_LEN)
				if not rp.is_empty() and rp["car"] != _strap_a["car"]:
					var span := a_pos.distance_to(rp["pos"])
					if span > Ropes.STRAP_LEN:
						prompt = "Too far: that hook is %.1f m from the first one (strap is %d m)" % [span, int(Ropes.STRAP_LEN)]
					else:
						prompt = "[Click] Hook the other end to %s %s (%.1f m - fits)" % [_car_name(rp["car"]), rp["label"], span]
		"inflator":
			player.pose_override = "hold"
			var own := player.car
			var hose_ok := own != null and (own.global_transform * SandVehicle.HOSE_POINT).distance_to(player.global_position) < HOSE_LEN
			var v := _nearest_valve(1.7)
			hint = "Hold left click on a tyre to pump it up (the hose reaches %d m from your tub)" % int(HOSE_LEN)
			if not hose_ok:
				hint = "Too far from your ute - the hose won't reach"
			elif not v.is_empty():
				var car: SandVehicle = v["car"]
				prompt = "%s  %.1f psi" % [car.wheels[v["i"]].name, car.wheels[v["i"]].psi]
			if _inflating >= 0:
				if v.is_empty() or v["car"] != _inflate_car or v["i"] != _inflating or not hose_ok:
					_inflating = -1
				else:
					var w: SandVehicle.Wheel = _inflate_car.wheels[_inflating]
					var np := minf(w.psi + INFLATE_RATE * delta, 45.0)
					if _inflate_car.local_control:
						_inflate_car.set_wheel_psi(_inflating, np, true)
					else:
						_inflate_send += delta
						if _inflate_send > 0.1:
							_inflate_send = 0.0
							_inflate_car.ask_owner("remote_set_psi", [_inflating, np])
						w.psi = np
					player.pose_override = "reel"
		"deflators":
			player.pose_override = "hold"
			hint = "Deflators set to %d psi - [ and ] to change. Click a tyre to screw one on / off." % int(deflate_target)
			var v := _nearest_valve(1.7)
			if not v.is_empty():
				var car: SandVehicle = v["car"]
				var on := car.deflators[v["i"]] >= 0.0
				prompt = "[Click] %s deflator %s %s  (%.1f psi)" % ["Remove" if on else "Fit", "from" if on else "to", car.wheels[v["i"]].name, car.wheels[v["i"]].psi]
		"remote":
			player.pose_override = "hold"
			var rid := _winch_id()
			if rid == "":
				hint = "Your winch isn't hooked to anything"
			else:
				var r: Dictionary = _main.ropes.ropes[rid]
				hint = "Hold Q to winch IN, E to let OUT  (press - to put the remote away and use E for doors / unhooking)"
				var what := "winding in..." if _remote_in else ("letting out..." if _remote_out else "")
				prompt = "Winch: %.1f m of cable out  %s" % [float(r["rest"]), what]
				if _remote_in or _remote_out:
					player.pose_override = "reel"
		"":
			player.pose_override = ""
			hint = ""
		"shovel":
			if _dig_t >= 0.0:
				_dig_t += delta
				player.pose_override = "dig"
				hint = "Digging..."
				if _dig_t > 1.6:
					_dig_t = -1.0
					player.pose_override = ""
					if is_instance_valid(_dig_car):
						_dig_car.ask_owner("remote_dig", [_dig_wheel])
						_toast("Dug out %s - now give it a go (air down helps!)" % _dig_car.wheels[_dig_wheel].name)
			else:
				player.pose_override = "hold"
				hint = "Click next to a bogged wheel to dig it out"
				var v := _nearest_valve(1.9)
				if not v.is_empty():
					prompt = "[Click] Dig out %s" % v["car"].wheels[v["i"]].name
		_:
			player.pose_override = ""
			hint = "Point where it goes and left click to place.  Hold right + drag to spin (or R).  Q picks up"
			_update_ghost()


func _update_ghost() -> void:
	if _ghost == null:
		return
	var me := player.global_position
	var p := _ghost_lock if _rotating else Vector3.INF
	if p == Vector3.INF and _mouse_aim:
		p = _mouse_ground()
	if p == Vector3.INF:
		var fwd := -player.global_basis.z
		p = me + fwd * 2.4
	# keep it within reach of where you're standing
	var off := Vector2(p.x - me.x, p.z - me.z)
	if off.length() > PLACE_RANGE:
		off = off.normalized() * PLACE_RANGE
		p = Vector3(me.x + off.x, 0.0, me.z + off.y)
		p.y = player.island.height_at(p.x, p.z)
	elif off.length() < 0.9:
		off = (off.normalized() if off.length() > 0.01 else Vector2(-player.global_basis.z.x, -player.global_basis.z.z)) * 0.9
		p = Vector3(me.x + off.x, 0.0, me.z + off.y)
		p.y = player.island.height_at(p.x, p.z)
	_ghost_ok = player.island.water_level_at(p.x, p.z) < p.y + 0.05
	_ghost.visible = true
	_ghost.global_transform = Transform3D(Basis(Vector3.UP, ghost_rot), p)
	if not _ghost_ok:
		hint = "Can't put that in the water"


## Where the mouse cursor points on the ground. Pointing at the sky / far off gives
## the furthest spot within reach in that direction.
func _mouse_ground() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.INF
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 80.0, 1))
	if not hit.is_empty():
		return hit["position"]
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.01:
		return Vector3.INF
	var p := player.global_position + flat.normalized() * PLACE_RANGE
	p.y = player.island.height_at(p.x, p.z)
	return p


# ------------------------------------------------------------- fishing aim
## Where the mouse points on the ground or the water's surface (INF if at the sky).
func _mouse_surface() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.INF
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var island := player.island
	var t := 0.0
	var prev := from
	while t < 160.0:
		t += 1.0
		var p := from + dir * t
		var surf := maxf(island.height_at(p.x, p.z), island.water_level_at(p.x, p.z))
		if p.y <= surf:
			# refine between the last two samples
			var a := prev
			var b := p
			for k in 6:
				var m := a.lerp(b, 0.5)
				if m.y <= maxf(island.height_at(m.x, m.z), island.water_level_at(m.x, m.z)):
					b = m
				else:
					a = m
			return Vector3(b.x, maxf(island.height_at(b.x, b.z), island.water_level_at(b.x, b.z)), b.z)
		prev = p
	return Vector3.INF


## The cast target ring: green on water within reach, red otherwise.
func _update_aim() -> void:
	var island := player.island
	var me := player.global_position
	var p := _mouse_surface() if _mouse_aim else Vector3.INF
	if p == Vector3.INF:
		var fwd := -player.global_basis.z
		p = me + fwd * 12.0
		p.y = maxf(island.height_at(p.x, p.z), island.water_level_at(p.x, p.z))
	_aim = p
	var flat := Vector2(p.x - me.x, p.z - me.z).length()
	var wet := island.water_level_at(p.x, p.z) > island.height_at(p.x, p.z) + 0.05
	_aim_ok = wet and flat <= CAST_RANGE and flat > 2.0
	_aim_why = ""
	if not wet:
		_aim_why = "Aim the ring at the water" if _water_near(me) else "Walk down to the water to go fishing"
	elif flat > CAST_RANGE:
		_aim_why = "Too far out - you can only cast %d m (red = out of reach)" % int(CAST_RANGE)
	elif flat <= 2.0:
		_aim_why = "A bit further out"
	_aim_mat.albedo_color = Color(0.3, 1.0, 0.4) if _aim_ok else Color(1.0, 0.2, 0.15)
	_aim_ring.visible = true
	_aim_ring.global_position = p + Vector3.UP * 0.06
	_aim_ring.scale = Vector3.ONE * (1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.008))
	if _fish == "idle":
		hint = "Hold left click to wind up, let go to cast at the ring" if _aim_ok else _aim_why
	if _fish == "charging" and _aim_ok:
		# turn to face where we're casting
		player._yaw = lerp_angle(player._yaw, atan2(-(p.x - me.x), -(p.z - me.z)), 0.25)


func _water_near(p: Vector3) -> bool:
	var island := player.island
	for k in 16:
		var a := TAU * k / 16.0
		for r in [6.0, 14.0, CAST_RANGE]:
			var x: float = p.x + cos(a) * r
			var z: float = p.z + sin(a) * r
			if island.water_level_at(x, z) > island.height_at(x, z) + 0.05:
				return true
	return false


# ------------------------------------------------------------- winch remote
func _winch_id() -> String:
	if player.car == null:
		return ""
	return _main.ropes.winch_rope_of(String(player.car.name))


func _update_remote() -> void:
	var ropes: Ropes = _main.ropes
	var holding := slot == Items.REMOTE and player.state == PlayerCharacter.State.ON_FOOT
	ropes.remote_in = holding and _remote_in
	ropes.remote_out = holding and _remote_out and not _remote_in
	if slot == Items.REMOTE and _winch_id() == "":
		select(-1)   # winch unhooked: remote goes back in the pocket


## Camping gear: right mouse spins the ghost instead of turning the camera.
## Winch remote: hold Q to wind in, E to let out (right mouse stays on the camera).
func _input(event: InputEvent) -> void:
	if player == null or not player.local_control or player._bonk != 0:
		return
	if event is InputEventMouseMotion:
		_mouse_aim = true
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4):
		_mouse_aim = false
	if slot == Items.REMOTE and player.state == PlayerCharacter.State.ON_FOOT and event is InputEventKey and not event.is_echo():
		var k := (event as InputEventKey).physical_keycode
		if k == KEY_Q or k == KEY_E:
			if k == KEY_Q:
				_remote_in = event.is_pressed()
			else:
				_remote_out = event.is_pressed()
			if event.is_pressed() and _winch_id() != "":
				_main.achievements.unlock("winch_remote")
			get_viewport().set_input_as_handled()
			return
	if player.state != PlayerCharacter.State.ON_FOOT or _ghost == null or item()["kind"] != "prop" or not _ghost.visible:
		_rotating = false
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_rotating = event.pressed
		if _rotating:
			_ghost_lock = _ghost.global_position
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _rotating:
		ghost_rot -= (event as InputEventMouseMotion).relative.x * 0.012
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------- input
func _unhandled_input(event: InputEvent) -> void:
	if player == null or not player.local_control or player._bonk != 0:
		return
	if player.state == PlayerCharacter.State.IN_CAR:
		if event.is_action_pressed("interact") and player.car and absf(player.car.speed_kmh) < 6.0:
			player.get_out()
			get_viewport().set_input_as_handled()
		return
	if player.state == PlayerCharacter.State.SITTING:
		if event.is_action_pressed("interact"):
			player.stand_up()
			get_viewport().set_input_as_handled()
		return
	if player.state != PlayerCharacter.State.ON_FOOT:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).physical_keycode
		var want := -2
		if k >= KEY_1 and k <= KEY_9:
			want = k - KEY_1
		elif k == KEY_0:
			want = 9
		elif k == KEY_MINUS and _winch_id() != "":
			want = Items.REMOTE
		if want != -2:
			toggle_slot(want)
			get_viewport().set_input_as_handled()
			return
		if k == KEY_Q:
			var any: Dictionary = _main.props.nearest(player.global_position, 2.0)
			if not any.is_empty():
				_main.props.remove(any["id"])
				_toast("Picked up the %s" % _prop_name(any["kind"]))
			return
		if k == KEY_R:
			ghost_rot += PI * 0.25
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			select(_cycle(-1))
			get_viewport().set_input_as_handled()
			return
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select(_cycle(1))
			get_viewport().set_input_as_handled()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_use(mb.pressed)
			return
	if event.is_action_pressed("hotbar_prev"):
		select(_cycle(-1))
		return
	if event.is_action_pressed("hotbar_next"):
		select(_cycle(1))
		return
	if event.is_action_pressed("use_item"):
		_use(true)
		return
	if event.is_action_released("use_item"):
		_use(false)
		return
	if event.is_action_pressed("interact") and _action.is_valid():
		_action.call()
		get_viewport().set_input_as_handled()
		return
	if item()["id"] == "deflators":
		if event.is_action_pressed("psi_down"):
			deflate_target = maxf(deflate_target - 1.0, 8.0)
		elif event.is_action_pressed("psi_up"):
			deflate_target = minf(deflate_target + 1.0, 40.0)


## Number key: pick that item, or put it away if it's already in your hand.
func toggle_slot(i: int) -> void:
	select(-1 if i == slot else i)


## Next / previous hotbar item (wheel / bumpers), skipping the remote when there's no winch out.
func _cycle(dir: int) -> int:
	var n := Items.LIST.size()
	var s := slot
	for k in n:
		s = (s + dir + n) % n
		if s != Items.REMOTE or _winch_id() != "":
			return s
	return slot


func _use(pressed: bool) -> void:
	var it := item()
	match it["id"]:
		"rod":
			if pressed:
				if _fish == "idle":
					if not _aim_ok:
						_toast(_aim_why if _aim_why != "" else "Aim the ring at the water")
						return
					_fish = "charging"
					charge = 0.0
				elif _fish == "out" or _fish == "flying":
					_start_reel()
					player.rpc_reel()
			elif _fish == "charging":
				if _aim_ok and _aim != Vector3.INF:
					cast_at(_aim)
				else:
					_fish = "idle"
					charge = -1.0
		"remote":
			_remote_in = pressed
			if pressed and _winch_id() != "":
				_main.achievements.unlock("winch_remote")
		"strap":
			if pressed:
				_use_strap()
		"inflator":
			if pressed:
				var v := _nearest_valve(1.7)
				if not v.is_empty():
					_inflating = v["i"]
					_inflate_car = v["car"]
			else:
				_inflating = -1
		"deflators":
			if pressed:
				var v := _nearest_valve(1.7)
				if not v.is_empty():
					var car: SandVehicle = v["car"]
					var i: int = v["i"]
					if car.deflators[i] >= 0.0:
						car.ask_owner("remote_deflator", [i, -1.0])
						_toast("Deflator off %s" % car.wheels[i].name)
					elif car.wheels[i].psi <= deflate_target:
						_toast("%s is already at %.0f psi" % [car.wheels[i].name, car.wheels[i].psi])
					else:
						car.ask_owner("remote_deflator", [i, deflate_target])
						_toast("Deflator on %s - letting it down to %d psi" % [car.wheels[i].name, int(deflate_target)])
		"shovel":
			if pressed and _dig_t < 0.0:
				var v := _nearest_valve(1.9)
				if not v.is_empty():
					_dig_car = v["car"]
					_dig_wheel = v["i"]
					_dig_t = 0.0
		_:
			if pressed and _ghost and _ghost.visible and _ghost_ok:
				_main.props.place(it["id"], _ghost.global_transform)
				if it["id"] == "fire":
					_main.achievements.unlock("happy_camper")


func _use_strap() -> void:
	var rp := _nearest_point(REACH)
	if _strap_a.is_empty():
		if rp.is_empty():
			_toast("Walk up to a bullbar or tow hitch to hook the strap on")
			return
		_strap_a = {"car": rp["car"], "p": rp["p"]}
		_toast("Strap hooked to %s %s - now hook the other end to another vehicle" % [_car_name(rp["car"]), rp["label"]])
		return
	if rp.is_empty():
		_strap_a = {}
		_toast("Dropped the strap end")
		return
	if rp["car"] == _strap_a["car"]:
		_toast("Hook the other end to a different vehicle")
		return
	var a_car: SandVehicle = _strap_a["car"]
	var a_pos := a_car.global_transform * (_strap_a["p"] as Vector3)
	var d := a_pos.distance_to(rp["pos"])
	if d > Ropes.STRAP_LEN:
		_toast("Too far apart (%.0f m) - the strap is only %d m, bring the cars closer" % [d, int(Ropes.STRAP_LEN)])
		return
	_main.ropes.create("strap", {"car": String(a_car.name), "p": _strap_a["p"]}, {"car": String(rp["car"].name), "p": rp["p"]}, Ropes.STRAP_LEN)
	_strap_a = {}
	_toast("Strap on! Leave a bit of slack, then the free car sends it")


# ------------------------------------------------------------- fishing
func _rod_tip_pos() -> Vector3:
	if _rod_tip and is_instance_valid(_rod_tip) and _rod_tip.is_inside_tree():
		return _rod_tip.global_position
	return player.global_position + Vector3.UP * 2.0


## The rod keeps its own angle (independent of the arm swing) so it reads clearly:
## up in front while holding, back over the shoulder winding up, whipped forward on the cast.
func _aim_rod(delta: float) -> void:
	if _rod == null or not is_instance_valid(_rod) or not _rod.is_inside_tree():
		return
	var want := -30.0
	match _fish:
		"charging":
			want = 40.0
		"throw":
			want = -75.0
		"out", "flying":
			want = -50.0
		"reeling":
			want = -40.0
	_rod_angle = lerpf(_rod_angle, want, minf(1.0, delta * (22.0 if _fish == "throw" else 9.0)))
	_rod.global_basis = player.global_basis * Basis(Vector3.RIGHT, deg_to_rad(_rod_angle))


func _cast(power: float) -> void:
	var fwd := -player.global_basis.z
	var vel := fwd * (5.0 + 15.0 * power) + Vector3.UP * (4.0 + 4.0 * power)
	var origin := player.global_position + Vector3.UP * 2.1 + fwd * 0.9
	start_cast(origin, vel)
	player.rpc_cast(origin, vel)


## Cast so the bobber lands on p: face it, then lob it there in a nice arc.
func cast_at(p: Vector3) -> void:
	var me := player.global_position
	var to := Vector3(p.x - me.x, 0.0, p.z - me.z)
	var fwd := to.normalized() if to.length() > 0.1 else -player.global_basis.z
	player._yaw = atan2(-fwd.x, -fwd.z)
	player.global_basis = Basis(Vector3.UP, player._yaw)
	var origin := me + Vector3.UP * 2.1 + fwd * 0.9
	var flat := Vector2(p.x - origin.x, p.z - origin.z).length()
	var t := 0.7 + flat * 0.035
	var vel := (p - origin) / t + Vector3.UP * 0.5 * 9.8 * t
	# make up for the bit of air drag in the flight sim
	vel = Vector3(vel.x, 0, vel.z) * (1.0 + 0.075 * t) + Vector3.UP * vel.y
	start_cast(origin, vel)
	player.rpc_cast(origin, vel)


## Also called on other machines when a remote player casts.
func start_cast(origin: Vector3, vel: Vector3) -> void:
	_fish = "throw"
	_throw_t = 0.0
	_bob_pos = origin
	_bob_vel = vel
	_bob_in_water = false
	_bobber.visible = true
	charge = -1.0
	Sfx.play_at(self, "whoosh", origin, -4.0)


func _start_reel() -> void:
	if _fish == "out" or _fish == "flying":
		# a line that's sat in the water a while might have something on it
		_hooked = _fish == "out" and _bob_in_water and _bob_t > 4.0 and randf() < clampf(0.25 + _bob_t * 0.04, 0.0, 0.8)
		_fish = "reeling"


const CATCHES := [["whiting", 18, 38], ["dart", 25, 50], ["tailor", 30, 65], ["bream", 20, 40], ["flathead", 30, 70],
	["old thong", 0, 0], ["clump of seaweed", 0, 0]]
var _hooked := false


## Reeled in with a bite on: land it.
func _land_catch() -> void:
	var c: Array = CATCHES[randi() % CATCHES.size()]
	if int(c[2]) == 0:
		_main.hud.show_toast("You reeled in... a %s. Better luck next cast!" % c[0])
		return
	var cm := randi_range(int(c[1]), int(c[2]))
	_main.hud.show_toast("You caught a %d cm %s! %s" % [cm, c[0], "Beauty!" if cm > int(c[2]) * 0.8 else "Not bad, mate."])
	Sfx.play_ui(self, "click", -2.0)
	_net().stat("fish_caught")


func _end_fishing() -> void:
	_fish = "idle"
	_bobber.visible = false
	charge = -1.0
	(_fish_mesh.mesh as ImmediateMesh).clear_surfaces()


func _update_fishing(delta: float) -> void:
	if _fish == "idle" or _fish == "charging":
		return
	var island := player.island
	match _fish:
		"throw", "flying":
			_throw_t += delta
			if _fish == "throw" and _throw_t > 0.25:
				_fish = "flying"
			_bob_vel.y -= 9.8 * delta
			_bob_vel *= 1.0 - 0.15 * delta
			_bob_pos += _bob_vel * delta
			var ground := island.height_at(_bob_pos.x, _bob_pos.z)
			var water := island.water_level_at(_bob_pos.x, _bob_pos.z)
			var surface := maxf(ground, water)
			if _bob_pos.y <= surface and _throw_t > 0.15:
				_bob_pos.y = surface
				_bob_in_water = water > ground
				_fish = "out"
				_bob_t = 0.0
				if _bob_in_water:
					Sfx.play_at(self, "splash", _bob_pos, -2.0, randf_range(0.9, 1.2))
					_splash(_bob_pos)
					if player.local_control:
						_main.achievements.unlock("gone_fishing")
		"out":
			_bob_t += delta
			var surf := maxf(island.height_at(_bob_pos.x, _bob_pos.z), island.water_level_at(_bob_pos.x, _bob_pos.z))
			_bob_pos.y = surf + (sin(_bob_t * 3.0) * 0.03 + 0.02 if _bob_in_water else 0.05)
		"reeling":
			var tip := _rod_tip_pos()
			var to := Vector3(tip.x - _bob_pos.x, 0, tip.z - _bob_pos.z)
			if to.length() < 1.2:
				if _hooked and player.local_control:
					_land_catch()
				_hooked = false
				_end_fishing()
				return
			_bob_pos += to.normalized() * 6.0 * delta
			var surf := maxf(player.island.height_at(_bob_pos.x, _bob_pos.z), player.island.water_level_at(_bob_pos.x, _bob_pos.z))
			_bob_pos.y = surf + 0.05
	_bobber.global_position = _bob_pos
	# line from the rod tip, sagging when there's slack
	var tip := _rod_tip_pos()
	var im := _fish_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	var sag := 0.0 if _fish == "throw" or _fish == "flying" or _fish == "reeling" else tip.distance_to(_bob_pos) * 0.12
	_ribbon(im, tip, _bob_pos, sag, 0.008, Color(0.95, 0.95, 0.95))


func _splash(p: Vector3) -> void:
	var c := CPUParticles3D.new()
	c.top_level = true
	add_child(c)
	c.global_position = p
	c.one_shot = true
	c.amount = 24
	c.explosiveness = 0.95
	c.lifetime = 0.7
	c.direction = Vector3.UP
	c.spread = 35.0
	c.initial_velocity_min = 1.5
	c.initial_velocity_max = 3.0
	c.gravity = Vector3(0, -9.8, 0)
	var sm := SphereMesh.new()
	sm.radius = 0.04
	sm.height = 0.08
	sm.radial_segments = 6
	sm.rings = 3
	c.mesh = sm
	c.material_override = Toon.mat(Color(0.85, 0.95, 1.0))
	c.emitting = true
	get_tree().create_timer(1.2).timeout.connect(c.queue_free)


# ------------------------------------------------------------- lines
func _draw_lines() -> void:
	var im := _carry_mesh.mesh as ImmediateMesh
	im.clear_surfaces()
	if player == null or player.state != PlayerCharacter.State.ON_FOOT:
		return
	var hand := player.avatar.hand_r.global_position
	if _carrying_winch and player.car:
		_ribbon(im, player.car.global_transform * SandVehicle.FRONT_POINT, hand, 0.4, 0.02, Color(0.16, 0.16, 0.18))
	elif item()["id"] == "strap" and not _strap_a.is_empty() and is_instance_valid(_strap_a["car"]):
		var a := (_strap_a["car"] as SandVehicle).global_transform * (_strap_a["p"] as Vector3)
		_ribbon(im, a, hand, 0.6, 0.07, Color(1.0, 0.82, 0.10))
	elif item()["id"] == "inflator" and player.car:
		var hose := player.car.global_transform * SandVehicle.HOSE_POINT
		if hose.distance_to(hand) < HOSE_LEN + 1.0:
			_ribbon(im, hose, hand, 0.8, 0.018, Color(0.08, 0.08, 0.09))


func _ribbon(im: ImmediateMesh, a: Vector3, b: Vector3, sag: float, width: float, col: Color) -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else a + Vector3.UP
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var segs := 16
	var tangent := (b - a).normalized()
	for i in segs + 1:
		var k := float(i) / segs
		var p := a.lerp(b, k)
		p.y -= sag * 4.0 * k * (1.0 - k)
		p.y = maxf(p.y, player.island.height_at(p.x, p.z) + 0.03)
		var side := tangent.cross(eye - p).normalized() * width
		im.surface_set_color(col)
		im.surface_add_vertex(p - side)
		im.surface_set_color(col)
		im.surface_add_vertex(p + side)
	im.surface_end()


func _toast(msg: String) -> void:
	if _main and _main.hud:
		_main.hud.show_toast(msg)


## The Net autoload, looked up at runtime (naming it directly breaks scripts that load this class early).
func _net() -> Node:
	return get_node("/root/Net")

extends SceneTree
## Trailer director: plays scripted scenes in the real game and marks the good bits.
##   godot --path . --resolution 1280x720 --fixed-fps 30 --write-movie <dir>/raw.avi -s res://tests/_trailer.gd -- <dir>
## Everything between mark_in / mark_out is kept; set-up time in between is cut later
## by tools/make_trailer.py (it reads <dir>/cuts.json and lays the music over the top).

const FPS := 30.0

var main
var out_dir := ""
var frame := 0
var cuts := []                 ## [start_frame, end_frame]
var _in := -1
var cam_fn := Callable()       ## (delta) -> moves the camera each frame while set
var cam: Camera3D
var _cap: Label
var _sub: Label
var _card: ColorRect
var _card_title: Label
var _card_sub: Label
var car: SandVehicle


func _initialize() -> void:
	out_dir = OS.get_cmdline_user_args()[0]
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	_build_overlay()
	await wait(0.3)
	main.player_name = "Harry"
	main._select_island("fraser")
	await main._start("solo")
	main.music.enabled = false     # the trailer gets the music laid over in one piece
	cam = main.camera
	car = main.local_car
	await wait(0.5)
	main.hud.visible = false
	await _title_card()
	await _barge()
	await _beach_run()
	await _bogged_and_helper()
	await _bots_life()
	await _help_and_winch()
	await _police()
	await _emergency()
	await _explore()
	await _end_card()
	# music for the edit
	for i in 200:
		if not main.music._songs.is_empty():
			break
		await wait(0.1)
	if not main.music._songs.is_empty():
		main.music._songs[0].save_to_wav(out_dir + "/music.wav")
	var f := FileAccess.open(out_dir + "/cuts.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"fps": FPS, "cuts": cuts}))
	f.close()
	print("TRAILER cuts: ", cuts.size(), " total ", _total(), " s")
	quit()


func _total() -> float:
	var t := 0.0
	for c in cuts:
		t += (c[1] - c[0]) / FPS
	return t


func _process(delta: float) -> bool:
	frame += 1
	if cam_fn.is_valid() and cam:
		cam.target = null
		cam_fn.call(delta)
	return false


func wait(t: float) -> void:
	await create_timer(t).timeout


## Keep the next `secs` seconds (with an optional caption over them).
func rec(secs: float, caption := "", sub := "") -> void:
	if caption != "":
		_caption(caption, sub)
	_in = frame
	await wait(secs)
	cuts.append([_in, frame])
	_in = -1
	_hide_caption()


# ---------------------------------------------------------------- overlay
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	get_root().add_child(layer)
	_card = ColorRect.new()
	_card.color = Color(0.03, 0.08, 0.16)
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.visible = false
	layer.add_child(_card)
	_card_title = _label(_card, 110, Color(1.0, 0.82, 0.25), Color(0.55, 0.18, 0.05), 22)
	_card_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_title.offset_top = -80
	_card_sub = _label(_card, 34, Color(0.75, 0.92, 1.0), Color(0, 0, 0, 0.6), 6)
	_card_sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card_sub.offset_top = 150
	_cap = _label(layer, 56, Color(1.0, 0.85, 0.25), Color(0.1, 0.05, 0.0, 0.9), 14)
	_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_cap.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_cap.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cap.offset_left = 60
	_cap.offset_bottom = -95
	_sub = _label(layer, 30, Color(1, 1, 1), Color(0, 0, 0, 0.85), 10)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_sub.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sub.offset_left = 64
	_sub.offset_bottom = -52


func _label(parent: Node, size: int, col: Color, outline: Color, osize: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", osize)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _caption(t: String, s: String) -> void:
	_cap.text = t
	_sub.text = s
	for l in [_cap, _sub]:
		l.modulate.a = 0.0
		l.visible = true
		var tw := create_tween()
		tw.tween_property(l, "modulate:a", 1.0, 0.35)


func _hide_caption() -> void:
	_cap.visible = false
	_sub.visible = false


func _card_show(title: String, sub: String, secs: float) -> void:
	_card.visible = true
	_card_title.text = title
	_card_sub.text = sub
	_card_title.modulate.a = 0.0
	_card_sub.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_card_title, "modulate:a", 1.0, 0.6)
	tw.tween_property(_card_sub, "modulate:a", 1.0, 0.5)
	await rec(secs)
	_card.visible = false


# ---------------------------------------------------------------- camera helpers
func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z).normalized()


## Camera at a point in a node's own space (smoothed), looking at another point in its space.
func follow(n: Node3D, off: Vector3, look_off: Vector3, smooth := 6.0) -> void:
	var first := [true]
	cam_fn = func(dt: float) -> void:
		if not is_instance_valid(n):
			return
		var yaw := atan2(-_flat(-n.global_basis.z).x, -_flat(-n.global_basis.z).z)
		var b := Basis(Vector3.UP, yaw)
		var want: Vector3 = n.global_position + b * off
		want.y = maxf(want.y, main.island.height_at(want.x, want.z) + 0.4)
		cam.global_position = want if first[0] else cam.global_position.lerp(want, minf(1.0, smooth * dt))
		first[0] = false
		cam.look_at(n.global_position + b * look_off, Vector3.UP)


## Slow circle round a point (or a node), radius r, height h.
func orbit(n: Node3D, centre_off: Vector3, r: float, h: float, speed: float, a0 := 0.0) -> void:
	var t := [a0]
	cam_fn = func(dt: float) -> void:
		t[0] += dt * speed
		var c: Vector3 = (n.global_position if is_instance_valid(n) else Vector3.ZERO) + centre_off
		var p := c + Vector3(cos(t[0]) * r, h, sin(t[0]) * r)
		p.y = maxf(p.y, main.island.height_at(p.x, p.z) + 0.6)
		cam.global_position = p
		cam.look_at(c, Vector3.UP)


## Fixed camera that keeps a node in view.
func watch(p: Vector3, n: Node3D, look_off := Vector3(0, 1, 0)) -> void:
	cam_fn = func(_dt: float) -> void:
		cam.global_position = p
		if is_instance_valid(n):
			cam.look_at(n.global_position + look_off, Vector3.UP)


## Drone move from a to b over `secs`, looking at `at`.
func dolly(a: Vector3, b: Vector3, at: Vector3, secs: float) -> void:
	var t := [0.0]
	cam_fn = func(dt: float) -> void:
		t[0] = minf(t[0] + dt / secs, 1.0)
		var k := smoothstep(0.0, 1.0, t[0])
		cam.global_position = a.lerp(b, k)
		cam.look_at(at, Vector3.UP)


func place_pos(nm: String) -> Vector3:
	for p in main.island.places:
		if p["name"] == nm:
			return p["pos"]
	return Vector3.ZERO


func _drive_north(c: SandVehicle, speed: float, metres: float) -> BotDriver:
	var d := BotDriver.new(c)
	var f0: float = main.island.z_to_f(c.global_position.z)
	d.set_path(main.bots.beach_path(f0, f0 + metres / main.island.length), speed)
	d.ease_to_end = false
	return d


# ---------------------------------------------------------------- scenes
func _title_card() -> void:
	await _card_show("ISLAND 4WD", "Fraser & Moreton  -  a cartoon beach-driving sandbox", 3.2)


func _barge() -> void:
	car.scripted = true
	# ride in on the barge, front three-quarter view
	await wait(9.0)
	follow(car, Vector3(-10, 4.5, -14), Vector3(0, 0.5, 0), 3.0)
	await wait(0.5)
	await rec(5.0, "Catch the barge across", "Fraser Island and Moreton Island")
	for i in 40:
		if car.carrier == null:
			break
		await wait(0.25)
	car.throttle = 0.5
	follow(car, Vector3(0, 3.0, 9.0), Vector3(0, 1.0, -4), 4.0)
	await rec(4.0)
	car.throttle = 0.0
	car.brake = 1.0


func _beach_run() -> void:
	main.set_tide(0.5)
	main.teleport_local(main.bots.lane_point(0.42, true))
	await wait(1.5)
	car.set_all_psi(24.0)
	car.brake = 0.0
	var d := _drive_north(car, 22.0, 900.0)
	var drive := func(secs: float) -> void:
		var n := int(secs * 30.0)
		for i in n:
			d.update(1.0 / 30.0)
			car.throttle = maxf(car.throttle, 0.8)
			await process_frame
	await drive.call(4.0)
	follow(car, Vector3(5.5, 0.9, -1.0), Vector3(0, 0.6, -2.0), 14.0)
	_in = frame
	_caption("Cruise the beach", "Hard sand at low tide - soft stuff up the top")
	await drive.call(3.5)
	follow(car, Vector3(-1.5, 1.1, -13.0), Vector3(0, 0.7, 0), 8.0)
	await drive.call(3.0)
	cuts.append([_in, frame])
	_hide_caption()
	# sweep past from the side, low and fast
	follow(car, Vector3(-9.0, 2.2, 6.0), Vector3(0, 0.8, -6), 14.0)
	_in = frame
	await drive.call(2.5)
	cuts.append([_in, frame])
	car.throttle = 0.0
	car.brake = 1.0
	await wait(2.0)


func _bogged_and_helper() -> void:
	main.teleport_local(place_pos("Eurong"))
	await wait(1.5)
	main.bots.spawn("helper")
	await wait(1.0)
	var h: HelperBot = main.bots.helper
	car.brake = 0.0
	car.throttle = 0.5
	await wait(4.0)
	car.throttle = 0.0
	car.brake = 1.0
	await wait(3.0)
	# bog it, low wheel camera
	main.island.force_soft = 1.0
	car.set_all_psi(32.0)
	car.brake = 0.0
	car.throttle = 1.0
	follow(car, Vector3(-2.7, 0.35, 3.0), Vector3(-0.9, 0.0, 1.4), 20.0)
	main.hud.visible = true
	main.hud.get_child(0).get_node("HelpPanel").visible = false
	await rec(4.0, "Air down... or get bogged!", "Tyre pressures, diff lockers, low range, deflators")
	car.throttle = 0.0
	main.island.force_soft = -1.0
	main.hud.visible = false
	for i in 120:
		await wait(0.5)
		if h.phase == "ready":
			break
	main.ropes.create("strap", {"car": String(h.car.name), "p": SandVehicle.FRONT_POINT}, {"car": String(car.name), "p": SandVehicle.REAR_POINT}, Ropes.STRAP_LEN)
	var mid: Vector3 = car.global_position.lerp(h.car.global_position, 0.5)
	var side := _flat(car.global_basis.x)
	watch(mid + side * 11.0 + Vector3.UP * 3.0, car, Vector3(0, 0.5, 0))
	cam_fn = func(_dt: float) -> void:
		if not is_instance_valid(h) or not is_instance_valid(h.car):
			return
		var m: Vector3 = car.global_position.lerp(h.car.global_position, 0.5)
		cam.global_position = mid + side * 11.0 + Vector3.UP * 3.0
		cam.look_at(m + Vector3.UP * 0.6, Vector3.UP)
	car.throttle = 0.6
	await rec(6.5, "Your helper bot snatches you out", "It follows you everywhere - you hook up the strap")
	car.throttle = 0.0
	car.brake = 1.0
	for id in main.ropes.ropes.keys():
		main.ropes.remove(id)
	main.bots.remove_helper()
	await wait(1.0)


func _bots_life() -> void:
	main.set_tide(0.25)
	main.teleport_local(place_pos("Happy Valley"))
	await wait(1.5)
	var fisher := await _spawn("fisher")
	var camper := await _spawn("camper")
	# fisher: straight down to the water for a cast
	fisher.plan.clear()
	fisher.plan.append({"do": "wait", "t": 0.3})
	fisher.car.teleport(main.bots.lane_point(main.island.z_to_f(car.global_position.z) + 0.01, true) + Vector3(-6, 1, 0), Vector3(0, 0, 1))
	fisher.plan.append({"do": "get_out"})
	fisher.plan.append({"do": "select", "slot": 0})
	fisher.plan.append({"do": "wait", "t": 3.0})
	fisher.plan.append({"do": "face", "dir": Vector3(1, 0, 0)})
	fisher.plan.append({"do": "wait", "t": 1.5})
	fisher.plan.append({"do": "cast", "power": 0.9})
	fisher.plan.append({"do": "wait", "t": 60.0, "pose": "hold"})
	for i in 60:
		await wait(0.25)
		if fisher.person.state == PlayerCharacter.State.ON_FOOT:
			break
	var edge: Vector3 = fisher.water_edge(fisher.car.global_position)
	fisher.person.global_position = edge + Vector3(-1.5, 0.3, 0)
	print("fisher: car x %.0f  edge x %.0f" % [fisher.car.global_position.x, edge.x])
	for i in 120:
		await wait(0.25)
		if not fisher.plan.is_empty() and String(fisher.plan[0]["do"]) == "wait" and float(fisher.plan[0]["t"]) == 1.5:
			break
	# from up the beach (north), looking past him out to sea
	var fp: Vector3 = fisher.person.global_position
	print("fisher at %s car %s" % [fp, fisher.car.global_position])
	dolly(fp + Vector3(-2.5, 2.4, 6.0), fp + Vector3(-1.0, 2.0, 4.5), fp + Vector3(6.0, 0.5, -2.0), 4.5)
	await rec(4.5, "Island bots fish...", "")
	for i in 160:
		await wait(0.5)
		if camper.person.state == PlayerCharacter.State.SITTING and camper._guest_chair != "":
			break
	# walk the player up to the camp so the camper calls him over
	var pl: PlayerCharacter = main.local_player
	if pl.state == PlayerCharacter.State.IN_CAR:
		pl.get_out()
		await wait(1.6)
	var chair: Node3D = main.props.props.get(camper._guest_chair)
	if chair:
		pl.global_position = chair.global_position + Vector3(6, 0.4, 3)
		pl.ai = true
		pl.ai_move = Vector3(-0.9, 0, -0.45).normalized() * 0.6
		orbit(chair, Vector3(-1.0, 0.8, 0), 6.0, 2.0, 0.1, 0.6)
		_in = frame
		_caption("...camp...", "and invite you over by name")
		await wait(1.2)
		pl.ai_move = Vector3.ZERO
		await wait(2.6)
		pl.ai = false
		pl.tools._sit({"node": chair, "id": camper._guest_chair})
		camper._chat_t = 0.6
		await wait(3.2)
		cuts.append([_in, frame])
		_hide_caption()
		pl.stand_up()
	# a cruiser passing waves out the window
	var cr := await _spawn("cruiser")
	cr.plan.clear()
	cr.plan.append({"do": "wait", "t": 0.5})
	var f0: float = main.island.z_to_f(pl.global_position.z)
	cr.car.teleport(main.bots.lane_point(f0 + 0.012, false) + Vector3.UP, Vector3(0, 0, 1))
	cr.plan.append({"do": "drive", "speed": 9.0, "make": func() -> PackedVector3Array:
		return main.bots.beach_path(main.island.z_to_f(cr.car.global_position.z), f0 - 0.02)})
	await wait(1.0)
	pl.global_position = main.bots.lane_point(f0, true) + Vector3(-9, 0.5, 0)
	for i in 80:
		await wait(0.2)
		if pl.global_position.distance_to(cr.car.global_position) < 40.0:
			break
	follow(cr.car, Vector3(5.5, 2.2, -6.5), Vector3(0, 1.2, 0), 6.0)
	await rec(4.0, "...and say g'day", "Arm out the window, beep beep!")
	main.bots.remove_all_ambient()
	await wait(1.0)


func _spawn(role: String) -> AmbientBot:
	var before: Array = main.bots.brains()
	main.bots.spawn(role)
	await wait(0.5)
	for b in main.bots.brains():
		if not before.has(b):
			return b
	return null


func _help_and_winch() -> void:
	var pl: PlayerCharacter = main.local_player
	if pl.state != PlayerCharacter.State.IN_CAR:
		pl.get_in()
		await wait(1.6)
	main.teleport_local(place_pos("Eli Creek"))
	await wait(1.5)
	var b := await _spawn("cruiser")
	b.plan.clear()
	b.plan.append({"do": "wait", "t": 2.0})
	b.car.teleport(car.global_position + Vector3(-4, 0, -22), Vector3(0, 0, -1))
	await wait(2.0)
	b.force_bog()
	await wait(5.0)
	orbit(b.person, Vector3(0, 1.6, 0), 8.0, 2.2, 0.15, 0.4)
	await rec(3.5, "Help out bogged strangers", "Look for the HELP sign")
	# park facing it and winch it out with the remote
	var back := _flat(b.car.global_basis.z)
	car.teleport(b.car.global_position + back * 17.0, -back)
	car.brake = 1.0
	car.handbrake = true
	await wait(2.0)
	pl.get_out()
	await wait(1.6)
	var wl := (car.global_transform * SandVehicle.FRONT_POINT).distance_to(b.car.global_transform * SandVehicle.REAR_POINT)
	main.ropes.create("winch", {"car": String(car.name), "p": SandVehicle.FRONT_POINT}, {"car": String(b.car.name), "p": SandVehicle.REAR_POINT}, wl + 0.3)
	pl.global_position = car.global_transform * Vector3(2.5, 0, -3.5)
	pl.tools.select(Items.REMOTE)
	await wait(3.0)
	pl.tools._remote_in = true
	var mid: Vector3 = car.global_position.lerp(b.car.global_position, 0.5)
	var side := _flat(car.global_basis.x)
	cam_fn = func(_dt: float) -> void:
		if not is_instance_valid(b) or not is_instance_valid(b.car):
			return
		cam.global_position = mid + side * 12.0 + Vector3.UP * 3.5
		cam.look_at(b.car.global_position.lerp(car.global_position, 0.4) + Vector3.UP * 0.6, Vector3.UP)
	await rec(6.0, "Winch remote", "Stand clear and wind them in")
	pl.tools._remote_in = false
	for id in main.ropes.ropes.keys():
		main.ropes.remove(id)
	pl.tools.select(-1)
	pl.global_position = pl.door_spot()
	pl.get_in()
	await wait(2.0)
	main.bots.remove_all_ambient()


func _police() -> void:
	main.set_tide(0.5)
	main.teleport_local(main.bots.lane_point(0.47, true))
	await wait(1.5)
	var p := await _spawn("police")
	p.plan.clear()
	p.plan.append({"do": "wait", "t": 1.0})
	var cf: float = main.island.z_to_f(car.global_position.z) - 0.045
	p.car.teleport(main.bots.lane_point(cf, false) + Vector3.UP, Vector3(0, 0, 1))
	p.plan.append({"do": "get_out"})
	p.plan.append({"do": "trap", "dur": 400.0, "face": Vector3(0, 0, 1)})
	p.plan.append({"do": "get_in"})
	await wait(9.0)
	orbit(p.person, Vector3(0, 1.3, 0), 4.5, 0.8, 0.18, 4.2)
	await rec(3.0, "Watch your speed...", "It's 60 on the beach")
	# come at the radar fast, from the south
	var cp: Vector3 = p.person.global_position
	car.teleport(main.bots.lane_point(main.island.z_to_f(cp.z + 700.0), true), Vector3(0, 0, -1))
	await wait(1.5)
	car.set_all_psi(36.0)
	car.brake = 0.0
	car.handbrake = false
	var d := _drive_north(car, 27.0, 1100.0)
	var caught := false
	_in = -1
	follow(car, Vector3(-3.0, 1.8, -9.0), Vector3(0, 0.8, 0), 6.0)
	for i in int(40 * 30):
		if not caught:
			d.update(1.0 / 30.0)
			car.throttle = 1.0
			car.brake = 0.0
		if not caught and p._chase_car != null:
			caught = true
			follow(car, Vector3(0, 3.2, 11.0), Vector3(0, 1.0, -3.0), 4.0)
			_in = frame
			_caption("...or get pulled over!", "Lights, sirens and a speeding fine")
		if caught and frame - _in > 30 * 4:
			car.throttle = 0.0
			car.brake = 1.0
		if caught and frame - _in > 30 * 7:
			break
		await process_frame
	if _in >= 0:
		cuts.append([_in, frame])
	_hide_caption()
	for i in 80:
		await wait(0.25)
		if not p.plan.is_empty() and String(p.plan[0]["do"]) == "ticket" and p.plan[0].has("at"):
			break
	follow(car, Vector3(5.0, 2.2, -2.5), Vector3(0.5, 1.1, 1.0), 4.0)
	await rec(4.0)
	await wait(4.0)
	main.bots.remove_all_ambient()
	await wait(1.0)


func _emergency() -> void:
	main.teleport_local(main.bots.lane_point(0.6, true))
	await wait(1.5)
	car.brake = 1.0
	var a := await _spawn("ambulance")
	var r := await _spawn("ranger")
	var f0: float = main.island.z_to_f(car.global_position.z)
	for k in 2:
		var b: AmbientBot = [a, r][k]
		b.plan.clear()
		b.plan.append({"do": "wait", "t": 0.5})
		b.car.teleport(main.bots.lane_point(f0 + 0.01 + k * 0.004, false) + Vector3.UP, Vector3(0, 0, 1))
		b.plan.append({"do": "lights", "l": true, "s": k == 0})
		b.plan.append({"do": "drive", "speed": 14.0, "make": func() -> PackedVector3Array:
			return main.bots.beach_path(main.island.z_to_f(b.car.global_position.z), f0 - 0.03)})
	await wait(1.5)
	follow(a.car, Vector3(-6.0, 1.6, -9.0), Vector3(0, 0.9, 2.0), 5.0)
	await rec(4.5, "Police, ambos and rangers on patrol", "")
	main.bots.remove_all_ambient()
	await wait(1.0)


func _explore() -> void:
	var spots := [["Lake McKenzie", "Explore lakes...", Vector3(70, 45, 60), Vector3(-30, 32, 55)],
		["Maheno Wreck", "...shipwrecks...", Vector3(-35, 9, 30), Vector3(-30, 6, -26)],
		["Sandy Cape Lighthouse", "...and lighthouses", Vector3(45, 25, 35), Vector3(30, 16, -40)]]
	for s in spots:
		var p := place_pos(String(s[0]))
		var at := p
		if String(s[0]) == "Maheno Wreck":
			for w in main.island.wrecks:
				at = w["pos"]
				break
		if String(s[0]) == "Sandy Cape Lighthouse" and not main.island.lighthouses.is_empty():
			at = main.island.lighthouses[0] + Vector3(0, 8, 0)
		main.teleport_local(p + Vector3(0, 0, 60))
		await wait(1.2)
		dolly(at + (s[2] as Vector3), at + (s[3] as Vector3), at, 3.5)
		await rec(3.3, String(s[1]), String(s[0]))


func _end_card() -> void:
	main.teleport_local(place_pos("Eurong"))
	await wait(1.5)
	car.brake = 1.0
	orbit(car, Vector3(0, 0.8, 0), 9.0, 2.5, 0.2, 1.0)
	await rec(3.0, "Play solo or with the family", "LAN multiplayer - everyone gets their own ute")
	await _card_show("ISLAND 4WD", "Air down.  Send it.  Don't get bogged!", 4.0)

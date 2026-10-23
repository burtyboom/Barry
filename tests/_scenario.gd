extends SceneTree
## Dev harness: godot --path . -s res://tests/_scenario.gd -- <island> <scenario> <out_prefix>
## Loads the real game, starts solo, runs a scripted scenario and saves screenshots.

var main
var out := ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[2]
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.3).timeout
	main._select_island(args[0])
	if args.size() > 3:
		main.avatar_style = args[3]
	await main._start("solo")
	await create_timer(0.5).timeout
	await call(args[1])
	quit()


func shot(name: String) -> void:
	await process_frame
	get_root().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)


func wait(t: float) -> void:
	await create_timer(t).timeout


func place(name: String, yaw_deg := 0.0) -> void:
	for p in main.island.places:
		if p["name"] == name:
			main.local_car.teleport(p["pos"], Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw_deg)))
	await wait(1.5)


# ---------------------------------------------------------------- scenarios
func barge_drive() -> void:
	await wait(17.5)
	main.local_car.scripted = true
	main.local_car.throttle = 0.5
	for i in 16:
		await wait(0.5)
		if main.achievements.is_unlocked("forty_psi"):
			print("forty_psi unlocked at t=", i * 0.5)
			await wait(0.6)
			await shot("ach")
			return
	print("forty_psi NOT unlocked")


func tides() -> void:
	main.set_tide(0.0)
	await place("Eurong", 150)
	await wait(1.0)
	await shot("high")
	main.set_tide(0.5)
	await wait(1.5)
	await shot("low")


func on_foot() -> void:
	await place("Eurong", 0)
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	await wait(0.62)
	await shot("exit_mid")
	await wait(1.2)
	print("state after exit: ", pl.state, " cam target: ", main.camera.target.name)
	await shot("out")
	# walk toward the sea (east = +X), then face it
	main.camera._foot_yaw = PI * 0.5   # camera looks east
	Input.action_press("throttle")
	await wait(1.5)
	Input.action_release("throttle")
	await wait(0.3)
	print("walked to ", pl.global_position)
	await shot("walked")
	# camp: chair + fire
	pl.tools.select(5)
	await wait(0.2)
	pl.tools._use(true)
	pl.tools.ghost_rot = PI
	pl._yaw += PI * 0.5
	await wait(0.2)
	pl.tools.select(6)
	await wait(0.2)
	pl.tools._use(true)
	await wait(0.5)
	await shot("camp")
	var chair = main.props.nearest(pl.global_position, 5.0, "chair")
	print("chair placed: ", not chair.is_empty(), " props: ", main.props.props.size())
	pl.tools._sit(chair)
	await wait(0.8)
	await shot("sit")
	pl.stand_up()
	await wait(0.3)
	# fishing: face the sea and cast hard
	pl._yaw = -PI * 0.5
	pl.global_basis = Basis(Vector3.UP, pl._yaw)
	pl.tools.select(0)
	await wait(0.2)
	pl.tools._use(true)
	await wait(1.0)
	await shot("windup")
	print("charge before release ", pl.tools.charge, " tip ", pl.tools._rod_tip_pos(), " player ", pl.global_position, " fwd ", -pl.global_basis.z)
	pl.tools._use(false)
	print("after release: fish=", pl.tools._fish, " vel ", pl.tools._bob_vel, " pos ", pl.tools._bob_pos)
	await wait(0.2)
	print("0.2s: fish=", pl.tools._fish, " pos ", pl.tools._bob_pos)
	await wait(0.25)
	await shot("cast")
	await wait(2.0)
	print("bobber in water: ", pl.tools._bob_in_water, " state ", pl.tools._fish)
	await shot("bobber")


## Free camera looking at a point (stops the follow camera).
func look(from: Vector3, at: Vector3) -> void:
	main.camera.target = null
	main.camera.global_position = from
	main.camera.look_at(at, Vector3.UP)


func showcase() -> void:
	await place("Eurong", 0)
	var car: SandVehicle = main.local_car
	# drive 25 m north, away from the sign
	car.teleport(car.global_position + Vector3(0, 0, -25), Vector3.FORWARD)
	await wait(1.5)
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	var side := car.global_transform * Vector3(4.5, 1.6, 1.5)
	look(side, car.global_transform * Vector3(0.8, 0.9, 0))
	for k in [0.35, 0.75, 1.05]:
		await wait(k - (0.0 if k == 0.35 else 0.0))
		await shot("exit_%.2f" % k)
	await wait(1.0)
	# camp: chair facing a fire, tent and umbrella behind, esky beside
	var base := pl.global_position
	var east := Vector3(1, 0, 0)
	main.props.place("fire", Transform3D(Basis.IDENTITY, _ground(base + east * 3.0)))
	main.props.place("chair", Transform3D(Basis(Vector3.UP, -PI * 0.5), _ground(base + east * 1.6)))
	main.props.place("tent", Transform3D(Basis(Vector3.UP, PI * 0.5), _ground(base + east * 3.2 + Vector3(0, 0, -4.0))))
	main.props.place("umbrella", Transform3D(Basis.IDENTITY, _ground(base + east * 5.0 + Vector3(0, 0, 2.0))))
	main.props.place("esky", Transform3D(Basis(Vector3.UP, 0.4), _ground(base + east * 2.0 + Vector3(0, 0, 1.2))))
	await wait(0.3)
	var chair = main.props.nearest(base + east * 1.6, 1.0, "chair")
	pl.tools._sit(chair)
	await wait(0.6)
	look(base + Vector3(2.5, 2.2, 6.5), base + east * 2.6 + Vector3(0, 0.6, -1))
	await wait(0.4)
	await shot("camp")
	pl.stand_up()
	await wait(0.2)
	# fishing from the waterline
	pl.global_position = _ground(base + east * 14.0)
	pl._yaw = -PI * 0.5
	pl.global_basis = Basis(Vector3.UP, pl._yaw)
	pl.tools.select(0)
	await wait(0.2)
	pl.tools._use(true)
	await wait(0.8)
	look(pl.global_position + Vector3(-1.0, 1.8, 5.0), pl.global_position + Vector3(1.5, 1.4, 0))
	await shot("windup")
	pl.tools._use(false)
	await wait(1.6)
	look(pl.global_position + Vector3(-4.0, 3.0, 6.0), pl.global_position + Vector3(8.0, 0.5, 0))
	await wait(0.3)
	await shot("fishing")


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, main.island.height_at(p.x, p.z), p.z)


func _second_car(pos: Vector3) -> SandVehicle:
	var c := SandVehicle.new()
	c.name = "Car_99"
	c.body_color = Color(0.8, 0.15, 0.12)
	c.local_control = true
	c.scripted = true
	main.cars.add_child(c)
	c.teleport(pos, Vector3.FORWARD)
	return c


func strap() -> void:
	await place("Eurong", 0)
	var a: SandVehicle = main.local_car         # the "bogged" car: soft sand, dug in
	a.scripted = true
	var b := _second_car(a.global_position + Vector3(0, 0, -7.5))
	await wait(1.5)
	# bury car A: deep dig on every wheel, handbrake off, no throttle
	for w in a.wheels:
		w.dig = 0.25
	a.handbrake = false
	main.ropes.create("strap", {"car": String(b.name), "p": SandVehicle.REAR_POINT}, {"car": String(a.name), "p": SandVehicle.FRONT_POINT}, Ropes.STRAP_LEN)
	await wait(0.3)
	look(a.global_position + Vector3(9, 4, -4), a.global_position + Vector3(0, 0.5, -6))
	b.throttle = 1.0
	var z0 := a.global_position.z
	var peak := 0.0
	for i in 30:
		await wait(0.1)
		var r: Dictionary = main.ropes.ropes.values()[0] if main.ropes.ropes.size() > 0 else {}
		var t: float = r.get("tension", 0.0)
		peak = maxf(peak, t)
		if i % 5 == 0:
			print("t=%.1f  B %.0f km/h  A moved %.2f m  A %.0f km/h  tension %.0f N" % [i * 0.1, b.speed_kmh, z0 - a.global_position.z, a.speed_kmh, t])
		if i == 9:
			look(a.global_position + Vector3(9, 4, -4), a.global_position + Vector3(0, 0.5, -6))
			await shot("strap_taut")
	print("peak tension %.0f N, A moved %.1f m" % [peak, z0 - a.global_position.z])


func winch() -> void:
	await place("Eurong", 0)
	var a: SandVehicle = main.local_car
	a.scripted = true
	await wait(1.0)
	for w in a.wheels:
		w.dig = 0.2
	var anchor := a.global_transform * Vector3(0, 0.9, -18.0)
	main.ropes.create("winch", {"car": String(a.name), "p": SandVehicle.FRONT_POINT}, {"world": anchor}, 15.0)
	Input.action_press("winch_in")
	var z0 := a.global_position.z
	for i in 10:
		await wait(1.0)
		var r: Dictionary = main.ropes.ropes.values()[0]
		print("t=%d  rope %.1f m  tension %.0f N  moved %.2f m" % [i + 1, r["rest"], r["tension"], z0 - a.global_position.z])
	Input.action_release("winch_in")
	look(a.global_position + Vector3(7, 3, 2), a.global_position + Vector3(0, 0.5, -5))
	await shot("winch")


func tyres() -> void:
	await place("Eurong", 0)
	var car: SandVehicle = main.local_car
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	await wait(1.6)
	# deflators on both front tyres, target 16
	pl.tools.select(3)
	pl.tools.deflate_target = 16.0
	for i in [0, 1]:
		pl.global_position = car.wheel_valve_world(i) + (car.global_basis.x * (0.6 if i == 1 else -0.6))
		pl.global_position.y = main.island.height_at(pl.global_position.x, pl.global_position.z)
		await wait(0.15)
		pl.tools._use(true)
		await wait(0.1)
	print("deflators: ", car.deflators)
	look(car.global_transform * Vector3(2.6, 0.9, -3.2), car.global_transform * Vector3(0.9, 0.2, -1.45))
	await wait(0.2)
	await shot("deflators")
	await wait(12.0)
	print("after 12 s: FL %.1f FR %.1f RL %.1f  achievements deflators=%s" % [car.wheels[0].psi, car.wheels[1].psi, car.wheels[2].psi, main.achievements.is_unlocked("deflators")])
	# inflator on FR
	pl.tools.select(2)
	await wait(0.2)
	pl.tools._use(true)
	await wait(3.0)
	pl.tools._use(false)
	print("FR after 3 s of inflating: %.1f" % car.wheels[1].psi)
	look(pl.global_position + Vector3(-3, 2.4, 4), pl.global_position + Vector3(0, 0.8, 0))
	await shot("inflator")
	# shovel on FR
	car.wheels[1].dig = 0.3
	pl.tools.select(4)
	await wait(0.2)
	pl.tools._use(true)
	await wait(0.8)
	await shot("shovel")
	await wait(1.2)
	print("FR dig after shovel: %.2f" % car.wheels[1].dig)


func _fps(label: String) -> void:
	await wait(2.5)
	print("PERF %-28s %d fps" % [label, Engine.get_frames_per_second()])


func perf() -> void:
	await place("Eurong", 0)
	await _fps("everything")
	main.hud.process_mode = Node.PROCESS_MODE_DISABLED
	await _fps("hud process off")
	main.hud.visible = false
	for c in main.hud.get_children():
		if c is SubViewport:
			c.queue_free()
	await _fps("hud viewports freed")
	main.players.process_mode = Node.PROCESS_MODE_DISABLED
	await _fps("players off")
	main.ropes.process_mode = Node.PROCESS_MODE_DISABLED
	main.props.process_mode = Node.PROCESS_MODE_DISABLED
	await _fps("ropes+props off")
	for c in main.cars.get_children():
		c.process_mode = Node.PROCESS_MODE_DISABLED
	await _fps("cars off")
	main.process_mode = Node.PROCESS_MODE_DISABLED
	await _fps("main off")


func perf2() -> void:
	await place("Eurong", 0)
	await _fps("everything")
	var w: Node = main.world
	for nm in ["CoffeeRocks", "PalmTrunks", "PalmFronds"]:
		var n = w.get_node_or_null(nm)
		if n:
			n.visible = false
	await _fps("rocks+palms hidden")
	var gc = w.get_node_or_null("GroundCover")
	if gc:
		gc.visible = false
	await _fps("ground cover hidden")
	for nm in ["TreeTrunks", "TreeLeaves", "TreePines", "Scrub"]:
		var n = w.get_node_or_null(nm)
		if n:
			n.visible = false
	await _fps("trees hidden")
	for c in w.get_children():
		if c is StaticBody3D:
			c.visible = false
	await _fps("bodies (wrecks/jetty/huts) hidden")
	for c in w.get_children():
		if c is MeshInstance3D and String(c.name).begins_with("Terrain"):
			c.visible = false
	await _fps("terrain hidden")
	for c in w.get_children():
		if c is Node3D:
			c.visible = false
	await _fps("whole world hidden")
	main.cars.visible = false
	main.players.visible = false
	await _fps("cars + players hidden")


func spare() -> void:
	await place("Eurong", 0)
	var first: SandVehicle = main.local_car
	main.spawn_spare_ute()
	await wait(1.5)
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	await wait(1.6)
	var spare_car: SandVehicle = null
	for c in main.cars.get_children():
		if c != first:
			spare_car = c
	var spot := spare_car.global_transform * PlayerCharacter.OUTSIDE
	pl.global_position = Vector3(spot.x, main.island.height_at(spot.x, spot.z), spot.z)
	await wait(0.4)
	print("prompt near spare: ", pl.tools.prompt)
	pl.tools._action.call()
	await wait(1.6)
	print("now driving ", main.local_car.name, " (spare=", spare_car.name, ") state=", pl.state, " first.driver=", first.driver_present, " spare.driver=", spare_car.driver_present)
	look(spare_car.global_position + Vector3(6, 3, 6), spare_car.global_position)
	await shot("spare")


func wildlife() -> void:
	await place("Eurong", 0)
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	await wait(1.6)
	# walk toward the dingo spot a little north
	var d0: Dingo = null
	for c in main.world.get_children():
		if c is Dingo:
			d0 = c
			break
	print("dingoes: ", main.island.dingo_homes.size(), " first at ", d0.global_position if d0 else Vector3.ZERO)
	pl.global_position = d0.global_position + Vector3(-5, 0.2, 2)
	await wait(4.0)
	print("dingo state near player: ", d0._state, " dist ", d0.global_position.distance_to(pl.global_position))
	look(pl.global_position + Vector3(-3, 2.0, 5), d0.global_position + Vector3(0, 0.5, 0))
	await shot("dingo")
	# a ute rolls into us
	main.island.force_soft = 0.1
	var c := _second_car(pl.global_position + Vector3(0, 0, 12))
	await wait(1.2)
	c.throttle = 0.7
	var y0 := pl.global_position.y
	var top := 0.0
	for i in 40:
		await wait(0.05)
		top = maxf(top, pl.global_position.y - y0)
		if i % 8 == 0:
			var lp := c.global_transform.affine_inverse() * (pl.global_position + Vector3.UP * 0.8)
			print("car %.1f m/s at %s  player local %s" % [c.linear_velocity.length(), c.global_position, lp])
		if i == 30:
			look(pl.global_position + Vector3(6, 2, 0), pl.global_position)
			await shot("bump")
	print("bumped: max height %.1f m, stun left %.2f" % [top, pl._stun])


func bead() -> void:
	await place("Eurong", 0)
	var car: SandVehicle = main.local_car
	main.island.force_soft = 0.1
	car.set_all_psi(10.0)
	car.scripted = true
	car.throttle = 1.0
	await wait(5.0)
	print("speed %.0f km/h, now hard left" % car.speed_kmh)
	car.steer = 0.5
	var risk := 0.0
	for i in 30:
		await wait(0.1)
		for w in car.wheels:
			risk = maxf(risk, w.bead_risk)
		if i % 5 == 0:
			var sl := 0.0
			for w in car.wheels:
				sl = maxf(sl, absf(w.lat_force) / maxf(w.load, 1.0))
			print("  turning %.0f km/h  max side load %.2f  max risk %.2f" % [car.speed_kmh, sl, risk])
		var flats := car.wheels.filter(func(w): return w.flat).map(func(w): return w.name)
		if flats.size() > 0:
			print("rolled a bead on ", flats, " at %.0f km/h" % car.speed_kmh)
			break
	car.throttle = 0.0
	car.steer = 0.0
	await wait(3.0)
	var w0 := -1
	for i in car.wheels.size():
		if car.wheels[i].flat:
			w0 = i
	if w0 < 0:
		print("no bead rolled")
		return
	car.set_all_psi(32.0)
	print("after pressing 1 (no pump): %s flat=%s psi %.0f" % [car.wheels[w0].name, car.wheels[w0].flat, car.wheels[w0].psi])
	for k in 20:
		car.set_wheel_psi(w0, car.wheels[w0].psi + 1.0, true)
	print("after pumping: flat=%s psi %.0f  achievements bead=%s reseat=%s" % [car.wheels[w0].flat, car.wheels[w0].psi, main.achievements.is_unlocked("bead"), main.achievements.is_unlocked("reseat")])


func achlist() -> void:
	await wait(0.5)
	main.achievements.unlock("bogged")
	main.achievements.unlock("forty_psi")
	await wait(5.0)
	main.hud._admin.visible = true
	main.hud._toggle_achievement_list()
	await wait(0.4)
	await shot("achlist")


func plane() -> void:
	await place("Eurong", 0)
	var pl = null
	for c in main.world.get_children():
		if c is Ambient.BeachPlane:
			pl = c
	pl._t = 27.0
	await wait(0.5)
	look(pl.global_position + Vector3(-14, 5, 10), pl.global_position + Vector3(0, 1, 0))
	await shot("plane")
	pl._t = 12.0
	await wait(0.3)
	look(pl.global_position + Vector3(-30, 6, 30), pl.global_position)
	await shot("plane_air")


func dolphins() -> void:
	var d = null
	for c in main.world.get_children():
		if c is Ambient.Dolphins:
			d = c
	d._phase[0] = 0.75
	await wait(0.05)
	var p: Vector3 = d.global_position
	look(p + Vector3(-12, 4, 10), p + Vector3(-6, 1, 0))
	await shot("dolphins")


func handling() -> void:
	await place("Eurong", 0)
	var car: SandVehicle = main.local_car
	main.island.force_soft = 0.08
	car.scripted = true
	car.set_all_psi(20.0)
	car.throttle = 1.0
	for i in 10:
		await wait(1.0)
	print("straight-line: %.0f km/h after 10 s" % car.speed_kmh)
	# slalom
	var max_roll := 0.0
	var max_yaw := 0.0
	for i in 60:
		car.steer = 0.35 * sign(sin(i * 0.1 * TAU / 3.0))
		await wait(0.1)
		max_roll = maxf(max_roll, absf(car.global_basis.get_euler().z))
		max_yaw = maxf(max_yaw, absf(car.angular_velocity.y))
	print("slalom at %.0f km/h: max roll %.0f deg, max yaw rate %.2f rad/s, flipped=%s" % [car.speed_kmh, rad_to_deg(max_roll), max_yaw, car.global_basis.y.y < 0.3])
	# hard turn at speed
	car.steer = 0.55
	var spun := false
	for i in 30:
		await wait(0.1)
		var fwd := -car.global_basis.z
		var vel := car.linear_velocity
		vel.y = 0
		if vel.length() > 3.0 and absf(fwd.angle_to(vel.normalized())) > 1.0:
			spun = true
	print("hard turn: spun out=%s, flipped=%s, %.0f km/h" % [spun, car.global_basis.y.y < 0.3, car.speed_kmh])
	car.steer = 0.0
	car.throttle = 0.0
	car.brake = 1.0
	var t0 := 0.0
	var v0 := car.speed_kmh
	while car.speed_kmh > 1.0 and t0 < 10.0:
		await wait(0.1)
		t0 += 0.1
	print("braking from %.0f km/h took %.1f s" % [v0, t0])


# ---------------------------------------------------------------- bots
## Bog it properly: sugar-soft sand at road pressure, foot down. Then the sand goes
## back to normal but the holes it dug stay.
func _bog(car: SandVehicle) -> void:
	main.island.force_soft = 1.0
	car.set_all_psi(32.0)
	car.brake = 0.0
	car.throttle = 1.0
	var was := false
	for i in 60:
		await wait(0.2)
		if car.is_bogged:
			was = true
			break
	car.throttle = 0.0
	main.island.force_soft = -1.0
	var dig := 0.0
	for w in car.wheels:
		dig = maxf(dig, w.dig)
	print("bogged: %s  dig %.2f" % [was, dig])


func _helper_follow(h: HelperBot, car: SandVehicle, secs: float) -> void:
	var maxd := 0.0
	var n := int(secs / 0.5)
	for i in n:
		car.steer = 0.10 * sin(i * 0.25)
		await wait(0.5)
		var d := h.car.global_position.distance_to(car.global_position)
		if i > 12:
			maxd = maxf(maxd, d)
		if i % 6 == 0:
			print("t=%4.1f  you %3.0f km/h  helper %3.0f km/h  gap %5.1f m  %s  [want %.1f thr %.2f brk %.2f steer %.2f soft %.2f]" % [i * 0.5, car.speed_kmh, h.car.speed_kmh, d, h.driver.status, h.driver.speed, h.car.throttle, h.car.brake, h.car.steer, h.car.avg_soft])
	print("FOLLOW max gap after settling: %.1f m" % maxd)


func helper() -> void:
	await place("Eurong", 0)
	var car: SandVehicle = main.local_car
	car.scripted = true
	car.set_all_psi(18.0)
	main.bots.spawn("helper")
	await wait(1.0)
	var h: HelperBot = main.bots.helper
	print("helper spawned %.0f m away" % h.car.global_position.distance_to(car.global_position))
	car.throttle = 0.55
	await _helper_follow(h, car, 24.0)
	print("-- flat out")
	car.throttle = 1.0
	await _helper_follow(h, car, 16.0)
	car.throttle = 0.0
	car.brake = 1.0
	await wait(5.0)
	print("stopped: gap %.1f m  %s" % [h.car.global_position.distance_to(car.global_position), h.driver.status])
	await _bog(car)
	for i in 60:
		await wait(0.5)
		if i % 4 == 0:
			print("assist t=%.0f phase %s gap %.1f  %s" % [i * 0.5, h.phase, h.car.global_position.distance_to(car.global_position), h.driver.status])
		if h.phase == "ready":
			break
	var bb := h.car.global_transform * SandVehicle.FRONT_POINT
	var hitch := car.global_transform * SandVehicle.REAR_POINT
	print("READY phase=%s  centre gap %.1f m  helper bullbar -> your hitch %.1f m" % [h.phase, h.car.global_position.distance_to(car.global_position), bb.distance_to(hitch)])
	look(car.global_position + Vector3(9, 5, 4), car.global_position.lerp(h.car.global_position, 0.5))
	await shot("ready")
	main.ropes.create("strap", {"car": String(h.car.name), "p": SandVehicle.FRONT_POINT}, {"car": String(car.name), "p": SandVehicle.REAR_POINT}, Ropes.STRAP_LEN)
	var p0 := car.global_position
	var peak := 0.0
	for i in 60:
		await wait(0.25)
		var r: Dictionary = main.ropes.ropes.values()[0] if main.ropes.ropes.size() > 0 else {}
		peak = maxf(peak, float(r.get("tension", 0.0)))
		if i % 4 == 0:
			print("snatch t=%.1f phase %-9s tension %6.0f  you moved %.1f m  %s" % [i * 0.25, h.phase, float(r.get("tension", 0.0)), car.global_position.distance_to(p0), h.driver.status])
		if i == 15:
			look(car.global_position + Vector3(9, 5, 4), car.global_position.lerp(h.car.global_position, 0.5))
			await shot("pull")
		if h.phase == "done":
			break
	print("SNATCH result: phase %s, peak %.0f N, you moved %.1f m, tries %d" % [h.phase, peak, car.global_position.distance_to(p0), h._tries])
	for id in main.ropes.ropes.keys():
		main.ropes.remove(id)
	await wait(1.0)
	print("after unhook: mode %d" % h.mode)
	# teleport: helper should turn up behind
	await place("Happy Valley", 0)
	await wait(1.0)
	print("after teleport gap %.1f m" % h.car.global_position.distance_to(car.global_position))


func helper_front() -> void:
	await place("Eurong", 0)
	var car: SandVehicle = main.local_car
	car.scripted = true
	main.bots.spawn("helper")
	await wait(2.0)
	var h: HelperBot = main.bots.helper
	await _bog(car)
	h.come("front")
	for i in 120:
		await wait(0.5)
		if i % 6 == 0:
			print("front t=%.0f phase %s gap %.1f  %s" % [i * 0.5, h.phase, h.car.global_position.distance_to(car.global_position), h.driver.status])
		if h.phase == "ready":
			break
	var hitch := h.car.global_transform * SandVehicle.REAR_POINT
	var bb := car.global_transform * SandVehicle.FRONT_POINT
	var align := (-h.car.global_basis.z).dot(-car.global_basis.z)
	print("FRONT phase=%s  helper hitch -> your bullbar %.1f m  heading match %.2f" % [h.phase, hitch.distance_to(bb), align])
	look(car.global_position + Vector3(10, 6, 2), car.global_position.lerp(h.car.global_position, 0.5))
	await shot("front")
	# winch from our bullbar to its tow hitch
	main.ropes.create("winch", {"car": String(car.name), "p": SandVehicle.FRONT_POINT}, {"car": String(h.car.name), "p": SandVehicle.REAR_POINT}, hitch.distance_to(bb) + 0.3)
	Input.action_press("winch_in")
	var p0 := car.global_position
	var h0 := h.car.global_position
	for i in 8:
		await wait(1.0)
	Input.action_release("winch_in")
	print("WINCH: you moved %.1f m, helper moved %.2f m (frozen=%s)" % [car.global_position.distance_to(p0), h.car.global_position.distance_to(h0), h.car.freeze])


func bots() -> void:
	await place("Eurong" if main.island.id == "fraser" else "Tangalooma Wrecks", 0)
	var car: SandVehicle = main.local_car
	car.scripted = true
	main.bots.build_segments()
	var segs := []
	for s in main.bots.segments:
		segs.append("%.3f-%.3f (%d m)" % [s.x, s.y, int((s.y - s.x) * main.island.length)])
	print("beach segments: ", segs)
	for r in ["fisher", "camper", "cruiser", "tracker"]:
		main.bots.spawn(r)
	await wait(1.0)
	var brains: Array = main.bots.brains()
	var start := {}
	for b in brains:
		start[b] = b.car.global_position
	for t in int(OS.get_environment("BOT_T")) if OS.get_environment("BOT_T") != "" else 24:
		await wait(10.0)
		var line := "t=%3d " % ((t + 1) * 10)
		for b in brains:
			var st: String = b.plan[0]["do"] if not b.plan.is_empty() else "-"
			line += " | %s %s %s%s" % [b.role, st, "car" if b.in_car() else "foot", " BOG" if b.car.is_bogged else ""]
			if b.role == "tracker" or st == "walk" or st == "walk_edge":
				line += " [%s @%.0f,%.0f psi %.0f %s]" % [b.driver.status, b.car.global_position.x, b.car.global_position.z, b.car.average_psi(), "pers %.0f,%.0f" % [b.person.global_position.x, b.person.global_position.z]]
		print(line, "  props=", main.props.props.size())
		if t == 5 or t == 14:
			for b in brains:
				if b.role == "fisher" or b.role == "camper":
					var p: Vector3 = b.person.global_position
					look(p + Vector3(-6, 4, 9), p + Vector3(2, 0.5, 0))
					await shot("%s_%d" % [b.role, t])
	for b in brains:
		print("%s %s travelled %.0f m (straight line), on beach=%s" % [b.role, b.display, b.car.global_position.distance_to(start[b]), main.bots.on_east_beach(b.car.global_position)])


## Drive a real inland track with the helper behind (autopilot on the track path).
func helper_track() -> void:
	var t: Dictionary = {}
	for tr in main.island.tracks_built:
		if tr["name"] == "Eurong - Central Station":
			t = tr
	var path: PackedVector2Array = t["path"]
	var car: SandVehicle = main.local_car
	var p0 := Vector3(path[0].x, 0, path[0].y)
	var p1 := Vector3(path[3].x, 0, path[3].y)
	car.teleport(p0, (p1 - p0).normalized())
	await wait(1.5)
	car.scripted = true
	car.set_all_psi(16.0)
	main.bots.spawn("helper")
	await wait(1.0)
	var h: HelperBot = main.bots.helper
	var d := BotDriver.new(car)
	var pts := PackedVector3Array()
	for v in path:
		pts.append(Vector3(v.x, 0, v.y))
	d.set_path(pts, 8.0)
	var maxd := 0.0
	for i in 400:
		await wait(0.25)
		if d.update(0.25):
			break
		var gap := h.car.global_position.distance_to(car.global_position)
		if i > 20:
			maxd = maxf(maxd, gap)
		if i % 20 == 0:
			print("t=%3.0f you %3.0f km/h  helper %3.0f km/h gap %5.1f  %s | lead %s" % [i * 0.25, car.speed_kmh, h.car.speed_kmh, gap, h.driver.status, d.status])
	print("TRACK done=%s max gap %.1f m, final gap %.1f" % [d.done, maxd, h.car.global_position.distance_to(car.global_position)])


func _mouse_btn(btn: int, pressed: bool, pos: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = btn
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	Input.parse_input_event(e)


func _mouse_move(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	Input.parse_input_event(e)


## Camp gear follows the mouse; right-drag spins it; left click places it there.
func place_mouse() -> void:
	await place("Eurong", 90)
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	await wait(1.8)
	pl.tools.select(7)   # tent
	await wait(0.2)
	var vp := get_root().get_visible_rect().size
	var target := Vector2(vp.x * 0.62, vp.y * 0.62)
	get_root().warp_mouse(target)
	_mouse_move(target, Vector2(5, 0))
	await wait(0.3)
	var g: Node3D = pl.tools._ghost
	print("mouse pos ", get_root().get_mouse_position(), " want ", target, " ground ", pl.tools._mouse_ground(), " aim ", pl.tools._mouse_aim)
	print("ghost at %s, %.1f m from you, ok=%s" % [g.global_position, g.global_position.distance_to(pl.global_position), pl.tools._ghost_ok])
	var yaw0 := g.global_rotation.y
	var cam_yaw0: float = main.camera._foot_yaw
	_mouse_btn(MOUSE_BUTTON_RIGHT, true, target)
	for k in 10:
		_mouse_move(target, Vector2(12, 0))
		await process_frame
	_mouse_btn(MOUSE_BUTTON_RIGHT, false, target)
	await wait(0.2)
	print("right-drag: tent turned %.0f deg, camera turned %.2f rad (should be 0), ghost moved %.2f m" % [rad_to_deg(angle_difference(yaw0, g.global_rotation.y)), main.camera._foot_yaw - cam_yaw0, 0.0])
	var spot := g.global_position
	_mouse_btn(MOUSE_BUTTON_LEFT, true, target)
	await process_frame
	_mouse_btn(MOUSE_BUTTON_LEFT, false, target)
	await wait(0.4)
	var t: Dictionary = main.props.nearest(spot, 0.5, "tent")
	print("placed tent where the ghost was: %s" % (not t.is_empty()))
	# far away point gets clamped to reach
	get_root().warp_mouse(Vector2(vp.x * 0.5, vp.y * 0.30))
	_mouse_move(Vector2(vp.x * 0.5, vp.y * 0.30), Vector2(1, 0))
	await wait(0.2)
	print("far mouse: ghost %.1f m away (max %.0f)" % [g.global_position.distance_to(pl.global_position), PlayerTools.PLACE_RANGE])
	get_root().warp_mouse(target)
	_mouse_move(target, Vector2(1, 0))
	await wait(0.3)
	await shot("ghost")
	# admin bots tab
	main.hud._admin.visible = true
	main.hud._show_tab(2)
	await wait(0.3)
	await shot("admin_bots")


# ---------------------------------------------------------------- 2026-10-23 batch
## Spawn one island bot of a role, parked near the player on the beach. Returns its brain.
func _one_bot(role: String) -> AmbientBot:
	var before: Array = main.bots.brains()
	main.bots.spawn(role)
	await wait(0.5)
	for b in main.bots.brains():
		if not before.has(b):
			return b
	return null


func _bot_line(b: AmbientBot) -> String:
	var st: String = b.plan[0]["do"] if not b.plan.is_empty() else "-"
	var ph := ""
	if st == "rescue":
		ph = String(b.plan[0].get("ph", "approach"))
	return "%s[%s %s %s %s%s]" % [b.short_name(), b.role, st, ph, "car" if b.in_car() else "foot",
		" HELP" if b.needs_help else ""]


## Bot bogs, another bot snatches it out (help chance forced to 100 %).
func rescue() -> void:
	await place("Eurong", 0)
	main.local_car.scripted = true
	main.bots.help_chance = 1.0
	var a := await _one_bot("cruiser")
	await wait(6.0)
	a.force_bog()
	await wait(4.0)
	print("bogged: needs_help=%s icon=%s" % [a.needs_help, a.person._icon != null])
	var b := await _one_bot("cruiser")
	# send the second bot along the beach right past the bogged one
	b.plan.clear()
	var f0: float = main.island.z_to_f(a.car.global_position.z)
	b.car.teleport(main.bots.lane_point(f0 - 0.02, true) + Vector3.UP, Vector3(0, 0, -1))
	b.plan.append({"do": "get_in"})
	b.plan.append({"do": "drive", "speed": 12.0, "make": func() -> PackedVector3Array:
		return main.bots.beach_path(main.island.z_to_f(b.car.global_position.z), f0 + 0.03)})
	var spot := a.car.global_position
	for i in 70:
		await wait(3.0)
		var r := ""
		for id in main.ropes.ropes:
			r = "rope %s %.1fkN" % [main.ropes.ropes[id]["kind"], float(main.ropes.ropes[id]["tension"]) / 1000.0]
		print("t=%3d %s  %s  A moved %.1f m  gap %.1f  %s  [%s]" % [i * 3, _bot_line(a), _bot_line(b),
			a.car.global_position.distance_to(spot), a.car.global_position.distance_to(b.car.global_position), r, b.driver.status])
		if i == 12 or (r != "" and not has_meta("shot")):
			if r != "":
				set_meta("shot", true)
			look(a.car.global_position + Vector3(-12, 5, 8), a.car.global_position.lerp(b.car.global_position, 0.5))
			await shot("rescue_%d" % i)
		if not a.needs_help and main.ropes.ropes.is_empty() and i > 3:
			print("RESCUED: A moved %.1f m from where it bogged" % a.car.global_position.distance_to(spot))
			return
	print("NOT rescued")


## Player snatches a bogged bot out with their own ute (strap), then winches another.
func player_rescue() -> void:
	await place("Eurong", 0)
	var car: SandVehicle = main.local_car
	car.scripted = true
	var a := await _one_bot("cruiser")
	await wait(4.0)
	a.force_bog()
	await wait(3.0)
	# park our ute 11 m behind it, facing it, and strap our bullbar to its tow hitch
	var back := a.car.global_basis.z
	back.y = 0
	back = back.normalized()
	car.teleport(a.car.global_position + back * 11.0, -back)
	await wait(2.0)
	look(a.car.global_position + Vector3(-12, 5, 8), a.car.global_position)
	await shot("bogged_bot")
	var spot := a.car.global_position
	main.ropes.create("strap", {"car": String(car.name), "p": SandVehicle.FRONT_POINT}, {"car": String(a.car.name), "p": SandVehicle.REAR_POINT}, Ropes.STRAP_LEN)
	await wait(5.0)
	print("after hook-up: %s in car=%s" % [_bot_line(a), a.in_car()])
	car.reversing = true
	car.throttle = 1.0
	for i in 12:
		await wait(0.5)
		print("  t=%.1f  bot moved %.1f m  %s freed=%s" % [i * 0.5, a.car.global_position.distance_to(spot), a.driver.status, a.freed])
	car.throttle = 0.0
	car.reversing = false
	car.brake = 1.0
	await wait(2.0)
	print("freed=%s samaritan=%s" % [a.freed, main.achievements.is_unlocked("samaritan")])
	for id in main.ropes.ropes.keys():
		main.ropes.remove(id)
	await wait(3.0)
	print("after unhook: %s" % _bot_line(a))
	# winch: bog it again, then winch it to us with the remote / cab buttons
	await wait(5.0)
	a.force_bog()
	await wait(3.0)
	back = a.car.global_basis.z
	back.y = 0
	back = back.normalized()
	car.teleport(a.car.global_position + back * 16.0, -back)
	car.brake = 1.0
	car.handbrake = true
	await wait(2.0)
	spot = a.car.global_position
	var wl := (car.global_transform * SandVehicle.FRONT_POINT).distance_to(a.car.global_transform * SandVehicle.REAR_POINT)
	main.ropes.create("winch", {"car": String(car.name), "p": SandVehicle.FRONT_POINT}, {"car": String(a.car.name), "p": SandVehicle.REAR_POINT}, wl + 0.3)
	await wait(4.0)
	main.ropes.cab_in = true
	var c0 := car.global_position
	for i in 10:
		await wait(1.0)
		var r: Dictionary = main.ropes.ropes.values()[0]
		print("  winch t=%d cable %.1f m  tension %.0f N  bot moved %.1f m  our ute moved %.1f m  freed=%s" % [i + 1, r["rest"], r["tension"],
			a.car.global_position.distance_to(spot), car.global_position.distance_to(c0), a.freed])
	main.ropes.cab_in = false


## Police speed trap: drive at the radar at ~80 km/h, get pulled over and fined.
func police() -> void:
	main.set_tide(0.5)
	await place("Eurong", 0)
	var car: SandVehicle = main.local_car
	car.scripted = true
	var p := await _one_bot("police")
	await wait(3.0)
	# set up the trap right here, facing south (+z)
	p.plan.clear()
	p.plan.append({"do": "wait", "t": 1.0})
	p.car.teleport(main.bots.lane_point(main.island.z_to_f(car.global_position.z) - 0.03, false) + Vector3.UP, Vector3(0, 0, 1))
	p.plan.append({"do": "get_out"})
	p.plan.append({"do": "trap", "dur": 300.0, "face": Vector3(0, 0, 1)})
	p.plan.append({"do": "get_in"})
	await wait(8.0)
	look(p.person.global_position + Vector3(-4, 2.5, -4), p.person.global_position + Vector3(0, 1.2, 2))
	await shot("radar")
	# line up 150 m south of the cop, heading north at him
	var cp := p.person.global_position
	var lp: Vector3 = main.bots.lane_point(main.island.z_to_f(cp.z + 160.0), true)
	car.teleport(lp, Vector3(0, 0, -1))
	await wait(1.5)
	car.set_all_psi(36.0)
	var d := BotDriver.new(car)
	d.set_path(main.bots.beach_path(main.island.z_to_f(car.global_position.z), main.island.z_to_f(cp.z - 300.0)), 23.0)
	d.ease_to_end = false
	var caught := false
	for i in 120:
		await wait(0.25)
		if not caught:
			d.update(0.25)
			car.throttle = 1.0
			car.brake = 0.0
		if not caught and p.plan.size() > 0 and String(p.plan[0]["do"]) in ["get_in", "chase"] and p._chase_car != null:
			caught = true
			print("CAUGHT at %.0f km/h (radar %d)" % [car.speed_kmh, p._chase_kmh])
			# pull over: brake to a stop
			car.throttle = 0.0
			car.brake = 1.0
		if i % 8 == 0:
			print("t=%.0f  us %.0f km/h  cop %s  lights=%s siren=%s  gap %.0f" % [i * 0.25, car.speed_kmh, _bot_line(p), p.car.lights_on, p.car.siren_on, p.car.global_position.distance_to(car.global_position)])
	for i in 30:
		await wait(1.0)
		if i % 3 == 0:
			print("t=%d  cop %s gap %.0f  fines $%d" % [i, _bot_line(p), p.person.global_position.distance_to(car.global_position), main.fines_total])
		if i == 6:
			look(car.global_position + Vector3(-7, 4, 10), car.global_position.lerp(p.car.global_position, 0.5))
			await shot("pulled_over")
		if main.fines_total > 0 and i > 10:
			break
	print("fines $%d  booked=%s" % [main.fines_total, main.achievements.is_unlocked("booked")])


## Camper invites you over; sit in the spare chair and have a yarn.
func camper_guest() -> void:
	await place("Eurong", 0)
	main.local_car.scripted = true
	var c := await _one_bot("camper")
	for i in 60:
		await wait(2.0)
		if c._guest_chair != "" and c.person.state == PlayerCharacter.State.SITTING:
			break
	print("camp set up: guest chair=%s  camper sitting=%s" % [c._guest_chair, c.person.state == PlayerCharacter.State.SITTING])
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	await wait(1.6)
	var chair: Node3D = main.props.props[c._guest_chair]
	pl.global_position = chair.global_position + Vector3(4, 0.5, 4)
	await wait(2.0)
	print("invited: %s" % c._invited.has(1))
	pl.tools._sit({"node": chair, "id": c._guest_chair})
	for i in 30:
		await wait(1.0)
		if pl._bubble == null:
			pass
	print("guest=%d campfire_guest=%s" % [c._guest, main.achievements.is_unlocked("campfire_guest")])
	look(chair.global_position + Vector3(-5, 3, 5), chair.global_position + Vector3(-1, 0.8, 0))
	await shot("campfire")


## Aimed casting: lands on the ring; dry land / too far is refused.
func fish_aim() -> void:
	await place("Eurong", 0)
	main.set_tide(0.0)
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	await wait(1.6)
	# stand at the water's edge, facing the sea
	var x := pl.global_position.x
	var z := pl.global_position.z
	for k in 200:
		if main.island.water_level_at(x, z) > main.island.height_at(x, z) - 0.3:
			break
		x += 1.0
	pl.global_position = Vector3(x - 3.0, main.island.height_at(x - 3.0, z) + 0.2, z)
	var t: PlayerTools = pl.tools
	t._mouse_aim = false
	t.toggle_slot(0)
	print("rod selected: slot=%d" % t.slot)
	t.toggle_slot(0)
	print("same key again: slot=%d (want -1)" % t.slot)
	t.toggle_slot(0)
	for target in [Vector3(x + 10, 0, z + 3), Vector3(x + 22, 0, z - 4), Vector3(x + 40, 0, z), Vector3(x - 15, 0, z)]:
		target.y = maxf(main.island.height_at(target.x, target.z), main.island.water_level_at(target.x, target.z))
		t._aim = target
		var flat := Vector2(target.x - pl.global_position.x, target.z - pl.global_position.z).length()
		var wet: bool = main.island.water_level_at(target.x, target.z) > main.island.height_at(target.x, target.z) + 0.05
		t._aim_ok = wet and flat <= PlayerTools.CAST_RANGE and flat > 2.0
		if not t._aim_ok:
			t._use(true)
			print("target %.0f m wet=%s -> refused (state %s)" % [flat, wet, t._fish])
			continue
		t.cast_at(target)
		await wait(4.0)
		print("target %.0f m: bobber landed %.2f m from the ring, in water=%s" % [flat, Vector2(t._bob_pos.x - target.x, t._bob_pos.z - target.z).length(), t._bob_in_water])
		t._end_fishing()
	pl.velocity = Vector3.ZERO
	pl.ai = true   # hold still, then run with the rod
	pl.ai_move = Vector3(0, 0, -1)
	pl.ai_run = true
	await wait(1.0)
	print("running pose with rod: %s" % pl._net_pose)


## Winch remote on foot pulls a free car toward you.
func winch_remote() -> void:
	await place("Eurong", 0)
	var car: SandVehicle = main.local_car
	var b := _second_car(car.global_position + Vector3(0, 0, -16.0))
	b.driver_present = false
	b.scripted = false
	await wait(1.5)
	var pl: PlayerCharacter = main.local_player
	var wl := (car.global_transform * SandVehicle.FRONT_POINT).distance_to(b.global_transform * SandVehicle.REAR_POINT)
	pl.get_out()
	await wait(1.6)
	main.ropes.create("winch", {"car": String(car.name), "p": SandVehicle.FRONT_POINT}, {"car": String(b.name), "p": SandVehicle.REAR_POINT}, wl + 0.2)
	pl.tools.select(Items.REMOTE)
	await wait(0.5)
	print("holding: %s  remote slot visible=%s" % [pl.tools.item()["id"], main.hud._slots[Items.REMOTE].visible])
	var b0 := b.global_position
	var c0 := car.global_position
	_key(KEY_Q, true)   # hold Q = winch in
	for i in 8:
		await wait(1.0)
		print("  t=%d  other ute moved %.1f m toward us, ours moved %.1f m" % [i + 1, b0.distance_to(b.global_position), c0.distance_to(car.global_position)])
	_key(KEY_Q, false)
	var b1 := b.global_position
	_key(KEY_E, true)   # hold E = let out
	await wait(2.0)
	_key(KEY_E, false)
	print("  E let out: cable now %.1f m, still on foot=%s" % [float(main.ropes.ropes[main.ropes.winch_rope_of(String(car.name))]["rest"]), pl.is_on_foot()])
	look(car.global_position + Vector3(6, 3, 0), car.global_position + Vector3(0, 0.5, -8))
	await shot("remote")
	pl.get_in()
	await wait(2.0)
	print("in cab: winch buttons visible=%s" % main.hud._winch_box.visible)
	await shot("cab_buttons")
	for id in main.ropes.ropes.keys():
		main.ropes.remove(id)
	await wait(0.5)
	print("after unhook: buttons visible=%s" % main.hud._winch_box.visible)


## Police / ambulance / ranger looks, lights flashing, a wave out the window.
func liveries() -> void:
	await place("Eurong", 0)
	main.local_car.scripted = true
	var ps: Array = []
	for r in ["police", "ambulance", "ranger"]:
		ps.append(await _one_bot(r))
	await wait(1.0)
	var c: Vector3 = main.local_car.global_position
	for k in ps.size():
		var b: AmbientBot = ps[k]
		b.plan.clear()
		b.plan.append({"do": "wait", "t": 999.0})
		b.car.teleport(c + Vector3(-6, 0, -8 - k * 7), Vector3(1, 0, -0.2).normalized())
		b.car.set_signals(true, false, false)
	await wait(2.0)
	(ps[0] as AmbientBot).car.wave(true)
	await wait(0.4)
	look(c + Vector3(6, 4, -2), c + Vector3(-6, 1, -15))
	await shot("liveries")
	(ps[0] as AmbientBot).force_bog()
	await wait(4.0)
	var hp: Vector3 = (ps[0] as AmbientBot).person.global_position
	look(hp + Vector3(7, 3.5, 5), hp + Vector3(0, 1.8, 0))
	await shot("help_sign")


func _key(k: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	ev.keycode = k
	ev.pressed = down
	get_root().push_input(ev)


## Ram the on-foot person with a driverless ute at `kmh` (from 7 m south, heading north).
func _ram(target: PlayerCharacter, car: SandVehicle, kmh: float) -> void:
	var p := target.global_position + Vector3(0.0, 0.0, 7.0)
	car.teleport(_ground(p) + Vector3.UP * 0.9, Vector3.FORWARD)
	await wait(0.6)
	for i in 160:
		car.linear_velocity = Vector3(0, car.linear_velocity.y, -kmh / 3.6)
		if target._bonk != 0 or target._stun > 0.0:
			break
		await physics_frame
	car.linear_velocity = Vector3.ZERO
	car.teleport(_ground(target.global_position + Vector3(12, 0, 30)) + Vector3.UP * 0.9, Vector3.FORWARD)


## Ute bonks: 5 hits knocks you out cold, an ambulance comes and does CPR; then a bot gets skittled.
func bonk() -> void:
	await place("Eurong", 0)
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	await wait(2.0)
	var rammer := _second_car(main.local_car.global_position + Vector3(20, 0, 40))
	rammer.driver_present = false
	await wait(1.0)
	for hit in 5:
		var p0 := pl.global_position
		await _ram(pl, rammer, 45.0 if hit != 1 else 14.0)
		var top := 0.0
		for k in 30:
			await wait(0.1)
			top = maxf(top, pl.global_position.y - main.island.height_at(pl.global_position.x, pl.global_position.z))
		print("hit %d: health %d  bonk=%d  flew %.1f m  peak %.1f m  down=%s" % [hit + 1, pl.health, pl._bonk,
			Vector2(pl.global_position.x - p0.x, pl.global_position.z - p0.z).length(), top, pl.is_down()])
		if hit == 0 and DisplayServer.get_name() != "headless":
			await shot("flat")
		await wait(1.5)
	print("down=%s  prompt='%s'" % [pl.is_down(), main.hud._prompt.text])
	var amb: AmbientBot = null
	for b in main.bots.brains():
		if b is AmbientBot and b.role == "ambulance":
			amb = b
	print("ambulance: ", amb.display if amb else "NONE", "  siren=", amb.car.siren_on if amb else false)
	var shot_cpr := false
	for k in 60:
		await wait(1.0)
		if amb == null or not is_instance_valid(amb):
			break
		var st := String(amb.plan[0]["do"]) if not amb.plan.is_empty() else "-"
		if k % 3 == 0:
			print("  t=%d  amb %s %s dist %.1f  lights=%s siren=%s  pose=%s  health=%d" % [k, st, "car" if amb.in_car() else "foot",
				amb.person.global_position.distance_to(pl.global_position), amb.car.lights_on, amb.car.siren_on, amb.person._net_pose, pl.health])
		if amb.person._net_pose == "cpr" and not shot_cpr and DisplayServer.get_name() != "headless":
			shot_cpr = true
			look(pl.global_position + Vector3(4, 2.5, 3), pl.global_position + Vector3(0, 0.4, 0))
			await shot("cpr")
		if not pl.is_down() and pl._bonk == 0:
			print("revived at t=%d: health %d, ambo achievement=%s" % [k, pl.health, main.achievements.is_unlocked("ambo")])
			break
	await wait(4.0)
	print("bubble: ", amb.person._bubble.text if amb and amb.person._bubble else "")
	# now skittle a bot on foot
	var fisher := await _one_bot("fisher")
	var bp: PlayerCharacter = fisher.person
	fisher.car.teleport(_ground(pl.global_position + Vector3(-8, 0, -20)) + Vector3.UP * 0.9, Vector3.FORWARD)
	await wait(2.0)
	fisher.plan.clear()
	fisher.plan.append({"do": "get_out"})
	fisher.plan.append({"do": "wait", "t": 30.0})
	await wait(4.0)
	print("fisher on foot=%s" % bp.is_on_foot())
	await _ram(bp, rammer, 40.0)
	await wait(3.0)
	print("bot after bonk: health %d bonk=%d  bubble='%s'" % [bp.health, bp._bonk, bp._bubble.text if bp._bubble else ""])
	print("achievements: skittled=%s bonked=%s seeing_stars=%s" % [main.achievements.is_unlocked("skittled"), main.achievements.is_unlocked("bonked"), main.achievements.is_unlocked("seeing_stars")])


## Dingo pinches your thong, you chase it down and get it back; dingoes scatter from a ute.
func dingo_thief() -> void:
	await place("Eurong", 0)
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	await wait(2.0)
	var d: Dingo = null
	var bd := INF
	for c in main.world.get_children():
		if c is Dingo and c.global_position.distance_to(pl.global_position) < bd:
			bd = c.global_position.distance_to(pl.global_position)
			d = c
	print("dingoes on island: %d, nearest %.0f m" % [main.island.dingo_homes.size(), bd])
	pl.global_position = _ground(d.global_position + Vector3(5, 0, 0)) + Vector3.UP * 0.3
	await wait(1.0)
	d.steal_from(pl)
	for k in 30:
		await wait(0.2)
		if d._state == "carry":
			break
	print("state after steal: %s  thong in mouth=%s  toast='%s'" % [d._state, d._thong.visible, main.hud._toast.text])
	await wait(3.0)
	print("ran off: %.1f m away, state %s" % [d.global_position.distance_to(pl.global_position), d._state])
	if DisplayServer.get_name() != "headless":
		look(d.global_position + Vector3(3, 1.5, 3), d.global_position + Vector3(0, 0.5, 0))
		await shot("thief")
	# chase: pop up right beside it
	pl.global_position = _ground(d.global_position + Vector3(1.0, 0, 0)) + Vector3.UP * 0.2
	await wait(0.5)
	print("caught: state %s, dropped thong=%s" % [d._state, d._dropped != null])
	if d._dropped:
		pl.global_position = _ground(d._dropped.global_position) + Vector3.UP * 0.2
	await wait(0.6)
	print("picked up: dropped=%s  achievement=%s  toast='%s'" % [d._dropped != null, main.achievements.is_unlocked("thong"), main.hud._toast.text])
	# a ute bearing down on a dingo: it gets out of the way
	var rammer := _second_car(d.global_position + Vector3(0, 0, 25))
	rammer.driver_present = false
	await wait(0.8)
	rammer.teleport(_ground(d.global_position + Vector3(0, 0, 18)) + Vector3.UP * 0.9, Vector3.FORWARD)
	await wait(0.3)
	var closest := INF
	var fled := false
	for i in 120:
		rammer.linear_velocity = Vector3(0, rammer.linear_velocity.y, -12.0)
		await physics_frame
		closest = minf(closest, Vector2(d.global_position.x - rammer.global_position.x, d.global_position.z - rammer.global_position.z).length())
		fled = fled or d._state == "flee"
	print("dingo fled=%s, closest the ute got: %.1f m" % [fled, closest])
	# howl
	d._howl_t = 0.0
	d._state = "idle"
	await wait(0.3)
	var howling := 0
	for o in main.world.get_children():
		if o is Dingo and o._state == "howl":
			howling += 1
	await wait(1.0)
	for o in main.world.get_children():
		if o is Dingo and o._state == "howl":
			howling += 1
	print("howl: state %s, pack howling (sampled) %d" % [d._state, howling])


## Top speed on hard / medium / soft sand at 32 and 18 psi (20 s flat out from a standstill).
func topspeed() -> void:
	for soft in [0.05, 0.3, 0.55, 0.8]:
		for psi in [32.0, 18.0]:
			await place("Eurong", 0)
			var car: SandVehicle = main.local_car
			main.island.force_soft = soft
			car.scripted = true
			car.set_all_psi(psi)
			car.steer = 0.0
			car.brake = 0.0
			car.throttle = 1.0
			var top := 0.0
			for i in 200:
				await wait(0.1)
				top = maxf(top, car.speed_kmh)
			car.throttle = 0.0
			print("soft %.2f  %2.0f psi: top %.0f km/h  (now %.0f)" % [soft, psi, top, car.speed_kmh])


## Bot rescuer tries a bumper nudge first (strap if that fails); then the player nudges a bogged bot out.
func nudge() -> void:
	await place("Eurong", 0)
	main.local_car.scripted = true
	main.bots.help_chance = 1.0
	var a := await _one_bot("cruiser")
	await wait(6.0)
	a.force_bog()
	for w in a.car.wheels:
		w.dig *= 0.5   # a light bog, the kind a nudge can shift
	await wait(4.0)
	var b := await _one_bot("cruiser")
	b.plan.clear()
	var f0: float = main.island.z_to_f(a.car.global_position.z)
	b.car.teleport(main.bots.lane_point(f0 - 0.02, true) + Vector3.UP, Vector3(0, 0, -1))
	b.plan.append({"do": "get_in"})
	b.plan.append({"do": "drive", "speed": 12.0, "make": func() -> PackedVector3Array:
		return main.bots.beach_path(main.island.z_to_f(b.car.global_position.z), f0 + 0.03)})
	var spot := a.car.global_position
	var shot_done := false
	for i in 60:
		await wait(2.0)
		if not b.plan.is_empty() and String(b.plan[0]["do"]) == "rescue" and not b.plan[0].has("forced"):
			b.plan[0]["forced"] = true
			b.plan[0]["nudge"] = true
		var ph := String(b.plan[0].get("ph", "")) if not b.plan.is_empty() else ""
		print("t=%3d %s  %s  A moved %.1f m  gap %.1f  pushed=%.1f" % [i * 2, _bot_line(a), _bot_line(b),
			a.car.global_position.distance_to(spot), a.car.global_position.distance_to(b.car.global_position), a.car._pushed_t] + "  [%s] %.0f km/h" % [b.driver.status, b.car.speed_kmh])
		if ph == "nudge" and not shot_done and DisplayServer.get_name() != "headless":
			shot_done = true
			look(a.car.global_position + Vector3(-10, 4, 6), a.car.global_position.lerp(b.car.global_position, 0.5))
			await shot("nudge")
		if not a.needs_help and i > 3:
			print("BOT FREED: A moved %.1f m, ropes=%d" % [a.car.global_position.distance_to(spot), main.ropes.ropes.size()])
			break
	# the player nudges a bogged bot out
	main.bots.remove_all_ambient()
	await wait(1.0)
	var c := await _one_bot("cruiser")
	await wait(6.0)
	c.force_bog()
	for w in c.car.wheels:
		w.dig *= 0.5
	await wait(5.0)
	var car: SandVehicle = main.local_car
	var fwd := -c.car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	car.teleport(_ground(c.car.global_position - fwd * 6.0) + Vector3.UP * 0.9, fwd)
	await wait(1.0)
	var spot2 := c.car.global_position
	car.low_range = true
	car.throttle = 0.6
	for i in 15:
		await wait(1.0)
		print("  player nudge t=%d: bot moved %.1f m, needs_help=%s, %s" % [i + 1, c.car.global_position.distance_to(spot2), c.needs_help, _bot_line(c)])
		if not c.needs_help:
			break
	car.throttle = 0.0
	print("player nudge: freed=%s samaritan=%s bubble='%s'" % [not c.needs_help, main.achievements.is_unlocked("samaritan"), c.person._bubble.text if c.person._bubble else ""])


## Googly eyes: close-ups while walking and once settled (cross-eyed).
func eyes() -> void:
	await place("Eurong", 0)
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	await wait(2.0)
	Input.action_press("throttle")
	await wait(1.6)
	var face := pl.global_position + (-pl.global_basis.z) * 1.6 + Vector3.UP * 1.7
	look(face, pl.global_position + Vector3.UP * 1.6)
	await shot("eyes_walk")
	for e in pl.avatar._eyes:
		print("walking pupil offset ", e["off"])
	Input.action_release("throttle")
	await wait(2.5)
	look(pl.global_position + (-pl.global_basis.z) * 1.3 + Vector3.UP * 1.65, pl.global_position + Vector3.UP * 1.6)
	await shot("eyes_rest")
	for e in pl.avatar._eyes:
		print("resting pupil offset ", e["off"], " inner ", e["inner"])


## Helper: you're bogged and never hook a strap - after ~10 s it tries bumping you out from behind.
func helper_nudge() -> void:
	await place("Eurong", 0)
	var car: SandVehicle = main.local_car
	car.scripted = true
	car.set_all_psi(18.0)
	main.bots.spawn("helper")
	await wait(1.0)
	var h: HelperBot = main.bots.helper
	car.throttle = 0.5
	await _helper_follow(h, car, 16.0)
	car.throttle = 0.0
	car.brake = 1.0
	await wait(4.0)
	await _bog(car)
	for w in car.wheels:
		w.dig *= 0.5
	car.set_all_psi(18.0)   # aired down, like you would
	car.brake = 0.0
	var spot := car.global_position
	for i in 120:
		await wait(0.5)
		car.low_range = true
		car.throttle = 0.6 if h.phase == "nudge" else 0.0   # give it some gas while it pushes
		if i % 4 == 0:
			print("t=%.0f phase %s  gap %.1f  you moved %.1f  bogged=%s pushed=%.1f  %s" % [i * 0.5, h.phase,
				h.car.global_position.distance_to(car.global_position), car.global_position.distance_to(spot), car.is_bogged, car._pushed_t, h.driver.status])
		if h.mode == HelperBot.Mode.FOLLOW and i > 4:
			print("OUT: helper back to following, you moved %.1f m" % car.global_position.distance_to(spot))
			break
	car.throttle = 0.0


## Bog chart: for each sand softness x tyre pressure, floor it from a standstill, then
## drive, stop and pull away again (the classic way to bog). Prints a grid of B (bogged) / ok.
func bograte() -> void:
	var car: SandVehicle = main.local_car
	var softs := [0.45, 0.6, 0.7, 0.8, 0.9, 1.0]
	var psis := [32.0, 18.0, 15.0, 12.0]
	var line := "soft   " 
	for p in psis:
		line += "  %2d psi      " % int(p)
	print(line)
	for sf in softs:
		line = "%.2f   " % sf
		for p in psis:
			await place("Eurong", 0)
			main.island.force_soft = sf
			car.scripted = true
			car.set_all_psi(p)
			car.brake = 0.0
			car.throttle = 0.0
			await wait(1.0)
			# 1) floor it from rest
			car.throttle = 1.0
			var bogged_a := false
			for i in 60:
				await wait(0.1)
				bogged_a = bogged_a or car.is_bogged
			var v := absi(roundi(car.speed_kmh))
			# 2) stop, then pull away again
			car.throttle = 0.0
			car.brake = 1.0
			await wait(2.5)
			car.brake = 0.0
			car.throttle = 1.0
			var bogged_b := false
			for i in 60:
				await wait(0.1)
				bogged_b = bogged_b or car.is_bogged
			line += "  %s/%s %3dkmh  " % ["B" if bogged_a else "-", "B" if bogged_b else "-", v]
			car.throttle = 0.0
		print(line)
	main.island.force_soft = -1.0


## Helper > Strap me out / Winch me out: the helper parks, hops out, hooks up, pulls you out,
## unhooks and drives off following you. HELPER_KIND=winch env picks the winch.
func helper_self() -> void:
	var kind := OS.get_environment("HELPER_KIND")
	if kind == "":
		kind = "strap"
	await place("Eurong", 0)
	var car: SandVehicle = main.local_car
	car.scripted = true
	car.set_all_psi(18.0)
	main.bots.spawn("helper")
	await wait(1.0)
	var h: HelperBot = main.bots.helper
	car.throttle = 0.5
	await _helper_follow(h, car, 16.0)
	car.throttle = 0.0
	car.brake = 1.0
	await wait(4.0)
	await _bog(car)
	car.brake = 0.0
	if kind == "winch":
		h.winch_me_out()
	else:
		h.strap_me_out()
	var spot := car.global_position
	var last := ""
	var max_span := 0.0
	for i in 400:
		await wait(0.5)
		if not h._rope_to_lead().is_empty() and not get_meta("traced", false):
			set_meta("traced", true)
			var rid: String = h._rope_to_lead()["id"]
			for k in 12:
				var r: Dictionary = main.ropes.ropes.get(rid, {})
				print("  trace %.1fs rest %.2f tension %.0f  lead v %.1f  helper frozen=%s v %.1f  lead pos %s" % [k * 0.1, float(r.get("rest", 0)), float(r.get("tension", 0)),
					car.linear_velocity.length(), h.car.freeze, h.car.linear_velocity.length(), car.global_position])
				if r.size() > 0:
					print("     pa %s pb %s  helper at %s facing %s  lead vel %s" % [main.ropes.anchor_pos(r["a"]), main.ropes.anchor_pos(r["b"]), h.car.global_position, -h.car.global_basis.z, car.linear_velocity])
				await wait(0.1)
		var pulling := h.phase in ["pulling", "winching"]
		car.throttle = 0.4 if pulling else 0.0
		var line := "%s/%s %s" % [h.phase, h._hook_step, "car" if h.in_car() else "foot"]
		if OS.get_environment("HELPER_TRACE") != "":
			print("   helper car %s frozen=%s  pending=%s %s" % [h.car.global_position, h.car.freeze, h.car._has_pending_place, h.car._pending_place.origin])
		if line != last or i % 20 == 0:
			var rope := h._rope_to_lead()
			print("t=%.1f %s  span %.1f  you moved %.1f  bogged=%s rope=%s  %s" % [i * 0.5, line, h._hook_span(car),
				car.global_position.distance_to(spot), car.is_bogged, rope.get("kind", "-"), h.driver.status])
			last = line
		if h.mode == HelperBot.Mode.FOLLOW and i > 4:
			print("DONE: helper following again, ropes left %d, you moved %.1f m" % [main.ropes.ropes.size(), car.global_position.distance_to(spot)])
			break
	car.throttle = 0.0


## Rollover: flat-beach hard turns must NOT roll; the Rollover Hill sidle CAN roll you; climb out
## of a ute on its side, crawl out from under one on its roof, R flips it back (on foot, nearby).
func rollover() -> void:
	var car: SandVehicle = main.local_car
	var pl: PlayerCharacter = main.local_player
	# 1) flat hard beach, flat out, full lock both ways
	for st in [0.6, -0.6]:
		await place("Eurong", 0)
		main.island.force_soft = 0.08
		car.scripted = true
		car.set_all_psi(32.0)
		car.steer = 0.0
		car.throttle = 1.0
		await wait(7.0)
		var v0 := car.speed_kmh
		var min_up := 1.0
		car.steer = st
		for i in 40:
			await wait(0.1)
			min_up = minf(min_up, car.global_basis.y.y)
		print("flat beach %.0f km/h steer %.1f: min up.y %.2f rolled=%s" % [v0, st, min_up, min_up < 0.3])
	main.island.force_soft = -1.0
	car.throttle = 0.0
	# 2) the sidle track along Rollover Hill: show its lean, then send it with a turn up the slope
	await place("Rollover Hill", 0)
	var rolled_any := false
	for attempt in 4:
		# start on the level stretch of the sidle (south end of the top), heading north along it
		car.teleport(Vector3(149.0, 0.0, 45.0), Vector3(0.05, 0, -1).normalized())
		await wait(1.0)
		car._recover_cd = 0.0
		car.scripted = true
		car.set_all_psi(18.0)
		car.steer = 0.0
		car.brake = 0.0
		car.throttle = 1.0
		var max_side := 0.0
		for i in 60:
			await wait(0.1)
			max_side = maxf(max_side, rad_to_deg(asin(clampf(absf(car.global_basis.x.y), 0.0, 1.0))))
		var v_turn := car.speed_kmh
		car.steer = [0.0, 0.12, 0.6, -0.6][attempt]   # straight along it should be scary but OK; a hard turn rolls it
		var min_up := 1.0
		for i in 60:
			await wait(0.1)
			min_up = minf(min_up, car.global_basis.y.y)
		car.throttle = 0.0
		car.steer = 0.0
		await wait(3.0)
		print("sidle attempt %d: side slope up to %.0f deg, turned at %.0f km/h, min up.y %.2f, roll_state %d" % [attempt, max_side, v_turn, min_up, car.roll_state])
		if car.roll_state != 0:
			rolled_any = true
			await shot("rolled_natural_%d" % attempt)
			if attempt >= 2:
				break
	print("natural rollover on the sidle: ", rolled_any, "  achievement: ", main.achievements.is_unlocked("rollover"))
	# 3) on its side (forced, so the test is repeatable) - climb out the top
	await place("Eurong", 0)
	car.scripted = false
	car.throttle = 0.0
	var p := car.global_position
	var side_xf := Transform3D(car.global_basis.rotated(-car.global_basis.z, PI * 0.5), Vector3(p.x, main.island.height_at(p.x, p.z) + 1.3, p.z))
	car._place(side_xf)
	await wait(3.0)
	print("on side: roll_state %d up.y %.2f" % [car.roll_state, car.global_basis.y.y])
	main.camera.mode = 0
	pl.get_out()
	await wait(1.0)
	await shot("side_climb")
	await wait(0.7)
	await shot("side_top")
	await wait(0.6)
	await shot("side_jump")
	await wait(1.0)
	print("after climb: state %d on foot %s pos %s" % [pl.state, pl.is_on_foot(), pl.global_position])
	await shot("side_out")
	pl.get_in()
	await wait(0.3)
	print("get_in refused while rolled: ", pl.state == PlayerCharacter.State.ON_FOOT)
	# R on foot next to it
	var ev := InputEventAction.new()
	ev.action = "recover"
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait(0.5)
	await shot("recovering")
	await wait(1.5)
	print("after R: up.y %.2f roll_state %d" % [car.global_basis.y.y, car.roll_state])
	# 4) on its roof - crawl out from underneath
	pl.get_in()
	await wait(1.6)
	p = car.global_position
	var roof_xf := Transform3D(car.global_basis.rotated(-car.global_basis.z, PI), Vector3(p.x, main.island.height_at(p.x, p.z) + 2.0, p.z))
	car._place(roof_xf)
	await wait(3.0)
	print("on roof: roll_state %d up.y %.2f" % [car.roll_state, car.global_basis.y.y])
	pl.get_out()
	await wait(0.9)
	await shot("roof_crawl1")
	await wait(0.9)
	await shot("roof_crawl2")
	await wait(0.6)
	await shot("roof_getup")
	await wait(1.0)
	print("after crawl: state %d on foot %s" % [pl.state, pl.is_on_foot()])
	await shot("roof_out")
	car._recover_cd = 0.0
	Input.parse_input_event(ev)
	await wait(2.0)
	print("after R again: up.y %.2f roll_state %d" % [car.global_basis.y.y, car.roll_state])
	# a rolled bead comes back on with the recovery
	car._roll_bead(car.wheels[0])
	car._recover_cd = 0.0
	car.recover()
	await wait(1.6)
	print("bead after recovery: flat=%s psi %.0f" % [car.wheels[0].flat, car.wheels[0].psi])


# ---------------------------------------------------------------- pets
func _pet_line(p) -> String:
	return "%s[%s a%d]" % [p.name, p.state, p.anim]


## Your dog rides in the tray, hops out, follows / wanders, plays with another dog,
## chases a cat (which bolts), comes when whistled, hops back in.
func pets() -> void:
	var me: int = main.multiplayer.get_unique_id()
	main._spawn_pet(me, main.local_player, "collie:0")
	var dog = main.pets.get_node("Pet_%d" % me)
	await wait(1.0)
	await place("Eurong", 0)
	await wait(1.0)
	print("start: ", _pet_line(dog), " in tray=", dog.global_position.distance_to((main.local_car.global_transform * dog.TRAY_XF).origin) < 0.3)
	main.local_car.scripted = true
	main.local_car.throttle = 0.6
	await wait(3.0)
	var tray_d: float = dog.global_position.distance_to((main.local_car.global_transform * dog.TRAY_XF).origin)
	print("driving %d km/h: %s tray gap %.2f m" % [main.local_car.speed_kmh, _pet_line(dog), tray_d])
	await shot("pet_tray")
	main.local_car.throttle = 0.0
	main.local_car.brake = 1.0
	await wait(2.5)
	main.local_car.brake = 0.0
	main.local_player.get_out()
	var seen := {}
	for i in 12:
		await wait(0.25)
		seen[dog.state] = true
	print("after get out: ", _pet_line(dog), " states seen ", seen.keys())
	# walk away: does it follow?
	var p: Vector3 = main.local_player.global_position + Vector3(-14, 0, 6)
	main.teleport_local(p)
	await wait(5.0)
	print("followed: dog %.1f m from you  %s" % [dog.global_position.distance_to(main.local_player.global_position), _pet_line(dog)])
	# mates: a second dog and a cat
	main._spawn_pet(9001, main.local_player, "cavoodle:0")
	main._spawn_pet(9002, main.local_player, "cat:0")
	var dog2 = main.pets.get_node("Pet_9001")
	var cat = main.pets.get_node("Pet_9002")
	dog2.set_multiplayer_authority(me)   # pretend-mates' pets, run on this machine for the test
	cat.set_multiplayer_authority(me)
	dog2.state = "follow"
	cat.state = "follow"
	dog2.global_position = main.local_player.global_position + Vector3(5, 0, -3)
	cat.global_position = main.local_player.global_position + Vector3(-12, 0, -8)
	dog._cool["play"] = 0.0
	seen = {}
	var cat_seen := {}
	var shot_play := false
	for i in 120:
		await wait(0.25)
		for d in [dog, dog2]:
			seen[d.state] = true
			if d.state == "roll" and not shot_play:
				shot_play = true
				await shot("pet_play")
		cat_seen[cat.state] = true
		if i % 20 == 0:
			print("  t=%4.1f %s %s %s" % [i * 0.25, _pet_line(dog), _pet_line(dog2), _pet_line(cat)])
	print("dogs did: ", seen.keys(), "   cat did: ", cat_seen.keys())
	# whistle
	dog.global_position = main.local_player.global_position + Vector3(20, 0, 0)
	dog.state = "wander"
	dog._target = dog.global_position
	main.whistle()
	print("whistle -> ", _pet_line(dog))
	for i in 20:
		await wait(0.25)
		if dog.state == "sit":
			break
	print("came back: %.1f m  %s" % [dog.global_position.distance_to(main.local_player.global_position), _pet_line(dog)])
	# back in the ute
	main.local_player.global_position = main.local_player.door_spot()
	main.local_player.get_in()
	for i in 16:
		await wait(0.25)
	print("got in: ", _pet_line(dog), " tray gap %.2f" % dog.global_position.distance_to((main.local_car.global_transform * dog.TRAY_XF).origin))


# ---------------------------------------------------------------- lasso + PvE
## A bot that's got out of its ute and is standing about (for lasso / bonk targets).
func _bot_on_foot(near: Vector3) -> PlayerCharacter:
	var b := await _one_bot("fisher")
	b.car.teleport(_ground(near) + Vector3.UP * 0.9, Vector3.FORWARD)
	await wait(2.0)
	b.plan.clear()
	b.plan.append({"do": "get_out"})
	b.plan.append({"do": "wait", "t": 300.0})
	await wait(4.0)
	return b.person


## Lasso a bot (count the throws), drag it, hitch it to the ute, tow it about, check it
## wriggles free and the cooldown stops a straight re-catch.
func lasso() -> void:
	var windowed := DisplayServer.get_name() != "headless"
	for d in [3.0, 8.0, 12.0, 15.0]:
		print("odds at %4.1f m: perfect %.2f  ok(0.6) %.2f  landed 1 m off %.2f" % [d, Lasso.hit_chance(d, 1.0, 0.0, 0.0),
			Lasso.hit_chance(d, 0.6, 0.0, 0.0), Lasso.hit_chance(d, 0.8, 1.0, 0.0)])
	await place("Eurong", 0)
	var pl: PlayerCharacter = main.local_player
	pl.get_out()
	await wait(2.5)
	var bp := await _bot_on_foot(pl.global_position + Vector3(-6, 0, -25))
	print("bot on foot=%s" % bp.is_on_foot())
	pl.tools.select(Items.LASSO)
	var la: Lasso = pl.tools.lasso
	# stand 8 m from it
	pl.global_position = _ground(bp.global_position + Vector3(8, 0, 0)) + Vector3.UP * 0.3
	await wait(0.5)
	if windowed:
		main.hud.get_child(0).get_node("HelpPanel").visible = false
		la.use(true)
		la._target = bp
		await wait(0.6)
		look(pl.global_position + Vector3(3, 2.2, 4), pl.global_position + Vector3(0, 1.6, 0))
		await shot("lasso_whirl")
		la.use(false)
		await wait(1.5)
	var tries := 0
	var caught_at := -1.0
	for i in 30:
		if bp.is_tied():
			break
		tries += 1
		la.throw_at(bp, randf_range(0.6, 1.0))
		await wait(1.2)
	print("lasso: caught=%s after %d throws at 8 m  tied for %.1f s  holder=%s" % [bp.is_tied(), tries, bp._tied_t, bp.tie_holder])
	if not bp.is_tied():
		return
	print("achievement yeehaw=%s" % main.achievements.is_unlocked("yeehaw"))
	var t_free := bp._tied_t
	bp._tied_t = 60.0   # hold them for the rest of the test
	if windowed:
		look(bp.global_position + Vector3(4, 2.5, 3), bp.global_position + Vector3(0, 0.3, 0))
		await wait(0.5)
		await shot("lasso_tied")
	# drag them 10 m by walking away
	var b0 := bp.global_position
	for k in 60:
		pl.global_position += Vector3(0.17, 0, 0)
		await physics_frame
		await physics_frame
	await wait(0.5)
	print("dragged: bot moved %.1f m, rope gap %.1f m" % [bp.global_position.distance_to(b0), bp.global_position.distance_to(pl.global_position)])
	# hitch to the ute's towbar
	var car: SandVehicle = main.local_car
	pl.global_position = car.global_transform * (SandVehicle.REAR_POINT + Vector3(0.6, 0, 0.8))
	await wait(0.3)
	print("prompt near hitch: '%s'" % pl.tools.prompt)
	la._hitch(car)
	await wait(0.5)
	print("hitched: tie_car=%s achievement hitched=%s" % [bp.tie_car, main.achievements.is_unlocked("hitched")])
	car.scripted = true
	car.handbrake = false
	car.set_all_psi(18.0)
	car.brake = 0.0
	car.throttle = 0.7
	var top := 0.0
	var start := bp.global_position
	for s in 15:
		if s == 6:
			car.steer = 0.4
		var hi := 0.0
		for f in 60:
			await physics_frame
			await physics_frame
			hi = maxf(hi, bp.global_position.y - float(main.island.height_at(bp.global_position.x, bp.global_position.z)))
		top = maxf(top, hi)
		print("  tow t=%2d  car %3.0f km/h bogged=%s  bot gap to towbar %.1f m  highest bounce %.2f m" % [s + 1, car.speed_kmh, car.is_bogged,
			bp.global_position.distance_to(car.global_transform * SandVehicle.REAR_POINT), hi])
		if s == 4 and windowed:
			look(car.global_position + Vector3(9, 4, 9), bp.global_position)
			await shot("lasso_towed")
	car.throttle = 0.0
	car.brake = 1.0
	print("towed %.0f m, highest bounce %.2f m" % [bp.global_position.distance_to(start), top])
	# let them go: they wriggle free and get a cooldown
	bp._tied_t = 0.05
	await wait(1.0)
	print("free=%s  cooldown %.1f s  (would have been tied %.1f s)" % [not bp.is_tied(), bp._lasso_cd, t_free])
	pl.global_position = _ground(bp.global_position + Vector3(3, 0, 0)) + Vector3.UP * 0.3
	await wait(0.3)
	bp.request_lasso(String(pl.name), "", 15.0)
	await wait(0.3)
	print("re-lasso during cooldown blocked=%s" % not bp.is_tied())
	main.lasso_cooldown = false
	bp.request_lasso(String(pl.name), "", 15.0)
	await wait(0.3)
	print("with admin cooldown OFF: caught=%s" % bp.is_tied())


## PvE: no bonks for you, none by you on other players; bots still fair game.
func pve() -> void:
	await place("Eurong", 0)
	var pl: PlayerCharacter = main.local_player
	main.pve = true
	pl.get_out()
	await wait(2.5)
	var rammer := _second_car(main.local_car.global_position + Vector3(20, 0, 40))
	rammer.driver_present = false
	await wait(1.0)
	await _ram(pl, rammer, 45.0)
	await wait(1.0)
	print("PvE me, rammed at 45: bonk=%d stun=%.1f health=%d" % [pl._bonk, pl._stun, pl.health])
	# a pretend second human on foot
	var other := PlayerCharacter.create("bean", Color(0.9, 0.3, 0.3))
	other.name = "Player_77"
	other.tag_text = "Mate"
	other.local_control = false
	other.ai = true
	other.state = PlayerCharacter.State.ON_FOOT
	main.players.add_child(other)
	other.global_position = _ground(pl.global_position + Vector3(10, 0, -10)) + Vector3.UP * 0.5
	await wait(1.0)
	# me (PvE) driving into them
	pl.global_position = pl.door_spot()
	pl.get_in()
	await wait(3.0)
	print("me in ute: state=%d" % pl.state)
	await _ram(other, main.local_car, 45.0)
	await wait(1.0)
	print("PvE me driving into a player: their bonk=%d stun=%.1f" % [other._bonk, other._stun])
	main.pve = false
	await wait(2.0)
	await _ram(other, main.local_car, 45.0)
	await wait(1.0)
	print("PvE off, same ram: their bonk=%d (should be 1 or 2)" % other._bonk)
	await wait(6.0)
	# lassos: refused on a player while I'm PvE, fine on a bot
	main.pve = true
	pl.get_out()
	await wait(2.5)
	other._bonk = 0
	other._stun = 0.0
	pl.tools.select(Items.LASSO)
	print("pve_blocks(player)=%s" % main.pve_blocks(other, String(pl.name)))
	other.request_lasso(String(pl.name), "", 12.0)
	await wait(0.3)
	print("lasso a player while PvE: tied=%s (should be false)" % other.is_tied())
	var bp := await _bot_on_foot(pl.global_position + Vector3(-6, 0, -25))
	bp.request_lasso(String(pl.name), "", 12.0)
	await wait(0.3)
	print("lasso a bot while PvE: tied=%s (should be true)" % bp.is_tied())
	bp._tied_t = 0.05
	await wait(2.5)
	await _ram(bp, rammer, 40.0)
	print("bot after a ute ram while I'm PvE: bonk=%d (bots can still be skittled)" % bp._bonk)

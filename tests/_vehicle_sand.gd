extends SceneTree
## Dev: godot --path . --headless -s res://tests/_vehicle_sand.gd
## Every machine on very soft sand at road pressure and aired down: how far it gets and
## whether it bogs (the dirt bike never should). Then a ute snatches a dug-in buggy and quad.

var main


func _drive(kind: String, psi: float, soft: float, secs: float) -> Dictionary:
	var car: SandVehicle = main.local_car
	car.set_kind(kind)
	main.island.force_soft = -1.0
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(1.0).timeout
	car.scripted = true
	car.set_all_psi(psi)
	main.island.force_soft = soft
	var p0 := car.global_position
	var bogged := false
	var top := 0.0
	car.throttle = 1.0
	car.steer = 0.0
	var t := 0.0
	while t < secs:
		await physics_frame
		t += 1.0 / 60.0
		bogged = bogged or car.is_bogged
		top = maxf(top, car.speed_kmh)
	car.throttle = 0.0
	car.brake = 1.0
	var d := Vector2(car.global_position.x - p0.x, car.global_position.z - p0.z).length()
	var out := {"dist": d, "bogged": bogged, "top": top, "sink": car.avg_sink, "upright": car.global_basis.y.y}
	main.island.force_soft = -1.0
	await create_timer(0.5).timeout
	car.brake = 0.0
	return out


func _snatch(kind: String) -> Dictionary:
	var a: SandVehicle = main.local_car
	a.set_kind(kind)
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(1.0).timeout
	a.scripted = true
	a.throttle = 0.0
	a.brake = 0.0
	var b := SandVehicle.new()
	b.name = "Snatcher_" + kind
	b.local_control = true
	b.scripted = true
	main.cars.add_child(b)
	b.teleport(a.global_transform * Vector3(0, 0, -(float(a.spec["z"]) + 1.45 + 6.5)), -a.global_basis.z)
	await create_timer(1.5).timeout
	for w in a.wheels:
		w.dig = 0.25
	a.handbrake = false
	main.ropes.create("strap", {"car": String(b.name), "p": b.rear_point()}, {"car": String(a.name), "p": a.front_point()}, Ropes.STRAP_LEN)
	await create_timer(0.3).timeout
	var p0 := a.global_position
	var top := 0.0
	b.throttle = 1.0
	for i in 40:
		await create_timer(0.1).timeout
		top = maxf(top, absf(a.speed_kmh))
	b.throttle = 0.0
	b.brake = 1.0
	var moved := Vector2(a.global_position.x - p0.x, a.global_position.z - p0.z).length()
	var out := {"moved": moved, "top": top, "upright": a.global_basis.y.y}
	for id in main.ropes.ropes.keys():
		main.ropes.remove(id)
	b.queue_free()
	await create_timer(0.5).timeout
	return out


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.5).timeout
	await main._start("solo")
	await create_timer(2.0).timeout
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(1.0).timeout
	for kind in ["ute", "buggy", "quad", "bike"]:
		for run in [[32.0, 0.9], [15.0, 0.9], [32.0, 0.65], [24.0, 0.75]]:
			var psi: float = run[0]
			var r: Dictionary = await _drive(kind, psi, run[1], 12.0)
			print(("SAND %-5s soft %.2f" % [kind, run[1]]) + (" %2d psi  went %5.1f m  top %4.1f km/h  bogged=%s  sink %.2f  upright %.2f" % [int(psi), r["dist"], r["top"], r["bogged"], r["sink"], r["upright"]]))
	var bike: SandVehicle = main.local_car
	bike.set_kind("bike")
	print("BIKE can_recover=%s has_winch=%s can_bog=%s dug_in=%s" % [bike.can_recover(), bike.has_winch(), bike.can_bog(), bike.dug_in()])
	for kind in ["buggy", "quad", "ute"]:
		var r: Dictionary = await _snatch(kind)
		print("SNATCH %-5s moved %4.1f m  top %4.1f km/h  upright %.2f" % [kind, r["moved"], r["top"], r["upright"]])
	quit()

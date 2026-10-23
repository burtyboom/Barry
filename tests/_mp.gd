extends SceneTree
## Two-process multiplayer check: run one with "host" and one with "client".
var main
var role := ""

func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.3).timeout
	if role == "host":
		main._select_island("moreton")
		main.avatar_style = "bean"
		main.pet_kind = "greyhound"
		await main._start("host")
		await create_timer(2.0).timeout
		_eurongish(main.local_car, 0.0)
		var waited := 0
		while main.ropes.ropes.size() == 0 and waited < 30:
			await create_timer(0.5).timeout
			waited += 1

		await create_timer(1.0).timeout
		print("[host] driving off to snatch the client car")
		main.local_car.scripted = true
		main.local_car.throttle = 1.0
		for i in 8:
			await create_timer(1.0).timeout
			print("[host] my speed %.0f km/h" % main.local_car.speed_kmh)
			_report()
		main.local_car.throttle = 0.0
		await create_timer(6.0).timeout
	else:
		main.avatar_style = "blocky"
		main.pet_kind = "cat"
		await create_timer(2.0).timeout
		get_root().get_node("Net").join("127.0.0.1")
		for k in 6:
			await create_timer(1.0).timeout
			var hc0 = main.cars.get_node_or_null("Car_1") if main.cars else null
			if hc0:
				print("[client] t=%d host car %s has_state=%s target=%s" % [k, hc0.global_position, hc0._net_has_state, hc0._net_target_pos])
		_eurongish(main.local_car, 8.0)
		await create_timer(1.5).timeout
		main.local_player.get_out()
		await create_timer(2.0).timeout
		main.props.place("chair", Transform3D(Basis.IDENTITY, main.local_player.global_position + Vector3(2, 0, 0)))
		var host_car: SandVehicle = main.cars.get_node("Car_1")
		var hc: SandVehicle = main.cars.get_node("Car_1")
		print("[client] my car ", main.local_car.global_position, " host car ", hc.global_position, " gap ", (main.local_car.global_transform * SandVehicle.FRONT_POINT).distance_to(hc.global_transform * SandVehicle.REAR_POINT))
		main.ropes.rope_snapped.connect(func(id): print("[client] SNAPPED ", id))
		main.ropes.create("strap", {"car": String(main.local_car.name), "p": SandVehicle.FRONT_POINT}, {"car": "Car_1", "p": SandVehicle.REAR_POINT}, Ropes.STRAP_LEN)
		main.local_player.tools.select(0)
		main.local_player.tools._use(true)
		await create_timer(0.6).timeout
		main.local_player.tools._use(false)
		var z0: float = main.local_car.global_position.z
		for i in 10:
			await create_timer(1.5).timeout
			_report()
			print("[client] my car moved %.1f m north" % (z0 - main.local_car.global_position.z))
	quit()

func _eurongish(car: SandVehicle, dz: float) -> void:
	var p: Vector3 = Vector3.ZERO
	for pl in main.island.places:
		if pl["name"] == "Tangalooma Wrecks":
			p = pl["pos"]
	car.teleport(p + Vector3(0, 0, dz), Vector3.FORWARD)

func _report() -> void:
	var tension := 0.0
	for r in main.ropes.ropes.values():
		tension = r["tension"]
	var s := "[%s] tension=%.0f island=%s cars=%d players=%d props=%d ropes=%d" % [role, tension, main.island.id if main.island else "-", main.cars.get_child_count(), main.players.get_child_count(), main.props.props.size(), main.ropes.ropes.size()]
	for p in main.players.get_children():
		var pc := p as PlayerCharacter
		s += "  %s(style=%s state=%d local=%s fish=%s)" % [pc.name, pc.avatar.style, pc.state, pc.local_control, pc.tools._fish]
	if main.get("pets"):
		for pet in main.pets.get_children():
			s += "  %s(%s state=%s anim=%d mine=%s)" % [pet.name, pet.kind, pet.state, pet.anim, pet.is_multiplayer_authority()]
	print(s)

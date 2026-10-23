extends SceneTree
## Dev: godot --path . --headless --fixed-fps 60 -s res://tests/_vehicle_bots.gd
## A bot on every kind of machine in every everyday role; let them potter about and report
## how far each went, whether any bogged, and that bike bots never did.

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.5).timeout
	await main._start("solo")
	await create_timer(2.0).timeout
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(2.0).timeout
	var bots: Bots = main.bots
	var me: int = main.multiplayer.get_unique_id()
	var n := 0
	var start := {}
	for kind in ["buggy", "quad", "bike"]:
		for role in ["cruiser", "fisher", "camper", "tracker"]:
			n += 1
			var nm := "Bot_%d_%d" % [me, 900 + n]
			var xf: Transform3D = bots._spawn_xf(role, main.local_car.global_position)
			bots._rpc_spawn(nm, role, xf, me, "blocky", n % 6, "%s-%s" % [kind, role], kind)
			await create_timer(0.3).timeout
	for b in bots.brains():
		start[b.name] = b.car.global_position
	var bogged := {}
	for t in 120:
		await create_timer(1.0).timeout
		for b in bots.brains():
			if b.car.is_bogged:
				bogged[b.display] = true
	for b in bots.brains():
		var p0: Vector3 = start.get(b.name, b.car.global_position)
		var d := Vector2(b.car.global_position.x - p0.x, b.car.global_position.z - p0.z).length()
		print("BOT %-14s %-5s went %5.0f m  bogged=%s  upright %.2f" % [b.display, b.car.kind, d, bogged.has(b.display), b.car.global_basis.y.y])
	quit()

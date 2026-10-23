extends SceneTree
## Two-process check that everyone sees everyone's machine:
##   godot --path . --headless -s res://tests/_mp_vehicle.gd -- host --port=7795
##   godot --path . --headless -s res://tests/_mp_vehicle.gd -- client --port=7795
## The host rides a dirt bike and has a quad-riding bot out before the client joins (late
## join sync); the client turns up in a buggy.

func _initialize() -> void:
	var role: String = OS.get_cmdline_user_args()[0]
	var net = root.get_node("Net")
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.3).timeout
	if role == "host":
		main.vehicle_kind = "bike"
		await main._start("host")
		await create_timer(3.0).timeout
		var me: int = main.multiplayer.get_unique_id()
		main.bots._rpc_spawn("Bot_%d_77" % me, "cruiser", Transform3D(Basis.IDENTITY, main.local_car.global_position + Vector3(10, 2, 0)),
			me, "blocky", 2, "Quaddy", "quad")
		for i in 30:
			await create_timer(1.0).timeout
			var cc = main.cars.get_node_or_null("Car_%d" % _other(main))
			if cc:
				await create_timer(3.0).timeout
				cc = main.cars.get_node_or_null("Car_%d" % _other(main))
				print("[host] I ride %s, client rides %s" % [main.local_car.kind, cc.kind if cc else "?"])
				break
		await create_timer(6.0).timeout
	else:
		main.vehicle_kind = "buggy"
		await create_timer(2.0).timeout
		net.join("127.0.0.1", net.host_port)
		for i in 30:
			await create_timer(1.0).timeout
			if main.local_car and main.cars.get_node_or_null("Car_1"):
				break
		await create_timer(4.0).timeout
		var hc: SandVehicle = main.cars.get_node_or_null("Car_1")
		var bot_kind := "?"
		for c in main.cars.get_children():
			if c.has_meta("bot"):
				bot_kind = c.kind
		var hp = main.players.get_node_or_null("Player_1")
		print("[client] I ride %s, host rides %s (rider visible=%s), host's bot rides %s" % [main.local_car.kind, hc.kind if hc else "?", hp.avatar.visible if hp else "?", bot_kind])
		await create_timer(2.0).timeout
	quit()


func _other(main) -> int:
	for p in main.multiplayer.get_peers():
		return p
	return 0

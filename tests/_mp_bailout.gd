extends SceneTree
## Two-process check that a quad throwing its rider shows up for the other player:
##   godot --path . --headless -s res://tests/_mp_bailout.gd -- host --port=7796
##   godot --path . --headless -s res://tests/_mp_bailout.gd -- client --port=7796
## The host rides a quad and tips it over at speed; the client watches the host's rider.

func _initialize() -> void:
	var role: String = OS.get_cmdline_user_args()[0]
	var net = root.get_node("Net")
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.3).timeout
	if role == "host":
		main.vehicle_kind = "quad"
		await main._start("host")
		for i in 40:
			await create_timer(0.5).timeout
			if main.multiplayer.get_peers().size() > 0:
				break
		await create_timer(3.0).timeout
		main.teleport_local(main.island.places[2]["pos"])   # off the barge
		await create_timer(3.0).timeout
		var car: SandVehicle = main.local_car
		var pl: PlayerCharacter = main.local_player
		car.scripted = true
		car.throttle = 0.8
		await create_timer(3.0).timeout
		car.apply_torque_impulse(-car.global_basis.z * car.mass * 6.0)
		for i in 30:
			await create_timer(0.2).timeout
			if pl.state == PlayerCharacter.State.EXITING:
				car.throttle = 0.0
				car.brake = 1.0
		print("[host] thrown and back up: on foot=%s" % pl.is_on_foot())
		await create_timer(3.0).timeout
	else:
		await create_timer(2.0).timeout
		net.join("127.0.0.1", net.host_port)
		var hp = null
		for i in 40:
			await create_timer(0.5).timeout
			hp = main.players.get_node_or_null("Player_1")
			if hp:
				break
		var seen := []
		for i in 120:
			await create_timer(0.1).timeout
			var p: String = hp._net_pose if hp.state == PlayerCharacter.State.EXITING else ""
			if p != "" and (seen.is_empty() or seen[-1] != p):
				seen.append(p)
		print("[client] host's rider went: ", seen, "  now state ", hp.state, " (3 = on foot)")
	quit()

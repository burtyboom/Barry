extends SceneTree
## Two-process lasso + PvE check (no --fixed-fps): run one with "host" and one with "client".
##   godot --headless --path . -s res://tests/_mp_lasso.gd -- host --port=7793
##   godot --headless --path . -s res://tests/_mp_lasso.gd -- client
var main
var role := ""


func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	await process_frame
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.3).timeout
	if role == "host":
		await main._start("host")
		await create_timer(3.0).timeout
		_put(main.local_car, 0.0)
		await create_timer(1.5).timeout
		main.local_player.get_out()
		var client: PlayerCharacter = null
		for k in 40:
			await create_timer(0.5).timeout
			for p in main.players.get_children():
				if p != main.local_player and (p as PlayerCharacter).is_on_foot():
					client = p
			if client:
				break
		if client == null:
			print("[host] client never got out")
			quit()
			return
		await create_timer(1.0).timeout
		main.local_player.global_position = client.global_position + Vector3(3, 0.5, 0)
		print("[host] lassoing %s (pve known=%s)" % [client.name, main.is_pve(client)])
		client.request_lasso(String(main.local_player.name), "", 6.0)
		for k in 8:
			await create_timer(0.5).timeout
			print("[host] t=%.1f client tied=%s pose=%s holder=%s" % [k * 0.5, client.is_tied(), client._net_pose, client.tie_holder])
			main.local_player.global_position += Vector3(1.0, 0, 0)   # walk off with them
		await create_timer(5.0).timeout
		print("[host] after timeout: client tied=%s" % client.is_tied())
		# by now the client has switched PvE on
		await create_timer(2.0).timeout
		print("[host] client pve now=%s, blocks=%s" % [main.is_pve(client), main.pve_blocks(client, String(main.local_player.name))])
		main.lasso_cooldown = false
		client.request_lasso(String(main.local_player.name), "", 6.0)
		await create_timer(1.5).timeout
		print("[host] lasso a PvE player: tied=%s (should be false)" % client.is_tied())
		await create_timer(2.0).timeout
	else:
		await create_timer(2.0).timeout
		get_root().get_node("Net").join("127.0.0.1", 7793)
		for k in 30:
			await create_timer(0.5).timeout
			if main.local_player:
				break
		await create_timer(2.0).timeout
		_put(main.local_car, 10.0)
		await create_timer(1.5).timeout
		main.local_player.get_out()
		var p0: Vector3 = main.local_player.global_position
		for k in 12:
			await create_timer(0.5).timeout
			var me: PlayerCharacter = main.local_player
			print("[client] t=%.1f tied=%s left=%.1f s moved %.1f m" % [k * 0.5, me.is_tied(), me._tied_t, me.global_position.distance_to(p0)])
		await create_timer(2.0).timeout
		main.lasso_cooldown = false
		main.local_player._lasso_cd = 0.0
		main.pve = true   # not set_pve: that would save it to settings
		main._announce_pve.rpc(true)
		print("[client] PvE on")
		await create_timer(6.0).timeout
		print("[client] tied at the end=%s (should be false)" % main.local_player.is_tied())
	quit()


func _put(car: SandVehicle, dz: float) -> void:
	var p: Vector3 = main.island.places[2]["pos"]
	car.teleport(p + Vector3(0, 0, dz), Vector3.FORWARD)

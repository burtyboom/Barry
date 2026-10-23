extends SceneTree
## Dev: godot --path . -s res://tests/_strap_unhook.gd
## Strap your ute to a bot's tow hitch, then click again at the hitch: the strap comes off
## (it used to try to hook a second strap on instead).

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.5).timeout
	await main._start("solo")
	await create_timer(2.0).timeout
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(1.5).timeout
	main.bots.spawn("tourist", main.local_car.global_position + main.local_car.global_basis.z * -12.0)
	await create_timer(1.0).timeout
	var bot_car: SandVehicle = null
	for c in main.cars.get_children():
		if c.has_meta("bot"):
			bot_car = c
	main.local_player.get_out()
	await create_timer(1.5).timeout
	var own: SandVehicle = main.local_car
	var pl: PlayerCharacter = main.local_player
	var t: PlayerTools = pl.tools
	t.select(1)
	# park the bot right in front of us, facing away
	bot_car.teleport(own.global_transform * Vector3(0, 0, -7.5), -own.global_basis.z)
	await create_timer(0.3).timeout
	pl.global_position = own.global_transform * SandVehicle.FRONT_POINT + own.global_basis.z * -0.8
	t._use_strap()
	pl.global_position = bot_car.global_transform * SandVehicle.REAR_POINT + bot_car.global_basis.z * 0.8
	t._use_strap()
	print("ropes after hooking: ", main.ropes.ropes.size())
	await process_frame
	await process_frame
	print("prompt at hitch: ", t.prompt)
	t._use_strap()
	await process_frame
	print("ropes after unhook click: ", main.ropes.ropes.size())
	quit()

extends SceneTree
## Dev: godot --path . --resolution 1280x720 -s res://tests/_pet_tray_shot.gd -- <out_prefix>
## Each pet riding in the ute's tray, close up from the driver's side and behind.

func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.5).timeout
	await main._start("solo")
	await create_timer(2.0).timeout
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(2.0).timeout
	main.hud.visible = false
	var car: SandVehicle = main.local_car
	var me: int = main.multiplayer.get_unique_id()
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.fov = 45.0
	for spec in ["collie:0", "greyhound:1", "cavoodle:0", "cat:2"]:
		var old: Node = main.pets.get_node_or_null("Pet_%d" % me)
		if old:
			old.free()
		main._spawn_pet(me, main.local_player, spec)
		await create_timer(1.5).timeout
		var b := car.global_transform.basis
		var tray := car.global_transform * Vector3(-0.4, 0.9, 1.9)
		cam.global_position = tray + b * Vector3(-2.2, 0.9, 1.6)
		cam.look_at(tray, Vector3.UP)
		cam.current = true
		await create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + "tray_" + spec.split(":")[0] + ".png")
	print("tray shots done")
	quit()

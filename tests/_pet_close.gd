extends SceneTree
## Close-up pet shots: dog in the tray, dogs + cat on the sand, the menu preview.
func _cam(main, pos: Vector3, look: Vector3) -> void:
	var cam: Camera3D = main.camera
	cam.set_process(false)
	cam.set_physics_process(false)
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)


func _initialize() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	await main._start("solo")
	var me: int = main.multiplayer.get_unique_id()
	main.teleport_local(main.island.places[2]["pos"])
	main._spawn_pet(me, main.local_player, "collie:1")
	await create_timer(2.0).timeout
	main.hud.visible = false
	var car = main.local_car
	_cam(main, car.global_transform * Vector3(-2.2, 3.4, 3.6), car.global_transform * Vector3(-0.3, 0.8, 1.9))
	await create_timer(1.0).timeout
	var dd = main.pets.get_node("Pet_%d" % me)
	print("tray dog: state=%s vis=%s pos=%s tray=%s car=%s player_on_foot=%s" % [dd.state, dd.visible, dd.global_position, (car.global_transform * dd.TRAY_XF).origin, car.global_position, main.local_player.is_on_foot()])
	root.get_texture().get_image().save_png(out + "close_tray.png")
	# out on the sand: three pets
	main.local_player.get_out()
	await create_timer(3.0).timeout
	var p: Vector3 = main.local_player.global_position
	var i := 0
	for spec in ["greyhound:3", "cavoodle:0", "cat:0", "cat:3"]:
		main._spawn_pet(9001 + i, main.local_player, spec)
		var pet = main.pets.get_node("Pet_%d" % (9001 + i))
		pet.set_multiplayer_authority(me)
		pet.state = "sit"
		pet.anim = 3 if i % 2 == 0 else 0
		pet.set_physics_process(false)
		var q := p + Vector3(-1.2 + i * 1.3, 0, -3.6)
		q.y = main.island.height_at(q.x, q.z)
		pet.global_position = q
		pet.rotation.y = 0.6
		for k in 10:
			pet._animate(0.1, pet.anim, 0.0)
		i += 1
	var dog = main.pets.get_node("Pet_%d" % me)
	dog.set_physics_process(false)
	var dq := p + Vector3(3.2, 0, -3.0)
	dq.y = main.island.height_at(dq.x, dq.z)
	dog.global_position = dq
	dog.rotation.y = 0.6
	dog._animate(0.5, 0, 0.0)
	_cam(main, p + Vector3(4.5, 1.4, -1.0), p + Vector3(0.0, 0.3, -3.6))
	await create_timer(1.0).timeout
	root.get_texture().get_image().save_png(out + "close_lineup.png")
	quit()

extends SceneTree
## Dev: godot --path . --resolution 1280x720 -s res://tests/_pet_window_shot.gd -- <out_prefix>
## Each breed riding in the ute's back seat with its head out the window (parked, then at
## speed with the ears flapping), one in the tray, and one perched on each of the other machines.

var main


func _shot(name: String) -> void:
	await create_timer(0.4).timeout
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + name + ".png")
	print("shot ", name)


func _pet(spec: String, ride: int) -> Pet:
	var id: int = main.multiplayer.get_unique_id()
	main._spawn_pet(id, main.local_player, spec)
	await process_frame
	var pet: Pet = main.pets.get_node_or_null("Pet_%d" % id)
	pet._ride = ride
	pet.state = "tray"
	await create_timer(0.6).timeout
	return pet


func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.5).timeout
	await main._start("solo")
	await create_timer(2.0).timeout
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(1.5).timeout
	main.hud.visible = false
	var car: SandVehicle = main.local_car
	var cam = main.camera
	cam.distance = 3.4
	cam._orbiting = true
	for spec in ["greyhound:0", "collie:0", "cavoodle:0", "cat:0"]:
		var pet := await _pet(spec, Pet.Anim.WINDOW)
		cam._orbit_pitch = 0.05
		cam._orbit_yaw = deg_to_rad(-70)
		await _shot("window_" + spec.split(":")[0])
		# at speed: ears in the wind
		car.scripted = true
		car.throttle = 0.8
		await create_timer(3.0).timeout
		await _shot("window_fast_" + spec.split(":")[0])
		print(spec, " anim ", pet.anim, " speed ", car.speed_kmh)
		car.throttle = 0.0
		car.brake = 1.0
		await create_timer(2.5).timeout
		car.brake = 0.0
	await _pet("collie:1", Pet.Anim.TRAY)
	cam._orbit_yaw = deg_to_rad(-120)
	await _shot("tray_collie")
	for k in ["buggy", "quad", "bike"]:
		car.set_kind(k)
		main.teleport_local(main.island.places[2]["pos"])
		await create_timer(1.0).timeout
		await _pet("cavoodle:0", Pet.Anim.PERCH)
		cam.distance = 4.5
		cam._orbit_yaw = deg_to_rad(-60)
		await _shot("perch_" + k)
	quit()

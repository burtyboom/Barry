extends SceneTree
## Dev: godot --path . --resolution 1280x720 -s res://tests/_vehicle_shot.gd -- <out_prefix> [kinds...]
## Each machine with you on / in it from a 3/4 view, side-on, and while driving + turning.

func _shot(name: String) -> void:
	await create_timer(0.5).timeout
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + name + ".png")
	print("shot ", name)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var kinds: Array = ["buggy", "quad", "bike"]
	var body := ""
	for a in args.slice(1):
		if a == "blocky" or a == "bean":
			body = a
	if args.size() > 1 and not (args.size() == 2 and body != ""):
		kinds = Array(args.slice(1)).filter(func(a): return a != "blocky" and a != "bean")
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.5).timeout
	if body != "":
		main.avatar_style = body
	await main._start("solo")
	await create_timer(2.0).timeout
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(1.5).timeout
	main.hud.visible = OS.get_environment("VSHOT_HUD") != ""
	for k in kinds:
		var pre: String = body + "_" if body != "" else ""
		var car: SandVehicle = main.local_car
		car.set_kind(k)
		main.teleport_local(main.island.places[2]["pos"])
		await create_timer(1.5).timeout
		var cam = main.camera
		cam.distance = 5.5 if k != "buggy" else 7.0
		cam._orbit_pitch = 0.18
		cam._orbiting = true
		cam._orbit_yaw = deg_to_rad(140)
		await _shot(pre + k + "_34")
		cam._orbit_yaw = deg_to_rad(90)
		await _shot(pre + k + "_side")
		# drive and turn
		car.scripted = true
		car.throttle = 0.7
		car.steer = 0.0
		await create_timer(2.5).timeout
		car.steer = 0.35
		await create_timer(1.2).timeout
		cam._orbit_yaw = deg_to_rad(180)
		await _shot(pre + k + "_turn")
		print(k, " speed ", car.speed_kmh, " up_y ", car.global_basis.y.y)
		car.throttle = 0.0
		car.steer = 0.0
		car.brake = 1.0
		await create_timer(2.0).timeout
		car.brake = 0.0
		car.scripted = false
		# hop off and stand beside it
		print(k, " before get_out speed ", car.speed_kmh, " state ", main.local_player.state)
		main.local_player.get_out()
		await create_timer(2.0).timeout
		print(k, " after get_out state ", main.local_player.state)
		cam._orbit_yaw = deg_to_rad(120)
		await _shot(pre + k + "_off")
		main.local_player.get_in()
		await create_timer(1.8).timeout
	quit()

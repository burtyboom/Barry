extends SceneTree
## Dev: godot --path . --resolution 1280x720 -s res://tests/_bailout_shot.gd -- <out_prefix> [kinds...]
## Roll each machine and screenshot the bail-out: the buggy squeezes out of its cage (on its
## side: up between the bars; on its roof: crawl out sideways), quads and bikes throw you off.

var main
var pre := ""


func _shot(name: String) -> void:
	get_root().get_texture().get_image().save_png(pre + name + ".png")
	print("shot ", name, "  state ", main.local_player.state, " pose ", main.local_player._net_pose)


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _cam(yaw_deg: float, dist: float) -> void:
	var cam = main.camera
	cam.distance = dist
	cam._orbit_pitch = 0.22
	cam._orbiting = true
	cam._orbit_yaw = deg_to_rad(yaw_deg)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	pre = args[0]
	var kinds: Array = ["buggy", "quad", "bike"] if args.size() < 2 else Array(args.slice(1))
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await _wait(0.5)
	await main._start("solo")
	await _wait(2.0)
	main.teleport_local(main.island.places[2]["pos"])
	await _wait(1.5)
	main.hud.visible = false
	var pl: PlayerCharacter = main.local_player
	var car: SandVehicle = main.local_car
	for k in kinds:
		car.set_kind(k)
		main.teleport_local(main.island.places[2]["pos"])
		await _wait(1.5)
		if k == "buggy":
			for sgn in [1.0, -1.0]:
				# on its side, each way up (driver's side up, then down)
				var p := car.global_position
				car._place(Transform3D(car.global_basis.rotated(-car.global_basis.z, PI * 0.5 * sgn), Vector3(p.x, main.island.height_at(p.x, p.z) + 0.95, p.z)))
				if sgn < 0:
					# this way over it tends to rock back onto its wheels - hold it on its side
					await _wait(0.05)
					var here: Transform3D = car.global_transform
					car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
					car.freeze = true
					car.global_transform = here
				await _wait(2.5)
				print("buggy side %d: roll_state %d up.y %.2f" % [sgn, car.roll_state, car.global_basis.y.y])
				_cam(215 if sgn > 0 else 325, 6.5)
				pl.get_out()
				var tag := "buggy_side%s_" % ("A" if sgn > 0 else "B")
				for t in [0.8, 1.5, 2.0, 2.45, 3.1]:
					await _wait(t - (0.0 if t == 0.8 else [0.8, 1.5, 2.0, 2.45, 3.1][[0.8, 1.5, 2.0, 2.45, 3.1].find(t) - 1]))
					await _shot(tag + str(t))
				print("  on foot: ", pl.is_on_foot(), "  dist from car %.1f" % pl.global_position.distance_to(car.global_position))
				car.freeze = false
				car._recover_cd = 0.0
				car.recover()
				await _wait(1.5)
				pl.get_in()
				await _wait(1.6)
			# on its roof
			var p2 := car.global_position
			car._place(Transform3D(car.global_basis.rotated(-car.global_basis.z, PI), Vector3(p2.x, main.island.height_at(p2.x, p2.z) + 1.8, p2.z)))
			await _wait(2.5)
			print("buggy roof: roll_state %d up.y %.2f" % [car.roll_state, car.global_basis.y.y])
			_cam(60, 7.0)
			pl.get_out()
			for t in [0.6, 1.3, 2.0, 2.6]:
				await _wait(0.6 if t == 0.6 else 0.7 if t != 2.6 else 0.6)
				await _shot("buggy_roof_" + str(t))
			await _wait(0.5)
			print("  on foot: ", pl.is_on_foot(), "  dist from car %.1f" % pl.global_position.distance_to(car.global_position))
			car._recover_cd = 0.0
			car.recover()
			await _wait(1.5)
			pl.get_in()
			await _wait(1.6)
		else:
			# ride along the beach and get tipped over at speed
			car.scripted = true
			car.throttle = 0.8
			car.steer = 0.0
			await _wait(3.0)
			var v0: float = car.speed_kmh
			_cam(100, 7.5)
			car.apply_torque_impulse(-car.global_basis.z * car.mass * 6.0)
			var shots := 0
			var from := Vector3.INF
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 4000:
				await _wait(0.25)
				if pl.state == PlayerCharacter.State.EXITING:
					car.throttle = 0.0   # (nobody's on it now)
					car.brake = 1.0
					if from == Vector3.INF:
						from = pl.global_position
				if pl.state == PlayerCharacter.State.EXITING and shots < 6:
					await _shot("%s_thrown_%d" % [k, shots])
					shots += 1
			car.throttle = 0.0
			car.brake = 0.0
			car.scripted = false
			print("%s tipped at %.0f km/h: thrown=%s  on foot=%s  rider %.1f m from it, flew %.1f m  up.y %.2f" % [k, v0, shots > 0, pl.is_on_foot(), pl.global_position.distance_to(car.global_position), Vector2(pl.global_position.x - from.x, pl.global_position.z - from.z).length() if from != Vector3.INF else -1.0, car.global_basis.y.y])
			await _wait(1.5)
			await _shot(k + "_after")
			car._recover_cd = 0.0
			car.recover()
			await _wait(1.5)
			pl.get_in()
			await _wait(1.6)
	quit()

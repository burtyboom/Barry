extends SceneTree
## Two-process check that everyone sees the same roos and gulls:
##   godot --path . --headless -s res://tests/_mp_wildlife.gd -- host --port=7796
##   godot --path . --headless -s res://tests/_mp_wildlife.gd -- client --port=7796
## Or against a local online server (see _online.gd for the backend + dedicated):
##   godot --path . --headless -s res://tests/_mp_wildlife.gd -- online --site=http://127.0.0.1:8099
## Both print the roos / flocks every second (ROO <unix s> <idx> <x> <z> <state>); compare
## the same second from both. Then the client drives up to the nearest roo, and the host
## should see that mob take off (HOST FLEE <idx>).

func _initialize() -> void:
	var role: String = OS.get_cmdline_user_args()[0]
	var net = root.get_node("Net")
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.3).timeout
	if role == "host":
		await main._start("host")
		await create_timer(2.0).timeout
		main.teleport_local(main.island.places[2]["pos"])
		var fled := {}
		for i in 110:
			await create_timer(0.5).timeout
			var w = main.world.get_node_or_null("Wildlife") if main.world else null
			if w == null:
				continue
			if i % 2 == 0:
				_dump("HOST", w)
			for k in w._roos.size():
				var r = w._roos[k]
				if r.is_processing() and r._state == "flee" and not fled.has(k):
					fled[k] = true
					print("HOST FLEE ", k)
	else:
		await create_timer(2.0).timeout
		if role == "online":
			var r: Dictionary = await net.http_json(net.site_url + "/api/register", {"username": "roowatcher", "password": "sandy123"})
			if not r.get("ok", false):
				r = await net.http_json(net.site_url + "/api/login", {"username": "roowatcher", "password": "sandy123"})
			main.join_online("127.0.0.1", 7777, String(r.get("username", "roowatcher")), String(r.get("token", "")))
			for i in 40:
				await create_timer(0.5).timeout
				if main.local_car:
					break
			await create_timer(3.0).timeout
			main.teleport_local(main.island.places[2]["pos"])
		else:
			net.join("127.0.0.1", net.host_port)
			for i in 30:
				await create_timer(1.0).timeout
				if main.local_car and main.cars.get_node_or_null("Car_1"):
					break
			await create_timer(2.0).timeout
			var hc: SandVehicle = main.cars.get_node_or_null("Car_1")
			main.teleport_local(hc.global_position + hc.global_basis.x * 20.0)
		for i in 10:
			await create_timer(1.0).timeout
			_dump("CLIENT", main.world.get_node("Wildlife"))
		var w = main.world.get_node("Wildlife")
		var shot_to := ""
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--wshot="):
				shot_to = a.substr(8)
		if shot_to != "":
			await _shots(main, w, shot_to)
		# drive (teleport) right up to the nearest roo
		var best := -1
		var bd := 1e9
		for k in w._roos.size():
			var r = w._roos[k]
			if r.is_processing():
				var d: float = r.global_position.distance_to(main.local_car.global_position)
				if d < bd:
					bd = d
					best = k
		if best >= 0:
			var rp: Vector3 = w._roos[best].global_position
			print("CLIENT SCARE ", best, " (was %.0f m away)" % bd)
			main.teleport_local(rp + Vector3(5, 0, 0))
			for i in 6:
				await create_timer(1.0).timeout
				print("CLIENT SEES roo %d state %s" % [best, w._roos[best]._state])
		else:
			print("CLIENT no roos!")
		await create_timer(2.0).timeout
	quit()


func _dump(who: String, w) -> void:
	var t := int(Time.get_unix_time_from_system())
	for k in w._roos.size():
		var r = w._roos[k]
		if r.is_processing():
			print("%s ROO %d %d %.1f %.1f %s" % [who, t, k, r.global_position.x, r.global_position.z, r._state])
	for k in w._flocks.size():
		var f = w._flocks[k]
		if f.placed:
			print("%s FLOCK %d %d %.1f %.1f air=%s" % [who, t, k, f.spot.x, f.spot.z, f._air])


## Client-side close-ups of what the host is running (windowed runs only).
func _shots(main, w, prefix: String) -> void:
	var cam := Camera3D.new()
	cam.fov = 50.0
	main.add_child(cam)
	var n := 0
	for k in w._roos.size():
		var r = w._roos[k]
		if not r.is_processing() or n >= 2:
			continue
		var p: Vector3 = r.global_position
		cam.global_position = p + Vector3(5.5, 1.6, 2.5)
		cam.look_at(p + Vector3(0, 0.6, 0))
		cam.current = true
		await create_timer(1.0).timeout
		get_root().get_texture().get_image().save_png("%sroo_%d.png" % [prefix, n])
		n += 1
	for k in w._flocks.size():
		var f = w._flocks[k]
		if not f.placed:
			continue
		var p: Vector3 = f.spot
		cam.global_position = p + Vector3(9, 3, 6)
		cam.look_at(p + Vector3(0, 1.5 if f._air else 0.2, 0))
		cam.current = true
		await create_timer(1.0).timeout
		get_root().get_texture().get_image().save_png("%sflock_%d.png" % [prefix, k])
	cam.current = false
	main.camera.current = true
	cam.queue_free()

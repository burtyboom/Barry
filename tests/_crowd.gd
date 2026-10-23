extends SceneTree
## Dev: one of N online players for a crowd test (see _online.gd for the backend + server).
##   godot --headless --path . -s res://tests/_crowd.gd -- --site=http://127.0.0.1:8099 <user> [seconds]
## Logs in, joins, drives around in circles and reports how many players / cars it sees.

func _initialize() -> void:
	var user := "crowd"
	var secs := 60
	var plain: Array = []
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			plain.append(a)
	if plain.size() > 0:
		user = plain[0]
	if plain.size() > 1:
		secs = int(plain[1])
	var net = root.get_node("Net")
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(1.0).timeout
	var r: Dictionary = await net.http_json(net.site_url + "/api/register", {"username": user, "password": "sandy123"})
	if not r.get("ok", false):
		r = await net.http_json(net.site_url + "/api/login", {"username": user, "password": "sandy123"})
	if not r.get("ok", false):
		print(user, " LOGIN FAILED ", r.get("error", ""))
		quit()
		return
	var failed := [""]
	net.session_failed.connect(func(why: String) -> void: failed[0] = why)
	var t0 := Time.get_ticks_msec()
	main.join_online("127.0.0.1", 7777, String(r.get("username", user)), String(r.get("token", "")))
	while main.local_car == null and failed[0] == "" and Time.get_ticks_msec() - t0 < 60000:
		await create_timer(0.25).timeout
	if failed[0] != "" or main.local_car == null:
		print(user, " JOIN FAILED ", failed[0])
		quit()
		return
	print(user, " JOINED in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	await create_timer(8.0).timeout
	main.teleport_local(main.island.places[2]["pos"] + Vector3(randf_range(-40, 40), 0, randf_range(-40, 40)))
	var car: SandVehicle = main.local_car
	car.scripted = true
	var end := Time.get_ticks_msec() + secs * 1000
	var lost := false
	while Time.get_ticks_msec() < end:
		car.throttle = 0.6
		car.steer = sin(Time.get_ticks_msec() / 3000.0) * 0.5
		await create_timer(10.0).timeout
		if failed[0] != "":
			lost = true
			break
		var peers: Array = Array(main.multiplayer.get_peers())
		var ping := -1
		var enet := main.multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if enet and enet.get_peer(1):
			ping = int(enet.get_peer(1).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
		print("%s sees %d players, %d cars, ping %d ms, %d fps" % [user, peers.size() - 1 + 1, main.cars.get_child_count(), ping, Engine.get_frames_per_second()])
	if lost:
		print(user, " DROPPED: ", failed[0])
	else:
		print(user, " DONE ok")
	quit()

extends SceneTree
## Dev: godot --headless --path . -s res://tests/_live_join.gd -- <user> [seconds]   (uses the REAL site + server)
## Live check with the shipped exe: sign up / log in a test account on the real site,
## join the real server, drive about for a bit, chat, then check the website sees us.

func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var user := args[0] if args.size() > 0 else "TestRig"
	var secs := int(args[1]) if args.size() > 1 else 60
	var net = root.get_node("Net")
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(1.0).timeout
	print("site ", net.site_url, " server ", net.server_host)
	var r: Dictionary = await net.http_json(net.site_url + "/api/login", {"username": user, "password": "testrig-" + user.to_lower()})
	if not r.get("ok", false):
		r = await net.http_json(net.site_url + "/api/register", {"username": user, "password": "testrig-" + user.to_lower()})
	print("LOGIN ", r.get("ok"), " ", r.get("username", r.get("error", "")))
	if not r.get("ok", false):
		quit(1)
		return
	var failed := [""]
	net.session_failed.connect(func(why: String) -> void: failed[0] = why)
	var t0 := Time.get_ticks_msec()
	main.join_online(net.server_host, GameVersion.SERVER_PORT, String(r["username"]), String(r["token"]))
	while main.local_car == null and failed[0] == "" and Time.get_ticks_msec() - t0 < 60000:
		await create_timer(0.25).timeout
	if main.local_car == null:
		print("JOIN FAILED: ", failed[0])
		quit(1)
		return
	print("JOINED in %.1f s on %s, dedicated=%s" % [(Time.get_ticks_msec() - t0) / 1000.0, net.island_id, net.server_dedicated])
	await create_timer(10.0).timeout
	main.send_chat("test rig checking in")
	var car: SandVehicle = main.local_car
	car.scripted = true
	var start := car.global_position
	var end := Time.get_ticks_msec() + secs * 1000
	while Time.get_ticks_msec() < end and failed[0] == "":
		car.throttle = 0.5
		car.steer = sin(Time.get_ticks_msec() / 4000.0) * 0.4
		await create_timer(5.0).timeout
	var enet := main.multiplayer.multiplayer_peer as ENetMultiplayerPeer
	var ping := int(enet.get_peer(1).get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME)) if enet and enet.get_peer(1) else -1
	var others: Array = []
	for id in main.multiplayer.get_peers():
		if id != 1:
			others.append(main.name_of(id))
	var chat: RichTextLabel = main.hud.chat._logs["players"]
	print("SEES ", others, " | chat: ", chat.get_parsed_text().replace("
", " / ").right(200))
	print("DROVE %.0f m, ping %d ms, lost=%s, cars %d" % [car.global_position.distance_to(start), ping, failed[0], main.cars.get_child_count()])
	var on: Dictionary = await net.http_json(net.site_url + "/api/online", null)
	print("ONLINE ", JSON.stringify(on).left(300))
	car.scripted = false
	main.back_to_menu()
	await create_timer(3.0).timeout
	print("BACK AT MENU ", main._menu.visible)
	quit()

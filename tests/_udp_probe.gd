extends SceneTree
## Dev: can we reach the online game server? Joins with no account token and logs each step.
##   godot --headless --path . -s res://tests/_udp_probe.gd -- <host>
func _initialize() -> void:
	await process_frame
	var net = root.get_node("Net")
	var host: String = OS.get_cmdline_user_args()[0]
	var t0 := Time.get_ticks_msec()
	var log := func(s: String) -> void: print("PROBE %5d ms  %s" % [Time.get_ticks_msec() - t0, s])
	var done := [false]
	net.session_failed.connect(func(why: String) -> void:
		log.call("refused: " + why.replace("\n", " | "))
		done[0] = true)
	net.island_received.connect(func(i: String) -> void:
		log.call("IN! island " + i)
		done[0] = true)
	(net.multiplayer as SceneMultiplayer).peer_authenticating.connect(func(id: int) -> void: log.call("ENet connected, logging in (peer %d)" % id))
	net.multiplayer.connected_to_server.connect(func() -> void: log.call("auth accepted"))
	net.join_name = "probe"
	net.join_token = ""
	net.join(host, 7777)
	log.call("connecting to %s:7777" % host)
	for i in 120:
		await create_timer(0.25).timeout
		if done[0]:
			break
	if not done[0]:
		log.call("no answer in 30 s")
	quit()

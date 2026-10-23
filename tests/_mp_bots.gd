extends SceneTree
## Two-process check that bots show up for other players:
##   godot --path . -s res://tests/_mp_bots.gd -- host     (and in another process: -- client)
## The host spawns a helper + fisher before the client joins (late-join sync) and a
## camper after (live spawn); both sides print what they see.
var main
var role := ""


func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.3).timeout
	if role == "host":
		main._select_island("fraser")
		await main._start("host")
		await create_timer(1.0).timeout
		_to_eurong()
		await create_timer(1.5).timeout
		main.local_car.scripted = true
		main.bots.spawn("helper")
		main.bots.spawn("fisher")
		await create_timer(8.0).timeout
		main.bots.spawn("camper")
		for k in 8:
			await create_timer(6.0).timeout
			_report()
	else:
		await create_timer(4.0).timeout
		get_root().get_node("Net").join("127.0.0.1")
		for k in 10:
			await create_timer(6.0).timeout
			_report()
	quit()


func _to_eurong() -> void:
	for pl in main.island.places:
		if pl["name"] == "Eurong":
			main.local_car.teleport(pl["pos"], Vector3.FORWARD)


func _report() -> void:
	var s := "[%s] props=%d cars=%s pending=%d" % [role, main.props.props.size(), main.cars.get_children().map(func(c): return c.name), main.bots._pending.size()]
	for c in main.cars.get_children():
		if c.has_meta("bot"):
			var p: Vector3 = c.global_position
			var person: PlayerCharacter = main.players.get_node_or_null("BotP_" + String(c.name).trim_prefix("Bot_"))
			s += "  %s(%s @%.0f,%.0f %s)" % [c.name, c.get_meta("bot"), p.x, p.z,
				("person state %d fish %s" % [person.state, person.tools._fish]) if person else "NO PERSON"]
	print(s)

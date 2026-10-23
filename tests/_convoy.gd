extends SceneTree
## Two-process convoy check: run one with "host" and one with "client" (LAN game).
## The client invites the host, the host accepts, both chat in the convoy tab.
var main

func _initialize() -> void:
	await process_frame
	var role: String = OS.get_cmdline_user_args()[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.3).timeout
	if role == "host":
		main.player_name = "Hosty"
		await main._start("host")
		# accept the first invite that turns up
		var orig: Callable = main.hud.chat.show_invite
		for i in 60:
			await create_timer(0.5).timeout
			if main.hud.chat._invite_box and is_instance_valid(main.hud.chat._invite_box):
				print("[host] invite card shown")
				var yes: Button = main.hud.chat._invite_box.get_child(0).get_child(1).get_child(0)
				yes.pressed.emit()
				break
		await create_timer(1.0).timeout
		main.convoy.send_chat("convoy hello from host")
		main.send_chat("public hello from host")
		await create_timer(12.0).timeout
	else:
		main.player_name = "Clienty"
		await create_timer(2.0).timeout
		root.get_node("Net").session_failed.connect(func(w: String) -> void: print("[client] DROPPED: ", w))
		root.get_node("Net").join_name = "Clienty"
		root.get_node("Net").join("127.0.0.1")
		for k in 6:
			await create_timer(1.0).timeout
			print("[client] t=%d peers=%s car=%s" % [k, main.multiplayer.get_peers(), main.local_car != null])
		main.convoy.invite(1)
		await create_timer(3.0).timeout
		main.convoy.send_chat("convoy hello from client")
		await create_timer(4.0).timeout
	var c = main.convoy
	print("[%s] my convoy=%s members=%s tab_visible=%s" % [role, c.my_id != "", c.my_members(), main.hud.chat._tab_btns["convoy"].visible])
	print("[%s] CONVOY LOG: %s" % [role, main.hud.chat._logs["convoy"].get_parsed_text().replace("\n", " | ")])
	print("[%s] PLAYERS LOG: %s" % [role, main.hud.chat._logs["players"].get_parsed_text().replace("\n", " | ")])
	quit()

extends SceneTree
## Dev: godot --path . --resolution 1600x900 -s res://tests/_hud_shot.gd -- <out_prefix>
## Solo game with a few bots, a chat line, then screenshots: HUD, big map, console, helper panel.

func _shot(name: String) -> void:
	await create_timer(0.6).timeout
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + name + ".png")
	print("shot ", name)


func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.5).timeout
	main.randomise_look()
	await main._start("solo")
	await create_timer(1.0).timeout
	var car: SandVehicle = main.local_car
	# skip the barge
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(1.5).timeout
	main.bots.spawn("helper")
	for k in 4:
		main.bots.spawn(main.bots.random_role(false))
	main.bots.spawn("police")
	await create_timer(4.0).timeout
	main.send_chat("G'day legends, who's up for a beach footy?")
	main.local_player.get_out()
	await create_timer(3.0).timeout
	main.local_player.wave()
	main.on_wave()
	await _shot("hud")
	main.hud.minimap.big_map.visible = true
	await _shot("bigmap")
	main.hud.minimap.big_map.visible = false
	main.hud._helper_panel.visible = true
	main.hud.chat.show_tab("bots")
	await _shot("helper")
	main.hud._helper_panel.visible = false
	main.console.toggle()
	main.console._run("admin 1234")
	await _shot("console")
	quit()

extends SceneTree
## Dev: godot --path . --resolution 1600x900 -s res://tests/_pause_shot.gd -- <out_prefix>
## Solo game: Esc menu, hold-Tab player list, back to the main menu, then a second game.

func _shot(name: String) -> void:
	await create_timer(0.6).timeout
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + name + ".png")
	print("shot ", name)


func _key(code: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)


func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.5).timeout
	await main._start("solo")
	await create_timer(2.0).timeout
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(1.5).timeout
	main.hud.get_child(0).get_node("HelpPanel").visible = false
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await create_timer(0.3).timeout
	print("pause open: ", main.hud.pause.visible, " typing ", Hud.typing(), " focus ", get_root().gui_get_focus_owner(), " hudvis ", main.hud.visible)
	await _shot("pause")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await create_timer(0.3).timeout
	print("pause closed: ", not main.hud.pause.visible)
	_key(KEY_TAB, true)
	await create_timer(0.3).timeout
	print("list open: ", main.hud.players_list.visible)
	await _shot("tab")
	_key(KEY_TAB, false)
	await create_timer(0.2).timeout
	main.back_to_menu()
	await create_timer(4.0).timeout
	print("menu visible: ", main._menu.visible, " car: ", main.local_car, " hud: ", main.hud != null and main.hud.visible)
	await _shot("menu")
	await main._start("solo")
	await create_timer(2.0).timeout
	print("second game car: ", main.local_car != null)
	await _shot("again")
	quit()

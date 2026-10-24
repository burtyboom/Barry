extends SceneTree
## Dev: godot --path . -s res://tests/_gfx_shot.gd -- <out_prefix>
## Same view on Graphics High and Low (Esc menu), with frame rates.

func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.5).timeout
	await main._start("solo")
	await create_timer(2.0).timeout
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(3.0).timeout
	main.hud.get_child(0).get_node("HelpPanel").visible = false
	for low in [false, true]:
		main.set_graphics_low(low)
		await create_timer(3.0).timeout
		print("low=%s fps %d" % [low, Engine.get_frames_per_second()])
		get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + ("low" if low else "high") + ".png")
	main.hud.pause.open()
	await create_timer(0.5).timeout
	get_root().get_texture().get_image().save_png(OS.get_cmdline_user_args()[0] + "menu.png")
	quit()

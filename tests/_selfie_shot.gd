extends SceneTree
## Dev: take a selfie in a solo game and keep the picture + a screenshot of the polaroid.
##   godot --path . --resolution 1600x900 -s res://tests/_selfie_shot.gd -- <out_prefix>
func _initialize() -> void:
	await process_frame
	var out: String = OS.get_cmdline_user_args()[0]
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	await main._start("solo")
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(1.5).timeout
	main.local_player.get_out()
	await create_timer(3.0).timeout
	var t = main.local_player.tools
	t.select(12)
	await create_timer(0.5).timeout
	await t._selfie().take()
	await create_timer(0.6).timeout
	root.get_texture().get_image().save_png(out + "selfie_hud.png")
	var d := DirAccess.open("user://selfies")
	var newest := ""
	for f in d.get_files():
		if f > newest:
			newest = f
	print("selfie file: ", newest)
	var img := Image.load_from_file("user://selfies/" + newest)
	img.save_png(out + "selfie_pic.png")
	quit()

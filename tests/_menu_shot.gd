extends SceneTree
## Dev: godot --path . -s res://tests/_menu_shot.gd -- --menu <out_prefix> [panel ...]
## Shows the main menu with its beach backdrop and saves screenshots: the front page,
## then each named side panel (online, lan, custom, news).

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[1]
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	for i in 120:
		await create_timer(0.25).timeout
		if main._show_car != null:
			break
	print("showcase up: ", main._show_car != null)
	await create_timer(4.0).timeout
	get_root().get_texture().get_image().save_png(out + "menu_0.png")
	print("shot menu_0")
	for k in range(2, args.size()):
		main.menu.show_panel(args[k])
		await create_timer(3.0).timeout
		get_root().get_texture().get_image().save_png(out + "menu_%s.png" % args[k])
		print("shot menu_%s" % args[k])
	quit()

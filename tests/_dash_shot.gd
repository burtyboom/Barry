extends SceneTree
## Dev: the dashboard while driving in soft sand with aired-down tyres (and a locker on).
##   godot --path . --resolution 1600x900 -s res://tests/_dash_shot.gd -- <out.png>
func _initialize() -> void:
	await process_frame
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	await main._start("solo")
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(1.5).timeout
	main.hud.get_child(0).get_node("HelpPanel").visible = false
	var car = main.local_car
	car.set_all_psi(15.0)
	car.rear_locker = true
	car.low_range = true
	main.island.force_soft = 0.7
	car.scripted = true
	car.throttle = 1.0
	await create_timer(4.0).timeout
	root.get_texture().get_image().get_region(Rect2i(0, 0, 420, 420)).save_png(OS.get_cmdline_user_args()[0])
	quit()

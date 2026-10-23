extends SceneTree
func _initialize() -> void:
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(1.0).timeout
	main.menu.show_panel("custom")
	await create_timer(0.5).timeout
	print("menu rect ", main.menu.get_global_rect(), " right ", main.menu._right.get_global_rect(), " vis ", main.menu._right.is_visible_in_tree())
	quit()

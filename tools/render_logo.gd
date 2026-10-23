extends SceneTree
## Saves the menu logo as a transparent PNG (for the website).
##   godot --path . --resolution 1280x720 -s res://tools/render_logo.gd -- out.png [scale]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "logo.png"
	var sc := float(args[1]) if args.size() > 1 else 2.0
	var vp := SubViewport.new()
	vp.transparent_bg = true
	vp.size = Vector2i(int(660 * sc), int(330 * sc))
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var holder := Control.new()
	holder.scale = Vector2(sc, sc)
	vp.add_child(holder)
	var logo := Logo.new()
	logo.animate = false
	logo.position = Vector2(10, 10)
	holder.add_child(logo)
	for i in 8:
		await process_frame
	vp.get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()

extends SceneTree
func _initialize() -> void:
	var which: String = OS.get_cmdline_user_args()[0]
	var out: String = OS.get_cmdline_user_args()[1]
	var d := IslandData.make(which)
	d.generate()
	var img := Image.create(d.cols, d.rows, false, Image.FORMAT_RGBA8)
	for y in d.rows:
		for x in d.cols:
			var i := y * d.cols + x
			var hh := d.heights[i]
			var c: Color
			if hh < 0.0 and d.surf[i] != IslandData.Surface.ROCK:
				c = Color(0.1, 0.35, 0.55).lerp(Color(0.3, 0.65, 0.75), clampf(1.0 + hh / 4.0, 0.0, 1.0))
			else:
				c = WorldBuilder.surface_color(d.surf[i], d.soft[i], hh)
				c = c.darkened(clampf((hh - 10.0) / 80.0, 0.0, 0.5))
				if d.surf[i] == IslandData.Surface.ROCK:
					c = Color(0.25, 0.15, 0.1)
				elif d.track[i] > 0.4:
					c = Color(0.85, 0.2, 0.1)
			img.set_pixel(x, y, c)
	for p in d.places:
		var pos: Vector3 = p["pos"]
		var px := int((pos.x - d.x_min) / IslandData.CELL)
		var pz := int((pos.z - d.z_min) / IslandData.CELL)
		for a in range(-2, 3):
			for b in range(-2, 3):
				img.set_pixel(clampi(px + a, 0, d.cols - 1), clampi(pz + b, 0, d.rows - 1), Color.BLACK)
	print("trees ", d.trees.size(), " palms ", d.palms.size(), " jetties ", d.jetty_list.size(), " structures ", d.structure_list.size())
	# crop: optional f range
	if OS.get_cmdline_user_args().size() > 3:
		var f0 := float(OS.get_cmdline_user_args()[2])
		var f1 := float(OS.get_cmdline_user_args()[3])
		var r0 := int((d.f_to_z(f1) - d.z_min) / IslandData.CELL)
		var r1 := int((d.f_to_z(f0) - d.z_min) / IslandData.CELL)
		img = img.get_region(Rect2i(0, r0, d.cols, r1 - r0))
		img.resize(img.get_width() * 3, img.get_height() * 3, Image.INTERPOLATE_NEAREST)
	img.save_png(out)
	quit()

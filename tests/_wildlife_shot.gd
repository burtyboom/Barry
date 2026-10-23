extends SceneTree
## Dev: godot --path . --resolution 1280x720 -s res://tests/_wildlife_shot.gd -- <out_prefix> [island]
## Close-ups of the ambient wildlife: kangaroos grazing / sitting up / bounding away,
## gulls on the sand and wheeling about, and the soaring birds of prey.

var main
var out := ""


func shot(name: String) -> void:
	await process_frame
	await process_frame
	get_root().get_texture().get_image().save_png(out + name + ".png")
	print("shot ", name)


func look(from: Vector3, at: Vector3) -> void:
	main.camera.target = null
	main.camera.global_position = from
	main.camera.look_at(at, Vector3.UP)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	out = args[0] if args.size() > 0 else "user://wild_"
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.5).timeout
	if args.size() > 1:
		main._select_island(args[1])
	await main._start("solo")
	await create_timer(1.0).timeout
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(5.0).timeout
	var wild: Wildlife = main.world.get_node("Wildlife")
	main.hud.visible = false
	for m in wild._mobs:
		var c: Vector3 = m["center"]
		print("mob of %d at %s surface %d placed %s" % [m["roos"].size(), c, main.island.surface_at(c.x, c.z), m["placed"]])
	for f in wild._flocks:
		print("flock of %d at %s placed %s" % [f.count, f.spot, f.placed])
	# --- kangaroos
	var r: Kangaroo = wild._mobs[0]["roos"][0]
	var rp := r.global_position
	main.local_car.teleport(rp + Vector3(80, 2, 0), Vector3.FORWARD)   # out of the way
	await create_timer(1.0).timeout
	r._set_state("graze")
	r._wait = 99.0
	await create_timer(1.0).timeout
	rp = r.global_position
	var side := -r.global_basis.x.normalized()
	look(rp + side * 3.2 + Vector3(0, 1.0, 0) - r.global_basis.z.normalized() * 1.0, rp + Vector3(0, 0.5, 0))
	await create_timer(0.4).timeout
	await shot("roo_graze")
	r._set_state("alert")
	await create_timer(0.8).timeout
	rp = r.global_position
	look(rp + side * 3.2 + Vector3(0, 1.0, 0) - r.global_basis.z.normalized() * 1.5, rp + Vector3(0, 0.7, 0))
	await shot("roo_alert")
	# the mob together, a bit wider
	look(rp + side * 9.0 + Vector3(0, 3.0, 0), wild._mobs[0]["center"])
	await shot("roo_mob")
	r.scare(rp + Vector3(12, 0, 0))
	for k in 6:
		await create_timer(0.17).timeout
		var p := r.global_position
		var sd := r.global_basis.x.normalized()
		look(p + sd * 4.5 + Vector3(0, 0.6, 0), p + Vector3(0, 0.6, 0))
		await shot("roo_hop%d" % k)
	print("roo state ", r._state, " hop ", r._hop, " speed ", r._speed)
	# --- gulls
	var f: Birds.GullFlock = wild._flocks[0]
	var sp := f.spot
	look(sp + Vector3(3.5, 1.2, 3.5), sp + Vector3(0, 0.2, 0))
	await create_timer(0.5).timeout
	await shot("gulls_ground")
	f.take_off()
	await create_timer(0.8).timeout
	look(sp + Vector3(9, 2, 9), sp + Vector3(0, 3, 0))
	await shot("gulls_takeoff")
	await create_timer(3.0).timeout
	var g: Birds.Gull = f.gulls[0]
	look(g.global_position + Vector3(3, 1, 3), g.global_position)
	await shot("gull_close")
	look(f._center + Vector3(20, 4, 20), f._center + Vector3(0, 10, 0))
	await shot("gulls_fly")
	# --- birds of prey
	var s: Birds.Soarer = wild._soarers[0]
	await create_timer(0.3).timeout
	look(s.global_position + Vector3(5, -2.5, 5), s.global_position)
	await shot("eagle")
	var s2: Birds.Soarer = wild._soarers[1]
	look(s2.global_position + Vector3(4, -2, 4), s2.global_position)
	await shot("kite")
	quit()

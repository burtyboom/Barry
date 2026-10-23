extends SceneTree
## Renders the website's pictures straight out of the game:
##   island-bg.jpg (a wide beach shot) and transparent cutouts: ute, fishing, dingo, camp, ball
##   godot --path . --resolution 1920x1080 -s res://tools/render_site_images.gd -- <out_dir>

var out := ""


func _initialize() -> void:
	out = OS.get_cmdline_user_args()[0]
	await process_frame   # let the autoloads (Net) settle before game classes compile
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await create_timer(0.5).timeout
	await main._start("solo")
	main.teleport_local(main.island.places[2]["pos"])
	await create_timer(2.0).timeout
	for k in 4:
		main.bots.spawn(main.bots.random_role(false))
	await create_timer(5.0).timeout
	# --- backdrop: high, wide view along the beach, no HUD
	main.hud.visible = false
	main.music.enabled = false
	var cam: Camera3D = main.camera
	cam.set_process(false)
	cam.set_physics_process(false)
	var c: Vector3 = main.local_car.global_position
	cam.global_position = c + Vector3(-60, 32, 70)
	cam.look_at(c + Vector3(30, 0, -60), Vector3.UP)
	cam.fov = 70
	await create_timer(1.5).timeout
	root.get_texture().get_image().save_jpg(out + "/island-bg.jpg", 0.85)
	print("saved island-bg.jpg")

	# --- cutouts, each in its own little transparent studio
	var ute = load("res://scripts/vehicle/sand_vehicle.gd").new()
	ute.scripted = true
	ute.freeze = true
	ute.body_color = Color(0.95, 0.45, 0.15)
	await _studio("ute", ute, Vector3(6.2, 3.0, -6.8), Vector3(0, 0.8, 0))

	var fisher = load("res://scripts/player/avatar.gd").create(load("res://scripts/player/avatar.gd").make_spec("blocky", "corks", "hawaiian", "thongs", Color(0.15, 0.55, 0.85)), Color.WHITE)
	var rod := Node3D.new()
	fisher.hand_r.add_child(rod)
	var stick = load("res://scripts/world/toon.gd").box(rod, Vector3(0.04, 2.2, 0.04), Vector3(0, 1.0, 0), Color(0.2, 0.2, 0.25))
	stick.rotation_degrees.x = -35.0
	await _studio("fishing", fisher, Vector3(2.6, 1.6, -3.2), Vector3(0, 1.1, 0), "hold")

	var dingo = load("res://scripts/world/dingo.gd").new()
	dingo.set_process(false)
	dingo.set_physics_process(false)
	await _studio("dingo", dingo, Vector3(2.0, 1.0, -2.2), Vector3(0, 0.45, 0))

	var camp := Node3D.new()
	for it in [["tent", Vector3(-1.6, 0, -1.2), 0.5], ["fire", Vector3(1.0, 0, 0.6), 0.0], ["chair", Vector3(2.4, 0, -0.4), 1.8], ["esky", Vector3(0.0, 0, 1.6), 0.4]]:
		var p = load("res://scripts/items/props.gd").build(String(it[0]), false)
		p.transform = Transform3D(Basis(Vector3.UP, float(it[2])), it[1])
		camp.add_child(p)
	await _studio("camp", camp, Vector3(7.5, 5.0, -8.0), Vector3(0.3, 0.5, 0.2))

	var ball = load("res://scripts/items/soccer_ball.gd").new()
	ball.freeze = true
	ball.set_physics_process(false)
	await _studio("ball", ball, Vector3(1.6, 0.9, -1.9), Vector3.ZERO)
	quit()


func _studio(name: String, model: Node3D, cam_pos: Vector3, look: Vector3, pose := "") -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(640, 640)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1.0, 0.97, 0.92)
	env.environment.ambient_light_energy = 0.8
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	vp.add_child(model)
	if name == "dingo":   # it'd wander off (and hide) if left to think
		model.set_process(false)
		model.set_physics_process(false)
		model.position = Vector3.ZERO
	var cam := Camera3D.new()
	cam.fov = 40
	vp.add_child(cam)
	cam.position = cam_pos
	cam.look_at(look, Vector3.UP)
	cam.current = true
	for i in 10:
		model.visible = true
		if pose != "" and model.has_method("animate"):
			model.animate(0.05, pose, 0.0)
		await process_frame
	vp.get_texture().get_image().save_png(out + "/%s.png" % name)
	print("saved %s.png" % name)
	vp.queue_free()

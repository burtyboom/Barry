extends SceneTree
## Dev: godot --path . --resolution 1400x700 -s res://tests/_pet_shot.gd -- <out_prefix> [colour index]
## Every pet side by side on a sandy plane, one shot per pose (idle, walk, run, sit,
## lie, tray, hop, roll), plus a close-up of each sitting from the side.

const KINDS := ["cavoodle", "greyhound", "collie", "cat"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var ci := int(args[1]) if args.size() > 1 else 0
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.78, 0.98)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	env.environment.ambient_light_energy = 0.6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.93, 0.85, 0.66)
	ground.material_override = gm
	world.add_child(ground)
	var pets: Array = []
	for i in KINDS.size():
		var pet = load("res://scripts/world/pet.gd").create("%s:%d" % [KINDS[i], ci])
		pet.preview = true
		pet.position = Vector3(i * 1.25 - 1.9, 0, 0)
		pet.rotation.y = PI * 0.5   # nose to the left of the shot (side view)
		world.add_child(pet)
		pets.append(pet)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.fov = 40.0
	cam.position = Vector3(0, 0.75, 4.4)
	cam.look_at(Vector3(0, 0.3, 0))
	cam.current = true
	# Anim: IDLE, WALK, RUN, SIT, ROLL, HOP, TRAY (+ LIE if present)
	var poses := [["idle", 0, 0.0], ["walk", 1, 2.5], ["run", 2, 9.0], ["sit", 3, 0.0], ["roll", 4, 0.0], ["hop", 5, 0.0], ["tray", 6, 0.0]]
	if pets[0].get_script().get_script_constant_map()["Anim"].has("LIE"):
		poses.append(["lie", pets[0].get_script().get_script_constant_map()["Anim"]["LIE"], 0.0])
	for p in poses:
		for pet in pets:
			pet.force_anim = p[1]
			pet.force_speed = p[2]
		await create_timer(0.9 if p[0] != "roll" else 0.55).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out + p[0] + ".png")
		if p[0] == "walk" or p[0] == "run":
			await create_timer(0.13).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out + p[0] + "_b.png")
	# 3/4 close-up of the sit
	for pet in pets:
		pet.force_anim = 3
	cam.position = Vector3(-1.2, 0.9, 2.6)
	cam.look_at(Vector3(-0.6, 0.3, 0))
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "sit_close.png")
	for pet in pets:
		pet.force_anim = 0
	await create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "idle_close.png")
	# the cat end, sitting and loafing
	cam.position = Vector3(1.4, 0.7, 2.2)
	cam.look_at(Vector3(1.4, 0.2, 0))
	for pet in pets:
		pet.force_anim = 3
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "cat_sit.png")
	for pet in pets:
		pet.force_anim = 1
		pet.force_speed = 2.0
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "cat_walk.png")
	print("pet shots done")
	quit()

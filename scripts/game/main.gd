extends Node3D
## Boots the game: builds the island, shows the menu, spawns cars.

const PLAYER_COLORS := [
	Color(0.92, 0.92, 0.88), Color(0.80, 0.15, 0.12), Color(0.15, 0.35, 0.75),
	Color(0.25, 0.45, 0.20), Color(0.95, 0.65, 0.10), Color(0.35, 0.35, 0.38),
]

var island: IslandData
var world: WorldBuilder
var cars: Node3D
var camera: ChaseCamera
var hud: Hud
var local_car: SandVehicle
var _menu: Control
var menu: MainMenu
var _loading: Label
var _teleport_i := 0
var _pending_peers: Array[int] = []   ## players who joined before our island was built
var achievements: Achievements
var props: Props
var ropes: Ropes
var bots: Bots
var players: Node3D
var local_player: PlayerCharacter
var avatar_style := "blocky"                ## body: blocky / bean (menu "Customise", saved)
var avatar_hat := "cap"
var avatar_shirt := "plain"
var avatar_shoes := "sneakers"
var pet_kind := "none"                     ## pet (menu "Customise"): none / cat / cavoodle / greyhound / collie
var pet_col := 0                           ## which colour of that breed
var pets: Node3D                           ## everyone's pets (Pet_<peer id>)
var _peer_pets := {}                       ## other players' pet specs
var _show_pet: Pet                         ## menu preview pet
var shirt_color := Color(0.95, 0.45, 0.15)
var car_color := Color(0.95, 0.45, 0.15)   ## your ute's paint (menu picker, saved)
var admin_unlocked := false                 ## console "admin 1234" shows the admin menu
var voice: Voice
var console: DevConsole
var convoy: Convoy
var _show_person: Avatar                    ## you, standing by the menu ute (customise preview)
var _custom_cam := false
var _km := 0.0                              ## distance driven not yet counted towards stats
var _last_car_pos := Vector3.INF
const CAR_PAINTS := [
	Color(0.95, 0.45, 0.15), Color(0.92, 0.92, 0.88), Color(0.80, 0.15, 0.12), Color(0.15, 0.35, 0.75),
	Color(0.25, 0.45, 0.20), Color(0.95, 0.80, 0.15), Color(0.18, 0.18, 0.20), Color(0.95, 0.45, 0.70),
	Color(0.35, 0.75, 0.95), Color(0.50, 0.25, 0.70),
]
var _peer_colors := {}               ## other players' ute colours
var _was_bogged := false
var _peer_styles := {}               ## other players' character styles (may arrive before they spawn)
var _ngkala_south := false           ## drove up to Ngkala Rocks from the south
var _last_f := 0.0
var _barge_watch: Barge              ## our barge, while checking for the "40 PSI Club"
var player_name := "Harry"           ## what the bots call you (menu, saved in user://settings.cfg)
var player_names := {}               ## peer id -> name, for everyone in the game
var music: Music
var fines_total := 0                 ## dollars of speeding fines this session
var bonk_mode := 2                   ## admin: utes send people flying - 0 off, 1 players only, 2 players and bots
var lasso_cooldown := true           ## admin: after wriggling free you can't be lassoed again for 30 s
var pve := false                     ## PvE mode (menu tick box): no ute bonks or lassos with other players
var peer_pve := {}                   ## other players' PvE setting, by peer id
var bonks_given := 0                 ## people you've skittled this session
var longest_flight := 0.0            ## metres, your best trip through the air
var _flights := 0
var _building := false               ## an island is being built right now
var _showcase: Node3D                ## menu backdrop: a ute parked up on the beach with a camp
var _show_car: SandVehicle
var _show_t := 0.0

const SETTINGS := "user://settings.cfg"


func _ready() -> void:
	_migrate_user_data()
	InputSetup.setup()
	Music.setup_buses()
	_load_settings()
	get_window().theme = UiTheme.make()
	DisplayServer.window_set_title(GameVersion.TITLE)
	_make_environment()
	music = Music.new()
	music.name = "Music"
	music.enabled = _settings_music
	add_child(music)
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_loading = Label.new()
	_loading.add_theme_font_size_override("font_size", 32)
	_loading.set_anchors_preset(Control.PRESET_CENTER)
	_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading.position = Vector2(-220, -40)
	_loading.visible = false
	ui.add_child(_loading)

	cars = Node3D.new()
	cars.name = "Cars"
	add_child(cars)
	players = Node3D.new()
	players.name = "Players"
	add_child(players)
	pets = Node3D.new()
	pets.name = "Pets"
	add_child(pets)
	props = Props.new()
	props.name = "Props"
	add_child(props)
	ropes = Ropes.new()
	ropes.name = "Ropes"
	ropes.cars_root = cars
	add_child(ropes)
	bots = Bots.new()
	bots.name = "Bots"
	add_child(bots)
	voice = Voice.new()
	voice.name = "Voice"
	add_child(voice)
	convoy = Convoy.new()
	convoy.name = "Convoy"
	add_child(convoy)
	ropes.rope_snapped.connect(func(_id: String) -> void:
		if hud:
			hud.show_toast("SNAP! The strap broke - too much stretch"))

	camera = ChaseCamera.new()
	add_child(camera)
	camera.position = Vector3(0, 40, 300)
	camera.look_at(Vector3(0, 0, 0))
	camera.current = true

	_build_menu(ui)
	console = DevConsole.new()
	console.main = self
	ui.add_child(console)
	achievements = Achievements.new()
	add_child(achievements)
	achievements.unlocked_one.connect(func(id: String) -> void: Net.achievement(id))
	# PvE: tell everyone who arrives (and everyone already here, once we're in)
	Net.player_joined.connect(func(id: int) -> void:
		if _online() and not Net.dedicated:
			_announce_pve.rpc_id(id, pve))
	Net.session_ready.connect(func(_id: int) -> void:
		if _online() and not Net.dedicated:
			_announce_pve.rpc(pve))
	Net.island_received.connect(func(_w: String) -> void:
		if _online():
			_announce_pve.rpc(pve))
	Net.progress_received.connect(func(ids: Array, _stats: Dictionary) -> void:
		for id in ids:
			achievements.mark(String(id)))

	Net.session_ready.connect(_on_session_ready)
	Net.session_failed.connect(_on_session_failed)
	Net.player_joined.connect(_spawn_car)
	Net.player_joined.connect(_on_peer_joined)
	Net.player_left.connect(_remove_car)
	Net.island_received.connect(_on_island_received)

	# Command line shortcuts:  -- [--island=moreton] --solo | --host | --join=192.168.1.10
	#   dedicated server:      -- --dedicated [--island=fraser] [--backend=http://127.0.0.1:8080]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--island="):
			_select_island(a.substr(9))
	if "--dedicated" in OS.get_cmdline_user_args():
		_start_dedicated()
		return
	for a in OS.get_cmdline_user_args():
		if a == "--solo":
			_start("solo")
		elif a == "--host":
			_start("host")
		elif a.begins_with("--join="):
			Net.join(a.substr(7))
		elif a.begins_with("--shot="):
			_shot_args(a.substr(7))
	if OS.get_cmdline_user_args().is_empty() or "--menu" in OS.get_cmdline_user_args():
		_menu_backdrop()


## Builds the chosen island (if it isn't already the one loaded). backdrop = for the
## main menu: keep the menu up and the HUD hidden.
func _load_island(which: String, backdrop := false) -> void:
	while _building:
		await get_tree().process_frame
	if island != null and island.id == which:
		return
	_building = true
	_clear_world()
	if not backdrop:
		_menu.visible = false
	_loading.text = "Building %s...\n(sand, tracks, lakes, trees)" % IslandData.ISLANDS.get(which, which)
	_loading.visible = not backdrop
	# let the loading text render before the heavy lifting
	await get_tree().process_frame
	await get_tree().process_frame

	var t0 := Time.get_ticks_msec()
	island = IslandData.make(which)
	island.generate()
	var t1 := Time.get_ticks_msec()
	world = WorldBuilder.new()
	world.name = "World"
	add_child(world)
	world.build(island)
	var amb := Ambience.new()
	amb.name = "Ambience"
	world.add_child(amb)
	var t2 := Time.get_ticks_msec()
	print("%s generated in %d ms, world built in %d ms (%d trees)" % [island.display_name, t1 - t0, t2 - t1, island.trees.size()])

	hud = Hud.new()
	hud.cars_root = cars
	add_child(hud)
	hud.visible = not backdrop
	if not backdrop:
		_spawn_balls()
	_loading.visible = false
	_building = false
	_teleport_i = 0
	for id in _pending_peers:
		_spawn_car(id)
	_pending_peers.clear()
	bots.flush_pending()


## Beach soccer: a couple of balls on the sand near where everyone lands (the server owns them).
func _spawn_balls() -> void:
	bots.build_segments()
	var k := 0
	for f in [0.27, 0.30, 0.5]:
		var seg := bots.segment_near(f)
		if seg.x < 0.0:
			continue
		var p := bots.lane_point(clampf(f, seg.x + 0.01, seg.y - 0.01), true)
		p.x -= 12.0   # up the beach from the driving lane
		p.y = island.height_at(p.x, p.z) + 0.6
		var ball := SoccerBall.new()
		ball.name = "Ball_%d" % k
		ball.home = p
		ball.set_multiplayer_authority(1)
		world.add_child(ball)
		ball.global_position = p
		k += 1


func _clear_world() -> void:
	_clear_showcase()
	for c in cars.get_children():
		c.queue_free()
	for c in players.get_children():
		c.queue_free()
	for c in pets.get_children():
		c.queue_free()
	props.clear_all()
	ropes.clear_all()
	bots.clear_all()
	local_car = null
	local_player = null
	camera.target = null
	if world:
		world.queue_free()
		world = null
	if hud:
		hud.queue_free()
		hud = null
	island = null


# ------------------------------------------------------------- menu backdrop
## Behind the menu: the island, a ute parked on the beach with a little camp set up,
## and the camera slowly circling it.
func _menu_backdrop() -> void:
	await _load_island(_selected_island(), true)
	if not _menu.visible or local_car != null:
		return
	_build_showcase()


func _build_showcase() -> void:
	_clear_showcase()
	bots.build_segments()
	var seg := bots.segment_near(0.28)
	var f := clampf(0.28, seg.x + 0.01, seg.y - 0.01)
	var p := bots.lane_point(f, true)
	_showcase = Node3D.new()
	_showcase.name = "Showcase"
	world.add_child(_showcase)
	_show_car = SandVehicle.new()
	_show_car.name = "MenuUte"
	_show_car.body_color = car_color
	_show_car.scripted = true
	_show_car.driver_present = false
	_show_car.transform = Transform3D(Basis.looking_at(Vector3(0.25, 0, -1).normalized(), Vector3.UP), p + Vector3.UP * 1.2)
	cars.add_child(_show_car)
	_show_car.handbrake = true
	_show_car.brake = 1.0
	_show_car.set_all_psi(18.0)
	# camp up the beach from the ute
	var c := p + Vector3(-8.0, 0, 1.0)
	for it in [["tent", Vector3(-3.5, 0, -1.5), 0.6], ["fire", Vector3(0.5, 0, 0.5), 0.0],
			["chair", Vector3(-1.3, 0, 1.4), -2.4], ["chair", Vector3(2.0, 0, 1.6), 2.4],
			["esky", Vector3(-1.4, 0, 2.6), 0.3], ["umbrella", Vector3(3.2, 0, -2.0), 0.0]]:
		var q: Vector3 = c + (it[1] as Vector3)
		q.y = island.height_at(q.x, q.z)
		var prop := Props.build(String(it[0]), false)
		_showcase.add_child(prop)
		prop.global_transform = Transform3D(Basis(Vector3.UP, float(it[2])), q)
	_show_t = 0.0
	camera.target = null
	_show_person = null
	_show_pet = null
	_rebuild_preview()


func _clear_showcase() -> void:
	if _showcase and is_instance_valid(_showcase):
		_showcase.queue_free()
	_showcase = null
	if _show_car and is_instance_valid(_show_car):
		_show_car.get_parent().remove_child(_show_car)   # out now, so player colours count right
		_show_car.queue_free()
	_show_car = null
	_show_person = null
	_show_pet = null


## Slow cinematic orbit round the parked ute, drifting in and out.
func _update_showcase(delta: float) -> void:
	if _show_car == null or not is_instance_valid(_show_car) or not _menu.visible or _custom_cam:
		if _custom_cam:
			_show_t += delta
		return
	_show_t += delta
	var t := _show_t
	# circle the middle of the ute + camp, wide enough to stay outside the tent
	var tp := _show_car.global_position + Vector3(-4.5, 0, 0.5)
	var r := 15.0 + 2.5 * sin(t * 0.13)
	var a := t * 0.09 + 2.2
	var want := tp + Vector3(cos(a) * r, 2.4 + 1.6 * (0.5 + 0.5 * sin(t * 0.09)), sin(a) * r)
	want.y = maxf(want.y, island.height_at(want.x, want.z) + 1.0)
	camera.global_position = camera.global_position.lerp(want, minf(1.0, 3.0 * delta)) if t > 0.2 else want
	camera.look_at(tp + Vector3(0, 0.8, 0), Vector3.UP)


## The online server: no player of its own, no menu. Builds the island, opens the port and
## reports to the website backend (if --backend is given).
func _start_dedicated() -> void:
	var backend := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--backend="):
			backend = a.substr(10)
	_menu.visible = false
	Net.setup_dedicated(backend)
	Net.island_id = _selected_island()
	await _load_island(Net.island_id)
	Net.host()
	if backend != "":
		Net.send_catalog()
	print("[server] %s v%s - %s on UDP %d%s" % [GameVersion.TITLE, GameVersion.VERSION, island.display_name, Net.PORT,
		", backend " + backend if backend != "" else " (no backend: anyone can join)"])


## Menu: log in to the online server.
func join_online(host: String, port: int, uname: String, token: String) -> void:
	_take_name()
	_clear_showcase()
	Net.join_name = uname
	Net.join_token = token
	Net.join(host, port)


func join_lan(ip: String) -> void:
	_take_name()
	_clear_showcase()
	Net.join_name = player_name
	Net.join_token = ""
	Net.join(ip)


## Solo / host: build the island first, then open the session.
func _start(kind: String) -> void:
	_take_name()
	_clear_showcase()
	Net.island_id = _selected_island()
	await _load_island(Net.island_id)
	if kind == "host":
		Net.host()
	else:
		Net.start_solo()


@rpc("any_peer", "call_remote", "reliable")
func _request_tide() -> void:
	_rpc_set_tide.rpc_id(multiplayer.get_remote_sender_id(), Tide.override_phase)


## Joined a game: the host told us which island, build it then drive.
func _on_island_received(which: String) -> void:
	if Net.server_dedicated:
		player_name = Net.join_name   # online: you're called your account name
	_request_tide.rpc_id(1)
	_select_island(which)
	await _load_island(which)
	_on_session_ready(multiplayer.get_unique_id())


func _make_environment() -> void:
	# Bright, saturated cartoon day: warm sun, cool soft shadows, glow and AO.
	var env := Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.10, 0.42, 0.98)
	psm.sky_horizon_color = Color(0.60, 0.85, 1.0)
	psm.sky_curve = 0.12
	psm.ground_horizon_color = Color(0.60, 0.85, 1.0)
	psm.ground_bottom_color = Color(0.12, 0.50, 0.75)
	psm.sun_angle_max = 12.0
	psm.sun_curve = 0.08
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(1.0, 0.96, 0.90)   # warm fill so whites stay white
	env.ambient_light_energy = 0.75
	env.ambient_light_sky_contribution = 0.35
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.ssao_enabled = true
	env.ssao_radius = 1.6
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.ssao_light_affect = 0.15
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.25
	env.adjustment_contrast = 1.06
	env.fog_enabled = true
	env.fog_light_color = Color(0.62, 0.82, 1.0)
	env.fog_density = 0.0006
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.4
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_angular_distance = 1.2   # soft shadow edges
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.8
	sun.shadow_blur = 1.5
	sun.shadow_bias = 0.08
	sun.shadow_normal_bias = 2.5
	sun.directional_shadow_max_distance = 180.0
	add_child(sun)


# ------------------------------------------------------------- menu
func _build_menu(ui: CanvasLayer) -> void:
	menu = MainMenu.new()
	menu.main = self
	ui.add_child(menu)
	_menu = menu


## The menu opened / closed one of its side panels. Customise = the camera swings round
## to you standing next to your ute.
func menu_panel_changed(id: String) -> void:
	_custom_cam = id == "custom"


## Everything about your look as one string (see Avatar.create).
func avatar_spec() -> String:
	return Avatar.make_spec(avatar_style, avatar_hat, avatar_shirt, avatar_shoes, shirt_color)


## Menu: change one bit of your look (rebuilds the preview, saves).
func set_look(kind: String, value) -> void:
	match kind:
		"body":
			avatar_style = value
		"hat":
			avatar_hat = value
		"shirt":
			avatar_shirt = value
		"shoes":
			avatar_shoes = value
		"shirt_color":
			shirt_color = value
		"car_color":
			car_color = value
			if _show_car and is_instance_valid(_show_car):
				_show_car.repaint(value)
		"pet":
			pet_kind = value
			pet_col = 0
		"pet_col":
			pet_col = value
	_rebuild_preview()
	save_settings()


func randomise_look() -> void:
	avatar_style = Avatar.STYLES[randi() % Avatar.STYLES.size()]
	avatar_hat = Avatar.HATS.keys()[randi() % Avatar.HATS.size()]
	avatar_shirt = Avatar.SHIRTS.keys()[randi() % Avatar.SHIRTS.size()]
	avatar_shoes = Avatar.SHOES.keys()[randi() % Avatar.SHOES.size()]
	shirt_color = CAR_PAINTS[randi() % CAR_PAINTS.size()]
	_rebuild_preview()
	save_settings()


func _rebuild_preview() -> void:
	if _showcase == null or not is_instance_valid(_showcase) or _show_car == null:
		return
	var xf := Transform3D.IDENTITY
	if _show_person and is_instance_valid(_show_person):
		xf = _show_person.global_transform
		_show_person.queue_free()
	else:
		# standing by the driver's door, facing out to sea
		var p := _show_car.global_transform * Vector3(2.1, 0, 0.4)
		p.y = island.height_at(p.x, p.z)
		var look := _show_car.global_basis.x
		look.y = 0.0
		xf = Transform3D(Basis.looking_at(look.normalized(), Vector3.UP), p)
	_show_person = Avatar.create(avatar_spec(), shirt_color)
	_showcase.add_child(_show_person)
	_show_person.global_transform = xf
	# your pet sits at your feet
	if _show_pet and is_instance_valid(_show_pet):
		_show_pet.queue_free()
	_show_pet = Pet.create(pet_spec())
	if _show_pet:
		_show_pet.preview = true
		_showcase.add_child(_show_pet)
		var pp := xf * Vector3(-0.9, 0, -0.5)
		pp.y = island.height_at(pp.x, pp.z)
		_show_pet.global_transform = Transform3D(xf.basis.rotated(Vector3.UP, -0.6), pp)


func pet_spec() -> String:
	return Pet.spec_of(pet_kind, pet_col)


## Your pet / someone else's: Pet_<id>, following that player's character.
func _spawn_pet(id: int, person: PlayerCharacter, spec: String) -> void:
	var old := pets.get_node_or_null("Pet_%d" % id)
	if old:
		old.name = "Pet_old_%d" % id
		old.queue_free()
	var pet := Pet.create(spec)
	if pet == null:
		return
	pet.name = "Pet_%d" % id
	pet.set_multiplayer_authority(id)
	pet.player = person
	pets.add_child(pet)
	var p := person.global_position + Vector3(1.2, 0, 1.2)
	pet.global_position = p
	pet.state = "tray"   # starts in the back of the ute on the barge


## B: whistle your pet back.
func whistle() -> void:
	var pet := pets.get_node_or_null("Pet_%d" % multiplayer.get_unique_id()) as Pet
	if pet:
		pet.whistle()
	elif local_player:
		Sfx.play_at(local_player, "whistle", local_player.global_position + Vector3.UP * 1.6, -2.0)


## Customise: frame you from the front, a little left of centre (the panel's on the right).
func _update_custom_cam(delta: float) -> void:
	if _show_person and is_instance_valid(_show_person):
		_show_person.animate(delta, "idle" if fmod(_show_t, 7.0) > 1.6 else "wave", 0.0)
	if not _custom_cam or _show_person == null or not is_instance_valid(_show_person) or not _menu.visible:
		return
	var fwd := -_show_person.global_basis.z
	var side := _show_person.global_basis.x
	var target := _show_person.global_position + Vector3.UP * 1.0
	var want := target + fwd * 4.4 - side * 1.0 + Vector3.UP * 0.5
	camera.global_position = camera.global_position.lerp(want, minf(1.0, 4.0 * delta))
	camera.look_at(target - side * 1.5, Vector3.UP)


# ------------------------------------------------------------- settings
var _settings_music := true


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) == OK:
		player_name = String(cf.get_value("player", "name", player_name))
		car_color = cf.get_value("player", "car_color", car_color)
		pve = bool(cf.get_value("player", "pve", false))
		avatar_style = String(cf.get_value("look", "body", avatar_style))
		avatar_hat = String(cf.get_value("look", "hat", avatar_hat))
		avatar_shirt = String(cf.get_value("look", "shirt", avatar_shirt))
		avatar_shoes = String(cf.get_value("look", "shoes", avatar_shoes))
		shirt_color = cf.get_value("look", "shirt_color", shirt_color)
		pet_kind = String(cf.get_value("look", "pet", pet_kind))
		pet_col = int(cf.get_value("look", "pet_col", pet_col))
		_settings_music = bool(cf.get_value("audio", "music", true))
		var vol := float(cf.get_value("audio", "sfx_db", 0.0))
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), vol)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("player", "name", player_name)
	cf.set_value("player", "car_color", car_color)
	cf.set_value("player", "pve", pve)
	cf.set_value("look", "body", avatar_style)
	cf.set_value("look", "hat", avatar_hat)
	cf.set_value("look", "shirt", avatar_shirt)
	cf.set_value("look", "shoes", avatar_shoes)
	cf.set_value("look", "shirt_color", shirt_color)
	cf.set_value("look", "pet", pet_kind)
	cf.set_value("look", "pet_col", pet_col)
	cf.set_value("audio", "music", music.enabled if music else true)
	cf.set_value("audio", "sfx_db", AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")))
	cf.save(SETTINGS)


## The game used to be called "Island 4WD": bring old settings across to the new save folder once.
func _migrate_user_data() -> void:
	if FileAccess.file_exists(SETTINGS):
		return
	var old := OS.get_user_data_dir().get_base_dir().path_join("Island 4WD (Fraser & Moreton)")
	var d := DirAccess.open(old)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".cfg"):
			d.copy(old.path_join(f), OS.get_user_data_dir().path_join(f))


func _take_name() -> void:
	if menu and menu.name_edit:
		var n := menu.name_edit.text.strip_edges()
		player_name = n if n != "" else "Mate"
	save_settings()


## What to call a player (bots use this to say your name).
func name_of(peer: int) -> String:
	if peer == multiplayer.get_unique_id():
		return player_name
	return String(player_names.get(peer, "mate"))


func toggle_music() -> void:
	var on := music.toggle()
	save_settings()
	if hud:
		hud.show_toast("Music %s  (N)" % ("on" if on else "off"))


func _selected_island() -> String:
	for b in menu.island_buttons:
		if b.button_pressed:
			return b.get_meta("island")
	return "fraser"


func _select_island(which: String) -> void:
	for b in menu.island_buttons:
		b.button_pressed = b.get_meta("island") == which


func _on_session_ready(local_id: int) -> void:
	_menu.visible = false
	_clear_showcase()
	if Net.dedicated:
		return
	if hud:
		hud.visible = true
	_spawn_car(local_id)
	if Net.mode == "host":
		hud.show_toast("Hosting - waiting for players")


func _on_session_failed(reason: String) -> void:
	if Net.dedicated:
		push_error(reason)
		return
	if local_car != null or local_player != null:
		# dropped out of a game: back to the menu with a fresh backdrop
		_clear_world()
		_menu_backdrop()
	_menu.visible = true
	menu.status.text = reason
	if "log in again" in reason:
		menu.token_rejected()


# ------------------------------------------------------------- cars
func _spawn_car(id: int) -> void:
	if (id == 1 and Net.server_dedicated) or (Net.dedicated and id == multiplayer.get_unique_id()):
		return   # the online server has no ute of its own
	if world == null:
		if not _pending_peers.has(id):
			_pending_peers.append(id)
		return
	var nm := "Car_%d" % id
	if cars.has_node(nm):
		return
	var car := SandVehicle.new()
	car.name = nm
	var idx := cars.get_child_count()
	car.body_color = PLAYER_COLORS[idx % PLAYER_COLORS.size()]
	car.set_multiplayer_authority(id)
	var is_local := id == multiplayer.get_unique_id()
	if is_local:
		car.body_color = car_color
	elif _peer_colors.has(id):
		car.body_color = _peer_colors[id]
	car.local_control = is_local
	if not is_local:
		car.freeze = true
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	# everyone arrives by barge at the south tip
	var barge := Barge.new()
	barge.name = "Barge_%d" % id
	barge.setup(Barge.lane_for(id))
	world.add_child(barge)
	car.transform = barge.car_spot()
	cars.add_child(car)
	barge.carry(car)
	# the driver
	var person := PlayerCharacter.create(avatar_spec() if is_local else String(_peer_styles.get(id, "blocky")), car.body_color.darkened(0.1) if idx > 0 else Color(0.95, 0.45, 0.15))
	person.name = "Player_%d" % id
	if not is_local and player_names.has(id):
		person.tag_text = String(player_names[id])
	person.set_multiplayer_authority(id)
	person.local_control = is_local
	person.car = car
	players.add_child(person)
	_spawn_pet(id, person, pet_spec() if is_local else String(_peer_pets.get(id, "")))
	if is_local:
		local_player = person
		hud.player = person
		person.state_changed.connect(_on_player_state)
		car.bead_rolled.connect(func(i: int) -> void:
			achievements.unlock("bead")
			hud.show_toast("You rolled the bead on %s! Get out and pump it back up with the tyre inflator (3)" % car.wheels[i].name))
		car.bead_reseated.connect(func(i: int) -> void:
			achievements.unlock("reseat")
			hud.show_toast("%s bead popped back on - good as new" % car.wheels[i].name))
		car.deflator_done.connect(func(i: int) -> void:
			hud.show_toast("%s deflator done - %.0f psi" % [car.wheels[i].name, car.wheels[i].psi])
			achievements.unlock("deflators"))
		person.tag_text = player_name
		if _online():
			_announce_style.rpc(avatar_spec(), player_name, car_color, pet_spec())
	if is_local:
		local_car = car
		camera.target = car
		hud.car = car
		hud.show_toast("Barge crossing to %s - landing at %s" % [island.display_name, island.barge_name])
		barge.ramp_down.connect(func() -> void:
			hud.show_toast("Ramp's down - drive off! " + island.barge_hint)
			_barge_watch = barge)
		car.rolled_over.connect(func(st: int) -> void:
			if st > 0:
				Net.stat("rollovers"))
		car.bogged_changed.connect(func(b: bool) -> void:
			if b:
				achievements.unlock("bogged")
				Net.stat("times_bogged")
				hud.show_toast("Bogged! Air down (2/3, or 4 = 12 psi), reverse out, or R to recover"))
	else:
		hud.show_toast("%s joined" % name_of(id) if player_names.has(id) else "A player joined")


func _remove_car(id: int) -> void:
	var nm := "Car_%d" % id
	if cars.has_node(nm):
		cars.get_node(nm).queue_free()
		hud.show_toast("%s left" % name_of(id))
	if players.has_node("Player_%d" % id):
		players.get_node("Player_%d" % id).queue_free()
	if pets.has_node("Pet_%d" % id):
		pets.get_node("Pet_%d" % id).queue_free()
	for rid in ropes.ropes_on(nm):
		ropes._rpc_remove(rid)
	bots.remove_owned_by(id)


func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Host: catch a new player up on placed gear and ropes; everyone re-sends their character style.
func _on_peer_joined(id: int) -> void:
	if multiplayer.is_server():
		props.sync_to(id)
		ropes.sync_to(id)
	bots.sync_to(id)
	if local_player:
		_announce_style.rpc_id(id, avatar_spec(), player_name, car_color, pet_spec())


@rpc("any_peer", "call_remote", "reliable")
func _announce_style(style: String, who := "", col := Color(0, 0, 0, 0), pet := "") -> void:
	var id := multiplayer.get_remote_sender_id()
	_peer_styles[id] = style
	if String(_peer_pets.get(id, "")) != pet or (pet != "" and not pets.has_node("Pet_%d" % id)):
		_peer_pets[id] = pet
		var who_p := players.get_node_or_null("Player_%d" % id) as PlayerCharacter
		if who_p:
			_spawn_pet(id, who_p, pet)
	if col.a > 0.0:
		_peer_colors[id] = col
		var c := cars.get_node_or_null("Car_%d" % id) as SandVehicle
		if c:
			c.repaint(col)
	if who != "":
		player_names[id] = who
	var p := players.get_node_or_null("Player_%d" % id) as PlayerCharacter
	if p and who != "":
		p.tag_text = who
	var differs := p != null and (p.avatar.spec() != style if style.contains(";") else p.avatar.style != style)
	if differs:
		var shirt := p.avatar.shirt
		p.avatar.queue_free()
		p.avatar = Avatar.create(style, shirt)
		p.add_child(p.avatar)
		p.tools.select(p.tools.slot)


func _on_player_state(s: int) -> void:
	var on_foot := s == PlayerCharacter.State.ON_FOOT or s == PlayerCharacter.State.SITTING
	if local_player.car and local_player.car != local_car:
		# hopped into a different ute
		local_car = local_player.car
		hud.car = local_car
		if not local_car.bogged_changed.is_connected(_on_local_bogged):
			local_car.bogged_changed.connect(_on_local_bogged)
	camera.target = local_player if on_foot else local_car
	camera.set_foot_mode(on_foot, local_car)


func _on_local_bogged(b: bool) -> void:
	if b:
		achievements.unlock("bogged")
		Net.stat("times_bogged")
		hud.show_toast("Bogged! Air down (2/3, or 4 = 12 psi), reverse out, or R to recover")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_award(id: String) -> void:
	achievements.unlock(id)
	if id in ["snatch", "winch", "samaritan"]:
		Net.stat("people_recovered")


## Someone's landed after a ute sent them flying: tell everyone (the victim, the driver, anyone nearby).
# ------------------------------------------------------------- PvE + lasso
@rpc("any_peer", "call_remote", "reliable")
func _announce_pve(on: bool) -> void:
	peer_pve[multiplayer.get_remote_sender_id()] = on


## Menu tick box: PvE on / off (saved, and everyone in the game is told).
func set_pve(on: bool) -> void:
	pve = on
	save_settings()
	if _online():
		_announce_pve.rpc(on)


## Is this person playing PvE? (Only real players can be; bots never are.)
func is_pve(p: PlayerCharacter) -> bool:
	if p == null or not String(p.name).begins_with("Player_"):
		return false
	if p == local_player:
		return pve
	return bool(peer_pve.get(p.get_multiplayer_authority(), false))


## PvE rules for ute bonks and lassos: a PvE player can't be got by anyone, and can't get
## other players (bots are fair game). actor_node = the driver's / thrower's person node name.
func pve_blocks(victim: PlayerCharacter, actor_node: String) -> bool:
	var victim_human := String(victim.name).begins_with("Player_")
	if victim_human and is_pve(victim):
		return true
	var actor := players.get_node_or_null(actor_node) as PlayerCharacter
	return victim_human and actor != null and actor != victim and is_pve(actor)


## Someone's been lassoed: tell the thrower's screen and anyone close by.
func report_lasso(by: String, victim: String, victim_node: String) -> void:
	if _online():
		_rpc_lasso_news.rpc(by, victim, victim_node)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_lasso_news(by: String, victim: String, victim_node: String) -> void:
	if hud == null or local_player == null or not is_instance_valid(local_player) or String(local_player.name) == victim_node:
		return
	var v := players.get_node_or_null(victim_node) as Node3D
	if v and v.global_position.distance_to(local_player.global_position) < 150.0 and by != player_name:
		hud.show_toast("%s lassoed %s! Yeehaw!" % [by, victim])


func report_bonk(victim: String, by: String, by_peer: int, by_node: String, dist: float, down: bool, victim_node: String) -> void:
	if _online():
		_rpc_bonk.rpc(victim, by, by_peer, by_node, dist, down, victim_node)
	else:
		_rpc_bonk(victim, by, by_peer, by_node, dist, down, victim_node)


@rpc("any_peer", "call_local", "reliable")
func _rpc_bonk(victim: String, by: String, by_peer: int, by_node: String, dist: float, down: bool, victim_node: String) -> void:
	var me_node := String(local_player.name) if local_player and is_instance_valid(local_player) else ""
	if victim_node == me_node:
		_flights += 1
		Net.stat("flights")
		longest_flight = maxf(longest_flight, dist)
		achievements.unlock("bonked")
		if dist >= 20.0:
			achievements.unlock("air_time")
		if _flights >= 10:
			achievements.unlock("frequent_flyer")
		if down:
			achievements.unlock("seeing_stars")
			hud.show_toast("Out cold after a %.1f m flight! Hang tight - an ambulance is on its way." % dist)
		else:
			hud.show_toast("Wheee! %s sent you %.1f m! (health %d/%d)" % [by, dist, local_player.health, PlayerCharacter.MAX_HEALTH])
	elif by_node != "" and by_node == me_node:
		bonks_given += 1
		achievements.unlock("skittled")
		hud.show_toast("BONK! You skittled %s - %.1f m!%s" % [victim, dist, " Out cold - call an ambo!" if down else ""])
	elif local_player and is_instance_valid(local_player):
		var v := players.get_node_or_null(victim_node) as Node3D
		if v and v.global_position.distance_to(local_player.global_position) < 150.0:
			hud.show_toast("%s skittled %s - %.1f m!%s" % [by, victim, dist, " Out cold!" if down else ""])
	bots.bonk_lines(by_node, victim_node, by, victim, down)


## Admin: park a spare ute (no driver) behind yours - for practising snatch recoveries
## solo, or as a winch anchor. You can get into any empty ute you own.
func spawn_spare_ute() -> void:
	if local_car == null:
		return
	var n := 0
	while cars.has_node("Car_spare_%d_%d" % [multiplayer.get_unique_id(), n]):
		n += 1
	var nm := "Car_spare_%d_%d" % [multiplayer.get_unique_id(), n]
	var back := local_car.global_transform * Vector3(-3.5, 0, 9.0 + n * 6.0)
	var fwd := -local_car.global_basis.z
	fwd.y = 0.0
	var xf := Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), Vector3(back.x, island.height_at(back.x, back.z) + 1.4, back.z))
	if _online():
		_rpc_spawn_spare.rpc(nm, xf, multiplayer.get_unique_id())
	else:
		_rpc_spawn_spare(nm, xf, 1)
	hud.show_toast("Spare ute parked behind you - walk to its driver's door and press E")


@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn_spare(nm: String, xf: Transform3D, owner_id: int) -> void:
	if world == null or cars.has_node(nm):
		return
	var car := SandVehicle.new()
	car.name = nm
	car.body_color = [Color(0.95, 0.75, 0.15), Color(0.20, 0.65, 0.35), Color(0.55, 0.25, 0.75)][cars.get_child_count() % 3]
	car.set_multiplayer_authority(owner_id)
	var mine := owner_id == multiplayer.get_unique_id()
	car.local_control = mine
	car.driver_present = false
	if not mine:
		car.freeze = true
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.transform = xf
	cars.add_child(car)


## Puts you (or your ute, if you're in it) somewhere on the island.
func teleport_local(pos: Vector3) -> void:
	print("Teleport to ", pos)
	if local_player and local_player.is_on_foot():
		if local_player.state == PlayerCharacter.State.SITTING:
			local_player.stand_up()
		var p := pos
		p.y = island.height_at(p.x, p.z) + 0.3
		local_player.global_position = p
		local_player.velocity = Vector3.ZERO
	elif local_car:
		local_car.teleport(pos, Vector3.FORWARD)


func _process(delta: float) -> void:
	_update_showcase(delta)
	Tide.update()
	if world:
		world.set_sea_level(Tide.level)
	if local_car and is_instance_valid(local_car):
		_track_achievements()
		# kilometres of sand, for the website
		var cp := local_car.global_position
		if _last_car_pos != Vector3.INF and local_player and not local_player.is_on_foot():
			var d := cp.distance_to(_last_car_pos)
			if d < 30.0:
				_km += d / 1000.0
		_last_car_pos = cp
		if _km >= 1.0:
			Net.stat("km_driven")
			_km -= 1.0
	_update_custom_cam(delta)


func _track_achievements() -> void:
	var car := local_car
	# 40 PSI Club: off the barge and onto the sand still at highway pressure
	if _barge_watch:
		if not is_instance_valid(_barge_watch):
			_barge_watch = null
		else:
			var d := car.global_position.distance_to(_barge_watch.global_position)
			var min_psi := 99.0
			var on_sand := true
			for w in car.wheels:
				min_psi = minf(min_psi, w.psi)
				if not w.grounded or w.on_deck:
					on_sand = false
			if min_psi < 30.0 or d > 80.0:
				_barge_watch = null   # aired down (or teleported away) - no badge this time
			elif on_sand and d > 16.0:
				achievements.unlock("forty_psi")
				_barge_watch = null
	if car.water_depth > 0.6:
		achievements.unlock("salty")
	# Ngkala Rocks: arrive from the south and make it over the dune (no teleporting!)
	if island.id == "fraser":
		var f := island.z_to_f(car.global_position.z)
		if absf(f - _last_f) > 0.01:
			_ngkala_south = false
		if f > 0.885 and f < 0.898:
			_ngkala_south = true
		elif _ngkala_south and f > 0.915:
			achievements.unlock("ngkala")
			_ngkala_south = false
		_last_f = f
	# got un-bogged while a strap / winch was pulling on us?
	if _was_bogged and not car.is_bogged:
		for rid in ropes.ropes_on(String(car.name)):
			var r: Dictionary = ropes.ropes[rid]
			if float(r["peak"]) > 8000.0:
				var kind: String = "snatch" if r["kind"] == "strap" else "winch"
				achievements.unlock(kind)
				Net.stat("times_recovered")
				# the other car's driver did the pulling - they get it too
				for e in ["a", "b"]:
					var other := cars.get_node_or_null(String(r[e].get("car", ""))) as SandVehicle
					if other and other != car and not other.local_control and _online():
						_rpc_award.rpc_id(other.get_multiplayer_authority(), kind)
	_was_bogged = car.is_bogged
	for lp in island.lighthouses:
		if Vector2(car.global_position.x - lp.x, car.global_position.z - lp.z).length() < 25.0:
			achievements.unlock("lighthouse")


# ------------------------------------------------------------- chat + waving
## Chat box: say something to everyone in the game.
func send_chat(text: String) -> void:
	text = text.strip_edges().left(160)
	if text == "":
		return
	if _online():
		_rpc_chat.rpc(player_name, text)
	else:
		_rpc_chat(player_name, text)


@rpc("any_peer", "call_local", "reliable")
func _rpc_chat(who: String, text: String) -> void:
	var from := multiplayer.get_remote_sender_id()
	if Net.dedicated or (multiplayer.is_server() and Net.accounts.has(from)):
		# the server knows who you really are
		var real := Net.username_of(from)
		if real != "":
			who = real
	if hud and hud.chat:
		var mine := from == multiplayer.get_unique_id() or from == 0
		hud.chat.add_line("players", who.left(16), text.left(160), UiTheme.ORANGE if mine else Color(0.55, 0.85, 1.0), from)
	if not Net.dedicated and not (from == multiplayer.get_unique_id() or from == 0):
		Sfx.play_ui(self, "blip", -10.0, 1.3)
	if Net.dedicated:
		print("[chat] %s: %s" % [who, text])


## You waved (Y): counts for your stats, and bots close by wave back.
func on_wave() -> void:
	Net.stat("waves")
	if local_player == null:
		return
	bots.wave_back(local_player.global_position)


## Admin menu: pin the tide to a phase (0 high .. 0.5 low), or -1 to follow the real clock.
func set_tide(phase: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_rpc_set_tide(phase)
	else:
		_rpc_set_tide.rpc(phase)


@rpc("any_peer", "call_local", "reliable")
func _rpc_set_tide(phase: float) -> void:
	Tide.override_phase = phase
	Tide.update()
	if hud:
		hud.show_toast(Tide.describe())


func _toggle_fullscreen() -> void:
	if Engine.is_embedded_in_editor():
		# the editor's Game tab draws the game inside the editor window - it can't go fullscreen
		var msg := "Fullscreen doesn't work in the editor's Game tab - untick 'Embed Game on Next Play' and run again"
		print(msg)
		if hud:
			hud.show_toast(msg)
		return
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		_toggle_fullscreen()
		return
	if event.is_action_pressed("music") and not (get_viewport().gui_get_focus_owner() is LineEdit):
		toggle_music()
		return
	if event.is_action_pressed("whistle") and not Hud.typing() and local_player:
		whistle()
		return
	if local_car == null or island == null:
		return
	if event.is_action_pressed("teleport"):
		_teleport_i = (_teleport_i + 1) % island.places.size()
		var p: Dictionary = island.places[_teleport_i]
		teleport_local(p["pos"])
		hud.show_toast("Teleported: %s" % p["name"])
	elif event.is_action_pressed("sand_harder"):
		island.softness_mult = maxf(island.softness_mult - 0.1, 0.3)
		hud.show_toast("Sand softness x%.1f" % island.softness_mult)
	elif event.is_action_pressed("sand_softer"):
		island.softness_mult = minf(island.softness_mult + 0.1, 1.6)
		hud.show_toast("Sand softness x%.1f" % island.softness_mult)


# ------------------------------------------------------------- dev: screenshots
# --shot=out.png,Place Name,cam_mode,seconds[,yaw_deg[,throttle[,force_soft[,orbit_deg]]]]   (used to check visuals headlessly)
func _shot_args(spec: String) -> void:
	var parts := spec.split(",")
	var out := parts[0]
	var place := parts[1] if parts.size() > 1 else ""
	var cam := int(parts[2]) if parts.size() > 2 else 0
	var secs := float(parts[3]) if parts.size() > 3 else 3.0
	var yaw := float(parts[4]) if parts.size() > 4 else 0.0
	var thr := float(parts[5]) if parts.size() > 5 else 0.0
	if local_car == null:
		await _start("solo")
	await get_tree().process_frame
	if parts.size() > 6 and parts[6] != "":
		island.force_soft = float(parts[6])
	if parts.size() > 7:
		camera._orbit_yaw = deg_to_rad(float(parts[7]))
		camera._orbit_pitch = 0.15
		camera._orbiting = true   # hold the orbit so the shot can look at the car's side / front
	for p in island.places:
		if p["name"] == place:
			local_car.teleport(p["pos"], Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw)))
	camera.mode = cam
	if thr > 0.0:
		local_car.scripted = true
		local_car.throttle = thr
	await get_tree().create_timer(secs).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved ", out)
	get_tree().quit()

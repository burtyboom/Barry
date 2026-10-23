class_name PlayerCharacter
extends CharacterBody3D
## The person: drives the ute, or gets out (E) and walks around.
##
## States:
##   IN_CAR   - sitting in the driver's seat (hidden inside the cab), the ute takes input
##   EXITING  - door swings open, slide across, hop down to the sand, door shuts
##   ENTERING - the same in reverse
##   ON_FOOT  - walk / run (Shift) / jump (Space), camera-relative, slower in soft sand and water
##   SITTING  - in a camp chair (any move key stands up)
##
## The owner simulates; everyone else gets position / state at 20 Hz.
## Bots use the same character with `ai` on: a BotBrain sets ai_move instead of the keyboard.

signal state_changed(new_state: int)

enum State { IN_CAR, EXITING, ENTERING, ON_FOOT, SITTING }

const WALK := 3.4
const RUN := 6.6
const JUMP := 5.2
const GRAVITY := 15.0
const MAX_HEALTH := 5         ## ute bumps you can take before you're out cold (an ambo fixes you up)
const EXIT_TIME := 1.25
const ENTER_TIME := 1.25

## Car-local keyframes (car front is -Z, driver sits on the right / +X).
const SEAT := Vector3(0.42, 0.10, 0.02)
const DOORWAY := Vector3(1.02, 0.25, 0.02)
const OUTSIDE := Vector3(1.85, 0.0, 0.05)    # y gets snapped to the ground

var state := State.IN_CAR
var car: SandVehicle
var avatar: Avatar
var tools: PlayerTools
var local_control := true
var pose_override := ""      ## set by tools (fishing, digging...) for the avatar
var ai := false              ## driven by a BotBrain on this machine (local_control stays false)
var ai_move := Vector3.ZERO  ## bot: world direction to walk, length 0..1
var ai_run := false
var tag_text := ""           ## name tag override (bots, players' chosen names)
var _bubble: Label3D         ## speech bubble over the head
var _bubble_t := 0.0
var _icon: Node3D            ## "needs help" sign over a bogged bot's head
var island: IslandData

var _t := 0.0
var _enter_from := Vector3.ZERO
var _yaw := 0.0
var _seat_xf := Transform3D.IDENTITY   ## chair we're sitting in
var _seat_id := ""
var _shape: CollisionShape3D
var _stun := 0.0             ## seconds of tumbling after a ute bumps you
var health := MAX_HEALTH
var _bonk := 0               ## 0, 1 = sent flying by a ute, 2 = flat on your back seeing stars
var _bonk_t := 0.0
var _bonk_from := Vector3.ZERO
var _bonk_by := ""           ## who was driving: name, peer (0 = a bot) and their person node
var _bonk_by_peer := 0
var _bonk_by_node := ""
var _down_t := 0.0
var _spin := Basis.IDENTITY
var _spin_axis := Vector3.RIGHT
var _spin_rate := 10.0
var _vis_pose := ""
var _stars: Node3D
var _hp_bar: Sprite3D
var _startle_t := 0.0
var wave_t := 0.0            ## waving at someone (Y)
var tie_holder := ""         ## lassoed: whose rope we're on (their person node name) - synced to everyone
var tie_car := ""            ## ...or the ute we're hitched behind
var _tied_t := 0.0           ## seconds till we wriggle free (on our own machine)
var _lasso_cd := 0.0         ## just wriggled free: can't be caught again for a bit (secret)
var _tie_anchor_last := Vector3.INF
var _tie_tumble := 0.0
var _tie_rope: MeshInstance3D
var _exit_kind := 0          ## how we're getting out: 0 door, 1 climb out the top, 2 crawl out from under
static var _hp_tex := {}
# network
var _net_timer := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_has := false
var _net_pose := "idle"
var _net_speed := 0.0


static func create(style: String, shirt: Color) -> PlayerCharacter:
	var p := PlayerCharacter.new()
	p.avatar = Avatar.create(style, shirt)
	return p


func _ready() -> void:
	island = IslandData.instance
	top_level = true
	collision_layer = 8
	collision_mask = 1 | 2 | 4
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(55.0)
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	_shape.shape = cap
	_shape.position = Vector3(0, 0.85, 0)
	add_child(_shape)
	add_child(avatar)
	if not local_control:
		var tag := Label3D.new()
		tag.name = "NameTag"
		tag.text = tag_text if tag_text != "" else "Player %d" % (get_multiplayer_authority() % 1000)
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.font_size = 48
		tag.pixel_size = 0.008
		tag.outline_size = 14
		tag.modulate = Color(1, 1, 1)
		tag.outline_modulate = Color(0, 0, 0, 0.8)
		tag.position = Vector3(0, 2.35, 0)
		tag.no_depth_test = false
		add_child(tag)
	tools = PlayerTools.new()
	tools.name = "Tools"
	tools.player = self
	add_child(tools)
	_apply_state_visuals()


# ------------------------------------------------------------- public
## Show a speech bubble over this person's head for a few seconds.
func say(text: String, secs := 4.5) -> void:
	if _bubble == null:
		_bubble = Label3D.new()
		_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_bubble.font_size = 44
		_bubble.pixel_size = 0.0055
		_bubble.outline_size = 16
		_bubble.modulate = Color(1.0, 1.0, 1.0)
		_bubble.outline_modulate = Color(0.05, 0.1, 0.25, 0.95)
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bubble.width = 520.0
		_bubble.position = Vector3(0, 2.95, 0)
		_bubble.no_depth_test = true
		add_child(_bubble)
	_bubble.text = text
	_bubble.visible = true
	_bubble_t = secs


## The bright "HELP!" sign floating over a stuck bot (everyone sees it).
func set_help_icon(on: bool) -> void:
	if on and _icon == null:
		_icon = Node3D.new()
		_icon.position = Vector3(0, 3.0, 0)
		add_child(_icon)
		# a bright red ball with a white "!" that always faces you
		var ball := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.42
		sm.height = 0.84
		ball.mesh = sm
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.22, 0.1)
		ball.material_override = m
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_icon.add_child(ball)
		var bang := Label3D.new()
		bang.text = "!"
		bang.font_size = 110
		bang.pixel_size = 0.0065
		bang.outline_size = 0
		bang.modulate = Color.WHITE
		bang.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bang.no_depth_test = true
		bang.render_priority = 2
		_icon.add_child(bang)
		var words := Label3D.new()
		words.text = "HELP! I'm bogged"
		words.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		words.font_size = 40
		words.pixel_size = 0.007
		words.outline_size = 12
		words.modulate = Color(1.0, 0.9, 0.3)
		words.position = Vector3(0, -0.78, 0)
		words.no_depth_test = true
		_icon.add_child(words)
	elif not on and _icon != null:
		_icon.queue_free()
		_icon = null


func is_on_foot() -> bool:
	return state == State.ON_FOOT or state == State.SITTING


func get_out() -> void:
	if state != State.IN_CAR or car == null:
		return
	if car.speed_kmh > 6.0 or car.carrier != null:
		return   # not while moving, or still on the barge
	_exit_kind = rolled_kind(car)
	_set_state(State.EXITING)


## 0 = on its wheels, 1 = on its side (climb out the top), 2 = on its roof (crawl out underneath).
static func rolled_kind(c: SandVehicle) -> int:
	var up_y := c.global_basis.y.y
	if up_y < -0.4:
		return 2
	if up_y < 0.5:
		return 1
	return 0


func get_in() -> void:
	if state != State.ON_FOOT or car == null:
		return
	if rolled_kind(car) != 0:
		if local_control and not ai:
			_toast("Roll it back over first - R to recover")
		return
	_enter_from = global_position
	_set_state(State.ENTERING)


func sit(seat_xf: Transform3D, seat_id: String) -> void:
	_seat_xf = seat_xf
	_seat_id = seat_id
	_set_state(State.SITTING)


func stand_up() -> void:
	if state == State.SITTING:
		global_position = _seat_xf.origin + _seat_xf.basis.z * 0.9
		_set_state(State.ON_FOOT)


## Where you stand to get in (world space).
func door_spot() -> Vector3:
	if car == null:
		return global_position
	var p := car.global_transform * car.outside_point()
	p.y = island.height_at(p.x, p.z)
	return p


func car_yaw() -> float:
	var f := -car.global_basis.z
	return atan2(-f.x, -f.z)


# ------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	if _bubble and _bubble.visible:
		_bubble_t -= delta
		_bubble.visible = _bubble_t > 0.0
		_bubble.position.y = 4.85 if _icon else 2.95   # above the HELP sign when there is one
	if _icon:
		# bob and spin so it catches your eye from down the beach
		var t := Time.get_ticks_msec() * 0.001
		_icon.position.y = (3.75 if is_on_foot() else 4.1) + sin(t * 3.0) * 0.12
		_icon.scale = Vector3.ONE * (1.0 + 0.08 * sin(t * 6.0))   # pulse
	if tag_text != "" and has_node("NameTag"):
		var tag := get_node("NameTag") as Label3D
		if tag.text != tag_text:
			tag.text = tag_text
	_update_hp_bar()
	if _stars and _stars.visible:
		var t2 := Time.get_ticks_msec() * 0.001
		for i in _stars.get_child_count():
			var a := t2 * 3.2 + i * TAU / _stars.get_child_count()
			_stars.get_child(i).position = Vector3(cos(a) * 0.38, sin(t2 * 5.0 + i) * 0.06, sin(a) * 0.38)
	_draw_tie_rope()


# ------------------------------------------------------------- lasso (victim's side)
func is_tied() -> bool:
	return tie_holder != "" or tie_car != ""


## Thrower: "I've caught you" (secs > 0), or "hitch the rope to this ute" (secs < 0).
## Goes to whichever machine runs this person; that machine decides.
func request_lasso(holder: String, car_name: String, secs: float) -> void:
	if local_control or ai or not _online():
		lassoed(holder, car_name, secs)
	else:
		_rpc_lassoed.rpc_id(get_multiplayer_authority(), holder, car_name, secs)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_lassoed(holder: String, car_name: String, secs: float) -> void:
	if local_control or ai:
		lassoed(holder, car_name, secs)


func lassoed(holder: String, car_name: String, secs: float) -> void:
	var main := get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	if secs < 0.0:
		# hitched to a towbar
		if is_tied() and tie_holder == holder:
			_set_tie(holder, car_name)
		return
	if is_tied() or not is_on_foot() or _bonk != 0 or is_down():
		return
	if _lasso_cd > 0.0 and main.lasso_cooldown:
		return   # still shaking it off from last time (nobody's told about this)
	if main.pve_blocks(self, holder):
		return
	_tied_t = secs
	_tie_anchor_last = Vector3.INF
	_set_tie(holder, car_name)
	velocity.y = 3.0
	Sfx.play_at(self, "twang", global_position + Vector3.UP, -2.0, 1.3)
	var who := _person_name(main, holder)
	if local_control and main.hud:
		main.hud.show_toast("%s lassoed you! Yeehaw! Hang tight, you'll wriggle free..." % who)
	main.report_lasso(who, _person_name(main, String(name)), String(name))


func _person_name(main: Node, node_name: String) -> String:
	var p := main.players.get_node_or_null(node_name) as PlayerCharacter
	if p == null:
		return "Someone"
	if p.tag_text != "":
		return p.tag_text
	return String(main.name_of(p.get_multiplayer_authority()))


func _set_tie(holder: String, car_name: String) -> void:
	if _online():
		_rpc_tie.rpc(holder, car_name)
	else:
		_rpc_tie(holder, car_name)


@rpc("any_peer", "call_local", "reliable")
func _rpc_tie(holder: String, car_name: String) -> void:
	tie_holder = holder
	tie_car = car_name


## Where our end of the rope is pulled to: the thrower's hand, or a ute's towbar.
func _tie_anchor(main: Node) -> Vector3:
	if tie_car != "":
		var c := main.cars.get_node_or_null(tie_car) as SandVehicle
		if c:
			return c.global_transform * c.rear_point()
	var h := main.players.get_node_or_null(tie_holder) as PlayerCharacter
	if h and tie_car == "":
		if h.is_on_foot():
			return h.avatar.hand_r.global_position
		if h.car:
			return h.car.global_transform * h.car.rear_point()   # they jumped in their ute: still on the end of it
	return Vector3.INF


## Tied up on our own machine: no walking, just get dragged (and bounced) about on the rope.
func _tied_walk(delta: float) -> void:
	var main := get_tree().root.get_node_or_null("Main")
	_tied_t -= delta
	velocity.y -= GRAVITY * delta
	var anchor := _tie_anchor(main) if main else Vector3.INF
	var water := island.water_level_at(global_position.x, global_position.z) - global_position.y
	if water > 0.6:
		velocity.y = move_toward(velocity.y, (water - 0.6) * 3.0, 20.0 * delta)   # float, don't drown
	if anchor != Vector3.INF:
		var avel := Vector3.ZERO
		if _tie_anchor_last != Vector3.INF and delta > 0.0:
			avel = ((anchor - _tie_anchor_last) / delta).limit_length(40.0)
		_tie_anchor_last = anchor
		var rope := 6.0 if tie_car != "" else 3.2
		var to := anchor - (global_position + Vector3.UP * 0.3)
		var d := to.length()
		if d > rope:
			var n := to / d
			velocity += n * (d - rope) * 30.0 * delta
			var along := velocity.dot(n)
			var a_along := avel.dot(n)
			if along < a_along:
				velocity += n * (a_along - along) * minf(1.0, 10.0 * delta)
			if d > rope + 10.0:
				global_position = anchor - n * (rope + 2.0)   # got way behind (lag / teleport): catch up
		var spd := Vector2(avel.x, avel.z).length()
		if is_on_floor():
			velocity.x *= 1.0 - minf(1.0, 2.5 * delta)
			velocity.z *= 1.0 - minf(1.0, 2.5 * delta)
			# behind a moving ute: bounce and skitter about
			if tie_car != "" and spd > 3.0 and randf() < 0.3:
				velocity.y = randf_range(2.0, 4.5) * clampf(spd / 7.0, 0.5, 2.0)
				velocity += Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)) * spd * 0.2
				if randf() < 0.3:
					Sfx.play_at(self, "thunk", global_position, -10.0, randf_range(1.2, 1.6))
		var flat := Vector3(to.x, 0, to.z)
		if flat.length() > 0.3:
			_yaw = lerp_angle(_yaw, atan2(-flat.x, -flat.z), minf(1.0, 6.0 * delta))   # head first, towards the rope
	velocity = velocity.limit_length(35.0)
	move_and_slide()
	var ground := island.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 0.5:
		global_position.y = ground + 0.1
		velocity.y = maxf(velocity.y, 0.0)
	global_basis = Basis(Vector3.UP, _yaw)
	_bonk_visuals(delta, "tied")
	_net_pose = "tied"
	_net_speed = velocity.length()
	avatar.animate(delta, "tied", 0.0)
	if _tied_t <= 0.0:
		_free_from_lasso(main)


func _free_from_lasso(main: Node) -> void:
	_set_tie("", "")
	_lasso_cd = 30.0
	velocity.y = 4.0
	Sfx.play_at(self, "boing", global_position + Vector3.UP, -2.0)
	if local_control and main and main.hud:
		main.hud.show_toast("You wriggled free! Shake it off, mate.")


## The rope, drawn on everyone's screen from the anchor to us.
func _draw_tie_rope() -> void:
	if not is_tied():
		if _tie_rope:
			(_tie_rope.mesh as ImmediateMesh).clear_surfaces()
		return
	var main := get_tree().root.get_node_or_null("Main")
	var anchor := _tie_anchor(main) if main else Vector3.INF
	if _tie_rope == null:
		_tie_rope = MeshInstance3D.new()
		_tie_rope.mesh = ImmediateMesh.new()
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_tie_rope.material_override = m
		_tie_rope.top_level = true
		_tie_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_tie_rope)
	var im := _tie_rope.mesh as ImmediateMesh
	im.clear_surfaces()
	if anchor == Vector3.INF:
		return
	var a := anchor
	var b := global_position + Vector3.UP * 0.35
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else a + Vector3.UP
	var slack := maxf(0.0, (6.0 if tie_car != "" else 3.2) - a.distance_to(b)) * 0.3 + 0.1
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in 13:
		var k := i / 12.0
		var p := a.lerp(b, k)
		p.y -= slack * 4.0 * k * (1.0 - k)
		p.y = maxf(p.y, island.height_at(p.x, p.z) + 0.04)
		var side := (b - a).normalized().cross(eye - p).normalized() * 0.03
		im.surface_set_color(Color(0.74, 0.56, 0.31))
		im.surface_add_vertex(p - side)
		im.surface_set_color(Color(0.74, 0.56, 0.31))
		im.surface_add_vertex(p + side)
	im.surface_end()


## Y: wave. On foot = a big two-second wave; in the ute = arm out the window and a toot.
func wave() -> void:
	if is_on_foot():
		wave_t = 2.2
	elif car and is_instance_valid(car):
		car.wave(true)


## Out cold: 5 ute bumps and you can't get up till the ambulance gets here.
func is_down() -> bool:
	return health <= 0


## The little health bar over heads - switched off: health is a secret, the ambos know when to come.
func _update_hp_bar() -> void:
	var show := false
	if not show:
		if _hp_bar:
			_hp_bar.visible = false
		return
	if _hp_bar == null:
		_hp_bar = Sprite3D.new()
		_hp_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_hp_bar.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_hp_bar.pixel_size = 0.011
		_hp_bar.position = Vector3(0, 2.62, 0)
		add_child(_hp_bar)
	_hp_bar.visible = true
	_hp_bar.texture = hp_texture(health)
	_hp_bar.position.y = 1.2 if _bonk == 2 else 2.62


## Health bar picture: five pips, green / orange / red as they run out.
static func hp_texture(h: int) -> ImageTexture:
	if _hp_tex.has(h):
		return _hp_tex[h]
	var img := Image.create(MAX_HEALTH * 10 + 3, 11, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.05, 0.05, 0.08, 0.85))
	var col := Color(0.3, 0.9, 0.3) if h >= 4 else (Color(1.0, 0.7, 0.15) if h >= 2 else Color(0.95, 0.2, 0.15))
	for i in MAX_HEALTH:
		img.fill_rect(Rect2i(2 + i * 10, 2, 9, 7), col if i < h else Color(0.32, 0.32, 0.35, 0.9))
	var tex := ImageTexture.create_from_image(img)
	_hp_tex[h] = tex
	return tex


## Back to full health and up on your feet (the ambo's done CPR). Runs on whoever simulates us.
func revive() -> void:
	if local_control or ai or not _online():
		_rpc_revive()
	else:
		_rpc_revive.rpc_id(get_multiplayer_authority())


@rpc("any_peer", "call_local", "reliable")
func _rpc_revive() -> void:
	health = MAX_HEALTH
	_down_t = 0.0
	if _bonk == 2:
		_get_up()
	if local_control:
		var main := get_tree().root.get_node_or_null("Main")
		if main and main.hud:
			main.hud.show_toast("You're back! Full health - thank the ambos!")
			main.achievements.unlock("ambo")


func _physics_process(delta: float) -> void:
	if not local_control and not ai:
		_remote_update(delta)
		return
	match state:
		State.IN_CAR:
			_follow_seat()
			avatar.animate(delta, car.ride_pose() if car else "drive", 0.0)
		State.EXITING:
			_run_exit(delta)
		State.ENTERING:
			_run_enter(delta)
		State.ON_FOOT:
			_walk(delta)
		State.SITTING:
			global_transform = _seat_xf
			_yaw = atan2(-_seat_xf.basis.z.x, -_seat_xf.basis.z.z)
			avatar.animate(delta, "sit", 0.0)
			if not ai and (_move_input().length() > 0.3 or Input.is_action_just_pressed("handbrake")):
				stand_up()
	_net_send(delta)


func _set_state(s: State) -> void:
	state = s
	_t = 0.0
	if car:
		car.driver_present = s == State.IN_CAR
	_apply_state_visuals()
	state_changed.emit(s)


func _apply_state_visuals() -> void:
	avatar.visible = state != State.IN_CAR or (car != null and car.rider_visible())
	_shape.disabled = state != State.ON_FOOT
	if state != State.ON_FOOT:
		_bonk = 0
		avatar.transform = Transform3D.IDENTITY
		if _stars:
			_stars.visible = false


func _follow_seat() -> void:
	if car == null:
		return
	if state == State.IN_CAR:
		avatar.visible = car.rider_visible()   # (a friend's machine can change under them)
	if car.rider_visible():
		# open machines: sit on it where everyone can see you (leaning with the bike)
		global_transform = car.rider_xf(avatar.hip_height())
	else:
		global_transform = car.global_transform * Transform3D(Basis.IDENTITY, SEAT)
	_yaw = car_yaw()
	avatar.rotation = Vector3.ZERO


## Where you sit / climb through / stand beside this machine (car-local).
func _seat_pt() -> Vector3:
	if car.rider_visible():
		return car.seat_point() - Vector3(0, avatar.hip_height(), 0)
	return SEAT


func _doorway_pt() -> Vector3:
	if car.rider_visible():
		return car.doorway_point() - Vector3(0, avatar.hip_height() * 0.6, 0)
	return DOORWAY


## Car-local point -> world, with OUTSIDE snapped to the ground.
func _car_point(p: Vector3, ground := false) -> Vector3:
	var w := car.global_transform * p
	if ground:
		w.y = island.height_at(w.x, w.z)
	return w


func _place_at(pos: Vector3, yaw: float) -> void:
	global_position = pos
	global_basis = Basis(Vector3.UP, yaw)
	_yaw = yaw


func _toast(text: String) -> void:
	var m := get_parent().get_parent() if get_parent() else null
	if m and m.get("hud"):
		m.hud.show_toast(text)


## Getting out of a rolled ute. On its side: up through the door window that's facing the
## sky, stand on the side of the ute, jump down. On its roof: belly-crawl out the side
## window, then get up.
func _run_rolled_exit(delta: float) -> void:
	_t += delta
	var xf := car.global_transform
	var pose := "idle"
	var spd := 0.0
	if _exit_kind == 1:
		var sx := 1.0 if car.global_basis.x.y >= 0.0 else -1.0   # which side is facing up
		var win := xf * Vector3(0.95 * sx, 1.05, 0.05)
		var top := xf * Vector3(1.0 * sx, 0.3, 0.45)
		var land := xf * Vector3(0.0, 2.6, 0.45)                  # beside the roof
		land.y = island.height_at(land.x, land.z)
		var out_yaw := atan2(-(land - top).x, -(land - top).z)
		if _t < 0.4:
			global_position = _car_point(_seat_pt())
			pose = "sit"
		elif _t < 1.3:
			global_position = _car_point(_seat_pt()).lerp(win - Vector3.UP * 0.9, smoothstep(0.4, 1.3, _t))
			pose = "climb_out"
		elif _t < 1.9:
			var k := smoothstep(1.3, 1.9, _t)
			global_position = (win - Vector3.UP * 0.9).lerp(top, k)
			pose = "climb_out" if k < 0.6 else "idle"
		elif _t < 2.0:
			global_position = top
		elif _t < 2.5:
			var k := (_t - 2.0) / 0.5
			global_position = top.lerp(land, k) + Vector3.UP * sin(k * PI) * 0.6
			pose = "jump"
		else:
			global_position = land
			pose = "getup" if _t < 2.65 else "idle"
		global_basis = Basis(Vector3.UP, out_yaw)
		_yaw = out_yaw
		if _t >= 2.9:
			velocity = Vector3.ZERO
			_set_state(State.ON_FOOT)
	else:
		# out the driver's side window at ground level
		var win := xf * Vector3(0.95, 1.25, 0.05)
		var out := xf * Vector3(2.9, 1.0, 0.05)
		win.y = island.height_at(win.x, win.z)
		out.y = island.height_at(out.x, out.z)
		var d := out - win
		var out_yaw := atan2(-d.x, -d.z)
		# feet start back inside the cab, the body stretched out ahead toward the window
		var start := win - d.normalized() * 1.4
		start.y = win.y
		if _t < 0.5:
			global_position = start
			pose = "crawl"
		elif _t < 2.4:
			global_position = start.lerp(out, (_t - 0.5) / 1.9)
			pose = "crawl"
			spd = 1.0
		else:
			global_position = out
			pose = "getup" if _t < 2.8 else "idle"
		global_basis = Basis(Vector3.UP, out_yaw)
		_yaw = out_yaw
		if _t >= 3.1:
			velocity = Vector3.ZERO
			_set_state(State.ON_FOOT)
	_net_pose = pose
	avatar.animate(delta, pose, spd)


func _run_exit(delta: float) -> void:
	if _exit_kind != 0:
		_run_rolled_exit(delta)
		return
	_t += delta
	var side_yaw := car_yaw() - PI * 0.5   # facing out of the driver's door
	car.door_target = 1.0 if _t < 1.0 else 0.0
	if _t < 0.3:
		_place_at(_car_point(_seat_pt()), car_yaw())
		avatar.animate(delta, "sit" if not car.rider_visible() else car.ride_pose(), 0.0)
	elif _t < 0.65:
		var k := smoothstep(0.3, 0.65, _t)
		_place_at(_car_point(_seat_pt()).lerp(_car_point(_doorway_pt()), k), lerp_angle(car_yaw(), side_yaw, k))
		avatar.animate(delta, "sit" if not car.rider_visible() else car.ride_pose(), 0.0)
	elif _t < 1.0:
		var k := (_t - 0.65) / 0.35
		var p := _car_point(_doorway_pt()).lerp(_car_point(car.outside_point(), true), k)
		p.y += sin(k * PI) * 0.35
		_place_at(p, side_yaw)
		avatar.animate(delta, "jump", 0.0)
	else:
		_place_at(_car_point(car.outside_point(), true), side_yaw)
		avatar.animate(delta, "idle", 0.0)
		if _t >= EXIT_TIME:
			velocity = Vector3.ZERO
			_set_state(State.ON_FOOT)


func _run_enter(delta: float) -> void:
	_t += delta
	var side_yaw := car_yaw() + PI * 0.5   # facing into the cab
	car.door_target = 1.0 if _t < 1.0 else 0.0
	if _t < 0.25:
		var k := _t / 0.25
		_place_at(_enter_from.lerp(_car_point(car.outside_point(), true), k), lerp_angle(_yaw, side_yaw, k))
		avatar.animate(delta, "walk", 2.0)
	elif _t < 0.6:
		var k := (_t - 0.25) / 0.35
		var p := _car_point(car.outside_point(), true).lerp(_car_point(_doorway_pt()), k)
		p.y += sin(k * PI) * 0.35
		_place_at(p, side_yaw)
		avatar.animate(delta, "jump", 0.0)
	elif _t < 0.95:
		var k := smoothstep(0.6, 0.95, _t)
		_place_at(_car_point(_doorway_pt()).lerp(_car_point(_seat_pt()), k), lerp_angle(side_yaw, car_yaw(), k))
		avatar.animate(delta, "sit" if not car.rider_visible() else car.ride_pose(), 0.0)
	else:
		_follow_seat()
		avatar.animate(delta, car.ride_pose(), 0.0)
		if _t >= ENTER_TIME:
			_set_state(State.IN_CAR)


func _move_input() -> Vector2:
	if Hud.typing():
		return Vector2.ZERO
	return Vector2(
		Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left"),
		Input.get_action_strength("throttle") - Input.get_action_strength("brake"))


## A ute driving into you sends you flying (cartoon style: flips, stars, no harm done).
## Slow bumps just knock you about; each one costs a bit of health. Runs on the victim's machine.
func _check_bumped() -> void:
	var main := get_tree().root.get_node_or_null("Main")
	if main == null or _bonk == 1 or (_stun > 0.0 and not is_down()):
		return
	if main.bonk_mode == 0 or (ai and main.bonk_mode < 2):
		return
	for c in main.cars.get_children():
		var other := c as SandVehicle
		if other == null:
			continue
		var v := other.linear_velocity
		if v.length() < 2.0:
			continue
		var lp := other.global_transform.affine_inverse() * (global_position + Vector3.UP * 0.8)
		if absf(lp.x) < float(other.spec["x"]) + 0.4 and absf(lp.y) < 1.6 and absf(lp.z) < float(other.spec["z"]) + 1.35:
			var away := (global_position - other.global_position)
			away.y = 0.0
			away = away.normalized()
			var by := _driver_of(other, main)
			if main.pve_blocks(self, String(by[2])):
				continue   # PvE: no skittling (them or by them)
			_bonk_by = by[0]
			_bonk_by_peer = by[1]
			_bonk_by_node = by[2]
			if not is_down():
				health -= 1
			if v.length() < 5.0 and not is_down():
				# a nudge: knocked off your feet for a moment
				velocity = v * 1.1 + away * 2.5 + Vector3.UP * 3.5
				_stun = 0.8
				Sfx.play_at(self, "bonk", global_position + Vector3.UP, -4.0, 1.3)
				if main.hud and local_control:
					main.hud.show_toast("Oof! %s bumped you! (health %d/%d)" % [_bonk_by, health, MAX_HEALTH])
				return
			_launch(v, away)
			if main.hud and local_control:
				main.hud.show_toast("BONK! %s sent you flying!" % _bonk_by)
			return


## Who's driving that ute: [name, peer (0 for a bot or nobody), person node name]
func _driver_of(c: SandVehicle, main: Node) -> Array:
	for p in main.players.get_children():
		var pc := p as PlayerCharacter
		if pc and pc.car == c and pc.state == State.IN_CAR:
			var peer := 0 if c.has_meta("bot") else pc.get_multiplayer_authority()
			var nm := pc.tag_text if pc.tag_text != "" else String(main.name_of(peer))
			return [nm, peer, String(pc.name)]
	return ["A runaway ute", 0, ""]


func _launch(v: Vector3, away: Vector3) -> void:
	var spd := minf(v.length(), 28.0)
	velocity = v.normalized() * spd * 0.75 + away * 3.0 + Vector3.UP * (6.5 + spd * 0.38)
	_bonk = 1
	_bonk_t = 0.0
	_stun = 99.0
	_bonk_from = global_position
	_start_spin()
	Sfx.play_at(self, "bonk", global_position + Vector3.UP, 0.0)
	Sfx.play_at(self, "slide_up", global_position + Vector3.UP, -3.0, randf_range(0.9, 1.1))


func _start_spin() -> void:
	_spin = Basis.IDENTITY
	_spin_axis = Vector3(1.0, randf_range(-0.4, 0.4), randf_range(-0.7, 0.7)).normalized() * (1.0 if randf() < 0.5 else -1.0)
	_spin_rate = randf_range(9.0, 15.0)


## Hit the ground (or the water): flat on your back, then report how far you flew.
func _land(wet: bool) -> void:
	_bonk = 2
	_bonk_t = 0.0
	var d := Vector2(global_position.x - _bonk_from.x, global_position.z - _bonk_from.z).length()
	if wet:
		Sfx.play_at(self, "splash", global_position, 0.0)
	else:
		Sfx.play_at(self, "thunk", global_position + Vector3.UP * 0.3, 0.0, 0.6)
		Sfx.play_at(self, "slide_down", global_position + Vector3.UP, -6.0)
	var main := get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	var me_name := tag_text if tag_text != "" else String(main.name_of(get_multiplayer_authority()))
	main.report_bonk(me_name, _bonk_by, _bonk_by_peer, _bonk_by_node, d, is_down(), String(name))
	if is_down():
		_down_t = 0.0
		main.bots.call_ambulance(self)


func _get_up() -> void:
	_bonk = 0
	_stun = 0.0
	velocity.y = 4.0
	Sfx.play_at(self, "boing", global_position + Vector3.UP, -2.0)


## Somebody honks right next to you: jump out of your skin.
func _check_startled(delta: float) -> void:
	_startle_t -= delta
	if _startle_t > 0.0 or _bonk != 0 or not is_on_floor():
		return
	var main := get_tree().root.get_node_or_null("Main")
	if main == null:
		return
	for c in main.cars.get_children():
		var other := c as SandVehicle
		if other and other != car and other.horn_on and other.global_position.distance_to(global_position) < 9.0:
			_startle_t = 3.0
			velocity.y = JUMP * 0.9
			if ai and randf() < 0.6 and main.bots:
				main.bots.say(self, tag_text, String(["Strewth!", "Jeez, you scared me!", "Righto, righto, I'm moving!"].pick_random()))
			return


## Flips through the air / lying spread-eagled with stars - drives the avatar on every machine.
func _bonk_visuals(delta: float, pose: String) -> void:
	var remote := not local_control and not ai
	if pose == "flail":
		if _vis_pose != "flail":
			if remote:
				_start_spin()
				Sfx.play_at(self, "bonk", global_position + Vector3.UP, 0.0)
				Sfx.play_at(self, "slide_up", global_position + Vector3.UP, -3.0)
		_spin = _spin.rotated(_spin_axis, _spin_rate * delta).orthonormalized()
		var piv := Vector3(0, 0.9, 0)
		avatar.transform = Transform3D(_spin, piv - _spin * piv)
	elif pose == "flat":
		if _vis_pose != "flat" and remote:
			Sfx.play_at(self, "thunk", global_position + Vector3.UP * 0.3, 0.0, 0.6)
		var lie := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.22, 0))
		avatar.transform = avatar.transform.interpolate_with(lie, minf(1.0, delta * 12.0))
		if _stars == null:
			_stars = _make_stars()
		_stars.visible = true
	elif pose == "tied":
		var spd := velocity.length() if (local_control or ai) else _net_speed
		_tie_tumble += delta * spd * 1.3
		var roll := sin(_tie_tumble) * clampf(spd / 7.0, 0.0, 1.0) * 1.1
		var lie := Transform3D(Basis(Vector3.BACK, roll) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 0.25, 0))
		avatar.transform = avatar.transform.interpolate_with(lie, minf(1.0, delta * 14.0))
	elif _vis_pose == "flail" or _vis_pose == "flat" or _vis_pose == "tied":
		avatar.transform = Transform3D.IDENTITY
		if _stars:
			_stars.visible = false
		if remote and _vis_pose == "flat":
			Sfx.play_at(self, "boing", global_position + Vector3.UP, -2.0)
	_vis_pose = pose


## A ring of little yellow stars circling the head (where it ends up when lying down).
func _make_stars() -> Node3D:
	var ring := Node3D.new()
	ring.position = Vector3(0, 0.75, 1.5)
	add_child(ring)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var a0 := TAU * i / 10.0
		var a1 := TAU * (i + 1) / 10.0
		var r0 := 0.13 if i % 2 == 0 else 0.055
		var r1 := 0.055 if i % 2 == 0 else 0.13
		st.add_vertex(Vector3.ZERO)
		st.add_vertex(Vector3(sin(a0) * r0, cos(a0) * r0, 0))
		st.add_vertex(Vector3(sin(a1) * r1, cos(a1) * r1, 0))
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.9, 0.2)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 4:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.add_child(mi)
	return ring


func _walk(delta: float) -> void:
	_lasso_cd -= delta
	if is_tied():
		_tied_walk(delta)
		return
	_check_bumped()
	_check_startled(delta)
	var dir := Vector3.ZERO
	if ai:
		dir = Vector3(ai_move.x, 0.0, ai_move.z) if _stun <= 0.0 else Vector3.ZERO
	else:
		var cam := get_viewport().get_camera_3d()
		var inp := _move_input() if _stun <= 0.0 else Vector2.ZERO
		var fwd := Vector3.FORWARD
		var right := Vector3.RIGHT
		if cam:
			fwd = -cam.global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			right = Vector3(-fwd.z, 0, fwd.x)
		dir = right * inp.x + fwd * inp.y
	if dir.length() > 1.0:
		dir = dir.normalized()
	var running := ai_run if ai else Input.is_key_pressed(KEY_SHIFT)
	var speed := RUN if running else WALK
	# soft sand and water slow you down
	var soft := island.softness_at(global_position.x, global_position.z)
	speed *= 1.0 - 0.3 * soft
	var water := island.water_level_at(global_position.x, global_position.z) - global_position.y
	if water > 0.4:
		speed *= 0.55
	if tools.slows_walking():
		speed = minf(speed, WALK * 0.7)
	var target := dir * speed
	var accel := (14.0 if is_on_floor() else 4.0) if _stun <= 0.0 else 0.0
	velocity.x = move_toward(velocity.x, target.x, accel * speed * delta)
	velocity.z = move_toward(velocity.z, target.z, accel * speed * delta)
	if _stun > 0.0:
		_stun -= delta
		var drag := 9.0 if _bonk == 2 else 2.0   # sliding to a stop on your back
		velocity.x = move_toward(velocity.x, 0.0, drag * delta)
		velocity.z = move_toward(velocity.z, 0.0, drag * delta)
		target = Vector3(velocity.x, 0, velocity.z)
	if water > 1.1:
		# treading water: float with your head out
		velocity.y = move_toward(velocity.y, (water - 1.1) * 3.0, 20.0 * delta)
	else:
		velocity.y -= GRAVITY * delta
		if not ai and is_on_floor() and Input.is_action_just_pressed("handbrake") and not Hud.typing():
			velocity.y = JUMP
	move_and_slide()
	if _bonk == 1:
		_bonk_t += delta
		if (_bonk_t > 0.25 and (is_on_floor() or water > 0.7)) or _bonk_t > 6.0:
			_land(water > 0.7)
	elif _bonk == 2:
		_bonk_t += delta
		_stun = 99.0
		if is_down():
			_down_t += delta
			if _down_t > 90.0:
				revive()   # nobody came: you come good on your own
		elif _bonk_t > 1.8:
			_get_up()
	# never fall through the world
	var ground := island.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 1.0:
		global_position.y = ground + 0.2
		velocity.y = 0.0
	# face where we're going
	var hv := Vector2(velocity.x, velocity.z)
	if hv.length() > 0.4:
		var want := atan2(-velocity.x, -velocity.z)
		_yaw = lerp_angle(_yaw, want, minf(1.0, 12.0 * delta))
	avatar.rotation.y = 0.0
	global_basis = Basis(Vector3.UP, _yaw)
	var pose := "idle"
	if water > 1.0:
		pose = "swim"
	elif not is_on_floor():
		pose = "jump"
	elif hv.length() > 4.6:
		pose = "run"
	elif hv.length() > 0.3:
		pose = "walk"
	if pose_override == "hold" and (pose == "walk" or pose == "run"):
		pose += "_hold"   # keep walking / running with the rod (or whatever) held up
	elif pose_override != "":
		pose = pose_override
	if wave_t > 0.0:
		wave_t -= delta
		if pose == "idle" or pose == "walk":
			pose = "wave"
	if _bonk == 1:
		pose = "flail"
	elif _bonk == 2:
		pose = "flat"
	elif _stun > 0.0:
		pose = "jump"
		avatar.rotation.x = sin(_stun * 9.0) * 0.6   # tumble
	else:
		avatar.rotation.x = 0.0
	_bonk_visuals(delta, pose)
	_net_pose = pose
	_net_speed = hv.length()
	avatar.animate(delta, pose, hv.length())


# ------------------------------------------------------------- network
func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func rpc_cast(origin: Vector3, vel: Vector3) -> void:
	if _online():
		_rpc_cast.rpc(origin, vel)


func rpc_reel() -> void:
	if _online():
		_rpc_reel.rpc()


@rpc("authority", "call_remote", "reliable")
func _rpc_cast(origin: Vector3, vel: Vector3) -> void:
	tools.start_cast(origin, vel)


@rpc("authority", "call_remote", "reliable")
func _rpc_reel() -> void:
	tools._start_reel()


func _net_send(delta: float) -> void:
	var mp := multiplayer.multiplayer_peer
	if mp == null or mp is OfflineMultiplayerPeer or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_net_timer += delta
	if _net_timer < 0.05:
		return
	_net_timer = 0.0
	var pose := _net_pose if state == State.ON_FOOT or (state == State.EXITING and _exit_kind != 0) else ""
	_net_state.rpc(global_position, _yaw, int(state), _t, pose, _net_speed, tools.slot, _seat_xf, health)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(pos: Vector3, yaw: float, st: int, t: float, pose: String, spd: float, slot: int, seat: Transform3D, hp: int) -> void:
	health = hp
	if st != state:
		state = st as State
		_apply_state_visuals()
		if car:
			car.driver_present = state == State.IN_CAR
	_t = t
	_net_pos = pos
	_net_yaw = yaw
	_net_pose = pose
	_net_speed = spd
	_seat_xf = seat
	if tools.slot != slot:
		tools.select(slot)
	if not _net_has or pos.distance_to(global_position) > 6.0:
		global_position = pos
		_net_has = true


func _remote_update(delta: float) -> void:
	# remote players: follow the stream, and play the door / pose locally
	if car:
		car.door_target = 1.0 if (state == State.EXITING or state == State.ENTERING) and _t < 1.0 else 0.0
	match state:
		State.IN_CAR:
			_follow_seat()
			avatar.animate(delta, car.ride_pose() if car else "drive", 0.0)
			return
		State.SITTING:
			global_transform = _seat_xf
			avatar.animate(delta, "sit", 0.0)
			return
	var k := minf(1.0, 14.0 * delta)
	global_position = global_position.lerp(_net_pos, k)
	_yaw = lerp_angle(_yaw, _net_yaw, k)
	global_basis = Basis(Vector3.UP, _yaw)
	var pose := _net_pose
	if (state == State.EXITING and pose == "") or state == State.ENTERING:
		pose = "jump" if _t > 0.3 and _t < 1.0 else "sit"
	_bonk_visuals(delta, pose)
	avatar.animate(delta, pose if pose != "" else "idle", _net_speed)

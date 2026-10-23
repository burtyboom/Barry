class_name Lasso
extends Node
## The lasso, thrower's side. Hold click to whirl it over your head, let go to throw the
## loop at whoever's nearest the mouse. It's a bit hit and miss on purpose: the loop has
## to land near where they are when it gets there, and then there's luck (roughly a third
## of decent throws at 6-12 m catch, more up close, fewer when they're running).
## A catch ties them up (see PlayerCharacter.lassoed); you drag them about on the rope,
## or walk to a ute's tow hitch and press E to hitch them on for a ride.

const RANGE := 16.0             ## longest throw (flat metres)
const PICK := 3.5               ## how close to the mouse someone has to be to be the target
const LOOP_SPEED := 15.0        ## m/s the loop flies at

var tools: PlayerTools
var player: PlayerCharacter
var state := "idle"             ## idle / whirl / flying
var charge := 0.0               ## whirl timing 0..1..0 (best throw at the top)
var victim: PlayerCharacter     ## who we've got on the end of the rope (by hand)
var _main: Node
var _t := 0.0
var _target: PlayerCharacter
var _loop: MeshInstance3D
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _fly_t := 0.0
var _fly_dur := 0.5
var _power := 0.0
var _rope: MeshInstance3D
var _hold_t := 0.0
var _mat: StandardMaterial3D


func _ready() -> void:
	_main = get_tree().root.get_node_or_null("Main")
	_loop = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	tm.rings = 20
	tm.ring_segments = 5
	_loop.mesh = tm
	_loop.material_override = Toon.mat(Color(0.80, 0.62, 0.35))
	_loop.top_level = true
	_loop.visible = false
	add_child(_loop)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rope = MeshInstance3D.new()
	_rope.mesh = ImmediateMesh.new()
	_rope.material_override = _mat
	_rope.top_level = true
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rope)


## Everyone you could throw at: people on foot, not you, not already tied up.
func _candidates() -> Array:
	var out := []
	if _main == null:
		return out
	for p in _main.players.get_children():
		var pc := p as PlayerCharacter
		if pc == null or pc == player or not pc.is_on_foot() or pc.is_tied():
			continue
		if Vector2(pc.global_position.x - player.global_position.x, pc.global_position.z - player.global_position.z).length() > RANGE:
			continue
		out.append(pc)
	return out


## Who the loop would go to: closest to the mouse (or straight ahead with a gamepad).
func _pick_target() -> PlayerCharacter:
	var aim: Vector3 = tools._mouse_ground() if tools._mouse_aim else Vector3.INF
	var best: PlayerCharacter = null
	var bd := INF
	for pc: PlayerCharacter in _candidates():
		var d: float
		if aim != Vector3.INF:
			d = Vector2(pc.global_position.x - aim.x, pc.global_position.z - aim.z).length()
			if d > PICK:
				continue
		else:
			var to := pc.global_position - player.global_position
			to.y = 0.0
			var ahead := (-player.global_basis.z).dot(to.normalized())
			if ahead < 0.6:
				continue
			d = to.length()
		if d < bd:
			bd = d
			best = pc
	return best


## Per frame while the lasso is in your hand (called from PlayerTools._update_item).
func update(delta: float) -> void:
	_t += delta
	var in_hand := victim != null and is_instance_valid(victim) and victim.is_tied() and victim.tie_holder == String(player.name) and victim.tie_car == ""
	if state == "idle":
		_target = _pick_target()
		player.pose_override = "hold"
		if in_hand:
			tools.hint = "You've got %s! Drag them about, or walk to a ute's tow hitch" % _name_of(victim)
			var hitch := _nearest_hitch()
			if not hitch.is_empty():
				tools.prompt = "[E] Hitch %s to %s's towbar" % [_name_of(victim), tools._car_name(hitch["car"])]
				tools._action = func() -> void: _hitch(hitch["car"])
		elif _target:
			tools.hint = "Hold left click to whirl, let go to throw at %s" % _name_of(_target)
		else:
			tools.hint = "Point the mouse at someone on foot (within %d m) and hold left click" % int(RANGE)
	elif state == "whirl":
		charge = pingpong(_t / 0.9, 1.0)
		tools.charge = charge
		player.pose_override = "wind"
		_target = _pick_target() if _target == null or not is_instance_valid(_target) else _target
		if _target:
			var to := _target.global_position - player.global_position
			player._yaw = lerp_angle(player._yaw, atan2(-to.x, -to.z), 0.2)
			tools.hint = "Let go when the bar's full!"
		else:
			tools.hint = "Nobody to throw at - point at someone"
	elif state == "flying":
		player.pose_override = "throw" if _fly_t < 0.35 else "hold"
	# the aim ring sits under whoever you'd catch
	if state != "flying" and _target and is_instance_valid(_target) and not in_hand:
		tools._aim_mat.albedo_color = Color(1.0, 0.75, 0.2)
		tools._aim_ring.visible = true
		tools._aim_ring.global_position = _target.global_position + Vector3.UP * 0.06
		tools._aim_ring.scale = Vector3.ONE * (1.0 + 0.1 * sin(_t * 9.0))


func use(pressed: bool) -> void:
	if pressed and state == "idle":
		if victim != null and is_instance_valid(victim) and victim.is_tied() and victim.tie_holder == String(player.name):
			return   # already got someone
		state = "whirl"
		_t = 0.0
		charge = 0.0
		_target = _pick_target()
		Sfx.play_at(self, "whoosh", player.global_position + Vector3.UP * 2.0, -6.0, 0.7)
	elif not pressed and state == "whirl":
		tools.charge = -1.0
		if _target == null or not is_instance_valid(_target):
			state = "idle"
			return
		throw_at(_target, charge)


## Let the loop go at someone. power 0..1 = how well-timed the whirl was.
func throw_at(target: PlayerCharacter, power: float) -> void:
	_target = target
	_power = power
	state = "flying"
	_fly_t = 0.0
	_from = player.avatar.hand_r.global_position + Vector3.UP * 0.6
	# lead them a little: aim where they're heading
	var lead := target.velocity * 0.25 if target.local_control or target.ai else Vector3.ZERO
	_to = target.global_position + lead + Vector3.UP * 0.9
	_fly_dur = clampf(_from.distance_to(_to) / LOOP_SPEED, 0.15, 1.2)
	_loop.visible = true
	Sfx.play_at(self, "whoosh", _from, -3.0, randf_range(0.9, 1.1))


func _process(delta: float) -> void:
	var im := _rope.mesh as ImmediateMesh
	im.clear_surfaces()
	if state == "whirl" and player:
		# the loop spinning over your head
		var c := player.global_position + Vector3.UP * 2.35
		_loop.visible = true
		_loop.global_position = c + Vector3(cos(_t * 14.0), 0, sin(_t * 14.0)) * 0.25
		_loop.global_rotation = Vector3(0, _t * 14.0, 0)
		_line(im, player.avatar.hand_r.global_position, _loop.global_position)
	elif state == "flying":
		_fly_t += delta
		var k := clampf(_fly_t / _fly_dur, 0.0, 1.0)
		var p := _from.lerp(_to, k) + Vector3.UP * sin(k * PI) * 1.4
		_loop.global_position = p
		_loop.global_rotation = Vector3(0.3, _fly_t * 9.0, 0)
		_line(im, player.avatar.hand_r.global_position, p)
		if k >= 1.0:
			_land()
	elif state == "idle" and not (victim != null and is_instance_valid(victim) and victim.is_tied()):
		_loop.visible = false
	if victim != null and is_instance_valid(victim) and state == "idle":
		_hold_t += delta
		_loop.visible = false
		# the victim's own rope is drawn on their node; we just let go if they wriggle free
		if not victim.is_tied() and _hold_t > 1.5:
			victim = null


func _line(im: ImmediateMesh, a: Vector3, b: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else a + Vector3.UP
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in 9:
		var k := i / 8.0
		var p := a.lerp(b, k)
		p.y -= 0.3 * 4.0 * k * (1.0 - k)
		var side := (b - a).normalized().cross(eye - p).normalized() * 0.025
		im.surface_set_color(Color(0.72, 0.55, 0.30))
		im.surface_add_vertex(p - side)
		im.surface_set_color(Color(0.72, 0.55, 0.30))
		im.surface_add_vertex(p + side)
	im.surface_end()


## The loop's come down: did it go over them?
func _land() -> void:
	state = "idle"
	_loop.visible = false
	var t := _target
	if t == null or not is_instance_valid(t) or not t.is_on_foot() or t.is_tied():
		return
	var miss := Vector2(t.global_position.x - _to.x, t.global_position.z - _to.z).length()
	var dist := Vector2(t.global_position.x - player.global_position.x, t.global_position.z - player.global_position.z).length()
	if _main and _main.has_method("pve_blocks") and _main.pve_blocks(t, String(player.name)):
		tools._toast("%s is in PvE mode - the loop slips right off" % _name_of(t))
		return
	var chance := hit_chance(dist, _power, miss, Vector2(t.velocity.x, t.velocity.z).length() if (t.local_control or t.ai) else 0.0)
	if randf() > chance:
		Sfx.play_at(self, "thunk", t.global_position, -8.0, 1.4)
		tools._toast(["Missed! The loop flops in the sand.", "So close! Have another go.", "Nope - %s ducked." % _name_of(t)][randi() % 3])
		return
	victim = t
	_hold_t = 0.0
	t.request_lasso(String(player.name), "", randf_range(10.0, 20.0))
	tools._toast("Yeehaw! You lassoed %s!" % _name_of(t))
	if _main:
		_main.achievements.unlock("yeehaw")
		get_node("/root/Net").stat("lassos")


## Odds of a catch: distance, how well-timed the whirl was, how far the loop landed from
## them, and whether they're running. Tuned so a decent throw at 6-12 m lands ~1 in 3.
static func hit_chance(dist: float, power: float, miss: float, speed: float) -> float:
	if miss > 1.6:
		return 0.0
	var c := 0.85 if dist < 4.0 else lerpf(0.55, 0.12, clampf((dist - 4.0) / (RANGE - 4.0), 0.0, 1.0))
	c *= 0.45 + 0.75 * clampf(power, 0.0, 1.0)
	c *= 1.0 - clampf(miss / 1.6, 0.0, 1.0) * 0.6
	if speed > 4.0:
		c *= 0.7
	return clampf(c, 0.0, 0.95)


func _nearest_hitch() -> Dictionary:
	var best := {}
	var bd := 2.4
	for c in _main.cars.get_children():
		var car := c as SandVehicle
		if car == null:
			continue
		var p := car.global_transform * car.rear_point()
		var d := p.distance_to(player.global_position + Vector3.UP * 0.3)
		if d < bd:
			bd = d
			best = {"car": car, "pos": p}
	return best


func _hitch(car: SandVehicle) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	victim.request_lasso(String(player.name), String(car.name), -1.0)
	tools._toast("%s's hitched to the towbar - take 'em for a spin!" % _name_of(victim))
	Sfx.play_at(self, "thunk", car.global_transform * car.rear_point(), -4.0)
	_main.achievements.unlock("hitched")
	victim = null


func _name_of(p: PlayerCharacter) -> String:
	if p.tag_text != "":
		return p.tag_text
	return String(_main.name_of(p.get_multiplayer_authority())) if _main else "them"


## Put the lasso away / swapped items: drop anything mid-throw.
func reset() -> void:
	state = "idle"
	tools.charge = -1.0
	_loop.visible = false

class_name Bots
extends Node3D
## Computer-driven utes: your helper (follows you and comes to pull you out when
## you're bogged) and island bots that cruise the beach, fish, camp and drive tracks.
##
## Whoever spawns a bot runs its brain. Everyone else just sees the ute and driver
## through the normal car / player network sync.

const ROLES := {"fisher": "Fisher", "camper": "Camper", "cruiser": "Beach cruiser", "tracker": "Track 4WDer",
	"police": "Police", "ambulance": "Ambulance", "ranger": "Ranger"}
const EMERGENCY := ["police", "ambulance", "ranger"]
const TITLES := {"police": "Constable", "ambulance": "Paramedic", "ranger": "Ranger"}
const NAMES := ["Dazza", "Shazza", "Macca", "Kylie", "Robbo", "Tash", "Jono", "Bazza", "Nat", "Davo",
	"Sal", "Hendo", "Gazza", "Bec", "Stevo", "Jacko", "Mel", "Wazza"]
const COLOURS := [
	Color(0.95, 0.75, 0.15), Color(0.20, 0.65, 0.35), Color(0.55, 0.25, 0.75), Color(0.90, 0.45, 0.10),
	Color(0.10, 0.60, 0.75), Color(0.75, 0.15, 0.30), Color(0.40, 0.40, 0.45), Color(0.95, 0.95, 0.92),
]
const HELPER_COLOUR := 8   ## index past COLOURS = high-vis green for the helper

var debug := false             ## admin: labels over bots, paths and the helper's breadcrumb trail
var helper_bog_proof := true   ## admin: the helper can't get bogged itself
var emergency_common := true   ## admin: police / ambulance / ranger turn up often (testing) or rarely
var help_chance := 0.5         ## chance a passing bot stops to snatch out a bogged one
var helper: HelperBot
var segments: Array[Vector2] = []   ## stretches of east beach (f ranges) that are clear to drive
var _counter := 0
var _pending: Array[Array] = []    ## spawns that arrived while our island was still building
var _main: Node
var _lines: MeshInstance3D


func _ready() -> void:
	_main = get_parent()
	_lines = MeshInstance3D.new()
	_lines.mesh = ImmediateMesh.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	_lines.material_override = m
	_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lines)


func clear_all() -> void:
	for b in brains():
		b.queue_free()
	helper = null
	segments.clear()


## The island's built: spawn any bots we were told about while it was loading.
func flush_pending() -> void:
	var todo := _pending.duplicate()
	_pending.clear()
	for a in todo:
		callv("_rpc_spawn", a)


func brains() -> Array[BotBrain]:
	var out: Array[BotBrain] = []
	for c in get_children():
		if c is BotBrain and not c.is_queued_for_deletion():
			out.append(c)
	return out


## What a bot turns up in: mostly a 4WD (the helper and emergency services always are),
## now and then a buggy, a quad or a dirt bike.
func random_kind(role: String) -> String:
	if role == "helper" or role in EMERGENCY or randf() >= 0.2:
		return "ute"
	return ["buggy", "quad", "bike"].pick_random()


## A role for a random island bot. Emergency services are rare unless the admin
## switch says otherwise.
func random_role(emergency := true) -> String:
	var everyday := ["fisher", "camper", "cruiser", "tracker"]
	if not emergency:
		return everyday.pick_random()
	var w_em := 1.0 if emergency_common else 0.06
	var total := everyday.size() + EMERGENCY.size() * w_em
	var r := randf() * total
	if r < everyday.size():
		return everyday[int(r)]
	return EMERGENCY[clampi(int((r - everyday.size()) / w_em), 0, EMERGENCY.size() - 1)]


## Bots stuck and waiting for a strap or winch.
func stuck_brains() -> Array[BotBrain]:
	var out: Array[BotBrain] = []
	for b in brains():
		if b is AmbientBot and (b as AmbientBot).needs_help:
			out.append(b)
	return out


## Real people's characters (not bots): [{peer, person, car}]
func humans() -> Array:
	var out := []
	for p in _main.players.get_children():
		var pc := p as PlayerCharacter
		if pc == null or pc.ai or pc.is_queued_for_deletion() or not String(pc.name).begins_with("Player_"):
			continue
		out.append({"peer": pc.get_multiplayer_authority(), "person": pc, "car": pc.car})
	return out


func name_of(peer: int) -> String:
	return _main.name_of(peer)


# ------------------------------------------------------------- talking
## A bot says something: bubble over its head for everyone, and a toast for anyone close by.
func say(person: PlayerCharacter, who: String, text: String) -> void:
	if _online():
		_rpc_say.rpc(String(person.name), who, text)
	else:
		_rpc_say(String(person.name), who, text)


@rpc("any_peer", "call_local", "reliable")
func _rpc_say(person_name: String, who: String, text: String) -> void:
	var p := _main.players.get_node_or_null(person_name) as PlayerCharacter
	if p == null:
		return
	p.say(text)
	if _main.hud and _main.hud.chat:
		_main.hud.chat.add_line("bots", who, text, Color(1.0, 0.8, 0.35))
	var me: PlayerCharacter = _main.local_player
	if me and is_instance_valid(me) and me.global_position.distance_to(p.global_position) < 45.0:
		_toast("%s: %s" % [who, text])
		Sfx.play_ui(self, "blip", -8.0, randf_range(0.9, 1.15))


## Someone waved at pos: bots nearby wave back (each machine answers for the bots it runs).
func wave_back(pos: Vector3) -> void:
	if _online():
		_rpc_wave_back.rpc(pos)
	else:
		_rpc_wave_back(pos)


@rpc("any_peer", "call_local", "reliable")
func _rpc_wave_back(pos: Vector3) -> void:
	for b in brains():
		var p: PlayerCharacter = b.person
		if p == null or not is_instance_valid(p) or p.global_position.distance_to(pos) > 30.0 or p.is_down():
			continue
		if p.is_on_foot():
			p.wave_t = 2.0
		elif b.car and is_instance_valid(b.car):
			b.car.wave(false)
		if randf() < 0.5:
			say(p, b.display, ["G'day!", "Hooroo!", "How ya goin'?", "Oi oi!", "Beauty of a day for it!"][randi() % 5])


## A message just for one player (pulled over, fined...). sound = an Sfx kind or "".
func tell(peer: int, text: String, sound := "") -> void:
	if peer == multiplayer.get_unique_id() or not _online():
		_rpc_tell(text, sound)
	else:
		_rpc_tell.rpc_id(peer, text, sound)


@rpc("any_peer", "call_local", "reliable")
func _rpc_tell(text: String, sound: String) -> void:
	_toast(text)
	if sound != "":
		Sfx.play_ui(self, sound, -2.0)


## Speeding fine for a player (runs on their machine).
func fine(peer: int, dollars: int, text: String) -> void:
	if peer == multiplayer.get_unique_id() or not _online():
		_rpc_fine(dollars, text)
	else:
		_rpc_fine.rpc_id(peer, dollars, text)


@rpc("any_peer", "call_local", "reliable")
func _rpc_fine(dollars: int, text: String) -> void:
	_main.fines_total += dollars
	_toast(text)
	Sfx.play_ui(self, "wahwah", -1.0)
	_main.achievements.unlock("booked")


# ------------------------------------------------------------- ute bonks
const SORRY := ["Sorry %s! Didn't see ya there!", "Whoops! You right, %s?", "My bad, %s! Sun was in my eyes!",
	"Oh no - %s! I swear the brakes were on!"]
const OUCH := ["Oi! Watch where you're going, %s!", "Strewth! Did anyone get the rego of that ute?",
	"%s, ya galah! I'd just had a coffee!", "Wheeee! ...I mean, OI, %s!", "Was that really necessary, %s?"]
const KO := ["Ugh... I'm seeing kookaburras...", "Somebody call an ambo...", "Five more minutes, Mum..."]


## After someone lands: bots involved (that run on this machine) have their say.
func bonk_lines(by_node: String, victim_node: String, by: String, victim: String, down: bool) -> void:
	for b in brains():
		var ab := b as AmbientBot
		if ab == null:
			continue
		if String(ab.person.name) == by_node:
			ab._say(String(SORRY.pick_random()) % victim.get_slice(" ", victim.get_slice_count(" ") - 1))
		elif String(ab.person.name) == victim_node:
			var line: String = KO.pick_random() if down else OUCH.pick_random()
			if not down and by_node == "":
				line = "Strewth! Did anyone get the rego of that ute?"   # nobody driving it
			ab._say(line.replace("%s", by))


## Someone's out cold: the nearest free ambulance comes (or one's sent from up the beach).
## Runs on the host, which owns the bots.
func call_ambulance(person: PlayerCharacter) -> void:
	if _online() and not multiplayer.is_server():
		_rpc_call_ambo.rpc_id(1, String(person.name))
	else:
		_rpc_call_ambo(String(person.name))


@rpc("any_peer", "call_local", "reliable")
func _rpc_call_ambo(person_name: String) -> void:
	if _online() and not multiplayer.is_server():
		return
	var p := _main.players.get_node_or_null(person_name) as PlayerCharacter
	if p == null or _main.world == null:
		return
	var best: AmbientBot = null
	var bd := 1500.0
	for b in brains():
		var ab := b as AmbientBot
		if ab == null or ab.role != "ambulance" or ab.needs_help or ab.person == p:
			continue
		if ab._patient == p:
			return   # already on the way
		if ab._patient != null and is_instance_valid(ab._patient) and ab._patient.is_down():
			continue
		var d := ab.car.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = ab
	if best == null:
		var nm := spawn("ambulance", p.global_position, true)
		if nm != "":
			best = get_node_or_null("Brain_" + nm) as AmbientBot
	if best:
		best.attend(p)
		_toast("%s is on the way with lights and siren!" % best.display)


## The floating "HELP!" sign over a bogged bot.
func set_help(person: PlayerCharacter, on: bool) -> void:
	if _online():
		_rpc_help.rpc(String(person.name), on)
	else:
		_rpc_help(String(person.name), on)


@rpc("any_peer", "call_local", "reliable")
func _rpc_help(person_name: String, on: bool) -> void:
	var p := _main.players.get_node_or_null(person_name) as PlayerCharacter
	if p:
		p.set_help_icon(on)


# ------------------------------------------------------------- admin debug
## Admin: bog the nearest island bot right where it is (to practise rescues).
func bog_nearest() -> void:
	var lead := _lead_pos()
	var best: AmbientBot = null
	var bd := INF
	for b in brains():
		var ab := b as AmbientBot
		if ab == null or ab.needs_help or not ab.in_car():
			continue
		var d := ab.car.global_position.distance_to(lead)
		if d < bd:
			bd = d
			best = ab
	if best == null:
		_toast("No island bot driving around to bog - spawn one first")
		return
	best.force_bog()
	_toast("%s is bogged %d m away - look for the HELP sign" % [best.display, roundi(bd)])


## Admin: free every stuck bot (no strap needed).
func free_stuck() -> void:
	var n := 0
	for b in stuck_brains():
		(b as AmbientBot).rescued(true)
		n += 1
	_toast("Freed %d stuck bot%s" % [n, "" if n == 1 else "s"])


func ambient_count() -> int:
	var n := 0
	for b in brains():
		if b.role != "helper":
			n += 1
	return n


func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _toast(msg: String) -> void:
	if _main.hud:
		_main.hud.show_toast(msg)


# ------------------------------------------------------------- the beach "road"
## How far up the beach (m from the waterline at mid tide) bots drive: low on the
## hard sand at low tide, pushed up toward the soft stuff at high tide.
func lane_d() -> float:
	return clampf(maxf(Tide.level, -0.3) / 0.034 + 9.0, 10.0, 31.0)


## A point in the beach lane. Keep left: northbound runs on the dune side.
func lane_point(f: float, north: bool) -> Vector3:
	var isl := IslandData.instance
	var d := lane_d() + (3.5 if north else -3.5)
	var z := isl.f_to_z(f)
	var x := isl.east_x(f) - d
	return Vector3(x, isl.height_at(x, z), z)


func beach_path(f0: float, f1: float) -> PackedVector3Array:
	var isl := IslandData.instance
	var out := PackedVector3Array()
	var north := f1 > f0
	var step := 6.0 / isl.length
	var n := maxi(int(absf(f1 - f0) / step), 1)
	for k in n + 1:
		out.append(lane_point(lerpf(f0, f1, float(k) / n), north))
	return out


func build_segments() -> void:
	segments.clear()
	var isl := IslandData.instance
	var step := 5.0 / isl.length
	var start := -1.0
	var f := 0.02
	while f < 0.985:
		var ok := _beach_clear(f)
		if ok and start < 0.0:
			start = f
		elif not ok and start >= 0.0:
			_add_segment(start, f - step)
			start = -1.0
		f += step
	if start >= 0.0:
		_add_segment(start, f)


func _add_segment(a: float, b: float) -> void:
	var isl := IslandData.instance
	# trim a little off each end so bots turn round before the rocks
	a += 12.0 / isl.length
	b -= 12.0 / isl.length
	if (b - a) * isl.length >= 150.0:
		segments.append(Vector2(a, b))


func _beach_clear(f: float) -> bool:
	var isl := IslandData.instance
	var z := isl.f_to_z(f)
	for d: float in [10.0, 18.0, 26.0, 34.0]:
		var x := isl.east_x(f) - d
		var s := isl.surface_at(x, z)
		if s == IslandData.Surface.ROCK or s == IslandData.Surface.OCEAN:
			return false
		var h := isl.height_at(x, z)
		if h > 2.4 or h < -0.5:
			return false
	for w in isl.wrecks:
		var p: Vector3 = w["pos"]
		if absf(p.z - z) < 30.0 and absf(p.x - (isl.east_x(f) - 20.0)) < 40.0:
			return false
	return true


## The clear stretch of beach a position (f) is in, or the nearest one.
func segment_near(f: float) -> Vector2:
	if segments.is_empty():
		build_segments()
	var best := Vector2(-1, -1)
	var bd := INF
	for s in segments:
		var d := 0.0 if f >= s.x and f <= s.y else minf(absf(f - s.x), absf(f - s.y))
		if d < bd:
			bd = d
			best = s
	return best


func on_east_beach(p: Vector3) -> bool:
	var isl := IslandData.instance
	var f := isl.z_to_f(p.z)
	var de := isl.east_x(f) - p.x
	return de > -5.0 and de < 45.0


# ------------------------------------------------------------- spawning
## Admin: spawn a bot near you. role = helper / fisher / camper / cruiser / tracker
## near: spawn close to there instead of you (an ambulance called out). Returns the ute's name.
func spawn(role: String, near := Vector3.INF, quiet := false) -> String:
	var lead := _lead_pos() if near == Vector3.INF else near
	if lead == Vector3.INF:
		return ""
	if near == Vector3.INF and _main.local_car and _main.local_car.carrier != null:
		_toast("Wait till you're off the barge")
		return ""
	if role == "helper" and helper != null and is_instance_valid(helper):
		_toast("You've already got a helper - it's the green ute")
		return ""
	var xf := _spawn_xf(role, lead)
	_counter += 1
	var me := multiplayer.get_unique_id()
	var nm := "Bot_%d_%d" % [me, _counter]
	var who := "Helper" if role == "helper" else String(NAMES[randi() % NAMES.size()])
	if TITLES.has(role):
		who = "%s %s" % [TITLES[role], who]
	var style: String = Avatar.STYLES[randi() % Avatar.STYLES.size()]
	var ci := HELPER_COLOUR if role == "helper" else randi() % COLOURS.size()
	if not role in EMERGENCY and randf() < 0.7:
		# dress them up: pirate hats, flannos, clown shoes...
		var bc: Color = Color(0.55, 0.90, 0.20) if ci >= COLOURS.size() else COLOURS[ci]
		style = Avatar.random_spec(style, bc.darkened(0.15))
	var kind := random_kind(role)
	if _online():
		_rpc_spawn.rpc(nm, role, xf, me, style, ci, who, kind)
	else:
		_rpc_spawn(nm, role, xf, me, style, ci, who, kind)
	if quiet:
		pass
	elif role == "helper":
		_toast("Your helper's here (green ute) - it'll follow you and come running when you bog it")
	elif role in EMERGENCY:
		_toast("%s is on patrol%s" % [who, " - watch your speed, it's 60 on the beach!" if role == "police" else ""])
	else:
		_toast("%s the %s has turned up" % [who, String(ROLES.get(role, role)).to_lower()])
	return nm


func _lead_pos() -> Vector3:
	if _main.local_player and _main.local_player.is_on_foot():
		return _main.local_player.global_position
	if _main.local_car:
		return _main.local_car.global_position
	return Vector3.INF


func _spawn_xf(role: String, lead: Vector3) -> Transform3D:
	var isl := IslandData.instance
	match role:
		"helper":
			var car: SandVehicle = _main.local_car
			var fwd := -car.global_basis.z
			fwd.y = 0.0
			fwd = fwd.normalized() if fwd.length() > 0.1 else Vector3.FORWARD
			var p := car.global_position - fwd * 20.0
			return Transform3D(Basis.looking_at(fwd, Vector3.UP), Vector3(p.x, isl.height_at(p.x, p.z) + 1.4, p.z))
		"tracker":
			var best := {}
			var bd := INF
			for t in isl.tracks_built:
				if t.get("no_bots", false):
					continue
				var path: PackedVector2Array = t["path"]
				for end in [0, path.size() - 1]:
					var ow := int(t.get("oneway", 0))
					if (ow == 1 and end != 0) or (ow == -1 and end == 0):
						continue
					var d := Vector2(lead.x, lead.z).distance_to(path[end])
					if d < bd and not _car_near(Vector3(path[end].x, 0, path[end].y), 8.0):
						bd = d
						best = {"path": path, "end": end}
			if not best.is_empty():
				var path: PackedVector2Array = best["path"]
				var e: int = best["end"]
				var a := path[e]
				var b := path[clampi(e + (4 if e == 0 else -4), 0, path.size() - 1)]
				var dir := Vector3(b.x - a.x, 0, b.y - a.y).normalized()
				return Transform3D(Basis.looking_at(dir, Vector3.UP), Vector3(a.x, isl.height_at(a.x, a.y) + 1.4, a.y))
	# beach bots: in the lane a little way up or down the beach from you
	var f0 := isl.z_to_f(lead.z)
	for tries in 12:
		var f := f0 + randf_range(0.006, 0.03) * (1.0 if randf() < 0.5 else -1.0)
		var seg := segment_near(f)
		if seg.x < 0.0:
			break
		f = clampf(f, seg.x + 0.003, seg.y - 0.003)
		var north := randf() < 0.5
		var p := lane_point(f, north)
		if _car_near(p, 10.0) and tries < 11:
			continue
		var dir := Vector3(0, 0, -1) if north else Vector3(0, 0, 1)
		return Transform3D(Basis.looking_at(dir, Vector3.UP), p + Vector3.UP * 1.4)
	return Transform3D(Basis.IDENTITY, lead + Vector3(8, 1.4, 8))


func _car_near(p: Vector3, r: float) -> bool:
	for c in _main.cars.get_children():
		if Vector2(c.global_position.x - p.x, c.global_position.z - p.z).length() < r:
			return true
	return false


@rpc("any_peer", "call_local", "reliable")
func _rpc_spawn(nm: String, role: String, xf: Transform3D, owner_id: int, style: String, ci: int, who: String, kind := "ute") -> void:
	if _main.world == null:
		_pending.append([nm, role, xf, owner_id, style, ci, who, kind])
		return
	if _main.cars.has_node(nm):
		return
	var mine := owner_id == multiplayer.get_unique_id()
	var car := SandVehicle.new()
	car.name = nm
	car.kind = kind
	car.body_color = Color(0.55, 0.90, 0.20) if ci >= COLOURS.size() else COLOURS[ci]
	if role in EMERGENCY:
		car.livery = role
		car.body_color = Color(0.97, 0.97, 0.95) if role != "ranger" else Color(0.86, 0.84, 0.74)
	car.set_multiplayer_authority(owner_id)
	car.local_control = mine
	car.scripted = true
	car.set_meta("bot", role)
	car.set_meta("bot_owner", owner_id)
	if not mine:
		car.freeze = true
		car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	car.transform = xf
	_main.cars.add_child(car)
	var shirt := car.body_color.darkened(0.15)
	var person := PlayerCharacter.create(style, shirt)
	person.name = "BotP_" + nm.trim_prefix("Bot_")
	person.set_multiplayer_authority(owner_id)
	person.local_control = false
	person.ai = mine
	person.tag_text = who
	person.car = car
	_main.players.add_child(person)
	if not mine:
		return
	car.set_all_psi(18.0)
	var brain: BotBrain = HelperBot.new() if role == "helper" else AmbientBot.new()
	brain.name = "Brain_" + nm
	brain.setup(self, role, car, person, who, style, ci)
	add_child(brain)
	if role == "helper":
		helper = brain
		car.bog_proof = helper_bog_proof


## Admin: take a bot away (and anything it had set up).
func remove(nm: String) -> void:
	if _online():
		_rpc_remove.rpc(nm)
	else:
		_rpc_remove(nm)


func remove_all_ambient() -> void:
	for b in brains():
		if b.role != "helper":
			remove(String(b.car.name))


func remove_helper() -> void:
	if helper and is_instance_valid(helper):
		remove(String(helper.car.name))


@rpc("any_peer", "call_local", "reliable")
func _rpc_remove(nm: String) -> void:
	_pending = _pending.filter(func(a: Array) -> bool: return a[0] != nm)
	var brain := get_node_or_null("Brain_" + nm) as BotBrain
	if brain:
		brain.cleanup()
		if brain == helper:
			helper = null
		brain.queue_free()
	for rid in _main.ropes.ropes_on(nm):
		_main.ropes._rpc_remove(rid)
	var car: Node = _main.cars.get_node_or_null(nm)
	if car:
		car.queue_free()
	var person: Node = _main.players.get_node_or_null("BotP_" + nm.trim_prefix("Bot_"))
	if person:
		person.queue_free()


## A player joined: show them the bots we're running.
func sync_to(peer: int) -> void:
	for b in brains():
		_rpc_spawn.rpc_id(peer, String(b.car.name), b.role, b.car.global_transform,
			multiplayer.get_unique_id(), b.style, b.colour_i, b.display, b.car.kind)
		if b is AmbientBot and (b as AmbientBot).needs_help:
			_rpc_help.rpc_id(peer, String(b.person.name), true)


## A player left: their bots go with them.
func remove_owned_by(peer: int) -> void:
	for c in _main.cars.get_children():
		if c.has_meta("bot") and int(c.get_meta("bot_owner")) == peer:
			_rpc_remove(String(c.name))


# ------------------------------------------------------------- debug drawing
func _process(_delta: float) -> void:
	var im := _lines.mesh as ImmediateMesh
	im.clear_surfaces()
	if not debug:
		return
	for b in brains():
		var col := Color(0.3, 1.0, 0.3) if b.role == "helper" else Color(1.0, 0.85, 0.2)
		var d := b.driver
		if not d.done and d.path.size() > 1:
			_polyline(im, d.path, col)
			_cross(im, d.target, Color(1, 0.2, 0.2))
	if helper and is_instance_valid(helper) and helper.trail.size() > 1:
		_polyline(im, helper.trail, Color(0.3, 0.7, 1.0))
		if helper.goal != Vector3.INF:
			_cross(im, helper.goal, Color(1, 0.3, 1))


func _polyline(im: ImmediateMesh, pts: PackedVector3Array, col: Color) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in pts:
		im.surface_set_color(col)
		im.surface_add_vertex(p + Vector3.UP * 0.4)
	im.surface_end()


func _cross(im: ImmediateMesh, p: Vector3, col: Color) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for v in [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)]:
		im.surface_set_color(col)
		im.surface_add_vertex(p + v * 1.2 + Vector3.UP * 0.5)
		im.surface_set_color(col)
		im.surface_add_vertex(p - v * 1.2 + Vector3.UP * 0.5)
	im.surface_end()

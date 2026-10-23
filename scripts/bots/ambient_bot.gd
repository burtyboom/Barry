class_name AmbientBot
extends BotBrain
## Island bots that get on with their day:
##   cruiser   - drives up and down the beach, now and then hops out for a look at the surf
##   fisher    - finds a spot, wanders down to the water and casts a line, again and again
##   camper    - sets up tent, fire, chair (and a spare chair for you) behind the beach, kicks back
##   tracker   - drives the inland tracks (aired down, low range), then along the beach to the next
##   police    - patrols, runs lights and siren to "jobs", sets up speed traps with a radar gun:
##               do more than 60 on the beach past one and you'll be pulled over and fined
##   ambulance - cruises, and every so often races off lights-and-siren to check on someone
##   ranger    - drives beach and tracks, stops for a chat and some island tips
##
## Everybody waves (arm out the window, beep beep) and says g'day to real players by name.
## If a bot bogs itself and can't reverse / air down its way out, it gets out, puts a big
## HELP sign over its head and waits for a snatch strap or winch. The next bot along has a
## 50/50 chance of stopping to snatch it out or just driving past.

const GREETINGS := ["G'day %s!", "How ya going, %s?", "Hey %s!", "Hooroo %s!", "Beautiful day for it, %s!",
	"Look who it is - %s!", "Whatcha up to, %s?"]
const PLEAS := ["Ah no, I'm bogged! Anyone got a snatch strap?", "%s! Mate, can you give us a pull out?",
	"Stuck like a pig in mud! Got a winch, %s?", "Help! She's dug in to the axles!"]
const PASS_BY := ["Sorry mate, can't stop!", "Ooh, that looks soft. Good luck!", "Should've aired down, mate!",
	"Someone'll be along to help!"]
const CAMP_CHAT := ["Caught anything today, %s?", "Want a snag, %s? They're nearly done!",
	"Watch the dingoes, %s - they'll pinch your thongs!", "Reckon the tide's on its way in, %s.",
	"Saw a whale out there this morning, %s!", "Best spot on the island this, hey %s?",
	"Did you air down, %s? It's soft up near the dunes.", "%s, chuck another log on the fire would ya?",
	"How good is camping, %s!", "Bit of a breeze tonight, %s. Good for keeping the mozzies off.",
	"My old ute got bogged right there last year, %s. Took three of us to get it out!",
	"You want a marshmallow, %s? Don't let it catch on fire!"]
const RANGER_TIPS := ["It's 60 on the beach and 30 on the inland tracks, %s.",
	"Keep your food locked up, %s - the dingoes are clever.",
	"Don't forget to air down, %s. Saves the tracks and gets you through the soft stuff.",
	"Take all your rubbish home with you, %s!", "Watch the tides around the headlands, %s.",
	"Seen any whales today, %s? They cruise right past this time of year.",
	"Give way to the walkers on the beach, %s. And no driving on the dunes!"]
const AMBO_LINES := ["All good here - just a bluebottle sting.", "False alarm! Someone ate too many snags.",
	"They'll be right. Plenty of water and some shade.", "Just a sprained ankle from the dunes!"]

var needs_help := false        ## bogged and given up: waiting for a strap or winch
var rescuer: AmbientBot = null ## another bot on its way to snatch us out
var stuck_spot := Vector3.ZERO
var freed := false             ## pulled out, waiting for the strap to come off
var _stuck_dig: Array[float] = []
var _plea_t := 0.0
var _tow_t := 0.0
var _push_hold := 0.0          ## someone's nudging our bogged ute with theirs
var _getin := {}
var _decided := {}             ## stuck bots we've already helped / driven past
var _scan_t := 0.0
var _greeted := {}             ## peer -> msec we last said g'day
var _social_t := 0.0
var _wave_t := 0.0
var _invited := {}
var _guest_chair := ""
var _guest := -1               ## peer sitting in our spare chair
var _chat_t := 4.0
var _last_track := ""
# police
var _chase_car: SandVehicle
var _chase_peer := 0
var _chase_kmh := 0
var _patient: PlayerCharacter = null   ## ambulance: someone knocked out cold we're on our way to


func _ready() -> void:
	super()
	driver.self_rescue = false
	if bots.segments.is_empty():
		bots.build_segments()


func short_name() -> String:
	return display.get_slice(" ", display.get_slice_count(" ") - 1)


func _say(text: String) -> void:
	bots.say(person, display, text)


func think(delta: float) -> void:
	_wave_t -= delta
	if needs_help:
		_think_stuck(delta)
		return
	if driver.gave_up:
		_become_stuck()
		return
	_social_t -= delta
	if _social_t <= 0.0:
		_social_t = 0.5
		_social()
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 1.0
		_look_for_stuck()
	super.think(delta)
	if role == "camper":
		_camp_chat(delta)
	if _wave_t > 0.0 and person.state == PlayerCharacter.State.ON_FOOT and person.tools._fish == "idle":
		person.pose_override = "wave"


func debug_text() -> String:
	if needs_help:
		return "%s  (%s)\nBOGGED - %s\n%s" % [display, role, "freed, unhook me" if freed else "waiting for help",
			"rescuer: " + rescuer.display if rescuer else ""]
	return super.debug_text()


func plan_next() -> void:
	match role:
		"fisher":
			_plan_fish()
		"camper":
			_plan_camp()
		"tracker":
			_plan_track()
		"police":
			_plan_police()
		"ambulance":
			_plan_ambulance()
		"ranger":
			_plan_ranger()
		_:
			_plan_cruise()


# ------------------------------------------------------------- shared bits
func _f() -> float:
	return island.z_to_f(car.global_position.z)


## A spot on the same clear stretch of beach, between min_m and max_m away.
func _beach_target(min_m: float, max_m: float) -> float:
	var f := _f()
	var seg := bots.segment_near(f)
	if seg.x < 0.0:
		return f
	var lo := seg.x + 0.002
	var hi := seg.y - 0.002
	var dist := randf_range(min_m, max_m) / island.length
	var dir := 1.0 if randf() < 0.5 else -1.0
	var t := f + dist * dir
	if t < lo or t > hi:
		t = f - dist * dir
	return clampf(t, lo, hi)


func _drive_beach(min_m: float, max_m: float, speed := 13.0) -> void:
	var target := _beach_target(min_m, max_m)
	plan.append({"do": "get_in"})
	plan.append({"do": "drive", "speed": speed, "make": func() -> PackedVector3Array:
		var from := _f()
		var path := bots.beach_path(from, target)
		# start from where the ute actually is, so it eases into the lane
		path.insert(0, car.global_position)
		return path})
	plan.append({"do": "park"})


## Side of the ute away from the sea (for walking round to the door etc.)
func _seaward() -> Vector3:
	return Vector3(1, 0, 0)


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The nearest real player (not a bot) within r of p: {peer, person, car} or {}.
func _nearest_human(p: Vector3, r: float) -> Dictionary:
	var best := {}
	var bd := r
	for h in bots.humans():
		var d := _flat_dist((h["person"] as PlayerCharacter).global_position, p)
		if d < bd:
			bd = d
			best = h
	return best


func _award(peer: int, id: String) -> void:
	if peer == multiplayer.get_unique_id() or not bots._online():
		_main._rpc_award(id)
	else:
		_main._rpc_award.rpc_id(peer, id)


# ------------------------------------------------------------- cruiser
func _plan_cruise() -> void:
	if not bots.on_east_beach(car.global_position):
		_return_to_beach()
		return
	_drive_beach(200.0, 700.0, randf_range(12.0, 16.0))
	if randf() < 0.5:
		# hop out and check the surf
		plan.append({"do": "get_out"})
		plan.append({"do": "walk_edge"})
		plan.append({"do": "face", "dir": _seaward()})
		plan.append({"do": "wait", "t": randf_range(6.0, 14.0)})
		plan.append({"do": "get_in"})
	else:
		plan.append({"do": "wait", "t": randf_range(2.0, 6.0)})


# ------------------------------------------------------------- fisher
func _plan_fish() -> void:
	if not bots.on_east_beach(car.global_position):
		_return_to_beach()
		return
	_drive_beach(120.0, 450.0, 12.0)
	plan.append({"do": "get_out"})
	plan.append({"do": "select", "slot": 0})
	plan.append({"do": "walk_edge"})
	plan.append({"do": "face", "dir": _seaward()})
	for k in randi_range(3, 6):
		plan.append({"do": "cast", "power": randf_range(0.55, 1.0)})
		plan.append({"do": "wait", "t": randf_range(8.0, 20.0), "pose": "hold"})
		plan.append({"do": "reel"})
		plan.append({"do": "wait", "t": randf_range(1.0, 3.0), "pose": "hold"})
	plan.append({"do": "select", "slot": -1})   # rod away
	plan.append({"do": "get_in"})


# ------------------------------------------------------------- camper
func _plan_camp() -> void:
	if not bots.on_east_beach(car.global_position):
		_return_to_beach()
		return
	_drive_beach(150.0, 500.0, 12.0)
	plan.append({"do": "get_out"})
	plan.append({"do": "select", "slot": -1})
	plan.append({"do": "camp_setup"})


## Lay the camp out on the firm-ish sand just up the beach from the ute.
func _camp_steps() -> void:
	var c := car.global_position
	var spot := Vector3(c.x - 9.0, 0.0, c.z + randf_range(-3.0, 3.0))   # landward of the ute
	spot.y = island.height_at(spot.x, spot.z)
	var sea := _seaward()
	var tent := spot + Vector3(-3.5, 0, -1.0)
	var fire := spot + Vector3(1.0, 0, 0.5)
	var chair := fire + Vector3(-1.8, 0, 0.6)
	var esky := chair + Vector3(0, 0, 1.0)
	var guest := fire + Vector3(1.7, 0, -0.5)   # a spare chair for visitors
	var steps: Array[Dictionary] = []
	for item in [["tent", tent, sea, false], ["fire", fire, sea, false], ["chair", chair, fire - chair, false],
			["esky", esky, sea, false], ["chair", guest, fire - guest, true]]:
		var p: Vector3 = item[1]
		p.y = island.height_at(p.x, p.z)
		var face: Vector3 = item[2]
		var yaw := atan2(-face.x, -face.z)
		var stand := p + Vector3(0.0, 0.0, 1.3)
		steps.append({"do": "walk", "to": stand})
		steps.append({"do": "place", "kind": item[0], "xf": Transform3D(Basis(Vector3.UP, yaw), p), "guest": item[3]})
	steps.append({"do": "sit_chair"})
	steps.append({"do": "wait", "t": randf_range(45.0, 110.0)})
	steps.append({"do": "stand"})
	if randf() < 0.6:
		steps.append({"do": "walk_edge"})
		steps.append({"do": "face", "dir": sea})
		steps.append({"do": "wait", "t": randf_range(5.0, 12.0)})
		steps.append({"do": "sit_chair"})
		steps.append({"do": "wait", "t": randf_range(40.0, 90.0)})
		steps.append({"do": "stand"})
	steps.append({"do": "pack_up"})
	steps.append({"do": "get_in"})
	# run these next, ahead of anything else queued
	for k in range(steps.size() - 1, -1, -1):
		plan.insert(1, steps[k])


func _pack_steps() -> void:
	var steps: Array[Dictionary] = []
	for id in camp_ids:
		var node: Node3D = _main.props.props.get(id)
		if node == null:
			continue
		var reach: float = {"tent": 2.1, "fire": 1.5}.get(String(node.get_meta("kind")), 1.1)
		steps.append({"do": "walk", "to": node.global_position, "within": reach})
		steps.append({"do": "pick_up", "id": id})
	for k in range(steps.size() - 1, -1, -1):
		plan.insert(1, steps[k])


## Someone (a real player) sitting in our spare chair? Their peer id, or -1.
func _guest_peer() -> int:
	var node: Node3D = _main.props.props.get(_guest_chair) if _guest_chair != "" else null
	if node == null:
		return -1
	for h in bots.humans():
		var pc: PlayerCharacter = h["person"]
		if pc.state == PlayerCharacter.State.SITTING and _flat_dist(pc.global_position, node.global_position) < 1.4:
			return int(h["peer"])
	return -1


## Campers call you over, then have a yarn while you're sitting at their fire.
func _camp_chat(delta: float) -> void:
	if camp_ids.is_empty():
		_guest = -1
		return
	var fire_node: Node3D = null
	for id in camp_ids:
		var n: Node3D = _main.props.props.get(id)
		if n and n.get_meta("kind") == "fire":
			fire_node = n
	if fire_node == null:
		return
	# invite anyone wandering (or driving slowly) past - once each
	var h := _nearest_human(fire_node.global_position, 18.0)
	if not h.is_empty() and not _invited.has(h["peer"]) and _guest_chair != "":
		var pc: PlayerCharacter = h["person"]
		if pc.is_on_foot() or absf((h["car"] as SandVehicle).speed_kmh) < 15.0:
			_invited[h["peer"]] = true
			_say("What's happening, %s? Pull up a chair, the fire's going!" % bots.name_of(h["peer"]))
			_wave_t = 1.8
	var g := _guest_peer()
	if g != _guest:
		if g >= 0:
			_chat_t = 3.0
			_say("Good to see ya, %s! Make yourself at home." % bots.name_of(g))
			_award(g, "campfire_guest")
		elif _guest >= 0:
			_say("See ya later, %s!" % bots.name_of(_guest))
		_guest = g
	if _guest >= 0:
		_chat_t -= delta
		if _chat_t <= 0.0:
			_chat_t = randf_range(9.0, 16.0)
			_say(String(CAMP_CHAT.pick_random()) % bots.name_of(_guest))


# ------------------------------------------------------------- tracker
func _plan_track(speed := 7.5) -> void:
	var track := _nearest_track_end(car.global_position, 60.0, "")
	if track.is_empty():
		# nowhere near a track: drive the beach to the closest track entrance
		var entry := _nearest_track_end(car.global_position, 1e9, "", true)
		if entry.is_empty() or not bots.on_east_beach(car.global_position):
			_plan_cruise()
			return
		var target_f := island.z_to_f((entry["start"] as Vector3).z)
		var seg := bots.segment_near(_f())
		if target_f < seg.x - 0.004 or target_f > seg.y + 0.004:
			_plan_cruise()   # it's past rocks we can't drive round - just cruise
			return
		plan.append({"do": "get_in"})
		plan.append({"do": "drive", "speed": 13.0, "make": func() -> PackedVector3Array:
			var path := bots.beach_path(_f(), clampf(target_f, seg.x, seg.y))
			path.insert(0, car.global_position)
			path.append(entry["start"])
			return path})
		return
	var pts: PackedVector3Array = track["pts"]
	plan.append({"do": "get_in"})
	plan.append({"do": "air", "psi": 15.0})
	plan.append({"do": "drive", "speed": speed, "low": true, "arrive": 5.0, "timeout": 400.0, "make": func() -> PackedVector3Array:
		var path := pts.duplicate()
		path.insert(0, car.global_position)
		return path})
	plan.append({"do": "air", "psi": 18.0})
	plan.append({"do": "park"})
	if randf() < 0.4:
		plan.append({"do": "get_out"})
		plan.append({"do": "wait", "t": randf_range(5.0, 10.0)})
		plan.append({"do": "get_in"})
	_last_track = String(track["name"])


## Nearest end of a track: {"name", "pts" (start -> other end), "start"}.
func _nearest_track_end(p: Vector3, max_d: float, _skip: String, beach_only := false) -> Dictionary:
	var best := {}
	var bd := max_d
	for t in island.tracks_built:
		var path: PackedVector2Array = t["path"]
		if path.size() < 4 or t.get("no_bots", false):
			continue
		for e in [0, path.size() - 1]:
			var ow := int(t.get("oneway", 0))
			if (ow == 1 and e != 0) or (ow == -1 and e == 0):
				continue   # one-way track: only in at its proper end
			var a := path[e]
			var d := Vector2(p.x, p.z).distance_to(a)
			# don't go straight back down the track we just came out of
			if String(t["name"]) == _last_track and d < 80.0:
				continue
			var start := Vector3(a.x, island.height_at(a.x, a.y), a.y)
			if beach_only and not bots.on_east_beach(start):
				continue
			if d < bd:
				bd = d
				var pts := PackedVector3Array()
				var idxs := range(path.size()) if e == 0 else range(path.size() - 1, -1, -1)
				for k in idxs:
					pts.append(Vector3(path[k].x, island.height_at(path[k].x, path[k].y), path[k].y))
				best = {"name": t["name"], "pts": pts, "start": start}
	return best


## Off the beach (end of a dead-end track, say): head back the nearest way.
func _return_to_beach() -> void:
	_last_track = ""
	var track := _nearest_track_end(car.global_position, 1e9, "")
	if track.is_empty():
		plan.append({"do": "wait", "t": 5.0})
		return
	var pts: PackedVector3Array = track["pts"]
	plan.append({"do": "get_in"})
	plan.append({"do": "air", "psi": 15.0})
	plan.append({"do": "drive", "speed": 7.5, "low": true, "arrive": 5.0, "timeout": 400.0, "make": func() -> PackedVector3Array:
		var path := PackedVector3Array([car.global_position])
		# from the track end we're at, follow it to its other end
		path.append_array(pts)
		return path})
	plan.append({"do": "park"})


# ------------------------------------------------------------- police
func _plan_police() -> void:
	if not bots.on_east_beach(car.global_position):
		_return_to_beach()
		return
	var r := randf()
	if r < 0.55:
		# speed trap: park up, stand by the ute with the radar gun pointed up the beach
		_drive_beach(150.0, 500.0, 13.0)
		plan.append({"do": "lights", "l": false, "s": false})
		plan.append({"do": "get_out"})
		plan.append({"do": "trap", "dur": randf_range(70.0, 150.0), "face": Vector3(0, 0, -1) if randf() < 0.5 else Vector3(0, 0, 1)})
		plan.append({"do": "get_in"})
	elif r < 0.8:
		# called to a job: lights only (the siren is just for pulling people over), quick down the beach
		plan.append({"do": "get_in"})
		plan.append({"do": "lights", "l": true, "s": false})
		_drive_beach(350.0, 900.0, 19.5)
		plan.append({"do": "get_out"})
		plan.append({"do": "wander", "r": 10.0})
		plan.append({"do": "wait", "t": randf_range(6.0, 12.0)})
		plan.append({"do": "get_in"})
		plan.append({"do": "lights", "l": false, "s": false})
	else:
		_drive_beach(250.0, 700.0, 12.0)
		plan.append({"do": "wait", "t": randf_range(3.0, 8.0)})


## Fine for km/h over the limit (a game version of a QLD-style table): [dollars, demerit points]
static func speeding_fine(kmh: int) -> Array:
	var over := kmh - 60
	if over <= 10:
		return [322, 1]
	if over <= 20:
		return [483, 3]
	if over <= 30:
		return [966, 4]
	if over <= 40:
		return [1452, 6]
	return [1935, 8]


## Radar gun: anyone coming at us over 60 gets pulled over.
func _trap(st: Dictionary, delta: float) -> bool:
	var t: float = st["_t"]
	var face: Vector3 = st["face"]
	if not st.has("spot"):
		var c := car.global_position
		st["spot"] = Vector3(c.x - 3.2, island.height_at(c.x - 3.2, c.z), c.z + face.z * 2.5)
	if not st.has("there"):
		if walk_to(st["spot"], false, 0.8) or t > 15.0:
			st["there"] = true
			person.ai_move = Vector3.ZERO
			person.tools.hold_extra("radar")
		return false
	person.pose_override = "radar"
	person._yaw = lerp_angle(person._yaw, atan2(-face.x, -face.z), minf(1.0, 6.0 * delta))
	var me := person.global_position
	for h in bots.humans():
		var c := h["car"] as SandVehicle
		var pc := h["person"] as PlayerCharacter
		if c == null or pc.state != PlayerCharacter.State.IN_CAR:
			continue
		var to := Vector3(c.global_position.x - me.x, 0, c.global_position.z - me.z)
		var d := to.length()
		if d > 170.0 or d < 3.0:
			continue
		if to.normalized().dot(face) < cos(deg_to_rad(40.0)):
			continue   # not in front of the radar
		var closing := -c.linear_velocity.dot(to.normalized())
		var kmh := roundi(c.linear_velocity.length() * 3.6)
		if closing > 3.0 and kmh > 60:
			_start_chase(h, kmh)
			return true
		var nod := "nod_%d" % h["peer"]
		if closing > 3.0 and d < 40.0 and kmh > 25 and not st.has(nod):
			st[nod] = true
			_say("%d km/h - nice and steady, %s!" % [kmh, bots.name_of(h["peer"])])
	if t > float(st["dur"]):
		person.tools.select(-1)
		return true
	return false


func _start_chase(h: Dictionary, kmh: int) -> void:
	person.tools.select(-1)
	_chase_car = h["car"]
	_chase_peer = int(h["peer"])
	_chase_kmh = kmh
	_say("Whoa! %d km/h!" % kmh)
	Sfx.play_at(person, "radio", person.global_position + Vector3.UP, 0.0)
	bots.tell(_chase_peer, "POLICE! Pull over, %s! The radar says %d km/h - it's 60 on the beach!" % [bots.name_of(_chase_peer), kmh], "radio")
	plan.resize(1)   # the trap step that's finishing gets popped by think()
	plan.append({"do": "get_in"})
	plan.append({"do": "chase"})


func _chase(st: Dictionary, delta: float) -> bool:
	var c := _chase_car
	var t: float = st["_t"]
	var nm := bots.name_of(_chase_peer)
	if c == null or not is_instance_valid(c):
		car.set_signals(false, false, false)
		return true
	car.set_signals(true, true, false)
	var me := car.global_position
	var tp := c.global_position
	var d := _flat_dist(me, tp)
	var tv := c.linear_velocity.length() * 3.6
	if d > 450.0 or t > 150.0:
		car.set_signals(false, false, false)
		bots.tell(_chase_peer, "The police lost you... this time! It's 60 on the beach, %s." % nm)
		_say("Oh well. Back to it.")
		_chase_car = null
		return true
	st["tell"] = float(st.get("tell", 5.0)) - delta
	if float(st["tell"]) <= 0.0 and tv > 8.0:
		st["tell"] = 7.0
		var line: String = ["Pull over, %s! Stop the car!", "%s! Pull over please!", "Lights and sirens means pull over, %s!"].pick_random()
		bots.tell(_chase_peer, line % nm, "radio")
	var stopped := tv < 4.0 or not c.driver_present
	st["still"] = (float(st.get("still", 0.0)) + delta) if stopped and d < 35.0 else 0.0
	if float(st["still"]) > 1.5:
		driver.stop(delta)
		plan.insert(1, {"do": "ticket"})
		return true
	st["pt"] = float(st.get("pt", 0.0)) - delta
	if float(st["pt"]) <= 0.0:
		st["pt"] = 0.4
		var aim := tp - (tp - me).normalized() * 9.0
		aim.y = island.height_at(aim.x, aim.z)
		driver.set_path(PackedVector3Array([me, aim]), clampf(tv / 3.6 + d * 0.15, 4.0, 28.0))
		driver.arrive = 2.5
		driver.ease_to_end = d < 40.0
		driver.ignore = [c]
	if d < 11.0:
		driver.stop(delta)
	else:
		driver.update(delta)
	return false


## Walk up to the driver's window, have a word, write the ticket.
func _ticket(st: Dictionary, delta: float) -> bool:
	var c := _chase_car
	var t: float = st["_t"]
	var nm := bots.name_of(_chase_peer)
	if c == null or not is_instance_valid(c):
		return true
	car.set_signals(true, false, false)
	if not st.has("out"):
		driver.stop(delta)
		if in_car():
			if absf(car.speed_kmh) < 2.0:
				person.get_out()
			return false
		if person.state != PlayerCharacter.State.ON_FOOT:
			return false
		st["out"] = t
	# their window, or them if they've hopped out
	var who := {}
	for h in bots.humans():
		if int(h["peer"]) == _chase_peer:
			who = h
	var spot := c.global_transform * Vector3(2.0, 0, -0.1)
	if not who.is_empty() and (who["person"] as PlayerCharacter).is_on_foot():
		spot = (who["person"] as PlayerCharacter).global_position
	spot.y = island.height_at(spot.x, spot.z)
	if not st.has("at"):
		if walk_to(spot, false, 1.8) or t - float(st["out"]) > 30.0:
			st["at"] = t
			person.ai_move = Vector3.ZERO
			_say("G'day %s. Do you know how fast you were going? %d in a 60 zone!" % [nm, _chase_kmh])
		return false
	var me := person.global_position
	person._yaw = lerp_angle(person._yaw, atan2(-(spot.x - me.x), -(spot.z - me.z)), minf(1.0, 6.0 * delta))
	var k := t - float(st["at"])
	if k > 4.0 and not st.has("fined"):
		st["fined"] = true
		var f := speeding_fine(_chase_kmh)
		bots.fine(_chase_peer, int(f[0]), "FINED $%d and %d demerit points for %d km/h in a 60 zone. Slow down on the beach, %s!" % [f[0], f[1], _chase_kmh, nm])
	if st.has("fined") and k < 7.0:
		person.pose_override = "dig"   # scribbling out the ticket
	if k > 7.5 and not st.has("bye"):
		st["bye"] = true
		_say("There's kids and wildlife about, %s. Take it easy and have a good one!" % nm)
	if k > 10.0:
		car.set_signals(false, false, false)
		_chase_car = null
		plan.insert(1, {"do": "get_in"})
		return true
	return false


# ------------------------------------------------------------- ambulance
func _plan_ambulance() -> void:
	if not bots.on_east_beach(car.global_position):
		_return_to_beach()
		return
	if randf() < 0.5:
		# a call-out: lights on (the siren's saved for someone knocked out cold - see attend)
		plan.append({"do": "get_in"})
		plan.append({"do": "lights", "l": true, "s": false})
		_drive_beach(350.0, 900.0, 19.0)
		plan.append({"do": "get_out"})
		plan.append({"do": "wander", "r": 9.0})
		plan.append({"do": "wait", "t": randf_range(6.0, 12.0), "pose": "dig"})
		plan.append({"do": "say", "text": AMBO_LINES.pick_random()})
		plan.append({"do": "wait", "t": 3.0})
		plan.append({"do": "get_in"})
		plan.append({"do": "lights", "l": false, "s": false})
	else:
		_drive_beach(200.0, 600.0, 12.0)
		plan.append({"do": "wait", "t": randf_range(3.0, 8.0)})


## Drop everything: someone's been knocked out cold by a ute. Lights and siren, then CPR.
func attend(p: PlayerCharacter) -> void:
	_patient = p
	_chase_car = null
	plan.clear()
	person.ai_move = Vector3.ZERO
	person.ai_run = false
	person.pose_override = ""
	if person.state == PlayerCharacter.State.SITTING:
		person.stand_up()
	plan.append({"do": "get_in"})
	plan.append({"do": "attend"})


func _attend(st: Dictionary, delta: float) -> bool:
	var p := _patient
	var t: float = st["_t"]
	if p == null or not is_instance_valid(p) or (not p.is_down() and not st.has("revived")):
		# came good on their own (or left): back to it
		_patient = null
		car.set_signals(false, false, false)
		plan.insert(1, {"do": "get_in"})
		return true
	var nm := p.tag_text if p.tag_text != "" else "mate"
	if not st.has("out"):
		if in_car():
			var me := car.global_position
			var tp := p.global_position
			var d := _flat_dist(me, tp)
			st["slow"] = (float(st.get("slow", 0.0)) + delta) if car.linear_velocity.length() < 1.0 and t > 4.0 else 0.0
			if d < 14.0 or t > 80.0 or float(st["slow"]) > 6.0:
				# there (or as close as the ute gets): siren off, lights stay on
				car.set_signals(true, false, false)
				driver.stop(delta)
				if absf(car.speed_kmh) < 2.0:
					person.get_out()
				return false
			car.set_signals(true, true, false)
			if not st.has("radio"):
				st["radio"] = true
				_say("Hang in there, %s! Ambulance on the way!" % nm)
			st["pt"] = float(st.get("pt", 0.0)) - delta
			if float(st["pt"]) <= 0.0:
				st["pt"] = 0.5
				var aim := tp - (tp - me).normalized() * 9.0
				aim.y = island.height_at(aim.x, aim.z)
				driver.set_path(PackedVector3Array([me, aim]), clampf(d * 0.2, 6.0, 24.0))
				driver.arrive = 3.0
				driver.ease_to_end = d < 50.0
				driver.ignore = [p]
			driver.update(delta)
			return false
		if person.state != PlayerCharacter.State.ON_FOOT:
			return false
		st["out"] = t
	# kneel beside their chest (they're lying on their back, head toward +Z)
	var chest := p.global_transform * Vector3(0.0, 0.0, 0.75)
	var spot := p.global_transform * Vector3(0.85, 0.0, 0.75)
	spot.y = island.height_at(spot.x, spot.z)
	if not st.has("cpr"):
		if walk_to(spot, true, 0.5) or t - float(st["out"]) > 45.0:
			st["cpr"] = t
			person.ai_move = Vector3.ZERO
			_say("Righto %s, I've got ya! Let's get you going again..." % nm)
		return false
	var me2 := person.global_position
	person._yaw = lerp_angle(person._yaw, atan2(-(chest.x - me2.x), -(chest.z - me2.z)), minf(1.0, 8.0 * delta))
	var k := t - float(st["cpr"])
	if k < 7.0:
		person.pose_override = "cpr"
		if k > 2.0 and not st.has("count"):
			st["count"] = true
			_say("One, two, three, four, five...")
		if k > 4.5 and not st.has("come_on"):
			st["come_on"] = true
			_say("Come on %s, stay with me!" % nm)
		return false
	if not st.has("revived"):
		st["revived"] = true
		person.pose_override = ""
		p.revive()
		_say(String(["There ya go, %s! Good as new. Maybe stay out of the way of utes, eh?",
			"Back with us, %s! Full health - off you go.", "You'll be right, %s! Just a few stars, that's all."].pick_random()) % nm)
	if k > 10.0:
		_patient = null
		car.set_signals(false, false, false)
		plan.insert(1, {"do": "get_in"})
		return true
	return false


# ------------------------------------------------------------- ranger
func _plan_ranger() -> void:
	if randf() < 0.4:
		_plan_track(7.0)
		return
	if not bots.on_east_beach(car.global_position):
		_return_to_beach()
		return
	_drive_beach(150.0, 500.0, 11.0)
	plan.append({"do": "lights", "l": true, "s": false})
	plan.append({"do": "visit"})
	plan.append({"do": "lights", "l": false, "s": false})


## Ranger: if someone's about, walk over and pass on a tip; otherwise have a look around.
func _visit(st: Dictionary, delta: float) -> bool:
	var t: float = st["_t"]
	if not st.has("who"):
		var h0 := _nearest_human(car.global_position, 70.0)
		st["who"] = h0
		if h0.is_empty():
			plan.insert(1, {"do": "wait", "t": randf_range(5.0, 10.0)})
			return true
	var h: Dictionary = st["who"]
	var pc: PlayerCharacter = h["person"]
	if not is_instance_valid(pc):
		return true
	if in_car():
		driver.stop(delta)
		if absf(car.speed_kmh) < 2.0:
			person.get_out()
		return false
	if person.state != PlayerCharacter.State.ON_FOOT:
		return false
	var target := pc.global_position if pc.is_on_foot() else pc.door_spot()
	if not st.has("said"):
		if walk_to(target, false, 2.5) or t > 40.0:
			st["said"] = t
			person.ai_move = Vector3.ZERO
			var nm := bots.name_of(h["peer"])
			_say("G'day %s, ranger here! %s" % [nm, String(RANGER_TIPS.pick_random()) % nm])
			_wave_t = 1.5
		return false
	if t - float(st["said"]) > 6.0:
		plan.insert(1, {"do": "get_in"})
		return true
	return false


# ------------------------------------------------------------- waves and g'days
func _social() -> void:
	var now := Time.get_ticks_msec()
	var me := person.global_position
	for h in bots.humans():
		var peer: int = h["peer"]
		if now - int(_greeted.get(peer, -999999)) < 35000:
			continue
		var pc: PlayerCharacter = h["person"]
		var d := _flat_dist(pc.global_position, me)
		if in_car():
			# passing on the beach: arm out the window, beep beep
			if d < 26.0 and absf(car.speed_kmh) > 5.0 and _chase_car == null:
				_greeted[peer] = now
				car.wave(randf() < 0.75)
				if randf() < 0.5:
					_say(String(GREETINGS.pick_random()) % bots.name_of(peer))
				return
		elif person.state == PlayerCharacter.State.ON_FOOT and pc.is_on_foot() and d < 9.0:
			_greeted[peer] = now
			_wave_t = 1.8
			_say(String(GREETINGS.pick_random()) % bots.name_of(peer))
			return


# ------------------------------------------------------------- stuck: waiting for help
func _become_stuck() -> void:
	needs_help = true
	freed = false
	rescuer = null
	stuck_spot = car.global_position
	_stuck_dig.clear()
	for w in car.wheels:
		_stuck_dig.append(w.dig)
	plan.clear()
	driver.stop(0.1)
	car.set_signals(false, false, false)
	_chase_car = null
	person.tools.select(-1)
	_plea_t = 2.0
	_getin = {}
	bots.set_help(person, true)
	_say("Ah no, I'm bogged!")


## Admin debug: dig this bot in where it is.
func force_bog() -> void:
	for w in car.wheels:
		w.dig = car.max_sink * 0.8
		w.sink = car.max_sink * 0.9
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO
	driver.gave_up = true


## Pulled out (or freed by the admin).
func rescued(instant := false) -> void:
	freed = true
	bots.set_help(person, false)
	if instant:
		for w in car.wheels:
			w.dig = 0.0
			w.sink *= 0.3
		if _main.ropes.ropes_on(String(car.name)).is_empty():
			_finish_rescue()


func _finish_rescue() -> void:
	needs_help = false
	freed = false
	rescuer = null
	bots.set_help(person, false)
	driver.reset_stuck()
	car.set_all_psi(18.0)
	car.low_range = false
	plan.clear()
	person.pose_override = ""


## The car (or tree) on the other end of the first rope hooked to us.
func _rope_other(ids: Array[String]) -> Dictionary:
	var r: Dictionary = _main.ropes.ropes[ids[0]]
	return r["b"] if String(r["a"].get("car", "")) == String(car.name) else r["a"]


func _think_stuck(delta: float) -> void:
	var ids: Array[String] = _main.ropes.ropes_on(String(car.name))
	if ids.is_empty():
		if freed:
			_finish_rescue()
			_say("Righto, back to it. Cheers again!")
			return
		if car._pushed_t > 0.0:
			_push_hold = 3.0
		_push_hold -= delta
		if _push_hold > 0.0:
			_think_pushed(delta)
			return
		if _flat_dist(car.global_position, stuck_spot) > 4.5 and not car.is_bogged:
			# the strap came off while we were still rolling out of the hole: we're free
			rescued()
			_say("Woohoo, I'm out! Thanks heaps!")
			return
		# wait by the ute, waving at anyone who comes near, until someone hooks on
		stuck_spot = car.global_position
		for i in mini(car.wheels.size(), _stuck_dig.size()):
			car.wheels[i].dig = maxf(car.wheels[i].dig, _stuck_dig[i])   # still dug in
		if in_car():
			driver.stop(delta)
			if absf(car.speed_kmh) < 3.0:
				person.get_out()
			return
		if person.state == PlayerCharacter.State.SITTING:
			person.stand_up()
		if person.state != PlayerCharacter.State.ON_FOOT:
			return
		driver.stop(delta)
		var spot := person.door_spot() + car.global_basis.x * 1.2
		if walk_to(spot, false, 1.0):
			person.ai_move = Vector3.ZERO
		var h := _nearest_human(person.global_position, 60.0)
		person.pose_override = "wave" if not h.is_empty() else ""
		if not h.is_empty():
			var hp := (h["person"] as PlayerCharacter).global_position
			var me := person.global_position
			person._yaw = lerp_angle(person._yaw, atan2(-(hp.x - me.x), -(hp.z - me.z)), minf(1.0, 5.0 * delta))
		_plea_t -= delta
		if _plea_t <= 0.0:
			_plea_t = randf_range(18.0, 30.0)
			if not h.is_empty():
				var line: String = PLEAS.pick_random()
				_say(line % bots.name_of(h["peer"]) if "%s" in line else line)
		return
	# hooked up: jump in and drive with the pull
	person.pose_override = ""
	if not in_car():
		_release_brakes()
		_getin["_t"] = float(_getin.get("_t", 0.0)) + delta
		if not _getin.has("said"):
			_getin["said"] = true
			var oc0 := _main.cars.get_node_or_null(String(_rope_other(ids).get("car", ""))) as SandVehicle
			if oc0 and not oc0.has_meta("bot"):
				_say("Legend! I'll jump in - pull when you're ready, %s!" % bots.name_of(oc0.get_multiplayer_authority()))
			else:
				_say("Beauty! Jumping in!")
		_getin["do"] = "get_in"
		super.run_step(_getin, delta)
		return
	_getin = {}
	if freed:
		driver.stop(delta)
		driver.status = "out! unhook the strap"
		return
	if car._towed_t > 0.0:
		_tow_t = 0.6
	_tow_t -= delta
	var other := _rope_other(ids)
	var op: Vector3 = _main.ropes.anchor_pos(other)
	var l := car.global_transform.affine_inverse() * op
	var dir := -1.0 if l.z > 0.0 else 1.0
	if _tow_t > 0.0:
		car.low_range = true
		driver.pull(dir, 0.6, delta)
		driver.status = "being pulled - giving it some gas"
	else:
		_release_brakes()
		driver.status = "hooked up - waiting for the pull"
	if _flat_dist(car.global_position, stuck_spot) > 4.5 and absf(car.speed_kmh) < 10.0 and not car.is_bogged:
		rescued()
		driver.stop(delta)
		var oc := _main.cars.get_node_or_null(String(other.get("car", ""))) as SandVehicle
		if oc and not oc.has_meta("bot"):
			var peer := oc.get_multiplayer_authority()
			_say("You legend, %s! Thanks heaps! Can you unhook the strap?" % bots.name_of(peer))
			_award(peer, "samaritan")
		else:
			_say("Woohoo, I'm out! Thanks heaps, %s!" % (rescuer.short_name() if rescuer else "mate"))


## Getting a nudge from another ute: hop in, give it some gas the way we're being shoved.
func _think_pushed(delta: float) -> void:
	person.pose_override = ""
	if not in_car():
		_release_brakes()
		_getin["_t"] = float(_getin.get("_t", 0.0)) + delta
		if not _getin.has("said"):
			_getin["said"] = true
			_say("Ooh, a nudge! Keep pushing, I'll jump in!")
		_getin["do"] = "get_in"
		super.run_step(_getin, delta)
		return
	_getin = {}
	var dir := 1.0 if (-car.global_basis.z).dot(car.push_dir) >= 0.0 else -1.0
	car.low_range = true
	driver.pull(dir, 0.6, delta)
	driver.status = "being nudged - giving it some gas"
	if _flat_dist(car.global_position, stuck_spot) > 4.5 and not car.is_bogged:
		rescued()
		driver.stop(delta)
		_push_hold = 0.0
		var pc := car.pusher
		if pc and is_instance_valid(pc) and not pc.has_meta("bot"):
			var peer := pc.get_multiplayer_authority()
			_say("You legend, %s! Nudged me right out!" % bots.name_of(peer))
			_award(peer, "samaritan")
		else:
			_say("Woohoo, the old nudge worked! Thanks, %s!" % (rescuer.short_name() if rescuer else "mate"))


func _release_brakes() -> void:
	car.handbrake = false
	car.brake = 0.0
	car.throttle = 0.0


# ------------------------------------------------------------- stopping to help
func _look_for_stuck() -> void:
	if not in_car() or plan.is_empty() or String(plan[0]["do"]) != "drive" or _chase_car != null:
		return
	for s in bots.stuck_brains():
		var sb := s as AmbientBot
		if sb == self or _decided.has(sb.name):
			continue
		if _flat_dist(car.global_position, sb.car.global_position) > 50.0:
			continue
		_decided[sb.name] = true
		if sb.rescuer != null or not _main.ropes.ropes_on(String(sb.car.name)).is_empty():
			continue
		if car.kind != "ute" or not sb.car.can_recover():
			car.wave(true)   # a buggy or a bike can't snatch a ute out: just a wave
			continue
		if randf() < bots.help_chance:
			sb.rescuer = self
			plan.clear()
			var nudge := randf() < 0.5
			plan.append({"do": "rescue", "who": sb, "nudge": nudge})
			_say(("Hang on %s, I'll give you a nudge!" if nudge else "Hang on %s, I'll snatch you out!") % sb.short_name())
		else:
			car.wave(true)
			_say(PASS_BY.pick_random())
		return


func _hook_span(sc: SandVehicle) -> float:
	return (car.global_transform * car.front_point()).distance_to(sc.global_transform * sc.rear_point())


func _rescue_rope(sc: SandVehicle) -> String:
	for id in _main.ropes.ropes_on(String(car.name)):
		var r: Dictionary = _main.ropes.ropes[id]
		if String(r["a"].get("car", "")) == String(sc.name) or String(r["b"].get("car", "")) == String(sc.name):
			return id
	return ""


## Drive up behind the bogged ute, strap our bullbar to its tow hitch, and snatch it
## out backwards. Up to four goes, then pack up the strap and carry on.
func _rescue(st: Dictionary, delta: float) -> bool:
	var s := st["who"] as AmbientBot
	var t: float = st["_t"]
	var ph := String(st.get("ph", "approach"))
	if s == null or not is_instance_valid(s) or not is_instance_valid(s.car):
		return true
	var sc := s.car
	var rope := _rescue_rope(sc)
	var someone_else: bool = rope == "" and not _main.ropes.ropes_on(String(sc.name)).is_empty()
	if (not s.needs_help or someone_else) and rope == "" and ph in ["approach", "creep", "nudge", "nudge_back", "hook"]:
		if someone_else:
			_say("Looks like you've got help already!")
		elif ph != "approach":
			_say("Look at that, you're out! Good on ya, %s." % s.short_name())
		if s.rescuer == self:
			s.rescuer = null
		car.low_range = false
		if st.has("bp"):
			car.bog_proof = bool(st["bp"])
		if not in_car():
			plan.insert(1, {"do": "get_in"})
		return true
	if t > 240.0 and ph in ["approach", "creep", "hook"]:
		_say("Sorry %s, I can't get to you!" % s.short_name())
		st["ph"] = "leave"
		ph = "leave"
	match ph:
		"approach":
			if not st.has("path"):
				var back := sc.global_basis.z
				back.y = 0.0
				back = back.normalized()
				var right := Vector3(-back.z, 0, back.x)
				var c := sc.global_position
				var me := car.global_position
				var pts := PackedVector3Array([me])
				var along := (me - c).dot(back)
				if along < 6.0:
					# beside or in front of it: swing round to come in from behind
					var sgn := 1.0 if (me - c).dot(right) >= 0.0 else -1.0
					pts.append(c + right * sgn * 8.0)
					pts.append(c + right * sgn * 6.0 + back * 15.0)
					pts.append(c + back * 21.0)
				elif along > 22.0 or absf((me - c).dot(right)) > 4.0:
					pts.append(c + back * 21.0)
				pts.append(c + back * 10.5)
				for k in pts.size():
					pts[k].y = island.height_at(pts[k].x, pts[k].z)
				st["path"] = pts
				driver.set_path(pts, 6.0)
				driver.arrive = 2.0
				driver.ease_to_end = true
				driver.ignore = [sc, s.person]   # they're standing by their ute waving us in
			if driver.update(delta) or _hook_span(sc) < 6.5:
				st["ph"] = "nudge" if bool(st.get("nudge", false)) else "creep"
				st["min"] = INF
				st["ct"] = t
		"nudge":
			# roll up to their tow bar at walking pace, then lean on it in low range
			var k := t - float(st["ct"])
			var hook := sc.global_transform * sc.rear_point()
			if not st.has("bp"):
				st["bp"] = car.bog_proof
			car.bog_proof = true   # don't dig ourselves in while we're shoving
			car.low_range = true
			if _hook_span(sc) > 1.2 and not st.has("touch"):
				if car.speed_kmh > 6.0:
					driver.stop(delta)
				else:
					driver.pull(1.0, clampf(0.35 + k * 0.08, 0.35, 0.7), delta, driver.steer_toward(hook, false))
			else:
				st["touch"] = st.get("touch", t)
				driver.pull(1.0, clampf(0.5 + (t - float(st["touch"])) * 0.1, 0.5, 0.85), delta, driver.steer_toward(hook, false))
			var budged := _flat_dist(sc.global_position, s.stuck_spot) > 0.6
			if s.freed or not s.needs_help:
				car.low_range = false
				car.bog_proof = bool(st["bp"])
				_say("Too easy - nothing like a nudge, %s!" % s.short_name())
				st["ph"] = "leave"
			elif k > 16.0 or (st.has("touch") and t - float(st["touch"]) > 4.0 and not budged) 					or (st.has("touch") and t - float(st["touch"]) > 9.0):
				_say("Not budging, %s. I'll get the strap out." % s.short_name())
				st["nudge"] = false
				st["ph"] = "nudge_back"
				st["ct"] = t
		"nudge_back":
			car.low_range = false
			car.bog_proof = bool(st.get("bp", car.bog_proof))
			driver.pull(-1.0, 0.4, delta)
			if t - float(st["ct"]) > 2.5 or _hook_span(sc) > 6.0:
				st["ph"] = "creep"
				st["min"] = INF
				st["ct"] = t
		"creep":
			var span := _hook_span(sc)
			var hook := sc.global_transform * sc.rear_point()
			var v := car.linear_velocity.dot(-car.global_basis.z)
			if v < -1.0:
				driver.stop(delta)
				st["min"] = INF
				return false
			st["min"] = minf(float(st["min"]), span)
			var k := t - float(st["ct"])
			if span < 4.0 and k < 25.0:
				driver.pull(-1.0, 0.3, delta)
			elif span > 6.0 and span < float(st["min"]) + 0.3 and k < 25.0:
				driver.pull(1.0, 0.3, delta, driver.steer_toward(hook, false))
			else:
				driver.stop(delta)
				if span > Ropes.STRAP_LEN - 0.8:
					st["retry"] = int(st.get("retry", 0)) + 1
					st.erase("path")
					st["ph"] = "approach" if int(st["retry"]) < 3 else "leave"
				else:
					st["ph"] = "hook"
		"hook":
			driver.stop(delta)
			if in_car():
				if absf(car.speed_kmh) < 1.0:
					person.get_out()
				return false
			if person.state != PlayerCharacter.State.ON_FOOT:
				return false
			if not st.has("bar"):
				# our bullbar first (grab the strap end), then their tow hitch
				st["ht"] = st.get("ht", t)
				if walk_to(car.global_transform * car.front_point(), false, 1.3) or t - float(st["ht"]) > 20.0:
					st["bar"] = t
				return false
			if not st.has("at"):
				var hitch := sc.global_transform * sc.rear_point()
				if not walk_to(hitch, false, 1.3) and t - float(st["bar"]) < 25.0:
					return false
				st["at"] = t
				person.ai_move = Vector3.ZERO
			person.pose_override = "dig"
			if t - float(st["at"]) < 1.0:
				return false
			person.pose_override = ""
			if _hook_span(sc) > Ropes.STRAP_LEN - 0.3:
				_say("Strap won't reach, sorry %s!" % s.short_name())
				st["ph"] = "leave"
				return false
			_main.ropes.create("strap", {"car": String(car.name), "p": car.front_point()},
				{"car": String(sc.name), "p": sc.rear_point()}, Ropes.STRAP_LEN)
			_say("Strap's on! Jump in and give it some gas when I pull, %s!" % s.short_name())
			st["ph"] = "back_in"
			st["bt"] = t
		"back_in":
			if not in_car():
				if person.state == PlayerCharacter.State.ON_FOOT:
					if walk_to(person.door_spot(), false, 1.0) or t - float(st["bt"]) > 40.0:
						person.ai_move = Vector3.ZERO
						person.get_in()
				return false
			driver.stop(delta)
			if not s.in_car() and t - float(st["bt"]) < 45.0:
				return false
			st["ph"] = "count"
			st["cnt"] = t
			_say("Ready? 3... 2... 1... GO!")
		"count":
			driver.stop(delta)
			if rope == "":
				st["ph"] = "leave"
				return false
			if t - float(st["cnt"]) > 2.5:
				st["ph"] = "pull"
				st["pt"] = t
				st["from"] = car.global_position
				st["tries"] = int(st.get("tries", 0)) + 1
		"pull":
			driver.pull(-1.0, 1.0, delta)
			var gone := car.global_position.distance_to(st["from"])
			var moved := _flat_dist(sc.global_position, s.stuck_spot)
			if (moved > 4.0 and gone > 5.0) or gone > 14.0 or t - float(st["pt"]) > 6.0:
				st["ph"] = "settle"
				st["sett"] = t
		"settle":
			driver.stop(delta)
			if t - float(st["sett"]) < 1.5:
				return false
			if s.freed or not s.needs_help or _flat_dist(sc.global_position, s.stuck_spot) > 4.5:
				if s.needs_help and not s.freed:
					s.rescued()   # still rolling when we stopped: it's out all the same
				_say("Too easy, %s!" % s.short_name())
				st["ph"] = "unhook"
			elif int(st["tries"]) < 4:
				st["ph"] = "slack"
				st["sl"] = t
			else:
				_say("She's stuck fast, %s - you'll need a winch. Sorry mate!" % s.short_name())
				st["ph"] = "unhook"
		"slack":
			if rope == "":
				st["ph"] = "leave"
				return false
			var r: Dictionary = _main.ropes.ropes[rope]
			var span: float = (_main.ropes.anchor_pos(r["a"]) as Vector3).distance_to(_main.ropes.anchor_pos(r["b"]))
			driver.pull(1.0, 0.4, delta)
			if span < Ropes.STRAP_LEN - 2.5 or t - float(st["sl"]) > 4.0:
				st["ph"] = "count"
				st["cnt"] = t
		"unhook":
			driver.stop(delta)
			if rope == "":
				st["ph"] = "leave"
				return false
			if in_car():
				if absf(car.speed_kmh) < 1.0:
					person.get_out()
				return false
			if person.state != PlayerCharacter.State.ON_FOOT:
				return false
			st["ut"] = st.get("ut", t)
			if walk_to(car.global_transform * car.front_point(), false, 1.3) or t - float(st["ut"]) > 20.0:
				_main.ropes.remove(rope)
				st["ph"] = "leave"
		"leave":
			if st.has("bp"):
				car.bog_proof = bool(st["bp"])
				car.low_range = false
			if rope != "":
				_main.ropes.remove(rope)
			if s.rescuer == self:
				s.rescuer = null
			plan.insert(1, {"do": "get_in"})
			return true
	return false


# ------------------------------------------------------------- extra steps
func run_step(st: Dictionary, delta: float) -> bool:
	match String(st["do"]):
		"walk_edge":
			if not st.has("to"):
				st["to"] = water_edge(person.global_position)
			return walk_to(st["to"]) or float(st["_t"]) > 30.0
		"camp_setup":
			_camp_steps()
			return true
		"pack_up":
			_pack_steps()
			return true
		"place":
			var done := super.run_step(st, delta)
			if done and bool(st.get("guest", false)) and not camp_ids.is_empty():
				_guest_chair = camp_ids[camp_ids.size() - 1]
			return done
		"pick_up":
			# don't whip the chair out from under a visitor
			if String(st["id"]) == _guest_chair and _guest_peer() >= 0 and float(st["_t"]) < 120.0:
				if not st.has("asked"):
					st["asked"] = true
					_say("No rush %s, I'll wait till you're done!" % bots.name_of(_guest_peer()))
				return false
			if String(st["id"]) == _guest_chair:
				_guest_chair = ""
			return super.run_step(st, delta)
		"stand":
			# got company at the fire: stay for a yarn (up to a few minutes)
			if _guest_peer() >= 0 and float(st["_t"]) < 240.0:
				return false
			return super.run_step(st, delta)
		"sit_chair":
			for id in camp_ids:
				var node: Node3D = _main.props.props.get(id)
				if node and node.get_meta("kind") == "chair" and id != _guest_chair:
					var front := node.global_transform * Vector3(0, 0, -0.9)
					if not walk_to(front, false, 0.6) and float(st["_t"]) < 20.0:
						return false
					return super.run_step({"do": "sit", "id": id, "_t": 0.0}, delta)
			return true
		"air":
			car.set_all_psi(float(st["psi"]))
			return true
		"lights":
			car.set_signals(bool(st["l"]), bool(st["s"]), false)
			return true
		"say":
			_say(String(st["text"]))
			return true
		"wander":
			if not st.has("to"):
				var a := randf() * TAU
				var p := person.global_position + Vector3(cos(a), 0, sin(a)) * float(st["r"])
				p.y = island.height_at(p.x, p.z)
				if island.water_level_at(p.x, p.z) > p.y:
					p = person.global_position
				st["to"] = p
			return walk_to(st["to"]) or float(st["_t"]) > 20.0
		"trap":
			return _trap(st, delta)
		"chase":
			return _chase(st, delta)
		"ticket":
			return _ticket(st, delta)
		"visit":
			return _visit(st, delta)
		"attend":
			return _attend(st, delta)
		"rescue":
			return _rescue(st, delta)
	return super.run_step(st, delta)

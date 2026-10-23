class_name HelperBot
extends BotBrain
## Your recovery buddy in the green ute.
##
## FOLLOW - drives your breadcrumb trail (so it goes where you went, tracks and all),
##          hanging about follow_dist behind and never more than ~30 m back.
## ASSIST - you bogged it: it drives up behind you (or round to your front) and parks
##          with a bit of slack for the strap. You hook up - strap from its bullbar /
##          tow hitch to yours. Once you're back in the driver's seat it counts down and
##          SENDS IT, then rolls back for another go if you're still stuck. Winch to it
##          instead and it chocks its wheels and holds still as an anchor.
## STAY   - parks where it is.
## "Strap me out" / "Winch me out" (Helper menu): it does the lot - parks, hops out,
##          hooks up, pulls you out, then unhooks and packs the gear away again.

enum Mode { FOLLOW, STAY, ASSIST }

const ASSIST_GAP := 10.5       ## centre to centre when parked for a strap (leaves ~3 m of slack)
const CATCH_UP := 150.0        ## further than this and it just turns up behind you
const MAX_TRIES := 4

var mode := Mode.FOLLOW
var follow_dist := 18.0
var assist_side := "rear"      ## rear / front
var phase := ""                ## ASSIST: approach / ready / countdown / pulling / settle / slack / done / anchor
var trail := PackedVector3Array()
var goal := Vector3.INF
var _phase_t := 0.0
var _path_t := 0.0
var _bog_spot := Vector3.ZERO
var _pull_from := Vector3.ZERO
var _pull_dir := 1.0
var _tries := 0
var _send_now := false
var _last_lead := Vector3.INF
var _lead_was_bogged := false
var _anchored := false
var _touch_t := 0.0           ## seconds our bumper's been on yours this nudge
var _nudge_from := Vector3.ZERO
var _nudged := false          ## already tried bumping you out this time
var _free_t := 0.0            ## how long you've been rolling free on this pull (keep going till it's a few seconds)
var _creep_pow := 0.3         ## creep throttle: goes up if we're not getting any closer
var _creep_chk_t := 0.0
var _creep_chk_span := INF
var _recreep := 0             ## extra goes at creeping in when we stopped too far out for the strap
var _creeping := false         ## last bit of the approach: inching in until the strap has ~3 m of slack
var _creep_min := INF
var _self_hook := ""          ## "strap" / "winch": the helper hops out and hooks up itself (Helper menu)
var _hook_step := ""
var _hook_t := 0.0


func lead_car() -> SandVehicle:
	var c: SandVehicle = _main.local_car
	return c if c and is_instance_valid(c) else null


func _say(msg: String) -> void:
	bots._toast("Helper: " + msg)


# ------------------------------------------------------------- admin
var _nudge_wait := 10.0   ## seconds in position (no strap) before trying a nudge


func follow() -> void:
	mode = Mode.FOLLOW
	phase = ""
	_say("following you")


func stay() -> void:
	mode = Mode.STAY
	_say("staying put")


func come(side: String) -> void:
	var lead := lead_car()
	if lead == null:
		return
	assist_side = side
	mode = Mode.ASSIST
	_bog_spot = lead.global_position
	_tries = 0
	_nudged = false
	_nudge_wait = 10.0
	_self_hook = ""
	_hook_step = ""
	_set_phase("approach")
	_path_t = 0.0
	_creeping = false
	_say("on my way to your %s" % ("tow hitch (rear)" if side == "rear" else "bullbar (front)"))


## Helper menu "Strap me out" / "Winch me out": comes round behind you, gets out and
## hooks everything up itself. The winch reaches 35 m, so it doesn't need to get close.
func strap_me_out() -> void:
	_begin_self_hook("strap")


func winch_me_out() -> void:
	_begin_self_hook("winch")


func _begin_self_hook(kind: String) -> void:
	var lead := lead_car()
	if lead == null:
		return
	if not _rope_to_lead().is_empty():
		_say("there's already a line on - send it or unhook it first")
		return
	var ready_behind := mode == Mode.ASSIST and assist_side == "rear" and phase in ["ready", "nudge_back"]
	if not ready_behind:
		come("rear")
	_self_hook = kind
	_hook_step = ""
	if ready_behind:
		_set_phase("ready")
	_say("righto - I'll %s you out. Sit tight in the driver's seat!" % ("snatch" if kind == "strap" else "winch"))


## Helper button "Nudge me out!": drive round to your back bumper and push straight away.
func nudge_me() -> void:
	come("rear")
	_nudge_wait = 0.5
	_say("coming round to give you a shove - give it some gas when I'm on your bumper!")


func send_it() -> void:
	if _rope_to_lead().is_empty():
		_say("hook a snatch strap between us first")
		return
	_send_now = true
	_tries = 0
	_set_phase("countdown")


func teleport_to_lead() -> void:
	var lead := lead_car()
	if lead:
		_catch_up(lead)


func cycle_follow_dist() -> float:
	follow_dist = 12.0 if follow_dist >= 24.0 else follow_dist + 6.0
	return follow_dist


func _set_phase(p: String) -> void:
	phase = p
	_phase_t = 0.0


func debug_text() -> String:
	var lead := lead_car()
	var gap := car.global_position.distance_to(lead.global_position) if lead else 0.0
	var m: String = ["FOLLOW", "STAY", "ASSIST"][mode]
	return "Helper  %s %s\n%.0f m from you (follow %.0f)\n%s" % [m, phase, gap, follow_dist, driver.status]


# ------------------------------------------------------------- brain
func think(delta: float) -> void:
	var lead := lead_car()
	if lead == null:
		driver.stop(delta)
		return
	if trail.is_empty():
		_lay_trail(car.global_position, lead.global_position)
	_record_trail(lead)
	if lead.is_bogged and not _lead_was_bogged and mode == Mode.FOLLOW:
		come(assist_side)
		_say("%s, you're bogged! Coming to your %s - get the snatch strap out (2)" % [bots.name_of(multiplayer.get_unique_id()), assist_side])
	_lead_was_bogged = lead.is_bogged
	_update_anchor()
	if _anchored and _self_hook != "winch":
		driver.status = "anchored - winch away"
		return
	match mode:
		Mode.FOLLOW:
			_follow(delta, lead)
		Mode.STAY:
			driver.stop(delta)
			driver.status = "staying put"
		Mode.ASSIST:
			_assist(delta, lead)


# ------------------------------------------------------------- following
func _record_trail(lead: SandVehicle) -> void:
	var p := lead.global_position
	if _last_lead != Vector3.INF and p.distance_to(_last_lead) > 40.0:
		_last_lead = p
		_catch_up(lead)   # you teleported (or swapped utes)
		return
	_last_lead = p
	if trail.is_empty() or trail[trail.size() - 1].distance_to(p) > 2.5:
		trail.append(p)
	if trail.size() > 500:
		trail = trail.slice(trail.size() - 400)


## Pop up behind the lead ute (after a teleport, or if left miles behind).
func _catch_up(lead: SandVehicle) -> void:
	var f := -lead.global_basis.z
	f.y = 0.0
	f = f.normalized() if f.length() > 0.1 else Vector3.FORWARD
	# behind you if that's dry sand, else in front, else either side
	var right := Vector3(-f.z, 0, f.x)
	var p := lead.global_position - f * follow_dist
	for off in [-f, f, right, -right]:
		var q: Vector3 = lead.global_position + off * follow_dist
		if island.height_at(q.x, q.z) > island.water_level_at(q.x, q.z) + 0.15 				and island.surface_at(q.x, q.z) != IslandData.Surface.ROCK:
			p = q
			break
	car.teleport(p, f)
	_lay_trail(p, lead.global_position)
	driver.set_path(PackedVector3Array(), 0.0)


## A straight breadcrumb trail from a to b (when there's no real one yet).
func _lay_trail(a: Vector3, b: Vector3) -> void:
	trail = PackedVector3Array()
	var n := maxi(int(a.distance_to(b) / 2.5), 1)
	for k in n + 1:
		trail.append(a.lerp(b, float(k) / n))


func _closest_idx(p: Vector3) -> int:
	var best := 0
	var bd := INF
	for k in trail.size():
		var d := Vector2(trail[k].x - p.x, trail[k].z - p.z).length_squared()
		if d < bd:
			bd = d
			best = k
	return best


## Walk back along the trail from index i until `dist` metres are covered.
func _back_from(i: int, dist: float) -> int:
	var acc := 0.0
	var k := i
	while k > 0 and acc < dist:
		acc += trail[k].distance_to(trail[k - 1])
		k -= 1
	return k


func _trail_len(i0: int, i1: int) -> float:
	var acc := 0.0
	for k in range(i0, i1):
		acc += trail[k].distance_to(trail[k + 1])
	return acc


func _follow(delta: float, lead: SandVehicle) -> void:
	var me := car.global_position
	var straight := Vector2(lead.global_position.x - me.x, lead.global_position.z - me.z).length()
	if straight > CATCH_UP:
		_catch_up(lead)
		return
	# you're backing toward us: get out of the way
	var to_me := (me - lead.global_position).normalized()
	if straight < 9.0 and lead.linear_velocity.dot(to_me) > 0.8:
		driver.pull(-1.0, 0.6, delta)
		driver.status = "backing off - you're reversing at me"
		_path_t = 0.0
		return
	_path_t -= delta
	if _path_t <= 0.0 and trail.size() > 1:
		_path_t = 0.3
		var last := trail.size() - 1
		var gi := _back_from(last, follow_dist)
		goal = trail[gi]
		var hi := _closest_idx(me)
		var gap := minf(_trail_len(hi, last), straight + 10.0)
		var lead_v := lead.linear_velocity.length()
		# match your speed, plus a bit when we've dropped back (less when too close)
		var spd := clampf(lead_v + (gap - follow_dist) * 0.55, 0.0, 26.0)
		if spd < 1.0 or straight < follow_dist * 0.55:
			driver.set_path(PackedVector3Array(), 0.0)   # close enough: wait
		else:
			# steer down the trail all the way to you
			var pts := PackedVector3Array([me])
			for k in range(hi + 1, last + 1):
				pts.append(trail[k])
			driver.set_path(pts, spd)
			driver.arrive = 2.5
			driver.ease_to_end = false
			driver.ignore = []
	if driver.done:
		driver.stop(delta)
		driver.status = "waiting %d m back" % roundi(straight)
	else:
		driver.update(delta)


# ------------------------------------------------------------- helping
## The strap / winch between us and the lead ute: {"id", "kind", "mine" (our end's car point)} or {}.
func _rope_to_lead() -> Dictionary:
	var lead := lead_car()
	if lead == null:
		return {}
	var me := String(car.name)
	var other := String(lead.name)
	var ropes: Dictionary = _main.ropes.ropes
	for id in ropes:
		var r: Dictionary = ropes[id]
		var a := String(r["a"].get("car", ""))
		var b := String(r["b"].get("car", ""))
		if a == me and b == other:
			return {"id": id, "kind": r["kind"], "mine": r["a"]["p"]}
		if b == me and a == other:
			return {"id": id, "kind": r["kind"], "mine": r["b"]["p"]}
	return {}


## Any winch hooked to us: chock the wheels (freeze) so we're a solid anchor.
func _update_anchor() -> void:
	var want := false
	for id in _main.ropes.ropes_on(String(car.name)):
		if _main.ropes.ropes[id]["kind"] == "winch":
			want = true
	if want != _anchored:
		_anchored = want
		if want:
			driver.stop(0.1)
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			# (freezing can snap a body back to the last transform set in code - here, where
			# it spawned - so pin it to where it actually is right now)
			var here := car.global_transform
			car.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			car.freeze = true
			car.global_transform = here
			if _self_hook != "winch":
				_say("wheels chocked - winch away (G in, H out)")
		else:
			car.freeze = false


func _assist(delta: float, lead: SandVehicle) -> void:
	_phase_t += delta
	var rope := _rope_to_lead()
	var moved := Vector2(lead.global_position.x - _bog_spot.x, lead.global_position.z - _bog_spot.z).length()
	if rope.is_empty() and moved > 10.0 and phase != "done":
		mode = Mode.FOLLOW
		phase = ""
		_say("you're out - nice work, %s!" % bots.name_of(multiplayer.get_unique_id()))
		return
	match phase:
		"approach":
			if not rope.is_empty():
				_set_phase("ready")
				return
			if _self_hook == "winch" and _phase_t > 1.0 and _hook_span(lead) < 20.0 \
					and (car.global_transform.affine_inverse() * lead.global_position).z < -3.0:
				_creeping = false
				driver.set_path(PackedVector3Array(), 0.0)
				_set_phase("ready")
				return
			_approach(delta, lead)
		"ready":
			driver.stop(delta)
			driver.status = "in position - hook the strap or winch on"
			if _self_hook != "" and (rope.is_empty() or _hook_step == "back"):
				_hook_up(delta, lead)
				return
			if _hook_step == "in" and not in_car():
				return   # still climbing back in
			if _hook_step == "in" and not rope.is_empty():
				# back in the cab after hooking up ourselves: go!
				_hook_step = ""
				if rope["kind"] == "winch":
					_set_phase("winching")
					return
				_send_now = true
			if not rope.is_empty() and rope["kind"] == "strap" and lead.driver_present and (_tries < MAX_TRIES or _send_now):
				_set_phase("countdown")
			elif rope.is_empty() and not _nudged and assist_side == "rear" and lead.driver_present and _phase_t > _nudge_wait:
				# no strap coming? try bumping you out from behind
				_nudged = true
				_say("No strap? I'll give you a nudge from behind, %s - give it some gas!" % bots.name_of(multiplayer.get_unique_id()))
				_touch_t = 0.0
				_nudge_from = lead.global_position
				_set_phase("nudge")
		"nudge":
			if not rope.is_empty():
				car.low_range = false
				_set_phase("ready")
				return
			car.low_range = true
			var hook := lead.global_transform * SandVehicle.REAR_POINT
			# ease on, then more and more right foot (it takes a bit to get rolling in soft sand)
			driver.pull(1.0, clampf(0.4 + _phase_t * 0.12, 0.4, 0.9), delta, driver.steer_toward(hook, false))
			driver.status = "nudging you out - give it some gas!"
			if lead._pushed_t > 0.0:
				_touch_t += delta
			var budged := lead.global_position.distance_to(_nudge_from) > 0.6
			if _phase_t > 18.0 or (_touch_t > 7.0 and not budged):
				_say("Not budging - hook the strap on and I'll snatch you out")
				_set_phase("nudge_back")
		"nudge_back":
			car.low_range = false
			driver.pull(-1.0, 0.4, delta)
			if _phase_t > 2.5:
				_creeping = true
				_creep_min = INF
				_recreep = 0
				_set_phase("approach")
		"countdown":
			driver.stop(delta)
			if rope.is_empty():
				_set_phase("ready")
				return
			if not lead.driver_present:
				driver.status = "waiting for you to get back in"
				_phase_t = 0.0
				return
			var left := 3 - int(_phase_t)
			driver.status = "sending it in %d..." % left
			if _phase_t < delta * 1.5:
				_say("strap's on! Hold on, %s - sending it in 3... drive out with me!" % bots.name_of(multiplayer.get_unique_id()))
			if _phase_t > 3.0:
				_send_now = false
				_tries += 1
				_pull_from = car.global_position
				# hooked at our bullbar: back away. At our tow hitch: drive away.
				var mine: Vector3 = rope["mine"]
				_pull_dir = -1.0 if mine.z < 0.0 else 1.0
				_free_t = 0.0
				_set_phase("pulling")
		"pulling":
			if rope.is_empty():
				_say("the strap's off - re-hook it and I'll go again")
				_set_phase("ready")
				return
			driver.pull(_pull_dir, 1.0, delta)
			driver.status = "PULLING (go %d)" % _tries
			var gone := car.global_position.distance_to(_pull_from)
			# don't stop the moment you twitch: keep pulling till you've been rolling free
			# (not dug in) for a couple of seconds and are well clear of the hole
			var rolling := lead.linear_velocity.length() > 2.0 and not lead.is_bogged
			_free_t = _free_t + delta if rolling else 0.0
			if (_free_t > 2.5 and moved > 8.0) or gone > 30.0 or _phase_t > 12.0:
				_set_phase("settle")
		"settle":
			driver.stop(delta)
			if _phase_t > 1.5:
				if moved > 6.0 and not lead.is_bogged:
					_set_phase("done")
					if _self_hook != "":
						_say("you're out, %s! Stay put, I'll grab the strap" % bots.name_of(multiplayer.get_unique_id()))
					else:
						_say("you're out, %s! Unhook the strap (E at either end) and I'll follow" % bots.name_of(multiplayer.get_unique_id()))
				elif _tries < MAX_TRIES:
					_set_phase("slack")
					_say("still stuck - rolling back for another go")
				else:
					_set_phase("ready")
					_say("can't shift you - air down or dig out, then Admin > Send it")
		"slack":
			if rope.is_empty():
				_set_phase("ready")
				return
			# roll back toward you until the strap's loose again
			var a: Vector3 = car.global_transform * (rope["mine"] as Vector3)
			var ends := _main.ropes.anchor_pos(_main.ropes.ropes[rope["id"]]["a"]) as Vector3
			var ende := _main.ropes.anchor_pos(_main.ropes.ropes[rope["id"]]["b"]) as Vector3
			var span := ends.distance_to(ende)
			driver.pull(-_pull_dir, 0.45, delta)
			driver.status = "rolling back for slack (%.1f m)" % span
			if span < Ropes.STRAP_LEN - 2.5 or _phase_t > 5.0 or a.distance_to(lead.global_position) < 4.0:
				_set_phase("countdown")
		"winching":
			driver.stop(delta)
			if rope.is_empty():
				_set_phase("ready")
				return
			var r: Dictionary = _main.ropes.ropes[rope["id"]]
			_main.ropes.auto_in[rope["id"]] = true
			driver.status = "WINCHING you in (%.1f m of cable)" % float(r["rest"])
			if _phase_t < delta * 1.5:
				_say("winching - give it a little gas and steer straight, %s!" % bots.name_of(multiplayer.get_unique_id()))
			var out := moved > 6.0 and not lead.is_bogged
			if out or float(r["rest"]) < 2.5 or _phase_t > 70.0:
				_main.ropes.auto_in.erase(rope["id"])
				if out:
					_set_phase("done")
					_say("you're out! Hang on, I'll grab the winch hook")
				else:
					_say("the winch can't shift you - air down or dig, then ask me again")
					_self_hook = ""
					_set_phase("ready")
		"done":
			driver.stop(delta)
			driver.status = "waiting for you to unhook"
			if _self_hook != "" and not rope.is_empty():
				_unhook(delta, lead, rope)
				return
			if rope.is_empty():
				if not in_car():
					# packed our gear away: back in the ute
					if person.state == PlayerCharacter.State.ON_FOOT and (walk_to(person.door_spot(), false, 1.0) or _phase_t > 40.0):
						person.ai_move = Vector3.ZERO
						person.get_in()
					return
				_self_hook = ""
				_hook_step = ""
				mode = Mode.FOLLOW
				phase = ""


func _approach(delta: float, lead: SandVehicle) -> void:
	var me := car.global_position
	var f := -lead.global_basis.z
	f.y = 0.0
	f = f.normalized() if f.length() > 0.1 else Vector3.FORWARD
	var gap := Vector2(lead.global_position.x - me.x, lead.global_position.z - me.z).length()
	_path_t -= delta
	if _creeping:
		# inch in (forward at your rear, backward at your front) until the hooks are ~5.5 m apart
		var span := _hook_span(lead)
		var toward := 1.0 if assist_side == "rear" else -1.0
		driver.status = "creeping in - %.1f m between hooks" % span
		var hook := lead.global_transform * (SandVehicle.REAR_POINT if assist_side == "rear" else SandVehicle.FRONT_POINT)
		var v := car.linear_velocity.dot(-car.global_basis.z)
		if absf(v) > 1.0 and signf(v) != toward:
			driver.stop(delta)   # still rolling the wrong way: stop first
			_creep_min = INF
			return
		_creep_min = minf(_creep_min, span)
		_creep_chk_t += delta
		if _creep_chk_t > 2.0:
			# barely moving in the soft stuff? a bit more throttle
			_creep_pow = minf(_creep_pow + 0.1, 0.8) if _creep_chk_span - span < 0.4 else maxf(_creep_pow - 0.05, 0.3)
			_creep_chk_t = 0.0
			_creep_chk_span = span
		if span < 4.0 and _phase_t < 30.0:
			driver.pull(-toward, 0.3, delta)
		elif span > 6.0 and (span < _creep_min + 0.3 or span > Ropes.STRAP_LEN - 1.0) and _phase_t < 45.0:
			driver.pull(toward, _creep_pow, delta, driver.steer_toward(hook, toward < 0.0))
		elif span > Ropes.STRAP_LEN - 1.0 and _recreep < 6:
			# stopped (timed out or slid) too far out for a 9 m strap: have another go
			_recreep += 1
			_creep_min = INF
			_phase_t = 0.0
		else:
			_parked()   # close enough (or it's started to slide past)
		return
	if assist_side == "rear":
		goal = lead.global_position - f * ASSIST_GAP
		var lp := car.global_transform.affine_inverse() * lead.global_position
		if gap < ASSIST_GAP - 2.0 and lp.z < 0.0:
			driver.pull(-1.0, 0.5, delta)   # too close: back up a touch
			driver.status = "backing up to leave some slack"
			return
		if _path_t <= 0.0:
			_path_t = 1.0
			var pts := PackedVector3Array([me])
			if trail.size() > 4 and trail[_closest_idx(me)].distance_to(me) < 15.0:
				var li := _closest_idx(lead.global_position)
				var gi := _back_from(li, ASSIST_GAP)
				goal = trail[gi]
				for k in range(_closest_idx(me) + 1, gi + 1):
					pts.append(trail[k])
			pts.append(goal)
			driver.set_path(pts, 7.0)
			driver.arrive = 1.5
			driver.ease_to_end = true
			driver.ignore = [lead]
		if driver.update(delta) or Vector2(goal.x - me.x, goal.z - me.z).length() < 1.5 or _hook_span(lead) < 6.0:
			_creeping = true
			_creep_min = INF
			_recreep = 0
			_creep_pow = 0.3
			_creep_chk_span = INF
	else:
		goal = lead.global_position + f * ASSIST_GAP
		if _phase_t < delta * 1.5:
			_path_t = 9999.0
			var right := Vector3(-f.z, 0, f.x)
			var side := 1.0
			var probe := lead.global_position + right * 7.0
			if island.height_at(probe.x, probe.z) < island.water_level_at(probe.x, probe.z) + 0.2 \
					or island.surface_at(probe.x, probe.z) == IslandData.Surface.ROCK:
				side = -1.0
			var c := lead.global_position
			var pts := PackedVector3Array([me])
			# swing wide past the stuck ute, then tuck in ahead of it facing the same way
			if (me - c).dot(f) < 4.0:
				pts.append(c + right * side * 7.0 - f * 3.0)
			pts.append(c + right * side * 7.0 + f * 5.0)
			pts.append(c + right * side * 4.0 + f * 11.0)
			pts.append(c + right * side * 1.0 + f * 16.0)
			pts.append(c + f * 19.0)
			driver.set_path(pts, 6.0)
			driver.arrive = 2.0
			driver.ease_to_end = true
			driver.ignore = [lead]
		# drive out in front, straighten up, then reverse back to strap distance
		if driver.update(delta):
			_creeping = true
			_creep_min = INF
			_recreep = 0
			_creep_pow = 0.3
			_creep_chk_span = INF


## Out of the cab, our bullbar, your tow hitch, a second fiddling with the shackle,
## then back in. If the strap won't reach from where we stopped, the winch it is.
func _hook_up(delta: float, lead: SandVehicle) -> void:
	_hook_t += delta
	match _hook_step:
		"":
			if in_car():
				if absf(car.speed_kmh) < 1.0:
					person.get_out()
				return
			if person.state != PlayerCharacter.State.ON_FOOT:
				return
			_hook_step = "bar"
			_hook_t = 0.0
		"bar":
			if walk_to(car.global_transform * SandVehicle.FRONT_POINT, false, 1.3) or _hook_t > 20.0:
				_hook_step = "hitch"
				_hook_t = 0.0
		"hitch":
			if walk_to(lead.global_transform * SandVehicle.REAR_POINT, false, 1.3) or _hook_t > 25.0:
				person.ai_move = Vector3.ZERO
				_hook_step = "tie"
				_hook_t = 0.0
		"tie":
			person.pose_override = "dig"
			if _hook_t < 1.2:
				return
			person.pose_override = ""
			var span := _hook_span(lead)
			if _self_hook == "strap" and span > Ropes.STRAP_LEN - 0.3:
				_self_hook = "winch"
				_say("strap won't reach from here (%.0f m) - I'll winch you instead" % span)
			var mine := {"car": String(car.name), "p": SandVehicle.FRONT_POINT}
			var yours := {"car": String(lead.name), "p": SandVehicle.REAR_POINT}
			if _self_hook == "winch":
				_main.ropes.create("winch", mine, yours, span + 0.3)
			else:
				_main.ropes.create("strap", mine, yours, Ropes.STRAP_LEN)
			_say("%s's on - back in a sec" % ("strap" if _self_hook == "strap" else "winch hook"))
			_hook_step = "back"
			_hook_t = 0.0
		"back":
			if walk_to(person.door_spot(), false, 1.0) or _hook_t > 40.0:
				person.ai_move = Vector3.ZERO
				person.get_in()
				_hook_step = "in"


## After a pull we did ourselves: walk over, unhook, pack it away (the "done" phase
## then walks us back to the cab).
func _unhook(delta: float, lead: SandVehicle, rope: Dictionary) -> void:
	_hook_t += delta
	if in_car():
		_hook_t = 0.0
		if absf(car.speed_kmh) < 1.0 and not lead.is_bogged:
			person.get_out()
		return
	if person.state != PlayerCharacter.State.ON_FOOT:
		return
	var hitch := lead.global_transform * SandVehicle.REAR_POINT
	if not walk_to(hitch, false, 1.3) and _hook_t < 30.0:
		return
	person.ai_move = Vector3.ZERO
	_main.ropes.remove(rope["id"])
	_main.ropes.auto_in.erase(rope["id"])
	_say("all packed up - see ya on the beach!")
	_phase_t = 0.0


## Distance between the hooks we'd strap together: our bullbar to your tow hitch
## (helping from behind) or our tow hitch to your bullbar (from in front).
func _hook_span(lead: SandVehicle) -> float:
	if assist_side == "rear":
		return (car.global_transform * SandVehicle.FRONT_POINT).distance_to(lead.global_transform * SandVehicle.REAR_POINT)
	return (car.global_transform * SandVehicle.REAR_POINT).distance_to(lead.global_transform * SandVehicle.FRONT_POINT)


func _parked() -> void:
	_creeping = false
	driver.set_path(PackedVector3Array(), 0.0)
	_set_phase("ready")
	var lead := lead_car()
	var span := _hook_span(lead) if lead else 0.0
	if span > Ropes.STRAP_LEN - 0.3 and _self_hook == "":
		_say("can't get any closer - %.0f m between hooks, too far for the strap. Use the winch (reaches 35 m), or Helper > Winch me out" % span)
		return
	if _self_hook != "":
		return   # we're hooking up ourselves - no instructions needed
	_say("in position at your %s - hook the strap from my %s to your %s (or winch to me)" % [
		assist_side, "bullbar" if assist_side == "rear" else "tow hitch", "tow hitch" if assist_side == "rear" else "bullbar"])

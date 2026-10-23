class_name BotDriver
extends RefCounted
## Drives a SandVehicle along a path of world points (pure pursuit), for bots.
##
## - steers at a point a little way along the path, slows for corners and the end
## - stops for cars, people and camping gear in front; pulls out to pass if they don't move
## - tries to get itself unstuck: reverse and retry, air down, low range. Island bots
##   then give up (gave_up) and wait for someone to snatch or winch them out; the
##   helper (self_rescue) also digs out and, as a last resort, hops along the path.

var car: SandVehicle
var path := PackedVector3Array()
var speed := 10.0              ## cruising speed m/s
var arrive := 3.0              ## done within this distance of the last point
var done := true
var ignore: Array = []         ## nodes that never count as "in the way" (e.g. the car we're helping)
var ease_to_end := true        ## slow down for the last point (off when chasing a moving target)
var status := ""               ## for the debug label
var target := Vector3.ZERO     ## current steering point (debug)
var self_rescue := true        ## dig out / hop when properly stuck (helper). Off = give up.
var gave_up := false           ## tried everything: bogged, needs a strap or winch

var _idx := 0
var _stuck_t := 0.0
var _backing_t := 0.0
var _attempts := 0
var _progress_from := Vector3.ZERO
var _blocked_t := 0.0
var _pass_t := 0.0
var _pass_side := 1.0
var _back_steer := 0.0


func _init(c: SandVehicle) -> void:
	car = c


func set_path(pts: PackedVector3Array, cruise: float) -> void:
	path = pts
	speed = cruise
	_idx = 0
	done = pts.size() == 0


## Path following for one physics tick. Returns true once arrived.
func update(delta: float) -> bool:
	if done or path.size() == 0:
		stop(delta)
		return true
	if gave_up:
		stop(delta)
		status = "bogged - waiting for a snatch or winch"
		return false
	var pos := car.global_position
	var v := car.linear_velocity.dot(-car.global_basis.z)
	if _backing_t > 0.0:
		_back_out(delta)
		return false

	# closest point, only ever moving forwards along the path
	var best := _idx
	var bd := INF
	for k in range(_idx, mini(_idx + 30, path.size())):
		var d := _flat(path[k] - pos).length()
		if d < bd:
			bd = d
			best = k
	_idx = best
	var end := path[path.size() - 1]
	var to_end := _flat(end - pos).length()
	if to_end < arrive or (_idx >= path.size() - 1 and to_end < arrive * 3.0):
		done = true
		stop(delta)
		return true

	# look-ahead point
	var look := clampf(5.0 + absf(v) * 0.7, 6.0, 16.0)
	var acc := 0.0
	var k := _idx
	var aim := path[k]
	while k < path.size() - 1 and acc < look:
		acc += _flat(path[k + 1] - path[k]).length()
		k += 1
		aim = path[k]
	# pulling out to pass something parked in the way (Aussie rules: pass on the right)
	if _pass_t > 0.0:
		_pass_t -= delta
		var dir := _flat(aim - pos).normalized()
		var right := Vector3(-dir.z, 0, dir.x)
		aim += right * 6.0 * _pass_side
	target = aim

	var local := car.global_transform.affine_inverse() * aim
	var ang := atan2(-local.x, -local.z)
	var lim := car.max_steer / (1.0 + absf(v) / 14.0)
	_steer_to(clampf(ang * 1.4, -lim, lim), delta)

	var want := speed * clampf(1.0 - absf(ang) * 0.9, 0.3, 1.0)
	if ease_to_end:
		want = minf(want, 1.5 + to_end * 0.45)
	var gap := _obstacle_ahead()
	if _pass_t > 0.0:
		want = minf(want, 4.0)   # swinging out round it at a crawl (else we'd sit behind it forever)
		_blocked_t = 0.0
	elif gap < 14.0:
		want = minf(want, maxf((gap - 6.0) * 0.8, 0.0))
		_blocked_t += delta
		if _blocked_t > 3.0 and _pass_t <= 0.0:
			_pass_t = 6.0
			_pass_side = 1.0
			_blocked_t = 0.0
	else:
		_blocked_t = 0.0
	_drive_at(want, v, delta)
	status = "driving %d km/h -> %d m" % [roundi(v * 3.6), roundi(to_end)]
	if want < 0.5:
		status = "waiting - something in the way"
	_check_stuck(delta, want, v)
	return false


## Hold position: brakes, handbrake once stopped.
func stop(delta: float) -> void:
	car.reversing = false
	car.throttle = 0.0
	var v := absf(car.linear_velocity.dot(-car.global_basis.z))
	car.brake = 1.0
	car.handbrake = v < 0.8
	_steer_to(0.0, delta)
	_stuck_t = 0.0


## Straight-line pull (snatch) or a slow creep: direction +1 forward, -1 reverse.
func pull(dir: float, power: float, delta: float, steer := 0.0) -> void:
	car.handbrake = false
	car.brake = 0.0
	car.reversing = dir < 0.0
	car.low_range = false
	car.throttle = power
	_steer_to(steer, delta)


## Steering that points the front (forward) or the back (reversing) at a world point.
func steer_toward(p: Vector3, reverse: bool) -> float:
	var l := car.global_transform.affine_inverse() * p
	var ang := atan2(-l.x, l.z) if reverse else atan2(-l.x, -l.z)
	return clampf(ang * 1.5, -car.max_steer, car.max_steer)


func _steer_to(s: float, delta: float) -> void:
	car.steer = move_toward(car.steer, s, 2.2 * delta)


func _drive_at(want: float, v: float, _delta: float) -> void:
	car.reversing = false
	car.handbrake = false
	if want < 0.3:
		car.throttle = 0.0
		car.brake = 1.0
		car.handbrake = absf(v) < 0.5
		return
	if v < want:
		car.throttle = clampf((want - v) * 0.35 + 0.35, 0.0, 1.0)
		car.brake = 0.0
	elif v > want + 1.5:
		car.throttle = 0.0
		car.brake = clampf((v - want) * 0.15, 0.0, 0.8)
	else:
		car.throttle = 0.25
		car.brake = 0.0


## Distance to the nearest car / person / camp gear in our lane ahead (INF if clear).
func _obstacle_ahead() -> float:
	var main := car.get_tree().root.get_node_or_null("Main")
	if main == null:
		return INF
	var inv := car.global_transform.affine_inverse()
	var best := INF
	var things: Array = []
	for c in main.cars.get_children():
		if c != car and not ignore.has(c):
			things.append(c)
	for p in main.players.get_children():
		var pc := p as PlayerCharacter
		if pc and pc.is_on_foot():
			things.append(pc)
	for id in main.props.props:
		things.append(main.props.props[id])
	for t in things:
		var n := t as Node3D
		if n == null or ignore.has(n):
			continue
		var l := inv * n.global_position
		if l.z < -1.5 and l.z > -18.0 and absf(l.x) < 2.8:
			best = minf(best, -l.z - 2.4)
	return best


## Fresh start after being pulled out.
func reset_stuck() -> void:
	gave_up = false
	_attempts = 0
	_stuck_t = 0.0
	_backing_t = 0.0
	_progress_from = car.global_position


func _check_stuck(delta: float, want: float, v: float) -> void:
	if want > 1.0 and absf(v) < 0.4 and car.throttle > 0.3:
		_stuck_t += delta
	else:
		_stuck_t = maxf(_stuck_t - delta * 0.5, 0.0)
	if _progress_from.distance_to(car.global_position) > 40.0:
		_progress_from = car.global_position
		_attempts = 0
	if _stuck_t > 2.5:
		_stuck_t = 0.0
		_attempts += 1
		match _attempts:
			1:
				pass
			2:
				car.set_all_psi(15.0)
			3:
				car.set_all_psi(12.0)
				car.low_range = true
			4, 5 when not self_rescue:
				gave_up = true
				_attempts = 0
				stop(delta)
				return
			4, 5:
				# dig it out: shovel away the ruts so the next go works
				for w in car.wheels:
					w.dig = 0.0
					w.sink *= 0.3
			_:
				# properly stuck (tree, wall of sand): hop a little way on down the path
				_hop_ahead()
				_attempts = 0
				return
		_backing_t = 2.2
		_back_steer = -car.steer


func _hop_ahead() -> void:
	var k := mini(_idx + 6, path.size() - 1)
	var nxt := mini(k + 2, path.size() - 1)
	var dir := _flat(path[nxt] - path[k])
	if dir.length() < 0.1:
		dir = -car.global_basis.z
	car.teleport(path[k], dir.normalized())
	_idx = k
	_stuck_t = 0.0


func _back_out(delta: float) -> void:
	_backing_t -= delta
	status = "stuck - backing out (try %d)" % _attempts
	car.handbrake = false
	car.brake = 0.0
	car.reversing = true
	car.throttle = 0.8
	_steer_to(_back_steer, delta)
	if _backing_t <= 0.0:
		car.reversing = false
		car.throttle = 0.0


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)

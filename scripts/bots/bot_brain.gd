class_name BotBrain
extends Node
## Runs one bot: its ute (through a BotDriver) and its driver (a PlayerCharacter in
## `ai` mode). Only exists on the machine that spawned the bot.
##
## Behaviour is a queue of simple steps - {"do": "drive", ...}, {"do": "walk", ...} -
## worked through one at a time. When the queue runs dry, plan_next() refills it.

var bots: Bots
var role := ""
var display := ""
var style := "blocky"
var colour_i := 0
var car: SandVehicle
var person: PlayerCharacter
var driver: BotDriver
var island: IslandData
var plan: Array[Dictionary] = []
var camp_ids: Array[String] = []   ## camping gear this bot has put out
var _main: Node
var _label: Label3D
var _walk_check_t := 0.0
var _walk_check_pos := Vector3.ZERO
var _side_step_t := 0.0


func setup(b: Bots, r: String, c: SandVehicle, p: PlayerCharacter, who: String, st: String, ci: int) -> void:
	bots = b
	role = r
	car = c
	person = p
	display = who
	style = st
	colour_i = ci


func _ready() -> void:
	island = IslandData.instance
	_main = get_tree().root.get_node("Main")
	driver = BotDriver.new(car)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 40
	_label.pixel_size = 0.008
	_label.outline_size = 12
	_label.modulate = Color(1.0, 1.0, 0.75)
	_label.position = Vector3(0, 3.4, 0)
	_label.visible = false
	car.add_child(_label)


## Clear up anything this bot put into the world.
func cleanup() -> void:
	for id in camp_ids:
		_main.props.remove(id)
	camp_ids.clear()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(car) or not is_instance_valid(person):
		queue_free()
		return
	if person._bonk != 0 or person.is_down() or person.is_tied():
		# sent flying by a ute or out cold: nothing happens till we're back on our feet
		person.ai_move = Vector3.ZERO
		if in_car():
			driver.stop(delta)
		return
	think(delta)
	_label.visible = bots.debug
	if bots.debug:
		_label.text = debug_text()


func debug_text() -> String:
	var step := String(plan[0]["do"]) if not plan.is_empty() else "-"
	return "%s  (%s)\n%s\n%s" % [display, role, step, driver.status if step == "drive" else ""]


## Default behaviour: work through the plan.
func think(delta: float) -> void:
	if plan.is_empty():
		plan_next()
	if plan.is_empty():
		return
	var st: Dictionary = plan[0]
	st["_t"] = float(st.get("_t", -delta)) + delta
	if run_step(st, delta):
		plan.pop_front()
		person.ai_move = Vector3.ZERO
		person.ai_run = false
		person.pose_override = ""


## Override: queue up the next thing to do.
func plan_next() -> void:
	plan.append({"do": "wait", "t": 2.0})


func in_car() -> bool:
	return person.state == PlayerCharacter.State.IN_CAR


## One step; true once it's finished.
func run_step(st: Dictionary, delta: float) -> bool:
	var t: float = st["_t"]
	match String(st["do"]):
		"drive":
			if not in_car():
				driver.stop(delta)
				return false
			if not st.has("path"):
				var mk: Callable = st.get("make", Callable())
				st["path"] = mk.call() if mk.is_valid() else PackedVector3Array()
				driver.set_path(st["path"], float(st.get("speed", 11.0)))
				driver.arrive = float(st.get("arrive", 3.0))
				car.low_range = bool(st.get("low", false))
			if t > float(st.get("timeout", 300.0)):
				return true
			return driver.update(delta)
		"park":
			driver.stop(delta)
			return absf(car.speed_kmh) < 1.0 and t > 0.4
		"get_out":
			driver.stop(delta)
			if in_car() and absf(car.speed_kmh) < 3.0:
				person.get_out()
			return person.state == PlayerCharacter.State.ON_FOOT
		"get_in":
			if in_car():
				return true
			if person.state == PlayerCharacter.State.SITTING:
				person.stand_up()
			if person.state == PlayerCharacter.State.ON_FOOT:
				if walk_to(person.door_spot(), false, 1.0) or t > 40.0:
					person.ai_move = Vector3.ZERO
					person.get_in()
			return false
		"walk":
			return walk_to(st["to"], bool(st.get("run", false)), float(st.get("within", 0.8))) or t > float(st.get("timeout", 30.0))
		"face":
			var d: Vector3 = st["dir"]
			person._yaw = lerp_angle(person._yaw, atan2(-d.x, -d.z), minf(1.0, 8.0 * delta))
			return t > 0.4
		"wait":
			person.pose_override = String(st.get("pose", ""))
			return t >= float(st["t"])
		"select":
			person.tools.select(int(st["slot"]))
			return true
		"cast":
			var tools := person.tools
			if t < 1.0:
				tools._fish = "charging"
				tools.charge = t
				person.pose_override = "wind"
				return false
			if tools._fish == "charging":
				tools._cast(float(st.get("power", 0.8)))
			person.pose_override = "throw" if t < 1.4 else "hold"
			return tools._fish == "out" or t > 6.0
		"reel":
			var tools := person.tools
			if not st.has("started"):
				st["started"] = true
				tools._start_reel()
				person.rpc_reel()
			person.pose_override = "reel"
			if t > 15.0:
				tools._end_fishing()
			return tools._fish == "idle"
		"place":
			person.pose_override = "dig"
			if t < 0.7:
				return false
			camp_ids.append(_main.props.place(String(st["kind"]), st["xf"]))
			return true
		"pick_up":
			person.pose_override = "dig"
			if t < 0.5:
				return false
			var id := String(st["id"])
			_main.props.remove(id)
			camp_ids.erase(id)
			return true
		"sit":
			var node: Node3D = _main.props.props.get(String(st["id"]))
			if node == null:
				return true
			var seat: Transform3D = node.global_transform * (node.get_meta("seat") as Transform3D)
			seat.origin.y -= person.avatar.hip_height() - 0.02
			person.sit(seat, String(st["id"]))
			return true
		"stand":
			person.stand_up()
			return true
	return true


## Walk the driver toward p (flat distance). True once there.
## Goes round our own ute rather than into it, and side-steps if something's in the way.
func walk_to(p: Vector3, run := false, within := 0.8) -> bool:
	var me := person.global_position
	var d := Vector3(p.x - me.x, 0.0, p.z - me.z)
	if d.length() < within:
		person.ai_move = Vector3.ZERO
		return true
	var aim := _round_the_ute(p)
	var dir := Vector3(aim.x - me.x, 0.0, aim.z - me.z).normalized()
	# not getting anywhere? step sideways for a moment
	_walk_check_t += get_physics_process_delta_time()
	if _walk_check_t > 1.5:
		if me.distance_to(_walk_check_pos) < 0.5:
			_side_step_t = 0.8
		_walk_check_t = 0.0
		_walk_check_pos = me
	if _side_step_t > 0.0:
		_side_step_t -= get_physics_process_delta_time()
		dir = (dir + Vector3(-dir.z, 0.0, dir.x) * 1.5).normalized()
	person.ai_move = dir * (1.0 if d.length() > 1.5 else 0.6)
	person.ai_run = run
	return false


## Next point to walk to so we don't walk through our own ute: round the nearer end.
func _round_the_ute(p: Vector3) -> Vector3:
	var inv := car.global_transform.affine_inverse()
	var a := inv * person.global_position
	var b := inv * p
	const HALF := 3.3
	if absf(a.z) > HALF or absf(a.x) < 1.0 or signf(a.x) == signf(b.x) or (absf(b.z) > HALF and signf(b.z) == signf(a.z)):
		return p
	var zend := HALF + 0.5 if (a.z + b.z) >= 0.0 else -HALF - 0.5
	if absf(a.z - zend) > 0.6:
		return car.global_transform * Vector3(signf(a.x) * 1.8, 0.0, zend)
	return car.global_transform * Vector3(signf(b.x) * 1.8, 0.0, zend)


## The water's edge straight out to sea (east) from p.
func water_edge(p: Vector3) -> Vector3:
	var x := p.x
	for k in 80:
		var h := island.height_at(x, p.z)
		if h < island.water_level_at(x, p.z) + 0.12:
			break
		x += 1.0
	x -= 1.2
	return Vector3(x, island.height_at(x, p.z), p.z)

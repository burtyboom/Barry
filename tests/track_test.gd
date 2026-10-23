extends SceneTree
## Autopilot drives a named track at several tyre pressures.
## godot --headless --path . -s res://tests/track_test.gd -- "Eurong - Central Station"

var island: IslandData
var world: WorldBuilder
var car: SandVehicle
var root3d: Node3D
var path: PackedVector2Array
var runs := [32.0, 18.0, 15.0, 12.0]
var run := -1
var t := 0.0
var idx := 0
var log_t := 0.0
var track_name := "Eurong - Central Station"
var max_t := 120.0
var target_kmh := 30.0
var bog_time := 0.0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		track_name = args[0]
	if args.size() > 1:
		target_kmh = float(args[1])
	island = IslandData.make("fraser")
	island.generate()
	root3d = Node3D.new()
	get_root().add_child(root3d)

func _start() -> void:
	world = WorldBuilder.new()
	root3d.add_child(world)
	world.build(island)
	for tb in island.tracks_built:
		if tb["name"] == track_name:
			path = tb["path"]
	car = SandVehicle.new()
	car.scripted = true
	root3d.add_child(car)

func _next() -> void:
	run += 1
	if run >= runs.size():
		quit()
		return
	car.set_all_psi(runs[run])
	var p0 := Vector3(path[0].x, 0, path[0].y)
	var p1 := Vector3(path[5].x, 0, path[5].y)
	car.teleport(p0, (p1 - p0).normalized())
	t = 0.0
	idx = 0
	bog_time = 0.0
	car.low_range = false
	print("\n=== %s @ %d psi (path %d pts, %.0f m)" % [track_name, runs[run], path.size(), path.size() * 2.0])

func _physics_process(delta: float) -> bool:
	if run == -1:
		if car == null:
			_start()
			return false
		_next()
		return false
	if run >= runs.size():
		return true
	t += delta
	var pos := car.global_position
	var p2 := Vector2(pos.x, pos.z)
	# advance along path
	while idx < path.size() - 1 and path[idx].distance_to(p2) < 8.0:
		idx += 1
	var la := path[mini(idx + 2, path.size() - 1)]
	var to := Vector3(la.x - pos.x, 0, la.y - pos.z).normalized()
	var fwd := -car.global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var ang := fwd.signed_angle_to(to, Vector3.UP)
	car.steer = clampf(ang * 1.5, -car.max_steer, car.max_steer)
	var err := target_kmh - car.speed_kmh
	car.throttle = clampf(err / 10.0, 0.0, 1.0)
	car.brake = clampf(-err / 10.0, 0.0, 1.0)
	if car.is_bogged:
		bog_time += delta
	log_t += delta
	if log_t > 5.0:
		log_t = 0.0
		print("t=%5.1f idx=%4d/%d v=%5.1f soft=%.2f sink=%.2f slip=%.2f h=%.1f bog=%s" % [t, idx, path.size(), car.speed_kmh, car.avg_soft, car.avg_sink, car.wheels[2].slip, pos.y, car.is_bogged])
	var done := idx >= path.size() - 2
	if done or t > max_t or bog_time > 8.0:
		print("RESULT: %s  t=%.1fs  progress=%d%%" % ["FINISHED" if done else ("BOGGED" if bog_time > 8.0 else "TIMEOUT"), t, 100 * idx / path.size()])
		_next()
	return false

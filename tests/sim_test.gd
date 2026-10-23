extends SceneTree
## Headless physics test:  godot --headless --path . -s res://tests/sim_test.gd

var island: IslandData
var world: WorldBuilder
var car: SandVehicle
var frame := 0
var scenarios := []
var cur := -1
var t := 0.0
var start_pos := Vector3.ZERO
var log_t := 0.0

func _initialize() -> void:
	island = IslandData.make("fraser")
	island.generate()
	var root3d := Node3D.new()
	get_root().add_child(root3d)
	world = WorldBuilder.new()
	root3d.add_child(world)
	world.build(island)
	car = SandVehicle.new()
	car.local_control = true
	car.scripted = true
	root3d.add_child(car)
	# flat-ish wet beach spot at f=0.20
	scenarios = [
		{"name": "settle hard 32psi", "soft": 0.05, "psi": 32, "thr": 0.0, "dur": 3.0, "low": false},
		{"name": "accel hard 32psi", "soft": 0.05, "psi": 32, "thr": 1.0, "dur": 12.0, "low": false},
		{"name": "soft0.75 32psi full", "soft": 0.75, "psi": 32, "thr": 1.0, "dur": 10.0, "low": false},
		{"name": "soft0.75 18psi full", "soft": 0.75, "psi": 18, "thr": 1.0, "dur": 10.0, "low": false},
		{"name": "soft0.75 32psi gentle", "soft": 0.75, "psi": 32, "thr": 0.35, "dur": 10.0, "low": false},
		{"name": "soft0.95 32psi full", "soft": 0.95, "psi": 32, "thr": 1.0, "dur": 10.0, "low": false},
		{"name": "soft0.95 18psi full", "soft": 0.95, "psi": 18, "thr": 1.0, "dur": 10.0, "low": false},
		{"name": "soft0.95 15psi full", "soft": 0.95, "psi": 15, "thr": 1.0, "dur": 10.0, "low": false},
		{"name": "soft0.95 15psi gentle", "soft": 0.95, "psi": 15, "thr": 0.45, "dur": 10.0, "low": false},
		{"name": "soft0.95 18psi 4L 0.5", "soft": 0.95, "psi": 18, "thr": 0.5, "dur": 10.0, "low": true},
		{"name": "soft1.0 32psi full", "soft": 1.0, "psi": 32, "thr": 1.0, "dur": 6.0, "low": false},
		{"name": "soft1.0 18psi full", "soft": 1.0, "psi": 18, "thr": 1.0, "dur": 8.0, "low": false},
		{"name": "soft1.0 15psi full", "soft": 1.0, "psi": 15, "thr": 1.0, "dur": 8.0, "low": false},
		{"name": "soft0.8 32psi full", "soft": 0.8, "psi": 32, "thr": 1.0, "dur": 8.0, "low": false},
		{"name": "soft0.6 32psi full", "soft": 0.6, "psi": 32, "thr": 1.0, "dur": 6.0, "low": false},
	]

func _place() -> void:
	var f := 0.20
	var x := island.east_base(f) - 25.0
	car.teleport(Vector3(x, 0, island.f_to_z(f)), Vector3.FORWARD)
	start_pos = car.global_position

func _next() -> void:
	cur += 1
	if cur >= scenarios.size():
		quit()
		return
	var s: Dictionary = scenarios[cur]
	island.force_soft = s["soft"]
	car.set_all_psi(s["psi"])
	car.low_range = s["low"]
	car.throttle = 0.0
	_place()
	t = 0.0
	log_t = 0.0
	print("\n=== ", s["name"])

func _physics_process(delta: float) -> bool:
	if cur == -1:
		_next()
		return false
	if cur >= scenarios.size():
		return true
	var s: Dictionary = scenarios[cur]
	t += delta
	# let it settle 1.5s before throttle
	car.throttle = s["thr"] if t > 1.5 else 0.0
	car.steer = 0.0
	log_t += delta
	if log_t >= 1.0:
		log_t = 0.0
		var d := Vector2(car.global_position.x - start_pos.x, car.global_position.z - start_pos.z).length()
		var w := car.wheels[2]
		print("t=%4.1f v=%5.1fkm/h dist=%6.1f sink=%.3f dig=%.3f rr=%.3f mu=%.2f slip=%.2f load=%.0f y=%.2f bog=%s" % [t, car.speed_kmh, d, w.sink, w.dig, w.rr, w.mu, w.slip, w.load, car.global_position.y, car.is_bogged])
	if t >= s["dur"]:
		_next()
	return false

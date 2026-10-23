class_name ChaseCamera
extends Camera3D
## C cycles: Chase -> Low wheel cam -> Bonnet. Hold right mouse to orbit, wheel to zoom.
## The orbit stays wherever you leave it (it turns with the ute); C puts it back behind.
## On foot it's a free third-person camera: right-drag to look around (it stays where you put it).

var target: Node3D
var mode := 0
var distance := 8.0
var height := 3.0
var _yaw := 0.0
var _orbit_yaw := 0.0
var _orbit_pitch := 0.0
var _orbiting := false
var _foot := false
var _foot_yaw := 0.0
var _foot_pitch := 0.25
var _foot_dist := 5.0


func _ready() -> void:
	far = 5000.0
	near = 0.1
	fov = 70.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera"):
		mode = (mode + 1) % 3
		_orbit_yaw = 0.0
		_orbit_pitch = 0.0
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			distance = maxf(distance - 0.8, 3.5)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			distance = minf(distance + 0.8, 40.0)
	elif event is InputEventMouseMotion and _orbiting and _foot:
		var fm := event as InputEventMouseMotion
		_foot_yaw -= fm.relative.x * 0.006
		_foot_pitch = clampf(_foot_pitch + fm.relative.y * 0.004, -0.2, 1.1)   # inverted Y, like the car cam
	elif event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_orbit_yaw -= mm.relative.x * 0.006
		_orbit_pitch = clampf(_orbit_pitch + mm.relative.y * 0.004, -0.5, 1.2)   # inverted Y


## Switch between the car chase cam and the on-foot camera (starts behind the ute).
func set_foot_mode(on: bool, car: Node3D) -> void:
	_foot = on
	if on and car:
		var f := -car.global_basis.z
		_foot_yaw = atan2(-f.x, -f.z) - PI * 0.5   # looking at the driver's door side
		_foot_pitch = 0.25


func _physics_process(delta: float) -> void:
	if target == null:
		return
	if _foot:
		_foot_yaw -= (Input.get_action_strength("look_right") - Input.get_action_strength("look_left")) * 2.2 * delta
		var tpf := target.global_position + Vector3.UP * 1.4
		var back := Vector3(sin(_foot_yaw), 0, cos(_foot_yaw))
		var wantf := tpf + back * _foot_dist * cos(_foot_pitch) + Vector3.UP * _foot_dist * sin(_foot_pitch)
		var groundf := IslandData.instance.height_at(wantf.x, wantf.z) + 0.5
		wantf.y = maxf(wantf.y, groundf)
		global_position = global_position.lerp(wantf, minf(1.0, 10.0 * delta))
		look_at(tpf, Vector3.UP)
		return
	var tb := target.global_basis
	var fwd := -tb.z
	var flat := Vector3(fwd.x, 0, fwd.z)
	var want_yaw := atan2(-flat.x, -flat.z) if flat.length() > 0.2 else _yaw
	_yaw = lerp_angle(_yaw, want_yaw, minf(1.0, 3.0 * delta))
	var tp := target.global_position
	match mode:
		0:
			var yaw := _yaw + _orbit_yaw
			var back := Vector3(sin(yaw), 0, cos(yaw))
			var h := height + _orbit_pitch * distance * 0.8
			var want := tp + back * distance + Vector3.UP * h
			var ground := IslandData.instance.height_at(want.x, want.z) + 0.8
			want.y = maxf(want.y, ground)
			global_position = global_position.lerp(want, minf(1.0, 8.0 * delta))
			look_at(tp + Vector3.UP * 1.0, Vector3.UP)
		1:
			# low cam beside the front-left wheel - good for watching sinkage
			var pos := target.global_transform * Vector3(-2.6, -0.2, -2.2)
			global_position = pos
			look_at(target.global_transform * Vector3(-0.8, -0.5, -0.8), Vector3.UP)
		2:
			global_position = target.global_transform * Vector3(0, 1.35, -1.3)
			look_at(target.global_transform * Vector3(0, 1.0, -12.0), tb.y)

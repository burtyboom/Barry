class_name Ambience
extends Node3D
## Background sounds around the listener: surf that swells as you get near the water,
## seagulls over the beach, kookaburras cackling in the bush, and a soft breeze.

var island: IslandData
var _surf: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _gull_t := 4.0
var _kooka_t := 25.0


func _ready() -> void:
	island = IslandData.instance
	_surf = _loop("surf")
	_wind = _loop("wind")


func _loop(kind: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = Sfx.get_stream(kind)
	p.volume_db = -60.0
	p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
	add_child(p)
	p.play()
	return p


## Metres from p to the nearest open sea (east or west coast).
func _to_sea(p: Vector3) -> float:
	var f := island.z_to_f(p.z)
	return maxf(minf(island.east_x(f) - p.x, p.x - island.west_x(f)), 0.0)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or island == null:
		return
	var p := cam.global_position
	var sea := _to_sea(p)
	var near := clampf(1.0 - sea / 260.0, 0.0, 1.0)
	_surf.volume_db = move_toward(_surf.volume_db, lerpf(-42.0, -9.0, near * near), delta * 20.0)
	_wind.volume_db = move_toward(_wind.volume_db, -24.0, delta * 10.0)
	# a gull now and then over the beach
	_gull_t -= delta
	if _gull_t <= 0.0:
		_gull_t = randf_range(5.0, 16.0)
		if sea < 120.0:
			var a := randf() * TAU
			var q := p + Vector3(cos(a) * 25.0, 12.0, sin(a) * 25.0)
			var n := randi_range(1, 3)
			for k in n:
				get_tree().create_timer(k * randf_range(0.35, 0.7)).timeout.connect(func() -> void:
					Sfx.play_at(self, "gull", q, -6.0, randf_range(0.85, 1.2)))
	# kookaburras live in the bush
	_kooka_t -= delta
	if _kooka_t <= 0.0:
		_kooka_t = randf_range(35.0, 80.0)
		if sea > 140.0:
			var a2 := randf() * TAU
			Sfx.play_at(self, "kooka", p + Vector3(cos(a2) * 30.0, 8.0, sin(a2) * 30.0), 2.0, randf_range(0.92, 1.08))

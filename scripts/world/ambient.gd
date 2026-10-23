class_name Ambient
extends RefCounted
## Island life that just plays on its own (not synced between players):
## a scenic plane that lands on the beach, and dolphins leaping in the bay.


## A little high-wing scenic flight plane. Circles in, lands on the hard sand,
## taxis to a stop, waits, then takes off and flies away. Repeats.
class BeachPlane extends Node3D:
	var island: IslandData
	var touchdown := Vector3.ZERO   ## where the wheels meet the sand
	var dir := Vector3(0, 0, -1)    ## landing direction (along the beach)
	var _t := 0.0
	var _prop: Node3D
	const CYCLE := 150.0

	func _ready() -> void:
		_build()

	func _build() -> void:
		var white := Color(0.97, 0.97, 0.95)
		var stripe := Color(0.15, 0.40, 0.85)
		var body := Node3D.new()
		add_child(body)
		Toon.box(body, Vector3(1.1, 1.1, 5.2), Vector3(0, 1.3, 0), white)                 # fuselage
		Toon.box(body, Vector3(1.12, 0.25, 5.0), Vector3(0, 1.1, 0.05), stripe)
		Toon.box(body, Vector3(9.0, 0.14, 1.3), Vector3(0, 2.0, -0.6), white)              # high wing
		Toon.box(body, Vector3(3.2, 0.1, 0.8), Vector3(0, 1.5, 2.4), white)                # tailplane
		Toon.box(body, Vector3(0.12, 1.2, 0.9), Vector3(0, 2.0, 2.4), stripe)              # fin
		Toon.box(body, Vector3(1.0, 0.5, 1.2), Vector3(0, 1.7, -1.1), Color(0.3, 0.55, 0.8))   # windows
		for x in [-0.8, 0.8]:
			Toon.box(body, Vector3(0.08, 0.9, 0.08), Vector3(x, 0.55, -0.6), Color(0.3, 0.3, 0.32))
			Toon.cyl_x(body, 0.22, 0.14, 16, Vector3(x, 0.15, -0.6), Color(0.12, 0.12, 0.12))
		Toon.cyl_x(body, 0.18, 0.12, 16, Vector3(0, 0.25, -2.3), Color(0.12, 0.12, 0.12))   # nose wheel
		_prop = Node3D.new()
		_prop.position = Vector3(0, 1.3, -2.75)
		body.add_child(_prop)
		Toon.box(_prop, Vector3(2.0, 0.18, 0.06), Vector3.ZERO, Color(0.15, 0.15, 0.16))

	func _process(delta: float) -> void:
		_t = fmod(_t + delta, CYCLE)
		_prop.rotation.z += delta * 40.0
		var side := dir.cross(Vector3.UP)
		var pos := Vector3.ZERO
		var pitch := 0.0
		var t := _t
		# 0-22 s approach and flare, 22-32 rollout, 32-62 parked, 62-74 takeoff roll + climb, then away
		if t < 22.0:
			var k := t / 22.0
			var back := (1.0 - k) * 600.0
			pos = touchdown - dir * back + Vector3.UP * (pow(1.0 - k, 1.6) * 60.0)
			pitch = -0.08 * (1.0 - k) + 0.06 * smoothstep(0.85, 1.0, k)
		elif t < 32.0:
			var k := (t - 22.0) / 10.0
			pos = touchdown + dir * (60.0 * (1.0 - (1.0 - k) * (1.0 - k)))
		elif t < 62.0:
			pos = touchdown + dir * 60.0
			_prop.rotation.z -= delta * 30.0    # idling slower
		elif t < 74.0:
			var k := (t - 62.0) / 12.0
			pos = touchdown + dir * (60.0 + 300.0 * k * k) + Vector3.UP * maxf(0.0, (k - 0.55)) * 70.0
			pitch = 0.18 * smoothstep(0.5, 0.7, k)
		else:
			var k := (t - 74.0) / (CYCLE - 74.0)
			pos = touchdown + dir * (360.0 + 900.0 * k) + Vector3.UP * (31.0 + 120.0 * k) + side * 200.0 * k * k
			pitch = 0.1
		if t >= 22.0 and t < 74.0:
			pos.y = maxf(pos.y, island.height_at(pos.x, pos.z))
		global_position = pos
		global_basis = Basis(Vector3.UP, atan2(-dir.x, -dir.z)) * Basis(Vector3.RIGHT, pitch)
		visible = t < CYCLE - 8.0


## A couple of dolphins arcing out of the water now and then.
class Dolphins extends Node3D:
	var island: IslandData
	var _pods: Array[Node3D] = []
	var _phase: Array[float] = []

	func _ready() -> void:
		for k in 3:
			var d := Node3D.new()
			add_child(d)
			var grey := Color(0.45, 0.52, 0.60)
			var mi := MeshInstance3D.new()
			var cm := CapsuleMesh.new()
			cm.radius = 0.32
			cm.height = 2.2
			mi.mesh = cm
			mi.material_override = Toon.mat(grey)
			mi.rotation_degrees = Vector3(90, 0, 0)
			d.add_child(mi)
			Toon.box(d, Vector3(0.06, 0.4, 0.35), Vector3(0, 0.38, 0.1), grey.darkened(0.1), true, Vector3(-25, 0, 0))   # dorsal fin
			Toon.box(d, Vector3(0.7, 0.06, 0.25), Vector3(0, 0, 1.15), grey.darkened(0.1))                             # tail flukes
			Toon.box(d, Vector3(0.12, 0.08, 0.3), Vector3(0, -0.05, -1.2), grey.lightened(0.2))                          # beak
			_pods.append(d)
			_phase.append(k * 2.3)

	func _process(delta: float) -> void:
		for k in _pods.size():
			_phase[k] += delta
			var cycle := 7.0
			var t := fmod(_phase[k], cycle)
			var d := _pods[k]
			var lane := Vector3(k * 6.0 - 6.0, 0, sin(_phase[k] * 0.1 + k) * 30.0)
			if t < 1.6:
				# leap: an arc out of the water
				var u := t / 1.6
				var along := (u - 0.5) * 5.0
				d.position = lane + Vector3(0, Tide.level + sin(u * PI) * 1.8 - 0.3, along)
				# swims toward +Z, so turn it round (beak is modelled at -Z); nose up out, down in
				d.rotation = Vector3(cos(u * PI) * 0.9, PI, 0)
				d.visible = true
			else:
				d.visible = false

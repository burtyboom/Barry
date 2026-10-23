class_name FlameFlicker
extends Node
## Wobbles campfire flames and their light so the fire feels alive.

var flames: Node3D
var light: OmniLight3D
var _t := randf() * 10.0


func _process(delta: float) -> void:
	_t += delta
	if flames:
		var k := 1.0 + sin(_t * 9.0) * 0.08 + sin(_t * 23.0) * 0.05
		flames.scale = Vector3(1.0 + sin(_t * 7.0) * 0.06, k, 1.0 + cos(_t * 8.0) * 0.06)
		flames.rotation.y = sin(_t * 1.3) * 0.4
	if light:
		light.light_energy = 2.0 + sin(_t * 11.0) * 0.35 + sin(_t * 27.0) * 0.2

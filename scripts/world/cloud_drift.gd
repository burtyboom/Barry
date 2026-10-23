extends Node3D
## Lazily drifts the cartoon clouds across the sky and wraps them around.

func _process(delta: float) -> void:
	for c in get_children():
		var n := c as Node3D
		n.position.x += 3.0 * delta
		n.position.z -= 1.0 * delta
		if n.position.x > 1000.0:
			n.position.x = -1000.0
		if n.position.z < -2400.0:
			n.position.z = 2400.0

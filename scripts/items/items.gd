class_name Items
extends RefCounted
## The hotbar (keys 1-9, 0, - or mouse wheel while on foot). Pressing the key of the
## thing you're holding puts it away (slot -1 = empty hands).
## kind "prop" items are placed in the world; "tool" items are held and used.
## The winch remote (last slot) only shows up while your winch is hooked on.

const LIST := [
	{"id": "rod", "name": "Fishing rod", "short": "Rod", "kind": "tool", "color": Color(0.30, 0.60, 0.95)},
	{"id": "strap", "name": "Snatch strap", "short": "Strap", "kind": "tool", "color": Color(0.95, 0.75, 0.10)},
	{"id": "inflator", "name": "Tyre inflator", "short": "Air up", "kind": "tool", "color": Color(0.25, 0.75, 0.35)},
	{"id": "deflators", "name": "Deflators", "short": "Air down", "kind": "tool", "color": Color(0.80, 0.55, 0.20)},
	{"id": "shovel", "name": "Shovel", "short": "Shovel", "kind": "tool", "color": Color(0.60, 0.42, 0.25)},
	{"id": "chair", "name": "Camp chair", "short": "Chair", "kind": "prop", "color": Color(0.20, 0.55, 0.85)},
	{"id": "fire", "name": "Campfire", "short": "Fire", "kind": "prop", "color": Color(0.95, 0.40, 0.10)},
	{"id": "tent", "name": "Tent", "short": "Tent", "kind": "prop", "color": Color(0.35, 0.75, 0.30)},
	{"id": "esky", "name": "Esky", "short": "Esky", "kind": "prop", "color": Color(0.20, 0.45, 0.85)},
	{"id": "umbrella", "name": "Beach umbrella", "short": "Brolly", "kind": "prop", "color": Color(0.90, 0.25, 0.30)},
	{"id": "remote", "name": "Winch remote", "short": "Winch", "kind": "tool", "color": Color(0.85, 0.15, 0.10)},
]
const REMOTE := 10              ## slot of the winch remote
const EMPTY := {"id": "", "name": "Nothing", "short": "", "kind": "none", "color": Color.WHITE}


## A model of the item for the hotbar icon.
static func icon_model(id: String) -> Node3D:
	var n := Node3D.new()
	match id:
		"rod":
			var rod := Node3D.new()
			rod.rotation_degrees = Vector3(0, 0, -50)
			n.add_child(rod)
			Props._cyl(rod, 0.02, 0.045, 2.0, Vector3(0, 1.0, 0), Color(0.15, 0.15, 0.16))
			Props._cyl(rod, 0.05, 0.05, 0.35, Vector3(0, 0.1, 0), Color(0.55, 0.35, 0.2))
			Props._cyl(rod, 0.11, 0.11, 0.08, Vector3(0.09, 0.32, 0), Color(0.75, 0.75, 0.78), Vector3(0, 0, 90))
		"strap":
			for k in 3:
				Props._cyl(n, 0.32 - k * 0.07, 0.32 - k * 0.07, 0.12, Vector3(0, k * 0.02, 0), Color(0.98, 0.80, 0.10).darkened(k * 0.08))
			Toon.box(n, Vector3(0.1, 0.06, 0.32), Vector3(0.36, 0.0, 0), Color(0.98, 0.80, 0.10))
		"inflator":
			Toon.box(n, Vector3(0.45, 0.3, 0.3), Vector3(0, 0.15, 0), Color(0.15, 0.15, 0.17))
			Props._cyl(n, 0.11, 0.11, 0.06, Vector3(0, 0.33, 0), Color(0.85, 0.15, 0.12))
			Props._cyl(n, 0.05, 0.05, 0.06, Vector3(0.12, 0.33, 0.06), Color(0.9, 0.9, 0.9))
			Props._cyl(n, 0.02, 0.02, 0.6, Vector3(0.35, 0.1, 0), Color(0.08, 0.08, 0.09), Vector3(0, 0, 70))
		"deflators":
			for k in 4:
				Props._cyl(n, 0.06, 0.06, 0.2, Vector3(-0.21 + k * 0.14, 0.1, 0), Color(0.85, 0.65, 0.20))
				Props._cyl(n, 0.035, 0.035, 0.05, Vector3(-0.21 + k * 0.14, 0.22, 0), Color(0.75, 0.75, 0.78))
		"remote":
			Toon.box(n, Vector3(0.22, 0.42, 0.10), Vector3(0, 0.21, 0), Color(0.15, 0.15, 0.17))
			Props._cyl(n, 0.06, 0.06, 0.04, Vector3(0, 0.30, -0.06), Color(0.3, 0.85, 0.3), Vector3(90, 0, 0))
			Props._cyl(n, 0.06, 0.06, 0.04, Vector3(0, 0.13, -0.06), Color(0.9, 0.2, 0.15), Vector3(90, 0, 0))
			Props._cyl(n, 0.012, 0.012, 0.6, Vector3(0, -0.25, 0), Color(0.08, 0.08, 0.09))
		"shovel":
			var sh := Node3D.new()
			sh.rotation_degrees = Vector3(0, 0, 40)
			n.add_child(sh)
			Props._cyl(sh, 0.035, 0.035, 1.2, Vector3(0, 0.6, 0), Color(0.6, 0.42, 0.25))
			Toon.box(sh, Vector3(0.3, 0.38, 0.04), Vector3(0, -0.15, 0), Color(0.62, 0.64, 0.68))
			Toon.box(sh, Vector3(0.24, 0.05, 0.05), Vector3(0, 1.22, 0), Color(0.15, 0.15, 0.16))
		_:
			var prop := Props.build(id, false)
			for c in prop.get_children():
				if c is CollisionShape3D:
					c.queue_free()
			n.add_child(prop)
	return n


static func get_item(slot: int) -> Dictionary:
	if slot < 0 or slot >= LIST.size():
		return EMPTY
	return LIST[slot]

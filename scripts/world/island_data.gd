class_name IslandData
extends RefCounted
## Deterministic, scaled-down sand island. This is the generic generator;
## each island (FraserIsland, MoretonIsland) fills in its shape in _define().
## North is -Z (Godot "forward"), south is +Z, east (surf beach) is +X.
##
## Everything is generated from a fixed seed so every player in a multiplayer
## session builds exactly the same island without sending it over the network.
##
## Grids (row-major, x fastest):
##   heights    - terrain height in metres (sea level = 0)
##   soft       - sand softness 0 (hard / rock) .. 1 (bottomless sugar sand)
##   surf       - Surface enum per cell (used for colour + grip)
##   track      - 0..1 how much this cell is a driving track
##   track_dist - distance to nearest track centreline (capped), for tree clearing

enum Surface { OCEAN, WET_SAND, DRY_SAND, SOFT_DUNE, TRACK, FOREST, ROCK, LAKE_BED, LAKE_SAND, WEST_FLATS, COLOURED_SAND }

const SURFACE_NAMES := [
	"Sea floor", "Hard wet sand", "Dry beach sand", "Soft dune sand", "Sand track",
	"Bush", "Rock", "Lake bed", "Silica sand", "Tidal flats", "Coloured sands",
]

const CELL := 2.5

# ---------------------------------------------------------------- island definition
# Set by each island's _define() (see FraserIsland / MoretonIsland).
# f runs 0 (south tip) .. 1 (north tip) along the island; x is east-west.
var id := ""
var display_name := ""
var x_min := 0.0
var z_min := 0.0
var cols := 0
var rows := 0
var south_z := 0.0                 ## z of f = 0
var length := 1.0                  ## z distance from f = 0 to f = 1
var seed := 0

## East coast (surf beach) and west coast as (f, x) control points.
var east: Array = []
var west: Array = []
## Rocky headlands on the east beach:
## [name, f, coast bulge m, bulge width (f), rock radius, rock height, rock x offset from coast]
var headlands: Array = []
## Perched dune lakes: [name, f, x, radius, colour]
var lake_defs: Array = []
## Bare sand blows: [name, f, x, radius x, radius z, height, slip face side (-1 west, +1 east, 0 none)]
var sandblows: Array = []
## Rounded hills on the island spine: [name, f, x, radius, height]
var hills: Array = []
## Steep bare sand ridges (rollover country): [name, f, x, x_mode, rx, rz, peak].
## Flat-ish top, faces ~40 degrees across the short axis, ~25 degrees at the ends.
var steeps: Array = []
## Creeks crossing the east beach (f of each)
var creeks: Array = []
## Coffee-rock bars lying across the east beach:
## [name, f, half length along the beach (m), from (m inland of the waterline), to (m), height]
## from > 0 leaves the lower beach clear, so you can sneak past at low tide.
var rock_bars: Array = []
## Single big rocks: [f, x, mode, radius, height]
var boulders: Array = []
## Low ground that the tide floods: [name, f, x, mode, radius x, radius z, floor height]
var tidal_flats: Array = []
## Rainforest: denser, taller trees with palms: [f, x, mode, radius]
var rainforests: Array = []
## Wooden jetties out into the bay: [name, f, length (m)] (west coast)
var jetties: Array = []
## Small structures (bunkers, huts): [kind, f, x, mode, yaw degrees]
var structures: Array = []
## Where wildlife hangs around: [f, x, mode, count]
var dingo_spots: Array = []
var dingo_homes: Array[Vector3] = []
## Scenic flights land on the beach here: f of touchdown (east beach), or -1 for none
var plane_f := -1.0
## Dolphins play off this spot: [f, x, mode] or []
var dolphin_spot: Array = []
## f ranges (Vector2) of coloured sand cliffs behind the east / west beach
var coloured_east: Array = []
var coloured_west: Array = []
## true = sandy western beaches; false = muddy tidal flats
var west_sandy := false
## Inland dune height: base + rise toward the spine + noise
var inland_base := 7.0
var inland_rise := 12.0
var inland_noise := 11.0
## Tracks. Points are Vector3(f, x, mode):
##   mode 0 = absolute x, 1 = x relative to east coast (base, no headland bulge),
##   2 = relative to west coast, 9 = relative to the island centre line
## soft = softness range along the track (noise picks within it).
var track_defs: Array = []
## Named places (for HUD location + teleport): [name, f, x, mode]
var place_defs: Array = []
## Where the vehicle barge lands: it sails along barge_dir from barge_anchor until it grounds.
var barge_name := ""
var barge_hint := ""               ## shown when the ramp drops
var barge_dir := Vector3(0, 0, -1)
var barge_anchor := Vector3.ZERO

static var instance: IslandData

var heights := PackedFloat32Array()
var soft := PackedFloat32Array()
var surf := PackedByteArray()
var track := PackedFloat32Array()
var track_dist := PackedFloat32Array()

var places: Array[Dictionary] = []    # {name, pos: Vector3}
var lakes: Array[Dictionary] = []     # {name, x, z, r, level, color}
var tracks_built: Array[Dictionary] = []  # {name, path: PackedVector2Array}
var trees: Array[Vector4] = []        # x, y, z, scale
var scrub: Array[Vector4] = []
var wrecks: Array[Dictionary] = []    # {pos, yaw, roll, scale}
var lighthouses: Array[Vector3] = []
var palms: Array[Vector4] = []        # x, y, z, scale
var rock_pieces: Array[Vector4] = []  # x, y, z, size - lumpy boulders sitting on rock bars
var jetty_list: Array[Dictionary] = []  # {name, start: Vector3, dir: Vector3, length}
var structure_list: Array[Dictionary] = []  # {kind, pos, yaw}

## Global multiplier so you can tune softness live while testing (F5/F6 in game).
var softness_mult := 1.0
## Testing: if >= 0, every cell reports this softness.
var force_soft := -1.0

var _n_dune := FastNoiseLite.new()
var _n_small := FastNoiseLite.new()
var _n_soft := FastNoiseLite.new()
var _n_coast := FastNoiseLite.new()
var _n_bog := FastNoiseLite.new()


# ---------------------------------------------------------------- helpers
func f_to_z(f: float) -> float:
	return south_z - f * length


func z_to_f(z: float) -> float:
	return (south_z - z) / length


static func _cr(pts: Array, f: float) -> float:
	var n := pts.size()
	var first: Vector2 = pts[0]
	var last: Vector2 = pts[n - 1]
	if f <= first.x:
		return first.y
	if f >= last.x:
		return last.y
	var i := 0
	while i < n - 2 and f > (pts[i + 1] as Vector2).x:
		i += 1
	var p0: Vector2 = pts[maxi(i - 1, 0)]
	var p1: Vector2 = pts[i]
	var p2: Vector2 = pts[i + 1]
	var p3: Vector2 = pts[mini(i + 2, n - 1)]
	var t := (f - p1.x) / (p2.x - p1.x)
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1.y) + (-p0.y + p2.y) * t
		+ (2.0 * p0.y - 5.0 * p1.y + 4.0 * p2.y - p3.y) * t2
		+ (-p0.y + 3.0 * p1.y - 3.0 * p2.y + p3.y) * t3)


static func _smin(a: float, b: float, k: float) -> float:
	var hh := maxf(k - absf(a - b), 0.0) / k
	return minf(a, b) - hh * hh * k * 0.25


func east_base(f: float) -> float:
	return _cr(east, f)


func east_x(f: float) -> float:
	var x := east_base(f)
	for h in headlands:
		var d: float = (f - float(h[1])) / float(h[3])
		x += float(h[2]) * exp(-d * d)
	return x + _n_coast.get_noise_1d(f * 400.0) * 3.0


func west_x(f: float) -> float:
	return _cr(west, f) + _n_coast.get_noise_1d(f * 300.0 + 100.0) * 14.0


func resolve_x(f: float, x: float, mode: int) -> float:
	match mode:
		1:
			return east_base(f) + x
		2:
			return west_x(f) + x
		9:
			return (east_x(f) + west_x(f)) * 0.5 + x
	return x


static func _beach_east(d: float) -> float:
	if d < 0.0:
		return maxf(d * 0.035, -9.0)
	if d < 50.0:
		return d * 0.034
	if d < 78.0:
		return 1.7 + smoothstep(50.0, 78.0, d) * 5.5
	return 7.2 + (d - 78.0) * 0.12


static func _beach_west(d: float) -> float:
	if d < 0.0:
		return maxf(d * 0.02, -5.0)
	if d < 20.0:
		return d * 0.04
	if d < 40.0:
		return 0.8 + smoothstep(20.0, 40.0, d) * 3.0
	return 3.8 + (d - 40.0) * 0.1


func idx(c: int, r: int) -> int:
	return r * cols + c


## Island ids for the menu, in order.
const ISLANDS := {"fraser": "Fraser Island", "moreton": "Moreton Island"}


static func make(island_id: String) -> IslandData:
	match island_id:
		"moreton":
			return MoretonIsland.new()
	return FraserIsland.new()


## Override: fill in the island definition vars.
func _define() -> void:
	pass


## Override: island-specific extras (wrecks, lighthouses) after places are built.
func _gen_features() -> void:
	pass


# ---------------------------------------------------------------- generation
func generate() -> void:
	_define()
	instance = self
	_setup_noise()
	var n := cols * rows
	heights.resize(n)
	soft.resize(n)
	surf.resize(n)
	track.resize(n)
	track_dist.resize(n)
	track.fill(0.0)
	track_dist.fill(999.0)

	_gen_base()
	_gen_rocks()
	_gen_hills()
	_gen_steeps()
	_gen_sandblows()
	_gen_rock_bars()
	_gen_lakes()
	_gen_tidal_flats()
	_gen_creeks()
	_gen_tracks()
	_gen_boulders()
	_gen_places()
	_gen_features()
	_gen_vegetation()


func _setup_noise() -> void:
	_n_dune.seed = seed
	_n_dune.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_dune.frequency = 0.0045
	_n_dune.fractal_type = FastNoiseLite.FRACTAL_FBM
	_n_dune.fractal_octaves = 3

	_n_small.seed = seed + 1
	_n_small.frequency = 0.03
	_n_small.fractal_octaves = 2

	_n_soft.seed = seed + 2
	_n_soft.frequency = 0.025
	_n_soft.fractal_octaves = 2

	_n_coast.seed = seed + 3
	_n_coast.frequency = 0.05

	_n_bog.seed = seed + 4
	_n_bog.frequency = 0.04
	_n_bog.fractal_octaves = 1


func _gen_base() -> void:
	for r in rows:
		var z := z_min + r * CELL
		var f := z_to_f(z)
		var ex := east_x(f)
		var wx := west_x(f)
		var tip := minf(f, 1.0 - f) * length
		var col_e := _in_ranges(coloured_east, f) > 0.0
		var col_w := _in_ranges(coloured_west, f)
		var bt := _beach_east(tip)
		for c in cols:
			var x := x_min + c * CELL
			var i := r * cols + c
			var de := ex - x
			var dw := x - wx
			var interior := clampf(minf(de, dw) / 160.0, 0.0, 1.0)
			var inland := inland_base + interior * inland_rise + _n_dune.get_noise_2d(x, z) * inland_noise * interior + _n_small.get_noise_2d(x, z) * 2.0
			inland = maxf(inland, 4.5)
			var h := _smin(_beach_east(de), _beach_west(dw), 6.0)
			h = _smin(h, bt, 8.0)
			h = _smin(h, inland, 6.0)
			if col_w > 0.0 and dw > 15.0 and dw < de:
				# coloured sand cliffs standing up behind the west beach
				h = maxf(h, (0.8 + smoothstep(18.0, 42.0, dw) * 14.0 * (1.0 - smoothstep(55.0, 95.0, dw))) * col_w)

			var sn := _n_soft.get_noise_2d(x, z) * 0.5 + 0.5
			var s := 0.3
			var sf := Surface.FOREST
			if h < -0.25:
				sf = Surface.OCEAN
				s = 0.2
			elif tip < 90.0 or (de < 78.0 and de <= dw):
				# East (surf) beach - the "highway"
				if h < 0.55:
					sf = Surface.WET_SAND
					s = 0.05 + 0.08 * sn
				elif h < 1.15:
					var t := (h - 0.55) / 0.6
					s = lerpf(0.12, 0.55 + 0.30 * sn, t)
					sf = Surface.WET_SAND if t < 0.5 else Surface.DRY_SAND
				elif de < 50.0 or tip < 90.0:
					sf = Surface.DRY_SAND
					s = 0.55 + 0.32 * sn
				else:
					sf = Surface.COLOURED_SAND if col_e else Surface.SOFT_DUNE
					s = 0.88 + 0.10 * sn
			elif col_w > 0.3 and dw < 70.0 and dw < de and h > 2.5:
				sf = Surface.COLOURED_SAND
				s = 0.85
			elif dw < 40.0 and dw < de:
				if not west_sandy:
					sf = Surface.WEST_FLATS
					s = 0.30 + 0.25 * sn
				elif h < 0.5:
					sf = Surface.WET_SAND
					s = 0.10 + 0.10 * sn
				else:
					sf = Surface.DRY_SAND
					s = 0.45 + 0.35 * sn
			heights[i] = h
			soft[i] = s
			surf[i] = sf


func _cells_in_radius(cx: float, cz: float, rad: float) -> Array[int]:
	# returns [c0, c1, r0, r1] bounds
	var c0 := maxi(int(floor((cx - rad - x_min) / CELL)), 0)
	var c1 := mini(int(ceil((cx + rad - x_min) / CELL)), cols - 1)
	var r0 := maxi(int(floor((cz - rad - z_min) / CELL)), 0)
	var r1 := mini(int(ceil((cz + rad - z_min) / CELL)), rows - 1)
	return [c0, c1, r0, r1]


## Dark coffee rock across the beach (Ngkala / Poyungan / Yidney style).
func _gen_rock_bars() -> void:
	for rb in rock_bars:
		var cz := f_to_z(rb[1])
		var half: float = rb[2]
		var de0: float = rb[3]
		var de1: float = rb[4]
		var top: float = rb[5]
		var r0 := clampi(int(floor((cz - half - 6.0 - z_min) / CELL)), 0, rows - 1)
		var r1 := clampi(int(ceil((cz + half + 6.0 - z_min) / CELL)), 0, rows - 1)
		for r in range(r0, r1 + 1):
			var z := z_min + r * CELL
			var f := z_to_f(z)
			var ex := east_x(f)
			var along := absf(z - cz) / half
			if along >= 1.15:
				continue
			for c in cols:
				var x := x_min + c * CELL
				var de := ex - x
				if de < de0 - 4.0 or de > de1 + 6.0:
					continue
				var i := r * cols + c
				var edge := smoothstep(1.15, 0.85, along) * smoothstep(de0 - 4.0, de0, de) * (1.0 - smoothstep(de1, de1 + 6.0, de))
				var lumpy := 0.65 + 0.35 * (_n_small.get_noise_2d(x * 3.0, z * 3.0) * 0.5 + 0.5)
				var rh := heights[i] + top * edge * lumpy
				if rh > heights[i] + 0.25:
					heights[i] = rh
					surf[i] = Surface.ROCK
					soft[i] = 0.0
					if (r * 7 + c * 13) % 11 == 0:
						rock_pieces.append(Vector4(x, rh, z, 0.7 + top * 0.45 * lumpy))


func _gen_boulders() -> void:
	for b in boulders:
		var f: float = b[0]
		var cx := resolve_x(f, b[1], int(b[2]))
		var cz := f_to_z(f)
		var rad: float = b[3]
		var top: float = b[4]
		var bb := _cells_in_radius(cx, cz, rad)
		for r in range(bb[2], bb[3] + 1):
			for c in range(bb[0], bb[1] + 1):
				var x := x_min + c * CELL
				var z := z_min + r * CELL
				var d := Vector2(x - cx, z - cz).length() / rad
				if d >= 1.0:
					continue
				var i := r * cols + c
				if track[i] > 0.1:
					continue   # boulders flank tracks, never block them
				var rh := heights[i] + top * pow(1.0 - d * d, 0.7) * (0.8 + 0.2 * _n_small.get_noise_2d(x * 4.0, z * 4.0))
				if rh > heights[i]:
					heights[i] = rh
					surf[i] = Surface.ROCK
					soft[i] = 0.0
					if (r * 5 + c * 3) % 4 == 0:
						rock_pieces.append(Vector4(x, rh, z, 0.5 + top * 0.3))


## Low sand flats behind the beach that the sea floods at high tide (Mirapool style).
func _gen_tidal_flats() -> void:
	for tf in tidal_flats:
		var f: float = tf[1]
		var cx := resolve_x(f, tf[2], int(tf[3]))
		var cz := f_to_z(f)
		var rx: float = tf[4]
		var rz: float = tf[5]
		var floor_h: float = tf[6]
		var bb := _cells_in_radius(cx, cz, maxf(rx, rz) * 1.3)
		for r in range(bb[2], bb[3] + 1):
			for c in range(bb[0], bb[1] + 1):
				var x := x_min + c * CELL
				var z := z_min + r * CELL
				var e := Vector2((x - cx) / rx, (z - cz) / rz).length()
				if e >= 1.3:
					continue
				var i := r * cols + c
				var t := smoothstep(1.3, 0.8, e)
				var target := floor_h + _n_small.get_noise_2d(x * 2.0, z * 2.0) * 0.08
				if target < heights[i]:
					heights[i] = lerpf(heights[i], target, t)
					if t > 0.4 and surf[i] != Surface.ROCK:
						surf[i] = Surface.WET_SAND
						soft[i] = 0.55


func _gen_rocks() -> void:
	for h in headlands:
		var f: float = h[1]
		var rad: float = h[4]
		var peak: float = h[5]
		var cx := east_base(f) + float(h[6])
		var cz := f_to_z(f)
		var b := _cells_in_radius(cx, cz, rad)
		for r in range(b[2], b[3] + 1):
			for c in range(b[0], b[1] + 1):
				var x := x_min + c * CELL
				var z := z_min + r * CELL
				var d := Vector2(x - cx, z - cz).length()
				if d >= rad:
					continue
				var k := 1.0 - (d / rad) * (d / rad)
				var rh := peak * pow(k, 1.5) + _n_small.get_noise_2d(x * 3.0, z * 3.0) * 2.0 - 1.5
				var i := r * cols + c
				if rh > heights[i]:
					heights[i] = rh
					if rh > 0.6:
						surf[i] = Surface.ROCK
						soft[i] = 0.0


## 0..1 how far inside one of the (f0, f1) ranges f is, with soft ends.
func _in_ranges(ranges: Array, f: float) -> float:
	var best := 0.0
	for rg in ranges:
		var v: Vector2 = rg
		best = maxf(best, smoothstep(v.x, v.x + 0.005, f) * (1.0 - smoothstep(v.y - 0.005, v.y, f)))
	return best


func _gen_hills() -> void:
	for hl in hills:
		var cx: float = hl[2]
		var cz := f_to_z(hl[1])
		var rad: float = hl[3]
		var peak: float = hl[4]
		var b := _cells_in_radius(cx, cz, rad * 1.6)
		for r in range(b[2], b[3] + 1):
			for c in range(b[0], b[1] + 1):
				var i := r * cols + c
				if heights[i] < 2.0:
					continue
				var x := x_min + c * CELL
				var z := z_min + r * CELL
				var d := Vector2(x - cx, z - cz).length() / rad
				heights[i] += peak * exp(-d * d * 2.2) * smoothstep(2.0, 6.0, heights[i]) \
					* (1.0 + _n_small.get_noise_2d(x * 1.5, z * 1.5) * 0.15)


func _gen_steeps() -> void:
	for st in steeps:
		var f: float = st[1]
		var cx := resolve_x(f, st[2], int(st[3]))
		var cz := f_to_z(f)
		var rx: float = st[4]
		var rz: float = st[5]
		var peak: float = st[6]
		var b := _cells_in_radius(cx, cz, maxf(rx, rz))
		for r in range(b[2], b[3] + 1):
			for c in range(b[0], b[1] + 1):
				var x := x_min + c * CELL
				var z := z_min + r * CELL
				var e := Vector2((x - cx) / rx, (z - cz) / rz).length()
				if e >= 1.0:
					continue
				var i := r * cols + c
				if heights[i] < 2.0 or surf[i] == Surface.ROCK:
					continue
				var prof := 1.0 - smoothstep(0.3, 1.0, e)
				heights[i] += peak * prof * (1.0 + _n_small.get_noise_2d(x * 1.3, z * 1.3) * 0.06)
				# bare, fairly firm sand (you can climb it aired down - and roll off it)
				var bare := smoothstep(0.02, 0.2, prof)
				if bare > 0.0:
					soft[i] = lerpf(soft[i], 0.30 + 0.14 * (_n_soft.get_noise_2d(x, z) * 0.5 + 0.5), bare)
					if bare > 0.5:
						surf[i] = Surface.SOFT_DUNE


func _gen_sandblows() -> void:
	# Big bare dunes, with a steep slip face on the downwind side.
	for sb in sandblows:
		var cx: float = sb[2]
		var cz := f_to_z(sb[1])
		var rx: float = sb[3]
		var rz: float = sb[4]
		var top: float = sb[5]
		var slip: float = sb[6]
		var b := _cells_in_radius(cx, cz, maxf(rx, rz))
		for r in range(b[2], b[3] + 1):
			for c in range(b[0], b[1] + 1):
				var x := x_min + c * CELL
				var z := z_min + r * CELL
				var e := Vector2((x - cx) / rx, (z - cz) / rz).length()
				if e >= 1.0:
					continue
				var i := r * cols + c
				var dome := top * pow(1.0 - e * e, 0.8) + _n_small.get_noise_2d(x * 2.0, z * 2.0) * 1.5
				if slip != 0.0 and (x - cx) * slip > 0.0:
					dome *= smoothstep(0.0, 0.45, 1.0 - e) * 1.2
				var t := smoothstep(1.0, 0.75, e)
				heights[i] = maxf(heights[i], lerpf(heights[i], heights[i] + dome, t))
				if t > 0.3 and surf[i] != Surface.ROCK:
					surf[i] = Surface.SOFT_DUNE
					soft[i] = 0.90 + 0.08 * (_n_soft.get_noise_2d(x, z) * 0.5 + 0.5)


func _gen_lakes() -> void:
	for l in lake_defs:
		var f: float = l[1]
		var cx: float = l[2]
		var rad: float = l[3]
		var cz := f_to_z(f)
		var level := height_at(cx, cz) - 1.0
		lakes.append({"name": l[0], "x": cx, "z": cz, "r": rad, "level": level, "color": l[4]})
		var outer := rad * 1.8
		var b := _cells_in_radius(cx, cz, outer)
		for r in range(b[2], b[3] + 1):
			for c in range(b[0], b[1] + 1):
				var x := x_min + c * CELL
				var z := z_min + r * CELL
				var d := Vector2(x - cx, z - cz).length()
				if d >= outer:
					continue
				var i := r * cols + c
				if d < rad:
					var q := d / rad
					heights[i] = level + 0.3 - 5.0 * (1.0 - q * q)
					surf[i] = Surface.LAKE_BED if q < 0.9 else Surface.LAKE_SAND
					soft[i] = 0.45
				else:
					var t := smoothstep(rad, outer, d)
					var rim := level + 0.4 + (d - rad) * 0.06
					heights[i] = lerpf(rim, heights[i], t)
					if t < 0.55 and surf[i] != Surface.ROCK:
						surf[i] = Surface.LAKE_SAND
						soft[i] = 0.62


func _gen_creeks() -> void:
	for cf in creeks:
		_gen_creek(cf)


## Fresh-water creek crossing the beach - a shallow wet channel you drive through.
func _gen_creek(cf: float) -> void:
	var cz := f_to_z(cf)
	var ex := east_x(cf)
	for r in rows:
		var z := z_min + r * CELL
		var dz := absf(z - cz)
		if dz > 9.0:
			continue
		for c in cols:
			var x := x_min + c * CELL
			var de := ex - x
			if de < -5.0 or de > 120.0:
				continue
			var i := r * cols + c
			var depth := 0.55 * (1.0 - smoothstep(2.0, 9.0, dz)) * smoothstep(-5.0, 10.0, de)
			heights[i] -= depth
			if dz < 6.0:
				surf[i] = Surface.WET_SAND
				soft[i] = minf(soft[i], 0.25)


func _track_soft(x: float, z: float, range_v: Vector2) -> float:
	var n := _n_soft.get_noise_2d(x * 1.7 + 500.0, z * 1.7) * 0.5 + 0.5
	var s := lerpf(range_v.x, range_v.y, n)
	# occasional bog holes - very soft patches
	var bog := _n_bog.get_noise_2d(x, z)
	if bog > 0.55:
		s = lerpf(s, 1.0, smoothstep(0.55, 0.75, bog))
	return clampf(s, 0.0, 1.0)


func _gen_tracks() -> void:
	var best_d := PackedFloat32Array()
	var best_h := PackedFloat32Array()
	best_d.resize(cols * rows)
	best_h.resize(cols * rows)
	for t in track_defs:
		var pts: Array = t["pts"]
		var ctrl: Array[Vector2] = []
		for p in pts:
			var v: Vector3 = p
			ctrl.append(Vector2(resolve_x(v.x, v.y, int(v.z)), f_to_z(v.x)))
		var path := _resample(ctrl, 2.0)
		# oneway: 1 = only drive it in the order it's defined, -1 = only backwards
		# no_bots: the ambient bots leave this one alone (rollover tracks)
		tracks_built.append({"name": t["name"], "path": path, "oneway": int(t.get("oneway", 0)), "no_bots": bool(t.get("no_bots", false))})
		var hw: float = t["w"]
		# camber: cross slope (rise per metre) - the right-hand side (in the direction it's
		# defined) sits lower, for sidling tracks along a steep face
		var camber: float = t.get("camber", 0.0)
		var best_k := PackedInt32Array()
		if camber != 0.0:
			best_k.resize(cols * rows)
		var blend := 9.0
		var srange: Vector2 = t["soft"]

		# smoothed height profile along the track
		var hs := PackedFloat32Array()
		hs.resize(path.size())
		for k in path.size():
			hs[k] = height_at(path[k].x, path[k].y)
		for pass_i in 3:
			var tmp := hs.duplicate()
			for k in path.size():
				var acc := 0.0
				var cnt := 0
				for j in range(maxi(k - 8, 0), mini(k + 9, path.size())):
					acc += hs[j]
					cnt += 1
				tmp[k] = acc / cnt
			hs = tmp

		best_d.fill(1e9)
		var touched: Dictionary = {}
		var reach := hw + blend
		for k in path.size():
			var px := path[k].x
			var pz := path[k].y
			var b := _cells_in_radius(px, pz, reach)
			for r in range(b[2], b[3] + 1):
				for c in range(b[0], b[1] + 1):
					var x := x_min + c * CELL
					var z := z_min + r * CELL
					var d := Vector2(x - px, z - pz).length()
					if d > reach:
						continue
					var i := r * cols + c
					if d < best_d[i]:
						best_d[i] = d
						best_h[i] = hs[k]
						touched[i] = true
						if camber != 0.0:
							best_k[i] = k
		for key in touched.keys():
			var i: int = key
			var d := best_d[i]
			var c := i % cols
			var r := i / cols
			var x := x_min + c * CELL
			var z := z_min + r * CELL
			track_dist[i] = minf(track_dist[i], d)
			if surf[i] == Surface.ROCK:
				continue
			var w := 1.0 - smoothstep(hw, hw + blend, d)
			var whoops := _n_small.get_noise_2d(x * 2.5, z * 2.5) * 0.18
			var target := best_h[i] + whoops
			if camber != 0.0:
				var k: int = best_k[i]
				var tg := (path[mini(k + 1, path.size() - 1)] - path[maxi(k - 1, 0)]).normalized()
				var lat := (Vector2(x, z) - path[k]).dot(Vector2(-tg.y, tg.x))
				# full camber in the middle of the track, easing off at the two ends
				var ends := smoothstep(0.0, 12.0, float(k)) * smoothstep(0.0, 12.0, float(path.size() - 1 - k))
				target -= camber * ends * clampf(lat, -hw - blend, hw + blend)
			# never carve tracks below the water table
			target = maxf(target, 0.7)
			heights[i] = lerpf(heights[i], target, w)
			var inner := 1.0 - smoothstep(hw - 0.5, hw + 1.5, d)
			if inner > track[i]:
				track[i] = inner
			if inner > 0.35:
				var on_beach := surf[i] == Surface.WET_SAND or surf[i] == Surface.DRY_SAND
				if not on_beach:
					surf[i] = Surface.TRACK
				soft[i] = lerpf(soft[i], _track_soft(x, z, srange), inner)


func _resample(ctrl: Array[Vector2], step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	for i in n - 1:
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, n - 1)]
		var segs := maxi(int(ceil(p1.distance_to(p2) / step)), 1)
		for s in segs:
			var t := float(s) / segs
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t
				+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
				+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(ctrl[n - 1])
	return out


func _gen_jetties_and_structures() -> void:
	for j in jetties:
		var f: float = j[1]
		var z := f_to_z(f)
		var x := west_x(f) + 6.0
		jetty_list.append({"name": j[0], "start": Vector3(x, height_at(x, z), z), "dir": Vector3(-1, 0, 0), "length": j[2]})
	for st in structures:
		var f: float = st[1]
		var x := resolve_x(f, st[2], int(st[3]))
		var z := f_to_z(f)
		structure_list.append({"kind": st[0], "pos": Vector3(x, height_at(x, z), z), "yaw": deg_to_rad(st[4])})


func _gen_places() -> void:
	_gen_jetties_and_structures()
	for ds in dingo_spots:
		var f: float = ds[0]
		var x := resolve_x(f, ds[1], int(ds[2]))
		var z := f_to_z(f)
		for k in int(ds[3]):
			dingo_homes.append(Vector3(x + k * 4.0, height_at(x, z), z + k * 3.0))
	for p in place_defs:
		var f: float = p[1]
		var x := resolve_x(f, p[2], int(p[3]))
		var z := f_to_z(f)
		places.append({"name": p[0], "pos": Vector3(x, height_at(x, z), z)})


func _gen_vegetation() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 99
	var spacing := 13.0
	var z := z_min
	while z < z_min + (rows - 1) * CELL:
		var x := x_min
		while x < x_min + (cols - 1) * CELL:
			var px := x + rng.randf() * spacing
			var pz := z + rng.randf() * spacing
			var roll := rng.randf()
			var sc := 0.7 + rng.randf() * 0.7
			var i := _nearest_idx(px, pz)
			var sf := surf[i]
			var rain := _rainforest_at(px, pz)
			if sf == Surface.FOREST and rain > 0.0 and track_dist[i] > 5.0:
				# rainforest: every spot gets a tall tree, plus palms in between
				trees.append(Vector4(px, height_at(px, pz), pz, sc * (1.25 + 0.4 * rain)))
				var qx := px + spacing * 0.5
				var qz := pz + spacing * 0.5
				if track_dist[_nearest_idx(qx, qz)] > 4.0 and surf[_nearest_idx(qx, qz)] == Surface.FOREST:
					palms.append(Vector4(qx, height_at(qx, qz), qz, 0.8 + rng.randf() * 0.5))
			elif sf == Surface.FOREST and track_dist[i] > 7.5 and roll < 0.72:
				trees.append(Vector4(px, height_at(px, pz), pz, sc))
			elif (sf == Surface.SOFT_DUNE or sf == Surface.WEST_FLATS) and track_dist[i] > 5.0 and roll < 0.55:
				scrub.append(Vector4(px, height_at(px, pz), pz, sc))
			x += spacing
		z += spacing


func _rainforest_at(x: float, z: float) -> float:
	var best := 0.0
	for rf in rainforests:
		var f: float = rf[0]
		var cx := resolve_x(f, rf[1], int(rf[2]))
		var d := Vector2(x - cx, z - f_to_z(f)).length() / float(rf[3])
		best = maxf(best, 1.0 - d)
	return best


# ---------------------------------------------------------------- queries
func _nearest_idx(x: float, z: float) -> int:
	var c := clampi(int(round((x - x_min) / CELL)), 0, cols - 1)
	var r := clampi(int(round((z - z_min) / CELL)), 0, rows - 1)
	return r * cols + c


func _bilinear(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x - x_min) / CELL, 0.0, cols - 1.001)
	var fz := clampf((z - z_min) / CELL, 0.0, rows - 1.001)
	var c := int(fx)
	var r := int(fz)
	var tx := fx - c
	var tz := fz - r
	var i := r * cols + c
	var a := lerpf(arr[i], arr[i + 1], tx)
	var b := lerpf(arr[i + cols], arr[i + cols + 1], tx)
	return lerpf(a, b, tz)


func height_at(x: float, z: float) -> float:
	return _bilinear(heights, x, z)


## Effective sand softness 0..1 at a world position (includes the live tuning multiplier).
func softness_at(x: float, z: float) -> float:
	if force_soft >= 0.0:
		return force_soft
	return clampf(_bilinear(soft, x, z) * softness_mult, 0.0, 1.0)


func surface_at(x: float, z: float) -> int:
	return surf[_nearest_idx(x, z)]


func track_at(x: float, z: float) -> float:
	return _bilinear(track, x, z)


## Water surface height at a point (the tide-driven sea level, or a lake's level).
func water_level_at(x: float, z: float) -> float:
	for l in lakes:
		var dx: float = x - float(l["x"])
		var dz: float = z - float(l["z"])
		var rr: float = float(l["r"])
		if dx * dx + dz * dz < rr * rr:
			return l["level"]
	return Tide.level


func nearest_place(pos: Vector3, max_dist := 300.0) -> String:
	var best := ""
	var bd := max_dist
	for p in places:
		var pp: Vector3 = p["pos"]
		var d := Vector2(pos.x - pp.x, pos.z - pp.z).length()
		if d < bd:
			bd = d
			best = p["name"]
	return best

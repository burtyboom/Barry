class_name MoretonIsland
extends IslandData
## Scaled-down Moreton Island, off Brisbane.
##
## Real island is ~37 km long and up to ~9 km wide (widest in the north).
## Here it is 3.4 km long (about 1:11) and squeezed a bit narrower, like Fraser.
## Ocean beach down the whole east side, sandy Moreton Bay beaches on the west,
## big dunes inland. Positions of tracks and places are approximate.
##
## Main tracks: Middle Road (Tangalooma - ocean beach), Rous Battery Road,
## Telegraph Road (Bulwer - ocean beach), Blue Lagoon access, the lighthouse road
## up to Cape Moreton and the North Point road, plus the Tangalooma beach bypass.


func _define() -> void:
	id = "moreton"
	display_name = "Moreton Island"
	x_min = -700.0
	z_min = -1850.0
	cols = 437         # 1090 m wide
	rows = 1481        # 3700 m long
	south_z = 1700.0   # f = 0 (South Point)
	length = 3400.0    # f = 1 at z = -1700 (North Point)
	seed = 7373
	west_sandy = true
	inland_base = 9.0
	inland_rise = 18.0
	inland_noise = 16.0

	# Long straight ocean beach on the east; the bay side bulges out in the north.
	east = [
		Vector2(0.00, -30), Vector2(0.02, 40), Vector2(0.05, 110), Vector2(0.10, 160),
		Vector2(0.18, 190), Vector2(0.30, 205), Vector2(0.45, 215), Vector2(0.60, 222),
		Vector2(0.72, 228), Vector2(0.82, 232), Vector2(0.90, 230), Vector2(0.95, 215),
		Vector2(0.98, 170), Vector2(1.00, 60),
	]
	west = [
		Vector2(0.00, -45), Vector2(0.02, -75), Vector2(0.05, -100), Vector2(0.10, -125),
		Vector2(0.18, -150), Vector2(0.28, -175), Vector2(0.38, -200), Vector2(0.45, -225),
		Vector2(0.52, -245), Vector2(0.60, -270), Vector2(0.68, -300), Vector2(0.75, -335),
		Vector2(0.82, -370), Vector2(0.88, -395), Vector2(0.93, -380), Vector2(0.95, -350),
		Vector2(0.98, -260), Vector2(1.00, -100),
	]

	headlands = [
		["Cape Moreton", 0.975, 35.0, 0.008, 55.0, 30.0, 10.0],
	]

	lake_defs = [
		["Blue Lagoon", 0.868, 135.0, 34.0, Color(0.30, 0.30, 0.18, 0.78)],   # tea-tree stained, clear but dark
		["Lake Jabiru", 0.882, 60.0, 16.0, Color(0.50, 0.32, 0.18, 0.80)],   # tea-tree stained
	]

	sandblows = [
		["Big Sandhills", 0.130, 70.0, 55.0, 110.0, 24.0, -1.0],
		["The Desert", 0.410, -40.0, 95.0, 70.0, 14.0, 1.0],
		["Little Sahara", 0.425, -165.0, 45.0, 32.0, 12.0, -1.0],
	]
	hills = [
		["Mount Tempest", 0.580, -40.0, 110.0, 38.0],
	]
	steeps = [["Sidewinder Ridge", 0.360, 60.0, 0, 50.0, 95.0, 26.0]]   # steep bare ridge behind Rous Battery
	creeks = [0.810]                         # Eagers Creek
	coloured_west = [Vector2(0.915, 0.942)]  # Yellow Patch sand cliffs
	# Mirapool Lagoon: floods across the south-east beach from mid to high tide - wait for low tide
	tidal_flats = [["Mirapool Lagoon", 0.100, -30.0, 1, 34.0, 50.0, -0.15]]
	jetties = [["Tangalooma jetty", 0.452, 70.0]]
	dolphin_spot = [0.455, -60.0, 2]   # dolphins come in near the Tangalooma jetty
	structures = [
		["shop", 0.070, 40.0, 2, -90.0],      # Kooringal - the Gutter Bar
		["bunker", 0.308, -45.0, 1, 90.0],    # Rous Battery WWII emplacement
		["shop", 0.448, 55.0, 2, -90.0],      # Tangalooma Resort
		["hut", 0.700, 40.0, 2, -90.0],       # Cowan Cowan
		["shop", 0.803, 45.0, 2, -90.0],      # Bulwer store (fuel!)
		["hut", 0.990, -30.0, 9, 0.0],        # North Point camp
	]

	track_defs = [
		# Middle Road is a pair of one-way tracks across the island
		{"name": "Middle Road (eastbound)", "soft": Vector2(0.50, 0.85), "w": 3.2, "oneway": 1, "pts": [
			Vector3(0.456, 6, 2), Vector3(0.456, 45, 2), Vector3(0.460, -110, 0), Vector3(0.466, -20, 0),
			Vector3(0.472, 80, 0), Vector3(0.476, -75, 1), Vector3(0.477, -32, 1)]},
		{"name": "Middle Road", "soft": Vector2(0.50, 0.85), "w": 3.5, "oneway": -1, "pts": [
			Vector3(0.452, 6, 2), Vector3(0.452, 45, 2), Vector3(0.456, -110, 0), Vector3(0.462, -20, 0),
			Vector3(0.468, 80, 0), Vector3(0.472, -75, 1), Vector3(0.473, -32, 1)]},
		{"name": "Rous Battery Road", "soft": Vector2(0.55, 0.90), "w": 3.2, "pts": [
			Vector3(0.300, 6, 2), Vector3(0.300, 40, 2), Vector3(0.305, -80, 0), Vector3(0.312, 40, 0),
			Vector3(0.310, -75, 1), Vector3(0.308, -32, 1)]},
		{"name": "Telegraph Road", "soft": Vector2(0.45, 0.85), "w": 3.5, "pts": [
			Vector3(0.800, 6, 2), Vector3(0.800, 50, 2), Vector3(0.808, -220, 0), Vector3(0.820, -80, 0),
			Vector3(0.835, 40, 0), Vector3(0.848, -75, 1), Vector3(0.850, -32, 1)]},
		{"name": "Blue Lagoon access", "soft": Vector2(0.60, 0.90), "w": 3.0, "pts": [
			Vector3(0.835, 40, 0), Vector3(0.845, 100, 0), Vector3(0.857, 115, 0)]},
		{"name": "Lighthouse Road", "soft": Vector2(0.60, 0.95), "w": 3.2, "pts": [
			Vector3(0.930, -32, 1), Vector3(0.935, -80, 1), Vector3(0.950, 120, 0), Vector3(0.962, 140, 0)]},
		{"name": "North Point Road", "soft": Vector2(0.65, 0.95), "w": 3.0, "pts": [
			Vector3(0.962, 140, 0), Vector3(0.975, 40, 0), Vector3(0.985, -120, 0), Vector3(0.994, -60, 9)]},
		{"name": "Bulwer high-tide bypass", "soft": Vector2(0.70, 0.95), "w": 3.0, "pts": [
			Vector3(0.784, 6, 2), Vector3(0.788, 34, 2), Vector3(0.796, 36, 2), Vector3(0.800, 6, 2)]},
		{"name": "Tangalooma bypass", "soft": Vector2(0.70, 0.95), "w": 3.0, "pts": [
			Vector3(0.442, 6, 2), Vector3(0.446, 40, 2), Vector3(0.455, 48, 2), Vector3(0.462, 40, 2), Vector3(0.466, 6, 2)]},
	]

	place_defs = [
		["South Point", 0.025, 0.0, 9],
		["Kooringal", 0.070, 15.0, 2],
		["Mirapool Lagoon", 0.100, -24.0, 1],
		["Big Sandhills", 0.130, -30.0, 1],
		["Rous Battery", 0.308, -24.0, 1],
		["Sidewinder Ridge", 0.345, 95.0, 0],
		["The Desert", 0.410, -40.0, 0],
		["Little Sahara", 0.425, 15.0, 2],
		["Tangalooma", 0.452, 15.0, 2],
		["Tangalooma Wrecks", 0.485, 12.0, 2],
		["Mount Tempest", 0.580, -40.0, 0],
		["Cowan Cowan", 0.700, 15.0, 2],
		["Bulwer", 0.800, 15.0, 2],
		["Eagers Creek", 0.810, -24.0, 1],
		["Blue Lagoon", 0.857, 115.0, 0],
		["Comboyuro Point", 0.880, 15.0, 2],
		["Yellow Patch", 0.928, 15.0, 2],
		["Honeymoon Bay", 0.955, -24.0, 1],
		["Cape Moreton Lighthouse", 0.975, 10.0, 1],
		["Champagne Pools", 0.993, 40.0, 9],
		["North Point", 0.988, -110.0, 9],
	]

	# Vehicle ferry from the mainland beaches at Tangalooma, heading east.
	barge_name = "Tangalooma"
	barge_hint = "Air down - Middle Road to the ocean beach starts just north"
	barge_dir = Vector3(1, 0, 0)
	barge_anchor = Vector3(x_min + 30.0, 0.0, f_to_z(0.462))


func _gen_features() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 5
	# Tangalooma Wrecks: a line of hulks sunk off the beach as a breakwall
	var wx := west_x(0.485) - 45.0
	var z := f_to_z(0.485)
	for k in 5:
		var sc := rng.randf_range(0.5, 0.6)
		wrecks.append({"pos": Vector3(wx + rng.randf_range(-3, 3), 1.4 - 4.4 * sc, z - k * 19.0),
			"yaw": rng.randf_range(-0.1, 0.1), "roll": rng.randf_range(-0.12, 0.12), "scale": sc})
	# Bulwer Wrecks: three rusty hulks right at the water's edge
	z = f_to_z(0.795)
	for k in 3:
		var sc := rng.randf_range(0.42, 0.5)
		var x := west_x(0.795) - 10.0
		wrecks.append({"pos": Vector3(x, height_at(x, z - k * 16.0) - 1.0, z - k * 16.0),
			"yaw": rng.randf_range(-0.2, 0.2), "roll": rng.randf_range(-0.15, 0.15), "scale": sc})
	# Cape Moreton lighthouse on top of the headland
	var lx := east_base(0.975) + 10.0
	var lz := f_to_z(0.975)
	lighthouses.append(Vector3(lx, height_at(lx, lz), lz))

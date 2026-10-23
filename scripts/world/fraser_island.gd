class_name FraserIsland
extends IslandData
## Scaled-down Fraser Island.
##
## Real island is ~123 km x ~22 km. Here it is ~4 km long (about 1:31 lengthwise)
## and a bit narrower than true scale so it doesn't feel empty.


func _define() -> void:
	id = "fraser"
	display_name = "Fraser Island"
	x_min = -420.0
	z_min = -2150.0
	cols = 337         # 840 m wide
	rows = 1721        # 4300 m long
	south_z = 2000.0   # f = 0 (Hook Point)
	length = 4000.0    # f = 1 at z = -2000 (Sandy Cape)
	seed = 4242

	# East coast (surf beach) and west coast (Great Sandy Strait / Platypus Bay)
	east = [
		Vector2(0.00, -55), Vector2(0.02, 20), Vector2(0.06, 120), Vector2(0.12, 195),
		Vector2(0.20, 235), Vector2(0.30, 255), Vector2(0.45, 265), Vector2(0.60, 262),
		Vector2(0.70, 255), Vector2(0.80, 245), Vector2(0.86, 225), Vector2(0.92, 175),
		Vector2(0.97, 95), Vector2(1.00, 15),
	]
	west = [
		Vector2(0.00, -75), Vector2(0.02, -110), Vector2(0.06, -170), Vector2(0.12, -230),
		Vector2(0.20, -270), Vector2(0.30, -300), Vector2(0.40, -310), Vector2(0.50, -295),
		Vector2(0.60, -255), Vector2(0.68, -175), Vector2(0.75, -90), Vector2(0.82, -20),
		Vector2(0.88, 30), Vector2(0.94, 45), Vector2(0.98, 25), Vector2(1.00, 5),
	]

	# Positions follow the real island (km from Hook Point / 123), see docs/island_research.md.
	headlands = [
		["Indian Head", 0.785, 35.0, 0.008, 46.0, 28.0, 12.0],
		["Middle Rocks", 0.805, 14.0, 0.004, 24.0, 7.0, 22.0],     # Champagne Pools
		["Waddy Point", 0.825, 40.0, 0.010, 52.0, 24.0, 12.0],
	]

	lake_defs = [
		["Lake Boomanjin", 0.193, -20.0, 40.0, Color(0.55, 0.32, 0.18, 0.80)],  # tea-tree stained
		["Lake Birrabeen", 0.238, -60.0, 28.0, Color(0.15, 0.55, 0.80, 0.55)],
		["Lake McKenzie", 0.306, -75.0, 42.0, Color(0.10, 0.62, 0.90, 0.50)],   # white silica sand
		["Lake Wabby", 0.322, 120.0, 24.0, Color(0.10, 0.50, 0.30, 0.65)],    # emerald
		["Lake Garawongera", 0.405, 30.0, 24.0, Color(0.30, 0.40, 0.25, 0.70)],
	]

	# Hammerstone Sandblow: a big bare dune marching west into Lake Wabby.
	sandblows = [["Hammerstone Sandblow", 0.3255, 178.0, 62.0, 48.0, 18.0, -1.0]]
	creeks = [0.550]                                                  # Eli Creek
	coloured_east = [Vector2(0.595, 0.607), Vector2(0.615, 0.628)]    # The Pinnacles, Cathedrals
	hills = [
		["Ngkala dune", 0.906, 100.0, 34.0, 12.0],        # the climb behind Ngkala Rocks
		["Sandy Cape hill", 0.942, 100.0, 40.0, 22.0],    # lighthouse hill, set back from the beach
	]
	# rollover country: steep bare ridges inland, away from the beach lane and the camps
	steeps = [
		["Rollover Hill", 0.505, 120.0, 0, 50.0, 160.0, 20.0],   # long ridge, a sidling track along its east face
		["Knife Edge", 0.700, 150.0, 0, 35.0, 70.0, 18.0],       # short and very steep - for showing off
	]
	# Coffee rock on the beach. Poyungan / Yidney leave the lower beach clear (get around
	# at low tide, bypass at high tide). Ngkala goes right across - always take the dune track.
	rock_bars = [
		["Poyungan Rocks", 0.382, 20.0, 16.0, 62.0, 1.6],
		["Yidney Rocks", 0.432, 16.0, 16.0, 60.0, 1.4],
		["Ngkala Rocks", 0.905, 14.0, -8.0, 58.0, 2.8],
	]
	# the tight entry to the Ngkala track, between two big rocks
	boulders = [
		[0.8990, -50.0, 1, 4.0, 3.2],
		[0.9002, -64.0, 1, 4.2, 3.6],
	]
	rainforests = [
		[0.280, 20.0, 0, 70.0],     # Central Station: satinay, brush box, piccabeen palms
		[0.300, -30.0, 0, 45.0],    # Pile Valley
	]
	jetties = [["Kingfisher Bay jetty", 0.333, 60.0]]
	structures = [
		["hut", 0.170, -100.0, 1, 90.0],       # Dilli Village
		["shop", 0.250, -102.0, 1, 90.0],      # Eurong
		["hut", 0.282, 38.0, 0, 0.0],          # Central Station ranger hut
		["shop", 0.333, 34.0, 2, -90.0],       # Kingfisher Bay Resort
		["shop", 0.470, -102.0, 1, 90.0],      # Happy Valley
		["hut", 0.852, -100.0, 1, 90.0],       # Orchid Beach
	]

	plane_f = 0.262     # scenic flights land on the beach just north of Eurong
	# dingoes hang around the beach near camps and townships
	# (and roam the dunes all the way up the east coast - K'gari has heaps of them)
	dingo_spots = [[0.255, -40.0, 1, 2], [0.475, -45.0, 1, 1], [0.635, -40.0, 1, 2], [0.285, 30.0, 0, 1], [0.857, -45.0, 1, 1],
		[0.075, -30.0, 1, 2], [0.14, -35.0, 1, 2], [0.20, -28.0, 1, 1], [0.32, -35.0, 1, 2], [0.40, -30.0, 1, 3],
		[0.55, -32.0, 1, 2], [0.70, -30.0, 1, 2], [0.77, -28.0, 1, 1], [0.93, -35.0, 1, 2]]

	track_defs = [
		{"name": "Eurong - Central Station", "soft": Vector2(0.45, 0.78), "w": 3.5, "pts": [
			Vector3(0.250, -32, 1), Vector3(0.255, -75, 1), Vector3(0.262, 120, 0), Vector3(0.270, 70, 0), Vector3(0.280, 20, 0)]},
		{"name": "Central Station - Kingfisher Bay", "soft": Vector2(0.50, 0.85), "w": 3.5, "pts": [
			Vector3(0.280, 20, 0), Vector3(0.287, -15, 0), Vector3(0.292, -50, 0), Vector3(0.2935, -78, 0),
			Vector3(0.299, -128, 0), Vector3(0.311, -172, 0), Vector3(0.323, -212, 0), Vector3(0.331, 32, 2), Vector3(0.333, 6, 2)]},
		{"name": "Dilli - Boomanjin - Birrabeen", "soft": Vector2(0.50, 0.92), "w": 3.2, "pts": [
			Vector3(0.170, -32, 1), Vector3(0.172, -95, 1), Vector3(0.180, 60, 0), Vector3(0.188, 30, 0),
			Vector3(0.198, 30, 0), Vector3(0.212, 0, 0), Vector3(0.226, -18, 0), Vector3(0.238, -24, 0),
			Vector3(0.255, 0, 0), Vector3(0.270, 15, 0), Vector3(0.280, 20, 0)]},
		{"name": "Lake Wabby lookout", "soft": Vector2(0.70, 0.95), "w": 3.0, "pts": [
			Vector3(0.336, -32, 1), Vector3(0.335, -70, 1), Vector3(0.334, 150, 0), Vector3(0.330, 122, 0)]},
		{"name": "Poyungan Rocks bypass", "soft": Vector2(0.60, 0.88), "w": 3.0, "pts": [
			Vector3(0.373, -24, 1), Vector3(0.376, -70, 1), Vector3(0.382, -80, 1), Vector3(0.388, -70, 1), Vector3(0.391, -24, 1)]},
		{"name": "Yidney Rocks jump-up", "soft": Vector2(0.65, 0.90), "w": 3.0, "pts": [
			Vector3(0.425, -24, 1), Vector3(0.428, -64, 1), Vector3(0.432, -70, 1), Vector3(0.436, -64, 1), Vector3(0.439, -24, 1)]},
		{"name": "Happy Valley - Garawongera", "soft": Vector2(0.55, 0.90), "w": 3.2, "pts": [
			Vector3(0.470, -32, 1), Vector3(0.466, -80, 1), Vector3(0.455, 130, 0), Vector3(0.425, 85, 0),
			Vector3(0.412, 58, 0), Vector3(0.399, 55, 0), Vector3(0.380, 30, 0), Vector3(0.360, 22, 0),
			Vector3(0.340, 12, 0), Vector3(0.315, 30, 0), Vector3(0.295, 32, 0), Vector3(0.280, 20, 0)]},
		{"name": "Northern Road", "soft": Vector2(0.40, 0.80), "w": 3.5, "pts": [
			Vector3(0.620, -32, 1), Vector3(0.625, -85, 1), Vector3(0.640, 120, 0), Vector3(0.670, 80, 0),
			Vector3(0.720, 60, 0), Vector3(0.760, 62, 0), Vector3(0.800, 72, 0), Vector3(0.835, 95, 0),
			Vector3(0.848, -70, 1), Vector3(0.852, -32, 1)]},
		{"name": "Indian Head bypass", "soft": Vector2(0.80, 0.97), "w": 3.0, "pts": [
			Vector3(0.771, -22, 1), Vector3(0.777, -52, 1), Vector3(0.785, -60, 1), Vector3(0.793, -52, 1), Vector3(0.799, -22, 1)]},
		{"name": "Waddy Point bypass", "soft": Vector2(0.75, 0.95), "w": 3.0, "pts": [
			Vector3(0.811, -22, 1), Vector3(0.818, -58, 1), Vector3(0.825, -68, 1), Vector3(0.832, -58, 1), Vector3(0.839, -22, 1)]},
		{"name": "Wathumba Creek road", "soft": Vector2(0.60, 0.90), "w": 3.2, "pts": [
			Vector3(0.852, -32, 1), Vector3(0.853, -80, 1), Vector3(0.856, 70, 0), Vector3(0.859, 25, 2), Vector3(0.860, 4, 2)]},
		# one-way over the dune: tight between the rocks, then deep soft sand up along the edge
		{"name": "Ngkala Rocks track", "soft": Vector2(0.90, 1.00), "w": 3.0, "oneway": 1, "pts": [
			Vector3(0.8975, -24, 1), Vector3(0.8995, -60, 1), Vector3(0.9025, -82, 1), Vector3(0.9060, -92, 1),
			Vector3(0.9095, -82, 1), Vector3(0.9120, -52, 1), Vector3(0.9135, -24, 1)]},
		# sidles along the east face of Rollover Hill, leaning towards the sea - take it slow
		{"name": "Rollover Hill sidle", "soft": Vector2(0.30, 0.45), "w": 3.4, "camber": 0.42, "no_bots": true, "pts": [
			Vector3(0.474, -32, 1), Vector3(0.477, -80, 1), Vector3(0.483, 150, 0), Vector3(0.492, 151, 0),
			Vector3(0.505, 152, 0), Vector3(0.518, 151, 0), Vector3(0.527, 150, 0), Vector3(0.533, -80, 1), Vector3(0.536, -32, 1)]},
		{"name": "Sandy Cape Lighthouse track", "soft": Vector2(0.65, 0.92), "w": 3.0, "pts": [
			Vector3(0.933, -26, 1), Vector3(0.936, -62, 1), Vector3(0.941, 96, 0)]},
	]

	place_defs = [
		["Hook Point", 0.012, 0.0, 9],
		["Dilli Village", 0.170, -24.0, 1],
		["Eurong", 0.250, -24.0, 1],
		["Central Station", 0.280, 20.0, 0],
		["Lake McKenzie", 0.2935, -78.0, 0],
		["Lake Wabby", 0.330, 122.0, 0],
		["Kingfisher Bay", 0.333, 14.0, 2],
		["Poyungan Rocks", 0.372, -24.0, 1],
		["Yidney Rocks", 0.424, -24.0, 1],
		["Happy Valley", 0.470, -24.0, 1],
		["Rollover Hill", 0.486, 150.0, 0],
		["Eli Creek", 0.550, -24.0, 1],
		["Maheno Wreck", 0.578, -30.0, 1],
		["The Pinnacles", 0.601, -28.0, 1],
		["Cathedrals", 0.621, -24.0, 1],
		["Dundubara", 0.636, -24.0, 1],
		["Indian Head", 0.769, -24.0, 1],
		["Champagne Pools", 0.805, -26.0, 1],
		["Waddy Point", 0.810, -24.0, 1],
		["Orchid Beach", 0.852, -24.0, 1],
		["Wathumba Creek", 0.860, 10.0, 2],
		["Ngkala Rocks", 0.896, -24.0, 1],
		["Sandy Cape Lighthouse", 0.940, 96.0, 0],
		["Sandy Cape", 0.975, 0.0, 9],
	]


	# Barge from Inskip Point beaches on the south tip, heading north.
	barge_name = "Hook Point"
	barge_hint = "Air down and head north up the ocean beach"
	barge_dir = Vector3(0, 0, -1)
	barge_anchor = Vector3(-45.0, 0.0, z_min + (rows - 1) * CELL - 30.0)


func _gen_features() -> void:
	# SS Maheno - rusty hull half buried on the east beach
	var p := Vector3(east_base(0.578) - 10.0, 0.0, f_to_z(0.578))
	p.y = height_at(p.x, p.z) - 1.2
	wrecks.append({"pos": p, "yaw": deg_to_rad(12.0), "roll": deg_to_rad(-7.0), "scale": 1.0})
	# Sandy Cape lighthouse (1870) on its hill
	var lz := f_to_z(0.942)
	lighthouses.append(Vector3(100.0, height_at(100.0, lz), lz))

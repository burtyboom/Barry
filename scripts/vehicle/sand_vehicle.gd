class_name SandVehicle
extends RigidBody3D
## A 4WD wagon with raycast wheels and a sand flotation / bogging model.
##
## THE SAND MODEL (per wheel, every physics tick)
## ------------------------------------------------
## 1. Ground pressure ~ tyre pressure (+ a bit for carcass stiffness).
##    Lower psi = bigger footprint = lower pressure on the sand.
## 2. Sand strength depends on softness (0 hard wet sand .. 1 sugar sand).
## 3. overload = ground_pressure / sand_strength. Sink target grows with overload^2,
##    shrinks with speed (momentum "planes" over soft sand).
## 4. Rolling resistance grows with sinkage (the tyre bulldozes a bow wave).
## 5. Grip falls on softer sand, but a lower psi footprint claws some back.
## 6. If you ask for more drive than the sand can take, the wheel spins and DIGS.
##    Dig depth adds to sinkage and only recovers when the wheel rolls without
##    spinning (e.g. reversing back out of your own ruts).
## Bogged = rolling resistance > grip, so the car won't move whatever you do.
##
## All the tuning numbers are @export so you can tweak them in the inspector.

signal bogged_changed(is_bogged: bool)
signal deflator_done(wheel: int)
signal bead_rolled(wheel: int)
signal bead_reseated(wheel: int)
signal rolled_over(state: int)   ## came to rest: 0 back on its wheels, 1 on its side, 2 on its roof

## Car-local points for recovery gear.
const FRONT_POINT := Vector3(0, 0.30, -2.50)   ## bullbar recovery point / winch fairlead
const REAR_POINT := Vector3(0, 0.10, 2.40)     ## tow hitch
const HOSE_POINT := Vector3(0.62, 0.95, 2.12)  ## compressor outlet at the back of the tub
const DEFLATE_RATE := 1.4                      ## psi per second through a deflator
## Rolling a bead off the rim needs very low pressure, real speed and sustained hard
## cornering on firm sand - a warning shows on the tyre display first.
const BEAD_PSI := 13.0
const BEAD_SPEED := 11.0                       ## m/s (~40 km/h)
const BEAD_SIDE_LOAD := 0.68                   ## sideways force / wheel load
const BEAD_LIMIT := 0.8

const TERRAIN_MASK := 1
const RECOVER_TIME := 1.1                      ## seconds for the R recovery lift-and-flip
const RECOVER_COOLDOWN := 5.0

# -- drivetrain
@export var drive_force_high := 15000.0     ## N at the wheels in 4H, low speed
@export var drive_force_low := 30000.0      ## N at the wheels in 4L
@export var engine_power := 155000.0        ## W, limits force at speed
@export var max_speed_high := 24.0          ## m/s (~86 km/h cap; drive eases off over the last 2 m/s): ~80 flat out on hard sand
@export var soft_drag := 900.0              ## N per m/s at full softness: soft sand holds you back more the faster you go
@export var max_speed_low := 11.0           ## m/s (~40 km/h)
@export var max_speed_reverse := 7.0
@export var brake_force := 26000.0

# -- suspension / chassis
@export var spring_k := 42000.0
@export var damper_c := 3800.0
@export var rest_length := 0.42
@export var wheel_radius := 0.50
@export var max_steer := 0.60
@export var anti_roll := 14000.0
@export var cornering_k := 9.0              ## lateral force per N load per rad slip

# -- sand
@export var sand_strength_hard := 50.0      ## "psi" bearing strength of hardest sand
@export var sand_strength_soft := 12.0      ## "psi" bearing strength of softest sand
@export var sink_base_hard := 0.010         ## m sinkage at overload 1, hard sand
@export var sink_base_soft := 0.14          ## m sinkage at overload 1, softest sand
@export var dig_rate := 0.20                ## m/s of digging at full wheelspin on softest sand
@export var max_sink := 0.42
@export var rr_sink_coeff := 1.6            ## rolling resistance per (sinkage^1.2)
@export var grip_hard := 0.95
@export var grip_soft := 0.52
@export var low_psi_grip_bonus := 0.32

@export var body_color := Color(0.85, 0.85, 0.80)

class Wheel:
	var name := ""
	var mount := Vector3.ZERO
	var front := false
	var left := false
	var psi := 32.0
	var sink := 0.0
	var dig := 0.0
	var comp := 0.0
	var prev_comp := 0.0
	var grounded := false
	var contact := Vector3.ZERO
	var normal := Vector3.UP
	var load := 0.0
	var soft := 0.0
	var surface := 0
	var in_water := false
	var on_deck := false      # on the barge's steel deck / ramp
	var spin_angle := 0.0
	var spin_speed := 0.0
	var slip := 0.0           # 0 = rolling, >0 = spinning
	var rr := 0.0             # rolling resistance coefficient
	var mu := 0.0             # grip coefficient
	var long_avail := 0.0
	var rr_left := 0.0        # unused rolling resistance (holds a stationary bogged car)
	var lat_force := 0.0
	var flat := false          # rolled off the bead: no air until it's pumped back up
	var bead_risk := 0.0
	var v_long := 0.0
	var fwd := Vector3.FORWARD
	var pivot: Node3D
	var spinner: Node3D
	var tyre_mesh: MeshInstance3D

var wheels: Array[Wheel] = []
var island: IslandData

# inputs / state
var throttle := 0.0
var brake := 0.0
var steer := 0.0
var handbrake := false
var low_range := false
var rear_locker := false
var front_locker := false
var reversing := false
var is_bogged := false
var _bog_timer := 0.0
var local_control := true   ## false for remote players' cars
var scripted := false       ## tests/AI: throttle/steer/brake set externally
var bog_proof := false      ## bots (admin toggle): sinks less and never digs itself in
var carrier: Node = null    ## barge carrying this car (frozen until the ramp drops)
var driver_present := true  ## false while the driver is out walking around (handbrake on)
var _towed_t := 0.0         ## > 0 while a strap / winch is pulling on us
var _pushed_t := 0.0        ## > 0 while another ute is nudging us with its bumper
var pusher: SandVehicle     ## who's doing the nudging
var push_dir := Vector3.ZERO   ## flat direction they're shoving us
var _engine_snd: AudioStreamPlayer3D
var _hiss_snd: AudioStreamPlayer3D
var livery := ""            ## "" / police / ambulance / ranger (set before adding to the tree)
var lights_on := false      ## flashing light bar
var siren_on := false
var horn_on := false
var _horn_snd: AudioStreamPlayer3D
var _siren_snd: AudioStreamPlayer3D
var _bar_mats: Array[StandardMaterial3D] = []
var _bar_lights: Array[OmniLight3D] = []
var _bar_cols: Array[Color] = []
var _wave_arm: Node3D
var _wave_t := 0.0
var _door_was := 0.0
var deflators := PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])   ## target psi per wheel, -1 = none
var _deflator_nodes: Array[Node3D] = []
var _deflator_mats: Array[StandardMaterial3D] = []
var door_pivot: Node3D
var door_target := 0.0      ## 0 shut .. 1 wide open
var _door := 0.0
var _pending_place := Transform3D.IDENTITY
var _has_pending_place := false
var roll_state := 0          ## 0 upright, 1 resting on its side, 2 on its roof
var _rest_t := 0.0
var _rolled_t := 0.0         ## how long it's been lying rolled (bots flip themselves back)
var _recover_t := -1.0       ## >= 0 while the R recovery is lifting / flipping the ute
var _recover_cd := 0.0
var _rec_from := Transform3D.IDENTITY
var _rec_to := Transform3D.IDENTITY

var speed_kmh := 0.0
var avg_sink := 0.0
var avg_soft := 0.0
var water_depth := 0.0       ## how deep the body is in the sea / a lake (m)
var surface_name := ""

# network
var _net_timer := 0.0
var _net_target_pos := Vector3.ZERO
var _net_target_rot := Quaternion.IDENTITY
var _net_has_state := false

var tracks: TyreTracks
var spray: SandSpray


func _ready() -> void:
	island = IslandData.instance
	mass = 2500.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.05, 0)
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	can_sleep = false
	contact_monitor = true      # to notice another ute nudging us out of a bog
	max_contacts_reported = 4
	continuous_cd = false
	linear_damp = 0.0
	angular_damp = 0.4
	var pm := PhysicsMaterial.new()
	pm.friction = 0.55
	physics_material_override = pm
	_build_body()
	_build_wheels()
	tracks = TyreTracks.new()
	tracks.name = "TyreTracks"
	add_child(tracks)
	spray = SandSpray.new()
	spray.name = "SandSpray"
	add_child(spray)
	spray.setup(self)
	_engine_snd = Sfx.make_loop("engine", -9.0)
	_engine_snd.position = Vector3(0, 0.6, -1.5)
	add_child(_engine_snd)
	_engine_snd.play()
	_hiss_snd = Sfx.make_loop("hiss", -14.0)
	add_child(_hiss_snd)
	_horn_snd = Sfx.make_loop("horn", -3.0)
	_horn_snd.position = Vector3(0, 0.6, -2.0)
	_horn_snd.max_distance = 200.0
	_horn_snd.unit_size = 14.0
	add_child(_horn_snd)
	if livery == "police" or livery == "ambulance":
		_siren_snd = Sfx.make_loop("siren_wail" if livery == "police" else "siren_yelp", -4.0)
		_siren_snd.position = Vector3(0, 1.8, 0)
		_siren_snd.max_distance = 400.0
		_siren_snd.unit_size = 22.0
		add_child(_siren_snd)


# ------------------------------------------------------------- construction
func _build_body() -> void:
	# --- collision (kept simple): main body + cab
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 1.0, 4.4)
	cs.shape = bs
	cs.position = Vector3(0, 0.1, 0)   # bottom at -0.4 => ~38 cm clearance on big tyres
	add_child(cs)
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(1.8, 0.7, 2.0)
	cs2.shape = bs2
	cs2.position = Vector3(0, 1.25, 0.05)
	add_child(cs2)
	_build_ranger()


## Cartoon dual-cab ute in the style of a Ford Ranger: tall flat nose with a big
## twin-bar grille, raked windscreen, flared arches, tub with a sports bar.
## Front is -Z. Wheels sit at x +-0.92, z +-1.45, centre y ~ -0.2.
func _build_ranger() -> void:
	var v := Node3D.new()
	v.name = "Visual"
	add_child(v)
	var paint := body_color
	var black := Color(0.13, 0.13, 0.14)
	var dark := Color(0.22, 0.22, 0.24)
	var glass := Color(0.20, 0.32, 0.45)
	var chrome := Color(0.80, 0.82, 0.86)
	var steel := Color(0.62, 0.64, 0.68)

	# --- main shell. Upper pieces sink well into the lower body so there are no
	# gaps or grooves between them - it should read as one solid ute.
	Toon.box(v, Vector3(1.9, 0.75, 4.36), Vector3(0, 0.225, 0), paint)            # lower body / doors
	Toon.box(v, Vector3(1.88, 0.62, 1.40), Vector3(0, 0.66, -1.48), paint)        # bonnet (top at 0.97)
	Toon.box(v, Vector3(1.0, 0.08, 1.1), Vector3(0, 0.97, -1.5), paint.darkened(0.06))   # power dome
	Toon.box(v, Vector3(1.86, 1.21, 1.34), Vector3(0, 1.005, 0.37), paint)        # cab, down to the sills
	# solid wedge under the raked windscreen (bonnet line up to the roof)
	Toon.prism_x(v, 1.84, PackedVector2Array([Vector2(-0.95, 0.70), Vector2(-0.28, 0.70),
		Vector2(-0.28, 1.58), Vector2(-0.95, 0.94)]), paint)
	var ws_c := Vector3(0, 1.26, -0.615)
	var ws_n := Basis(Vector3.RIGHT, deg_to_rad(-43.7)) * Vector3.UP
	Toon.box(v, Vector3(1.58, 0.05, 0.84), ws_c + ws_n * 0.03, glass, true, Vector3(-43.7, 0, 0))
	# side glass (front + rear doors) and back window
	Toon.box(v, Vector3(0.06, 0.40, 0.52), Vector3(-0.935, 1.33, -0.02), glass)   # passenger front (driver's is on the door)
	Toon.box(v, Vector3(1.90, 0.40, 0.56), Vector3(0, 1.33, 0.70), glass)
	Toon.box(v, Vector3(1.91, 0.42, 0.08), Vector3(0, 1.33, 0.34), paint)         # B-pillar
	Toon.box(v, Vector3(1.40, 0.34, 0.06), Vector3(0, 1.35, 1.055), glass)
	# door shut lines + handles
	for z in [-0.30, 0.34, 1.02]:
		Toon.box(v, Vector3(1.905, 0.95, 0.02), Vector3(0, 0.42, z), paint.darkened(0.3))
	for x in [-0.965, 0.965]:
		for z in [0.10, 0.80]:
			Toon.box(v, Vector3(0.04, 0.05, 0.18), Vector3(x, 0.52, z), black)
		Toon.box(v, Vector3(0.12, 0.12, 0.20), Vector3(signf(x) * 1.03, 1.12, -0.28), black)   # mirrors
	# roof rails
	for x in [-0.72, 0.72]:
		Toon.box(v, Vector3(0.06, 0.06, 1.15), Vector3(x, 1.63, 0.38), black)

	# --- driver's door (right-hand drive): hinged at its front edge, swings out
	door_pivot = Node3D.new()
	door_pivot.name = "DriverDoor"
	door_pivot.position = Vector3(0.955, 0, -0.29)
	v.add_child(door_pivot)
	Toon.box(door_pivot, Vector3(0.05, 1.60, 0.62), Vector3(0, 0.78, 0.31), paint)
	Toon.box(door_pivot, Vector3(0.06, 0.40, 0.50), Vector3(0.006, 1.33, 0.30), glass)
	Toon.box(door_pivot, Vector3(0.04, 0.05, 0.18), Vector3(0.035, 0.52, 0.44), black)
	Toon.box(door_pivot, Vector3(0.052, 0.02, 0.60), Vector3(0, 1.10, 0.31), paint.darkened(0.3))

	# --- nose: big grille with twin chrome bars, slim headlights, bumper
	Toon.box(v, Vector3(1.24, 0.38, 0.08), Vector3(0, 0.72, -2.19), black)
	for y in [0.65, 0.80]:
		Toon.box(v, Vector3(1.30, 0.07, 0.07), Vector3(0, y, -2.23), chrome)
	for x in [-0.73, 0.73]:
		Toon.box(v, Vector3(0.36, 0.17, 0.06), Vector3(x, 0.82, -2.19), Color(1.0, 0.98, 0.88), true, Vector3.ZERO, true)
		Toon.box(v, Vector3(0.36, 0.04, 0.05), Vector3(x, 0.72, -2.20), Color(1.0, 0.75, 0.3), true, Vector3.ZERO, true)  # DRL strip
	Toon.box(v, Vector3(1.96, 0.28, 0.28), Vector3(0, 0.30, -2.18), dark)          # front bumper
	# steel bullbar with a winch in the middle
	Toon.box(v, Vector3(2.0, 0.16, 0.16), Vector3(0, 0.30, -2.42), steel)
	var drum := Node3D.new()
	drum.position = Vector3(0, 0.30, -2.30)
	v.add_child(drum)
	Toon.cyl_x(drum, 0.12, 0.42, 20, Vector3.ZERO, Color(0.12, 0.12, 0.13))
	Toon.cyl_x(drum, 0.10, 0.44, 20, Vector3.ZERO, Color(0.85, 0.15, 0.10))
	Toon.box(v, Vector3(0.12, 0.08, 0.06), Vector3(0, 0.30, -2.51), Color(0.75, 0.75, 0.78))   # fairlead
	Toon.box(v, Vector3(0.05, 0.12, 0.05), Vector3(0, 0.22, -2.54), Color(0.95, 0.75, 0.10))   # hook
	for x in [-0.5, 0.5]:
		Toon.box(v, Vector3(0.12, 0.72, 0.12), Vector3(x, 0.62, -2.42), steel)
	Toon.box(v, Vector3(1.12, 0.12, 0.12), Vector3(0, 0.98, -2.40), steel)
	for x in [-0.82, 0.82]:
		Toon.box(v, Vector3(0.18, 0.14, 0.14), Vector3(x, 0.42, -2.38), Color(1.0, 0.95, 0.7), true, Vector3.ZERO, true)  # spotties

	# --- flared wheel arches (big black discs the tyres sit in front of)
	for x in [-0.97, 0.97]:
		for z in [-1.45, 1.45]:
			var arch := Node3D.new()
			arch.position = Vector3(x, -0.18, z)
			v.add_child(arch)
			Toon.cyl_x(arch, 0.66, 0.22, 28, Vector3.ZERO, black)
	# side steps + chassis
	for x in [-1.0, 1.0]:
		Toon.box(v, Vector3(0.16, 0.06, 1.35), Vector3(x, -0.10, 0.36), black)
	Toon.box(v, Vector3(1.5, 0.22, 4.0), Vector3(0, -0.24, 0), black)

	# --- tub: walls, tailgate, liner, tail lights, rear bumper
	for x in [-0.89, 0.89]:
		Toon.box(v, Vector3(0.14, 0.60, 1.18), Vector3(x, 0.71, 1.62), paint)
		Toon.box(v, Vector3(0.10, 0.42, 0.08), Vector3(x * 1.01, 0.80, 2.17), Color(1, 0.18, 0.12), true, Vector3.ZERO, true)
	Toon.box(v, Vector3(1.70, 0.60, 0.12), Vector3(0, 0.71, 2.16), paint)
	Toon.box(v, Vector3(0.50, 0.08, 0.04), Vector3(0, 0.86, 2.23), black)          # tailgate handle
	Toon.box(v, Vector3(1.66, 0.04, 1.08), Vector3(0, 0.62, 1.62), black)          # tub liner
	Toon.box(v, Vector3(1.9, 0.18, 0.24), Vector3(0, 0.10, 2.22), dark)            # rear bumper / step
	# sports bar behind the cab
	for x in [-0.78, 0.78]:
		Toon.box(v, Vector3(0.10, 0.62, 0.10), Vector3(x, 1.28, 1.18), black, true, Vector3(-12, 0, 0))
	Toon.box(v, Vector3(1.66, 0.10, 0.10), Vector3(0, 1.58, 1.24), black)

	# --- camping gear: swag on a roof platform, jerry cans + spare in the tub
	if livery == "":   # emergency utes keep the roof clear for the light bar
		Toon.box(v, Vector3(1.55, 0.05, 1.10), Vector3(0, 1.70, 0.38), black)
		Toon.box(v, Vector3(1.10, 0.30, 0.55), Vector3(0, 1.88, 0.40), Color(0.25, 0.45, 0.85))
	Toon.box(v, Vector3(0.42, 0.50, 0.26), Vector3(-0.55, 0.90, 1.35), Color(0.9, 0.15, 0.1))
	Toon.box(v, Vector3(0.42, 0.50, 0.26), Vector3(-0.55, 0.90, 1.66), Color(0.2, 0.6, 0.2))
	var spare := Node3D.new()
	spare.position = Vector3(0.35, 1.02, 1.62)
	v.add_child(spare)
	Toon.cyl_x(spare, 0.40, 0.30, 24, Vector3.ZERO, Color(0.18, 0.18, 0.18))
	Toon.cyl_x(spare, 0.22, 0.32, 24, Vector3.ZERO, Color(0.85, 0.85, 0.88))
	# shovel strapped to the tub side - for when you bog it
	Toon.box(v, Vector3(0.05, 0.08, 0.9), Vector3(-0.98, 0.82, 1.55), Color(0.6, 0.4, 0.2))
	Toon.box(v, Vector3(0.05, 0.28, 0.22), Vector3(-0.98, 0.82, 2.05), steel)
	# snorkel up the passenger-side A-pillar (very Fraser)
	Toon.box(v, Vector3(0.14, 0.95, 0.14), Vector3(1.0, 1.05, -0.82), black)
	Toon.box(v, Vector3(0.18, 0.16, 0.34), Vector3(1.0, 1.58, -0.88), black)
	_build_wave_arm(v)
	if livery != "":
		_build_livery(v)


## The driver's arm, poked out the window for a wave (hidden until a bot says g'day).
func _build_wave_arm(v: Node3D) -> void:
	_wave_arm = Node3D.new()
	_wave_arm.position = Vector3(1.0, 1.22, 0.02)
	_wave_arm.visible = false
	v.add_child(_wave_arm)
	var skin := Color(0.96, 0.78, 0.62)
	Toon.box(_wave_arm, Vector3(0.16, 0.16, 0.16), Vector3(0.06, 0.0, 0), body_color.darkened(0.15))   # sleeve on the sill
	Toon.box(_wave_arm, Vector3(0.13, 0.50, 0.13), Vector3(0.14, 0.26, 0), skin)
	Toon.box(_wave_arm, Vector3(0.10, 0.16, 0.16), Vector3(0.14, 0.58, 0), skin)                      # hand


## Respray the ute (the menu colour picker, or a friend's chosen colour arriving online).
func repaint(c: Color) -> void:
	if livery != "" or c.is_equal_approx(body_color):
		return
	var swaps := {}
	for k in [0.0, 0.06, 0.15, 0.3]:
		swaps[Toon.mat(body_color.darkened(k))] = Toon.mat(c.darkened(k))
	body_color = c
	_repaint(self, swaps)


func _repaint(n: Node, swaps: Dictionary) -> void:
	for ch in n.get_children():
		var mi := ch as MeshInstance3D
		if mi and swaps.has(mi.material_override):
			mi.material_override = swaps[mi.material_override]
		_repaint(ch, swaps)


## Emergency services / ranger paint, light bar and door writing.
func _build_livery(v: Node3D) -> void:
	var a := Color.WHITE
	var b := Color.WHITE
	var word := ""
	var bar: Array[Color] = []
	match livery:
		"police":
			a = Color(0.08, 0.20, 0.62)
			b = Color(0.97, 0.97, 0.97)
			word = "POLICE"
			bar = [Color(1.0, 0.1, 0.1), Color(0.15, 0.35, 1.0)]
		"ambulance":
			a = Color(0.85, 0.08, 0.10)
			b = Color(1.0, 0.85, 0.10)
			word = "AMBULANCE"
			bar = [Color(1.0, 0.1, 0.1), Color(1.0, 1.0, 1.0)]
		"ranger":
			a = Color(0.18, 0.40, 0.20)
			b = Color(0.95, 0.80, 0.25)
			word = "RANGER"
			bar = [Color(1.0, 0.6, 0.05), Color(1.0, 0.6, 0.05)]
	# checker band (Battenburg) down each side
	if livery == "ranger":
		for x in [-0.96, 0.96]:
			Toon.box(v, Vector3(0.02, 0.14, 4.0), Vector3(x * 1.01, 0.42, 0.0), a)
			Toon.box(v, Vector3(0.02, 0.05, 4.0), Vector3(x * 1.01, 0.32, 0.0), b)
	else:
		var sq := 0.24
		var n := int(3.9 / sq)
		for x in [-0.96, 0.96]:
			for k in n:
				for row in 2:
					var c := a if (k + row) % 2 == 0 else b
					Toon.box(v, Vector3(0.02, sq, sq), Vector3(x * 1.01, 0.30 + row * sq, -1.95 + (k + 0.5) * sq), c, false)
	# name on the doors and across the bonnet
	for side in [-1.0, 1.0]:
		var l := Label3D.new()
		l.text = word
		l.font_size = 64
		l.pixel_size = 0.0045
		l.outline_size = 0
		l.modulate = a if livery != "ranger" else Color(0.15, 0.3, 0.15)
		l.position = Vector3(side * 0.99, 0.80, 0.25)
		l.rotation_degrees = Vector3(0, 90.0 * side, 0)
		l.double_sided = false
		v.add_child(l)
	var top := Label3D.new()
	top.text = word
	top.font_size = 64
	top.pixel_size = 0.004
	top.modulate = a
	top.position = Vector3(0, 0.98, -1.55)
	top.rotation_degrees = Vector3(-90, 0, 0)
	v.add_child(top)
	if livery == "ambulance":
		# canopy on the tub with a big red cross
		Toon.box(v, Vector3(1.78, 0.80, 1.20), Vector3(0, 1.30, 1.62), Color(0.97, 0.97, 0.97))
		for s in [-1.0, 1.0]:
			Toon.box(v, Vector3(0.02, 0.44, 0.14), Vector3(s * 0.90, 1.32, 1.62), a)
			Toon.box(v, Vector3(0.02, 0.14, 0.44), Vector3(s * 0.90, 1.32, 1.62), a)
		Toon.box(v, Vector3(0.44, 0.02, 0.14), Vector3(0, 1.71, 1.62), a)
		Toon.box(v, Vector3(0.14, 0.02, 0.44), Vector3(0, 1.71, 1.62), a)
	# light bar across the front of the roof
	Toon.box(v, Vector3(1.50, 0.08, 0.26), Vector3(0, 1.73, -0.08), Color(0.12, 0.12, 0.13))
	for k in 2:
		var m := StandardMaterial3D.new()
		m.albedo_color = bar[k].darkened(0.45)
		m.emission_enabled = true
		m.emission = bar[k]
		m.emission_energy_multiplier = 0.0
		var lb := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.66, 0.14, 0.22)
		lb.mesh = bm
		lb.material_override = m
		lb.position = Vector3(-0.37 + k * 0.74, 1.83, -0.08)
		v.add_child(lb)
		_bar_mats.append(m)
		_bar_cols.append(bar[k])
		var ol := OmniLight3D.new()
		ol.light_color = bar[k]
		ol.omni_range = 9.0
		ol.light_energy = 0.0
		ol.position = lb.position + Vector3(0, 0.2, 0)
		v.add_child(ol)
		_bar_lights.append(ol)


# ------------------------------------------------------------- lights, siren, horn, wave
## Owner sets these; everyone else gets told.
func set_signals(lights: bool, siren: bool, horn: bool) -> void:
	if lights == lights_on and siren == siren_on and horn == horn_on:
		return
	_apply_signals(lights, siren, horn)
	if _online_net():
		_rpc_signals.rpc(lights, siren, horn)


@rpc("authority", "call_remote", "reliable")
func _rpc_signals(lights: bool, siren: bool, horn: bool) -> void:
	_apply_signals(lights, siren, horn)


func _apply_signals(lights: bool, siren: bool, horn: bool) -> void:
	lights_on = lights
	siren_on = siren and _siren_snd != null
	horn_on = horn
	if _siren_snd and siren_on != _siren_snd.playing:
		if siren_on:
			_siren_snd.play()
		else:
			_siren_snd.stop()
	if horn_on != _horn_snd.playing:
		if horn_on:
			_horn_snd.play()
		else:
			_horn_snd.stop()


## Arm out the window for a wave, optionally with a friendly beep beep.
func wave(beep := true) -> void:
	_do_wave(beep)
	if _online_net():
		_rpc_wave.rpc(beep)


@rpc("authority", "call_remote", "reliable")
func _rpc_wave(beep: bool) -> void:
	_do_wave(beep)


func _do_wave(beep: bool) -> void:
	_wave_t = 2.6
	if beep:
		Sfx.play_at(self, "beep2", global_transform * Vector3(0, 0.6, -2.0), 0.0, randf_range(0.95, 1.08))


func _online_net() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _update_signals(delta: float) -> void:
	if _wave_arm:
		_wave_t -= delta
		_wave_arm.visible = _wave_t > 0.0 and driver_present
		if _wave_arm.visible:
			_wave_arm.rotation = Vector3(0, 0, -0.25 + sin(_wave_t * 11.0) * 0.45)
	if _bar_mats.is_empty():
		return
	var t := Time.get_ticks_msec() * 0.001
	for k in _bar_mats.size():
		var on := 0.0
		if lights_on:
			# double-flash each side in turn
			var ph := fposmod(t * 2.0 + k * 0.5, 1.0)
			on = 1.0 if (ph < 0.12 or (ph > 0.2 and ph < 0.32)) else 0.0
		_bar_mats[k].emission_energy_multiplier = 4.0 * on
		_bar_mats[k].albedo_color = _bar_cols[k] if on > 0.5 else _bar_cols[k].darkened(0.45)
		_bar_lights[k].light_energy = 3.0 * on


func _build_wheels() -> void:
	var defs := [
		["FL", Vector3(-0.92, 0.0, -1.45), true, true],
		["FR", Vector3(0.92, 0.0, -1.45), true, false],
		["RL", Vector3(-0.92, 0.0, 1.45), false, true],
		["RR", Vector3(0.92, 0.0, 1.45), false, false],
	]
	for d in defs:
		var w := Wheel.new()
		w.name = d[0]
		w.mount = d[1]
		w.front = d[2]
		w.left = d[3]
		w.pivot = Node3D.new()
		w.pivot.position = w.mount - Vector3(0, rest_length, 0)
		add_child(w.pivot)
		w.spinner = Node3D.new()
		w.pivot.add_child(w.spinner)
		# chunky 10-sided tyre, bright rim, hub cap - blocky so you can SEE it spin
		var side := -1.0 if w.left else 1.0
		w.tyre_mesh = Toon.cyl_x(w.spinner, wheel_radius, 0.42, 10, Vector3.ZERO, Color(0.2, 0.19, 0.19))
		Toon.cyl_x(w.spinner, wheel_radius * 0.55, 0.44, 6, Vector3.ZERO, Color(1.0, 0.82, 0.2), false)
		Toon.box(w.spinner, Vector3(0.06, 0.16, wheel_radius * 0.9), Vector3(0.22 * side, 0, 0), Color(0.15, 0.15, 0.15), false)
		# tread blocks
		for k in 10:
			var a := TAU * k / 10.0
			var tb := Toon.box(w.spinner, Vector3(0.44, 0.08, 0.14),
				Vector3(0, cos(a) * (wheel_radius + 0.02), sin(a) * (wheel_radius + 0.02)),
				Color(0.15, 0.14, 0.14), false)
			tb.rotation.x = -a
		wheels.append(w)
		# deflator cap on the valve, hidden until one is screwed on
		var cap := Node3D.new()
		cap.position = Vector3(0.25 * side, 0.18, 0.0)
		cap.visible = false
		w.pivot.add_child(cap)
		var cm := StandardMaterial3D.new()
		cm.albedo_color = Color(0.85, 0.65, 0.20)
		cm.metallic = 0.6
		cm.roughness = 0.35
		var cmesh := CylinderMesh.new()
		cmesh.top_radius = 0.035
		cmesh.bottom_radius = 0.035
		cmesh.height = 0.12
		var cmi := MeshInstance3D.new()
		cmi.mesh = cmesh
		cmi.material_override = cm
		cmi.rotation_degrees = Vector3(0, 0, 90)
		cap.add_child(cmi)
		_deflator_nodes.append(cap)
		_deflator_mats.append(cm)


# ------------------------------------------------------------- tyre pressure API
func set_all_psi(p: float) -> void:
	for i in wheels.size():
		set_wheel_psi(i, p)


func adjust_all_psi(delta_psi: float) -> void:
	for i in wheels.size():
		set_wheel_psi(i, wheels[i].psi + delta_psi)


func _roll_bead(w: Wheel) -> void:
	w.flat = true
	w.psi = 2.0
	w.bead_risk = 0.0
	bead_rolled.emit(wheels.find(w))


func set_wheel_psi(index: int, p: float, from_pump := false) -> void:
	var w := wheels[index]
	if w.flat:
		# a rolled bead only reseats once you've pumped plenty of air back in with the inflator
		if not from_pump:
			return
		if p > 15.0:
			w.flat = false
			bead_reseated.emit(index)
		else:
			w.psi = clampf(p, 2.0, 15.0)
			return
	var np := clampf(p, 8.0, 45.0)
	# Airing down while dug in helps: the bigger footprint lifts the tyre
	# up out of the hole it dug.
	if np < w.psi and w.dig > 0.0:
		w.dig *= pow(np / w.psi, 1.5)
	w.psi = np


func average_psi() -> float:
	var t := 0.0
	for w in wheels:
		t += w.psi
	return t / wheels.size()


# ------------------------------------------------------------- recovery gear
func wheel_valve_world(i: int) -> Vector3:
	return wheels[i].pivot.global_position + global_basis.x * (0.25 if not wheels[i].left else -0.25)


func _run_deflators(delta: float) -> void:
	for i in wheels.size():
		var target := deflators[i]
		if target < 0.0:
			continue
		var w := wheels[i]
		if w.psi > target + 0.05:
			set_wheel_psi(i, maxf(w.psi - DEFLATE_RATE * delta, target))
			if w.psi <= target + 0.05:
				deflator_done.emit(i)


func _update_deflator_visuals() -> void:
	for i in _deflator_nodes.size():
		var on := deflators[i] >= 0.0
		_deflator_nodes[i].visible = on
		if on:
			var done := wheels[i].psi <= deflators[i] + 0.1
			_deflator_mats[i].albedo_color = Color(0.3, 0.85, 0.35) if done else Color(0.85, 0.65, 0.20)


func _update_sounds() -> void:
	if _engine_snd == null:
		return
	# revs from road speed (per gear range) plus a flare when you're on the throttle / spinning
	var top := max_speed_low if low_range else max_speed_high
	var spin := 0.0
	for w in wheels:
		spin = maxf(spin, absf(w.spin_speed) * wheel_radius)
	var rev := clampf(spin / top, 0.0, 1.0)
	var thr := throttle if local_control else clampf(absf(speed_kmh) / 30.0, 0.0, 1.0)
	_engine_snd.pitch_scale = 0.75 + rev * 1.35 + thr * 0.3
	_engine_snd.volume_db = -14.0 + thr * 7.0 + rev * 3.0
	var hissing := false
	for i in wheels.size():
		if deflators[i] >= 0.0 and wheels[i].psi > deflators[i] + 0.1:
			hissing = true
	if hissing != _hiss_snd.playing:
		if hissing:
			_hiss_snd.play()
		else:
			_hiss_snd.stop()


## Bogged, or sitting dug into the sand (wheels in holes) - the one a winch should pull out.
func dug_in() -> bool:
	if is_bogged:
		return true
	for w in wheels:
		if w.dig > 0.06:
			return true
	return false


## Called by the rope system while a strap / winch is pulling on this car.
## Another ute leaning on our bumper: counts as a tow (handbrake off if nobody's in),
## and bots that are bogged hop in and drive with the push.
func _check_pushed(delta: float) -> void:
	_pushed_t -= delta
	if _pushed_t > 0.0:
		# a steady shove rocks the tyres up out of their holes (that's why a nudge works)
		for w in wheels:
			w.dig = move_toward(w.dig, 0.0, 0.15 * delta)
	for b in get_colliding_bodies():
		var other := b as SandVehicle
		if other == null:
			continue
		var d := global_position - other.global_position
		d.y = 0.0
		var closing := other.linear_velocity.dot(d.normalized())
		if closing > 0.3 or (absf(other.throttle) > 0.2 and other.local_control):
			_pushed_t = 0.6
			pusher = other
			push_dir = d.normalized()
			note_towed()


func note_towed() -> void:
	_towed_t = 0.5


## Other players can use their tools on this car: the owner applies the change.
@rpc("any_peer", "call_local", "reliable")
func remote_set_psi(i: int, psi: float) -> void:
	if local_control:
		set_wheel_psi(i, psi, true)


@rpc("any_peer", "call_local", "reliable")
func remote_deflator(i: int, target: float) -> void:
	if local_control:
		deflators[i] = target


@rpc("any_peer", "call_local", "reliable")
func remote_dig(i: int) -> void:
	if local_control:
		wheels[i].dig = 0.0
		wheels[i].sink *= 0.35
		_bog_timer = 0.0


## Calls one of the remote_* functions on whoever owns this car.
func ask_owner(method: String, args: Array) -> void:
	if local_control or multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		callv(method, args)
	else:
		callv("rpc_id", [get_multiplayer_authority(), method] + args)


## Barge API: ride frozen on the deck until released.
func set_carried(by: Node) -> void:
	carrier = by
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	speed_kmh = 0.0
	surface_name = "On the barge"
	for w in wheels:
		w.grounded = true
		w.comp = rest_length * 0.45
		w.spin_speed = 0.0
		w.sink = 0.0
		w.dig = 0.0


func release_from_carrier() -> void:
	carrier = null
	if local_control:
		freeze = false
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


## R: lift the ute up, flip it back onto its wheels and set it down (about a second),
## pop any rolled beads back on and clear the holes it's dug. Returns false on cooldown.
func recover() -> bool:
	if carrier != null or _recover_t >= 0.0:
		return false
	if _recover_cd > 0.0:
		_toast("Recovery ready in %d s" % ceili(_recover_cd))
		return false
	_recover_cd = RECOVER_COOLDOWN
	var fwd := -global_basis.z
	fwd.y = 0
	if fwd.length() < 0.2:
		# nose straight up or down: use the roof direction instead
		fwd = global_basis.y
		fwd.y = 0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	var pos := global_position
	pos.y = island.height_at(pos.x, pos.z) + 1.4
	_rec_from = global_transform
	_rec_to = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), pos)
	_recover_t = 0.0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	Sfx.play_at(self, "whoosh", global_position, -6.0, 0.8)
	return true


func _run_recovery(delta: float) -> void:
	_recover_t += delta
	var k := clampf(_recover_t / RECOVER_TIME, 0.0, 1.0)
	var pos := _rec_from.origin.lerp(_rec_to.origin, smoothstep(0.0, 1.0, k))
	pos.y += sin(k * PI) * 2.2
	var q := _rec_from.basis.get_rotation_quaternion().slerp(_rec_to.basis.get_rotation_quaternion(), smoothstep(0.12, 0.85, k))
	global_transform = Transform3D(Basis(q), pos)
	if k < 1.0:
		return
	_recover_t = -1.0
	freeze = false
	_place(_rec_to)
	for w in wheels:
		w.prev_comp = 0.0
		if w.flat:
			# the loose tyre goes back on the rim with enough air to drive on
			w.flat = false
			w.psi = 18.0
		w.bead_risk = 0.0
	_bog_timer = 0.0
	if is_bogged:
		is_bogged = false
		bogged_changed.emit(false)
	_rest_t = 0.0
	_rolled_t = 0.0
	if roll_state != 0:
		roll_state = 0
		rolled_over.emit(0)
	Sfx.play_at(self, "thunk", global_position, -2.0, 0.8)


## Has it come to rest on its side or roof? Bots that roll flip themselves back after a bit.
func _check_rolled(delta: float) -> void:
	var still := linear_velocity.length() < 0.6 and angular_velocity.length() < 0.6
	_rest_t = _rest_t + delta if still else 0.0
	var up_y := global_basis.y.y
	if _rest_t > 1.0 or (roll_state != 0 and up_y > 0.75):
		var st := 0
		if up_y < -0.5:
			st = 2
		elif up_y < 0.55:
			st = 1
		if st != roll_state:
			roll_state = st
			rolled_over.emit(st)
			if st != 0:
				_on_local_rollover()
	_rolled_t = _rolled_t + delta if roll_state != 0 else 0.0
	if scripted and _rolled_t > 6.0:
		_recover_cd = 0.0
		recover()


func _main() -> Node:
	return get_parent().get_parent() if get_parent() else null


func _toast(text: String) -> void:
	var m := _main()
	if local_control and m and m.get("hud") and is_local_players():
		m.hud.show_toast(text)


## Is this the local player's ute (the one they drive / just got out of)? Toasts are only for them.
func is_local_players() -> bool:
	var m := _main()
	var lp: Node = m.get("local_player") if m else null
	return lp != null and is_instance_valid(lp) and lp.get("car") == self


func _on_local_rollover() -> void:
	var m := _main()
	if m == null or not is_local_players():
		return
	var ach: Node = m.get("achievements")
	if ach:
		ach.unlock("rollover")
	_toast("You've rolled it! Climb out (E) or press R to flip it back on its wheels")


func teleport(pos: Vector3, heading := Vector3.FORWARD) -> void:
	release_from_carrier()
	var p := pos
	p.y = island.height_at(p.x, p.z) + 1.4
	_place(Transform3D(Basis.looking_at(heading, Vector3.UP), p))
	if tracks:
		tracks.clear()


## Moves the car instantly. Applied again inside the next physics step
## (_integrate_forces), because setting the transform directly can be lost -
## e.g. on the same frame the car is released from the barge.
func _place(xf: Transform3D) -> void:
	global_transform = xf
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_pending_place = xf
	_has_pending_place = true
	for w in wheels:
		w.sink = 0.0
		w.dig = 0.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _has_pending_place:
		_has_pending_place = false
		state.transform = _pending_place
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO


# ------------------------------------------------------------- input
func _read_input(delta: float) -> void:
	var typing := Hud.typing()   # typing in chat: hands off the controls
	var fwd_in := 0.0 if typing else Input.get_action_strength("throttle")
	var back_in := 0.0 if typing else Input.get_action_strength("brake")
	var steer_in := 0.0 if typing else Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	handbrake = Input.is_action_pressed("handbrake")
	var v_long := linear_velocity.dot(-global_basis.z)

	if reversing:
		if fwd_in > 0.05:
			if v_long < -0.8:
				throttle = 0.0
				brake = fwd_in
			else:
				reversing = false
				throttle = fwd_in
				brake = 0.0
		else:
			throttle = back_in
			brake = 0.0
	else:
		if back_in > 0.05 and v_long < 0.8:
			reversing = true
			throttle = back_in
			brake = 0.0
		else:
			throttle = fwd_in
			brake = back_in

	var speed := absf(v_long)
	var lim := max_steer / (1.0 + speed / 14.0)
	var target := steer_in * lim
	var rate := 1.8 if absf(target) > absf(steer) else 3.0
	steer = move_toward(steer, target, rate * delta)


func _unhandled_input(event: InputEvent) -> void:
	if not local_control or not driver_present or scripted:
		return
	if event.is_action_pressed("psi_road"):
		set_all_psi(32.0)
	elif event.is_action_pressed("psi_sand"):
		set_all_psi(18.0)
	elif event.is_action_pressed("psi_soft"):
		set_all_psi(15.0)
	elif event.is_action_pressed("psi_stuck"):
		set_all_psi(12.0)
	elif event.is_action_pressed("psi_down"):
		adjust_all_psi(-1.0)
	elif event.is_action_pressed("psi_up"):
		adjust_all_psi(1.0)
	elif event.is_action_pressed("range_toggle"):
		if absf(speed_kmh) < 8.0:
			low_range = not low_range
	elif event.is_action_pressed("rear_locker"):
		rear_locker = not rear_locker
	elif event.is_action_pressed("front_locker"):
		front_locker = not front_locker
	elif event.is_action_pressed("recover"):
		recover()


## R on foot, next to your own ute: recover it from outside.
func _input(event: InputEvent) -> void:
	if not local_control or driver_present or scripted or not event.is_action_pressed("recover"):
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var m := _main()
	var lp: Node3D = m.get("local_player") if m else null
	if lp == null or not is_instance_valid(lp) or lp.get("car") != self or not lp.call("is_on_foot"):
		return
	if lp.global_position.distance_to(global_position) < 8.0:
		recover()
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------- physics
func _physics_process(delta: float) -> void:
	if not local_control:
		_remote_update(delta)
		return
	_check_pushed(delta)
	_recover_cd = maxf(_recover_cd - delta, 0.0)
	if carrier != null:
		_net_send(delta)   # others still see us riding in
		return
	if _recover_t >= 0.0:
		_run_recovery(delta)
		_net_send(delta)
		return
	_check_rolled(delta)
	if not scripted:
		if driver_present:
			_read_input(delta)
			set_signals(lights_on, siren_on, Input.is_action_pressed("horn"))
		else:
			# nobody at the wheel: handbrake on, foot off
			throttle = 0.0
			brake = 0.0
			handbrake = _towed_t <= 0.0   # let it roll when someone's pulling it out
			steer = move_toward(steer, 0.0, delta)
			if horn_on:
				set_signals(lights_on, siren_on, false)
	_towed_t -= delta
	_simulate(delta)
	_run_deflators(delta)
	_net_send(delta)


func _simulate(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var up := global_basis.y
	var fwd_body := -global_basis.z
	var com := global_transform * center_of_mass
	var v_body := linear_velocity.dot(fwd_body)
	var m4 := mass * 0.25
	var g := 9.81

	# ---- pass 1: suspension
	var sink_sum := 0.0
	var soft_sum := 0.0
	var grounded_n := 0
	# lying on its side or roof: the wheels are in the air, whatever a ray might find
	var wheels_down := up.y > 0.4
	for w in wheels:
		if not wheels_down:
			w.prev_comp = w.comp
			w.grounded = false
			w.comp = 0.0
			w.load = 0.0
			continue
		var origin := global_transform * w.mount
		var ray_len := rest_length + wheel_radius + max_sink + 0.15
		var q := PhysicsRayQueryParameters3D.create(origin, origin - up * ray_len, TERRAIN_MASK, [get_rid()])
		var hit := space.intersect_ray(q)
		w.prev_comp = w.comp
		if hit.is_empty():
			w.grounded = false
			w.comp = 0.0
			w.load = 0.0
			continue
		var hp: Vector3 = hit["position"]
		var dist := origin.distance_to(hp)
		w.contact = hp
		w.normal = hit["normal"]
		w.surface = island.surface_at(hp.x, hp.z)
		w.soft = island.softness_at(hp.x, hp.z)
		if w.surface == IslandData.Surface.ROCK:
			w.soft = 0.0
		w.in_water = hp.y < island.water_level_at(hp.x, hp.z) - 0.05
		if w.in_water:
			w.soft = minf(w.soft, 0.18)   # submerged sand is firm
		var col: Object = hit.get("collider")
		w.on_deck = col != null and col.has_meta("deck")
		if w.on_deck:
			w.surface = IslandData.Surface.ROCK   # hard, no sinking, no tracks
			w.soft = 0.0
			w.in_water = false
		var comp := rest_length + wheel_radius - (dist + w.sink)
		if comp <= 0.0:
			w.grounded = false
			w.comp = 0.0
			w.load = 0.0
			continue
		w.grounded = true
		w.comp = minf(comp, rest_length)
		grounded_n += 1
		sink_sum += w.sink
		soft_sum += w.soft

	# water: drag and a little buoyancy once the body is in the sea or a lake,
	# so high tide really does cut off parts of the beach
	var sea := island.water_level_at(global_position.x, global_position.z)
	var sea_depth := sea - (global_position.y - 0.45)
	water_depth = maxf(sea_depth, 0.0)
	if sea_depth > 0.0:
		var dd := minf(sea_depth, 1.6)
		apply_central_force(-linear_velocity * (900.0 + 2600.0 * dd))
		apply_central_force(Vector3.UP * mass * 9.81 * 0.22 * dd)

	# anti-roll bars (only while both wheels on the axle are down: once one lifts
	# the bar can't hold the car up any more, and it rolls)
	var ar_front := (wheels[0].comp - wheels[1].comp) * anti_roll if wheels[0].grounded and wheels[1].grounded else 0.0
	var ar_rear := (wheels[2].comp - wheels[3].comp) * anti_roll if wheels[2].grounded and wheels[3].grounded else 0.0
	# Side slopes: sliding sideways across a steep face, the downhill tyres dig into the
	# sand and trip the ute - so the sideways grip acts low down and can roll it over.
	# On flat ground it acts a little above the contact patch, so it never rolls there.
	var side_slope := asin(clampf(absf(global_basis.x.y), 0.0, 1.0)) if grounded_n > 0 else 0.0
	var trip := smoothstep(deg_to_rad(14.0), deg_to_rad(28.0), side_slope)

	for k in wheels.size():
		var w := wheels[k]
		if not w.grounded:
			continue
		var comp_vel := (w.comp - w.prev_comp) / delta
		var fs := spring_k * w.comp + damper_c * comp_vel
		if w.comp > rest_length * 0.9:
			fs += (w.comp - rest_length * 0.9) * spring_k * 6.0
		var ar := ar_front if w.front else ar_rear
		fs += ar if w.left else -ar
		fs = maxf(fs, 0.0)
		w.load = fs
		var origin := global_transform * w.mount
		apply_force(up * fs, origin - global_position)

	# ---- drive force available from the engine
	var speed := absf(v_body)
	var f_max := drive_force_low if low_range else drive_force_high
	var v_max := max_speed_low if low_range else max_speed_high
	if reversing:
		v_max = minf(v_max, max_speed_reverse)
	var drive_total := minf(f_max, engine_power / maxf(speed, 1.0))
	drive_total *= clampf((v_max - speed) / 2.0, 0.0, 1.0)
	drive_total *= throttle * (-1.0 if reversing else 1.0)

	# ---- pass 2: per-wheel tyre / sand model
	for w in wheels:
		w.slip = 0.0
		w.lat_force = 0.0
		w.rr_left = 0.0
		if not w.grounded:
			w.long_avail = 0.0
			w.v_long = v_body
			continue
		var n := w.normal
		var fwd := fwd_body
		if w.front:
			fwd = fwd.rotated(up, steer)
		fwd = (fwd - n * fwd.dot(n)).normalized()
		var side := fwd.cross(n)
		w.fwd = fwd
		var r := w.contact - com
		var v := linear_velocity + angular_velocity.cross(r)
		var v_long := v.dot(fwd)
		var v_lat := v.dot(side)
		w.v_long = v_long

		# --- sand flotation
		var s := w.soft
		var psi := w.psi
		var ground_p := psi * 0.85 + 5.5
		var strength := lerpf(sand_strength_hard, sand_strength_soft, s)
		var overload := ground_p / strength
		var load_f := sqrt(w.load / (m4 * g))
		var speed_f := 1.0 / (1.0 + absf(v_long) / 9.0)
		var target := lerpf(sink_base_hard, sink_base_soft, s) * overload * overload * load_f * speed_f
		if w.surface == IslandData.Surface.ROCK:
			target = 0.0
			w.dig = 0.0
		if bog_proof:
			target *= 0.5
			w.dig = 0.0
		target = minf(target + w.dig, max_sink)
		var rate := 3.0 if target > w.sink else 1.5
		w.sink = lerpf(w.sink, target, minf(1.0, rate * delta))

		# --- grip + rolling resistance
		var mu := lerpf(grip_hard, grip_soft, s)
		mu *= 1.0 + low_psi_grip_bonus * clampf((32.0 - psi) / 17.0, 0.0, 1.3) * s
		if w.flat:
			mu *= 0.55   # flapping sidewall, no grip
		if w.surface == IslandData.Surface.ROCK:
			mu = 0.85
		var rr := 0.015 + rr_sink_coeff * pow(w.sink, 1.2) + (0.3 if w.flat else 0.0)
		if w.surface == IslandData.Surface.FOREST:
			rr += 0.05
		w.mu = mu
		w.rr = rr

		# --- lateral
		var grip := mu * w.load
		var slip_angle := atan2(absf(v_lat), maxf(absf(v_long), 2.0))
		var sidewall := lerpf(0.6, 1.0, clampf((psi - 12.0) / 20.0, 0.0, 1.0))
		var lat_cap := minf(w.load * cornering_k * sidewall * slip_angle, grip)
		var lat_req := -v_lat * m4 / delta * 0.5
		var f_lat := clampf(lat_req, -lat_cap, lat_cap)
		if speed < 2.0:
			f_lat = clampf(lat_req, -grip, grip)
		w.lat_force = f_lat
		w.long_avail = sqrt(maxf(grip * grip - f_lat * f_lat, 0.0))
		var side_load := absf(f_lat) / maxf(w.load, 1.0)
		if not w.flat and psi < BEAD_PSI and speed > BEAD_SPEED and s < 0.45 and side_load > BEAD_SIDE_LOAD:
			# lower pressure = quicker to go: 12 psi takes ~3 s of flat-out cornering, 10 psi ~1 s
			w.bead_risk += clampf((BEAD_PSI - psi) / 4.0, 0.25, 1.0) * delta
			if w.bead_risk > BEAD_LIMIT:
				_roll_bead(w)
		else:
			w.bead_risk = maxf(w.bead_risk - delta * 2.0, 0.0)

		var pos := w.contact + up * 0.25 - global_position
		var trip_k := trip * clampf(maxf(absf(v_lat) / 1.5, speed / 10.0), 0.0, 1.0)
		apply_force(side * f_lat, w.contact + up * lerpf(0.25, -0.85, trip_k) - global_position)

		# --- rolling resistance (never reverses the car)
		var f_rr := minf(rr * w.load, absf(v_long) * m4 / delta * 0.9)
		apply_force(-fwd * signf(v_long) * f_rr, pos)
		w.rr_left = rr * w.load - f_rr

		# --- brakes
		var b := brake
		if handbrake and not w.front:
			b = 1.0
		if handbrake and w.front and speed < 1.0:
			b = 1.0
		if b > 0.0:
			var f_b := minf(minf(brake_force * 0.25 * b, w.long_avail), absf(v_long) * m4 / delta)
			apply_force(-fwd * signf(v_long) * f_b, pos)

	# ---- pass 3: distribute drive through the diffs (centre locked, part-time 4WD)
	_drive_axle(0, 1, drive_total * 0.5, front_locker, delta)
	_drive_axle(2, 3, drive_total * 0.5, rear_locker, delta)

	# ---- digging + visuals bookkeeping
	for w in wheels:
		if w.grounded and w.slip > 0.0 and w.surface != IslandData.Surface.ROCK:
			# (being pushed: the shove keeps the tyres climbing instead of digging)
			w.dig += dig_rate * minf(w.slip, 2.0) * pow(w.soft, 1.5) * delta * (0.25 if _pushed_t > 0.0 else 1.0)
		# rolling cleanly lets the wheel climb out of its hole
		if w.grounded and w.slip <= 0.0:
			var recover_k := absf(w.v_long) * 0.45
			w.dig = maxf(w.dig - w.dig * recover_k * delta - 0.002 * delta, 0.0)
		w.dig = clampf(w.dig, 0.0, max_sink)
		var roll_speed := w.v_long / wheel_radius
		var spin_extra := w.slip * 9.0 * signf(drive_total)
		w.spin_speed = roll_speed + spin_extra
		if not w.grounded:
			w.spin_speed = lerpf(w.spin_speed, 0.0, delta)

	# ---- aero drag + water
	var v2 := linear_velocity.length_squared()
	if v2 > 0.01:
		apply_central_force(-linear_velocity.normalized() * v2 * 1.1)
	# soft sand: the tyres plough a bow wave that pushes back harder the faster you go -
	# ~80 km/h on the hard sand by the water, a lot less up in the soft stuff (airing down helps)
	var on_ground := 0
	var psi_sum := 0.0
	for w in wheels:
		if w.grounded:
			on_ground += 1
		psi_sum += w.psi
	if on_ground > 0 and v2 > 0.01:
		var soft := island.softness_at(global_position.x, global_position.z)
		var psi_k := lerpf(0.65, 1.0, clampf((psi_sum / wheels.size() - 15.0) / 17.0, 0.0, 1.0))
		var hv := Vector3(linear_velocity.x, 0.0, linear_velocity.z)
		apply_central_force(-hv * soft_drag * soft * soft * psi_k * on_ground / 4.0)
	var wl := island.water_level_at(global_position.x, global_position.z)
	var depth := wl - (global_position.y - 0.7)
	if depth > 0.0:
		var dk := clampf(depth, 0.0, 1.5)
		apply_central_force(-linear_velocity * 1800.0 * dk)
		apply_central_force(Vector3.UP * mass * g * 0.25 * clampf(depth - 0.6, 0.0, 1.0))

	# ---- stats
	speed_kmh = v_body * 3.6
	avg_sink = sink_sum / maxf(grounded_n, 1)
	avg_soft = soft_sum / maxf(grounded_n, 1)
	var ws := wheels[0]
	surface_name = IslandData.SURFACE_NAMES[ws.surface] if ws.grounded else "Airborne"
	if ws.grounded and ws.on_deck:
		surface_name = "Barge deck"
	if roll_state != 0:
		surface_name = "On its roof!" if roll_state == 2 else "On its side!"
	var any_slip := false
	for w in wheels:
		if w.slip > 0.2:
			any_slip = true
	var stuck_now := throttle > 0.3 and speed < 0.3 and (any_slip or avg_sink > 0.25)
	_bog_timer = clampf(_bog_timer + (delta if stuck_now else -delta * 2.0), 0.0, 3.0)
	var b_now := _bog_timer > 1.5
	if b_now != is_bogged:
		is_bogged = b_now
		bogged_changed.emit(is_bogged)


func _drive_axle(il: int, ir: int, f_axle: float, locked: bool, _delta: float) -> void:
	var wl := wheels[il]
	var wr := wheels[ir]
	var req := absf(f_axle)
	if req < 1.0:
		return
	var al := wl.long_avail if wl.grounded else 0.0
	var ar := wr.long_avail if wr.grounded else 0.0
	var fl := 0.0
	var fr := 0.0
	var half := req * 0.5
	if locked:
		# a locked axle can push with whichever wheel has grip
		fl = minf(half, al)
		fr = minf(half, ar)
		var spare := req - fl - fr
		if spare > 0.0:
			var extra_l := minf(spare, al - fl)
			fl += extra_l
			spare -= extra_l
			fr += minf(spare, ar - fr)
		var total_avail := al + ar
		if req > total_avail:
			var sl := (req - total_avail) / maxf(total_avail, 200.0)
			wl.slip = sl
			wr.slip = sl
	else:
		# open diff: equal torque each side, capped by the weaker wheel
		var weak := minf(al, ar)
		var each := minf(half, weak)
		fl = each
		fr = each
		if half > weak:
			var sl := (half - weak) / maxf(weak, 200.0)
			if al <= ar:
				wl.slip = sl
			else:
				wr.slip = sl
	var dir := signf(f_axle)
	# when (nearly) stopped, rolling resistance acts like static friction against the drive
	if absf(wl.v_long) < 0.5:
		fl = maxf(fl - wl.rr_left, 0.0)
	if absf(wr.v_long) < 0.5:
		fr = maxf(fr - wr.rr_left, 0.0)
	if wl.grounded:
		apply_force(wl.fwd * fl * dir, wl.contact + global_basis.y * 0.25 - global_position)
	if wr.grounded:
		apply_force(wr.fwd * fr * dir, wr.contact + global_basis.y * 0.25 - global_position)


# ------------------------------------------------------------- visuals
func _process(delta: float) -> void:
	_update_deflator_visuals()
	_update_sounds()
	_update_signals(delta)
	if door_pivot:
		if door_target > 0.5 and _door_was <= 0.01:
			Sfx.play_at(self, "thunk", door_pivot.global_position, -10.0, 1.4)   # door unlatch
		if door_target < 0.5 and _door > 0.02 and _door - delta * 3.2 <= 0.0:
			Sfx.play_at(self, "thunk", door_pivot.global_position, -4.0)        # door shut
		_door_was = _door
		_door = move_toward(_door, door_target, delta * 3.2)
		door_pivot.rotation.y = smoothstep(0.0, 1.0, _door) * 1.2
	for w in wheels:
		var susp := rest_length - w.comp if w.grounded else rest_length
		w.pivot.position = w.mount - Vector3(0, susp, 0)
		w.pivot.rotation.y = steer if w.front else 0.0
		w.spin_angle = fmod(w.spin_angle - w.spin_speed * delta, TAU)
		w.spinner.rotation.x = w.spin_angle
		# squish the tyre a little at low pressure so you can see it
		# fatter, saggier tyre at low pressure so you can see it
		var squish := clampf((32.0 - w.psi) / 20.0, 0.0, 1.0)
		w.tyre_mesh.scale = Vector3(1.0, 1.0 + squish * 0.12, 1.0)
	if tracks and local_control:
		tracks.update_from(self, delta)
	if spray:
		spray.update_from(self)


# ------------------------------------------------------------- network
func _net_send(delta: float) -> void:
	var mp := multiplayer.multiplayer_peer
	if mp == null or mp is OfflineMultiplayerPeer or mp.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_net_timer += delta
	if _net_timer < 0.05:
		return
	_net_timer = 0.0
	var psis := PackedFloat32Array()
	var comps := PackedFloat32Array()
	var spins := PackedFloat32Array()
	for w in wheels:
		psis.append(w.psi)
		comps.append(w.comp)
		spins.append(w.spin_speed)
	_net_state.rpc(global_position, global_basis.get_rotation_quaternion(), linear_velocity, steer, psis, comps, spins, deflators, is_bogged)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(pos: Vector3, rot: Quaternion, vel: Vector3, st: float, psis: PackedFloat32Array, comps: PackedFloat32Array, spins: PackedFloat32Array, defl: PackedFloat32Array, bogged: bool) -> void:
	deflators = defl
	if bogged != is_bogged:
		is_bogged = bogged
		bogged_changed.emit(bogged)
	_net_target_pos = pos + vel * 0.05
	_net_target_rot = rot
	linear_velocity = vel
	steer = st
	for k in mini(wheels.size(), psis.size()):
		wheels[k].psi = psis[k]
		wheels[k].comp = comps[k]
		wheels[k].spin_speed = spins[k]
		wheels[k].grounded = comps[k] > 0.0
	# first update, or a big jump (teleport / barge): snap there rather than sweeping
	# the body across the island, which would shove other cars into the ground
	if not _net_has_state or pos.distance_to(global_position) > 8.0:
		global_position = pos
		global_basis = Basis(rot)
		_net_has_state = true


func _remote_update(delta: float) -> void:
	if not _net_has_state:
		return
	var t := minf(1.0, 12.0 * delta)
	global_position = global_position.lerp(_net_target_pos, t)
	var q := global_basis.get_rotation_quaternion().slerp(_net_target_rot, t)
	global_basis = Basis(q)
	speed_kmh = linear_velocity.length() * 3.6
	var up_y := global_basis.y.y
	roll_state = 2 if up_y < -0.5 else (1 if up_y < 0.55 else 0)

class_name SandSpray
extends Node3D
## Sand kicked up by the tyres. Only on soft sand: hard wet beach, rock, bush
## and water throw nothing. Amount grows with wheel speed and a lot with wheelspin,
## so a bogged car spinning its wheels roosts sand.
## Works for remote cars too (uses only the networked wheel state).

const AMOUNT := 220
const LIFETIME := 0.75
const SOFT_START := 0.38    ## softness where spray begins
const SOFT_FULL := 0.70     ## softness for full spray

var _emitters: Array[GPUParticles3D] = []
var _mats: Array[ParticleProcessMaterial] = []


func setup(car: SandVehicle) -> void:
	var grain := SphereMesh.new()
	grain.radius = 0.5
	grain.height = 1.0
	grain.radial_segments = 6
	grain.rings = 3
	var draw_mat := StandardMaterial3D.new()
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	draw_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	draw_mat.roughness = 1.0
	grain.material = draw_mat

	# grains shrink away at the end of their life instead of fading (stays toon)
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(0.6, 0.9))
	shrink.add_point(Vector2(1.0, 0.0))
	var shrink_tex := CurveTexture.new()
	shrink_tex.curve = shrink

	# per-grain brightness jitter, multiplied with the sand colour
	var jitter := Gradient.new()
	jitter.set_color(0, Color(0.80, 0.78, 0.74))
	jitter.set_color(1, Color(1.08, 1.06, 1.02))
	var jitter_tex := GradientTexture1D.new()
	jitter_tex.gradient = jitter

	for w in car.wheels:
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 0.45, 1)   # local +Z = kick direction, set each frame
		pm.spread = 20.0
		pm.initial_velocity_min = 1.5
		pm.initial_velocity_max = 3.0
		pm.gravity = Vector3(0, -9.8, 0)
		pm.damping_min = 0.5
		pm.damping_max = 1.5
		pm.inherit_velocity_ratio = 0.7
		pm.scale_min = 0.035
		pm.scale_max = 0.10
		pm.scale_curve = shrink_tex
		pm.angle_min = 0.0
		pm.angle_max = 360.0
		pm.angular_velocity_min = -400.0
		pm.angular_velocity_max = 400.0
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(0.18, 0.04, 0.08)
		pm.color_initial_ramp = jitter_tex

		var e := GPUParticles3D.new()
		e.name = "Spray" + w.name
		e.amount = AMOUNT
		e.lifetime = LIFETIME
		e.explosiveness = 0.0
		e.randomness = 0.4
		e.local_coords = false
		e.emitting = false
		e.process_material = pm
		e.draw_pass_1 = grain
		e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		e.visibility_aabb = AABB(Vector3(-6, -3, -6), Vector3(12, 8, 12))
		add_child(e)
		_emitters.append(e)
		_mats.append(pm)


func update_from(car: SandVehicle) -> void:
	var island := car.island
	var up := car.global_basis.y
	var fwd_body := -car.global_basis.z
	for i in car.wheels.size():
		var w: SandVehicle.Wheel = car.wheels[i]
		var e := _emitters[i]
		var amt := 0.0
		# bottom of the tyre, a touch behind the axle
		var p := w.pivot.global_position - up * (car.wheel_radius * 0.8)
		var rim := w.spin_speed * car.wheel_radius
		var kick := -fwd_body * signf(rim)   # tread throws sand opposite to its spin
		if w.grounded and absf(rim) > 0.3:
			var sf := island.surface_at(p.x, p.z)
			var throws := sf != IslandData.Surface.WET_SAND and sf != IslandData.Surface.ROCK \
				and sf != IslandData.Surface.OCEAN and sf != IslandData.Surface.WEST_FLATS \
				and sf != IslandData.Surface.FOREST
			var water := island.water_level_at(p.x, p.z)
			if p.y < water + 0.25 and absf(car.speed_kmh) > 4.0:
				# driving through the shallows: a white splash, bigger with speed
				var spd := absf(car.speed_kmh) / 3.6
				amt = clampf(spd / 10.0, 0.15, 1.0)
				var pmw := _mats[i]
				pmw.initial_velocity_min = minf(1.0 + spd * 0.25, 4.0)
				pmw.initial_velocity_max = minf(2.0 + spd * 0.4, 6.5)
				pmw.color = Color(0.92, 0.97, 1.0)
				kick = (-fwd_body * 0.6 + car.global_basis.x * (1.0 if not w.left else -1.0)).normalized()
			elif throws and p.y > water + 0.05:
				var soft := island.softness_at(p.x, p.z)
				var gate := smoothstep(SOFT_START, SOFT_FULL, soft)
				var v_long := car.linear_velocity.dot(fwd_body)
				var slipv := absf(rim - v_long)
				amt = gate * clampf(absf(rim) / 12.0 * 0.4 + slipv / 2.5, 0.0, 1.0)
				if amt > 0.02:
					var pm := _mats[i]
					# capped so even a wild roost only reaches about car height (~1.5 m)
					pm.initial_velocity_min = minf(1.2 + slipv * 0.35, 4.0)
					pm.initial_velocity_max = minf(2.4 + slipv * 0.6, 7.0)
					pm.color = WorldBuilder.surface_color(sf, soft, p.y)
		if amt > 0.02:
			e.global_position = p + kick * 0.25
			var flat := (kick - up * kick.dot(up)).normalized()
			if flat.length_squared() > 0.5:
				e.global_basis = Basis.looking_at(-flat, up)   # local +Z -> kick
			e.amount_ratio = amt
			if not e.emitting:
				e.emitting = true
		elif e.emitting:
			e.emitting = false

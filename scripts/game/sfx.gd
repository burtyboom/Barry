class_name Sfx
extends RefCounted
## Sound effects synthesised in code (no audio files): engine loop, splash, cast whoosh,
## door thunk, strap twang, winch whirr, air hiss, compressor buzz, placing pop,
## horns, sirens, surf, seagulls, kookaburras, the speeding-fine "wah wah", radio squelch,
## cartoon bonk / slide whistle / boing for people sent flying, dingo howls and yips,
## the pet whistle, woofs and meows.

const RATE := 22050
static var _cache := {}


static func get_stream(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var s: AudioStreamWAV
	match kind:
		"engine":
			s = _engine()
		"splash":
			s = _noise_burst(0.45, 9.0, 0.55, 0.55)
		"whoosh":
			s = _whoosh()
		"thunk":
			s = _thunk()
		"twang":
			s = _twang()
		"winch":
			s = _loop_buzz(120.0, 0.35, 0.25)
		"hiss":
			s = _loop_noise(0.25, 0.85)
		"compressor":
			s = _loop_buzz(95.0, 0.5, 0.15)
		"pop":
			s = _pop()
		"horn":
			s = _horn()
		"beep2":
			s = _beep2()
		"siren_wail":
			s = _siren(650.0, 1450.0, 4.0, true)
		"siren_yelp":
			s = _siren(700.0, 1550.0, 0.36, false)
		"surf":
			s = _surf()
		"wind":
			s = _loop_noise(0.12, 0.85)
		"gull":
			s = _gull()
		"kooka":
			s = _kooka()
		"click":
			s = _click()
		"blip":
			s = _blip()
		"wahwah":
			s = _wahwah()
		"radio":
			s = _radio()
		"ratchet":
			s = _ratchet()
		"bonk":
			s = _bonk()
		"slide_up":
			s = _slide(420.0, 1500.0, 0.75)
		"slide_down":
			s = _slide(1300.0, 380.0, 0.6)
		"boing":
			s = _boing()
		"howl":
			s = _howl()
		"yip":
			s = _yip()
		"whistle":
			s = _whistle()
		"woof":
			s = _woof()
		"meow":
			s = _meow()
		_:
			s = _pop()
	_cache[kind] = s
	return s


## Plays a one-shot 3D sound at a position (cleans itself up).
static func play_at(parent: Node, kind: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = get_stream(kind)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 6.0
	p.max_distance = 80.0
	p.bus = _bus()
	parent.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


static func _bus() -> String:
	return "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"


## A one-shot sound that isn't in the world (UI clicks, the fine trombone).
static func play_ui(parent: Node, kind: String, volume_db := 0.0, pitch := 1.0) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = get_stream(kind)
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.bus = _bus()
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## A looping 3D player you keep around (engine, hiss...).
static func make_loop(kind: String, volume_db := 0.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_stream(kind)
	p.volume_db = volume_db
	p.unit_size = 8.0
	p.max_distance = 120.0
	p.bus = _bus()
	return p


# ------------------------------------------------------------- synthesis
static func _wav(data: PackedByteArray, loop := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size() / 2
	return w


static func _pack(samples: PackedFloat32Array) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 30000.0))
	return data


## Diesel-ish idle: 25 cycles of a lumpy 50 Hz pulse train with harmonics -> seamless loop.
## Pitch it up with pitch_scale for revs.
static func _engine() -> AudioStreamWAV:
	var f0 := 50.0
	var n := int(RATE * 25.0 / f0)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ph := TAU * f0 * t
		var v := 0.45 * sin(ph) + 0.25 * sin(ph * 2.0 + 0.5) + 0.15 * sin(ph * 3.0 + 1.1) + 0.08 * sin(ph * 5.0)
		# firing pulses: 4 cylinders -> 2 pulses per cycle
		var pulse := pow(maxf(0.0, sin(ph * 2.0)), 6.0)
		v = v * 0.6 + pulse * 0.5
		out[i] = v * 0.55
	return _wav(_pack(out), true)


static func _noise_burst(length: float, decay: float, amp: float, smooth: float) -> AudioStreamWAV:
	var n := int(RATE * length)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1.0, 1.0)
		prev = lerpf(x, prev, smooth)     # crude low-pass
		out[i] = prev * amp * exp(-t * decay) * minf(1.0, t * 200.0)
	return _wav(_pack(out))


static func _whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in n:
		var k := float(i) / n
		var smooth := lerpf(0.92, 0.5, k)
		prev = lerpf(rng.randf_range(-1.0, 1.0), prev, smooth)
		out[i] = prev * sin(PI * k) * 0.7
	return _wav(_pack(out))


static func _thunk() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in n:
		var t := float(i) / RATE
		out[i] = (sin(TAU * 90.0 * t) * 0.8 + rng.randf_range(-1, 1) * 0.25) * exp(-t * 28.0)
	return _wav(_pack(out))


static func _twang() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var f := 140.0 * (1.0 + 0.6 * exp(-t * 12.0))   # pitch drops as the band relaxes
		out[i] = (sin(TAU * f * t) + 0.4 * sin(TAU * f * 2.01 * t)) * exp(-t * 6.0) * 0.6
	return _wav(_pack(out))


static func _loop_buzz(f0: float, amp: float, noise: float) -> AudioStreamWAV:
	var cycles := 30.0
	var n := int(RATE * cycles / f0)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in n:
		var t := float(i) / RATE
		var saw := fposmod(f0 * t, 1.0) * 2.0 - 1.0
		out[i] = (saw * 0.6 + sin(TAU * f0 * 2.0 * t) * 0.3 + rng.randf_range(-1, 1) * noise) * amp
	return _wav(_pack(out), true)


static func _loop_noise(amp: float, smooth: float) -> AudioStreamWAV:
	var n := int(RATE * 0.5)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in n:
		prev = lerpf(rng.randf_range(-1.0, 1.0), prev, smooth * 0.0 + 0.2)
		out[i] = prev * amp
	return _wav(_pack(out), true)


static func _pop() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * (600.0 - t * 2500.0) * t) * exp(-t * 35.0) * 0.6
	return _wav(_pack(out))


## Car horn: two notes a major third apart (420 / 525 Hz) - both fit a whole number of
## cycles into 210 samples, so it loops cleanly while you hold the button.
static func _horn() -> AudioStreamWAV:
	var n := 210 * 30
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		# soft-cornered squares: brassy but not harsh
		var v := tanh(sin(TAU * 420.0 * t) * 3.0) * 0.5 + tanh(sin(TAU * 525.0 * t) * 3.0) * 0.4
		out[i] = v * 0.45
	return _wav(_pack(out), true)


## Friendly "beep beep" (bots saying g'day).
static func _beep2() -> AudioStreamWAV:
	var n := int(RATE * 0.62)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var first := t < 0.2
		if not first and (t < 0.32 or t > 0.56):
			continue
		var lt := t if first else t - 0.32
		var ln := 0.2 if first else 0.24
		var env := minf(1.0, lt * 120.0) * minf(1.0, (ln - lt) * 80.0)
		var v := tanh(sin(TAU * 440.0 * t) * 3.0) * 0.5 + tanh(sin(TAU * 554.0 * t) * 3.0) * 0.4
		out[i] = v * env * 0.45
	return _wav(_pack(out))


## Siren loop sweeping lo -> hi -> lo over `period` seconds. Wail = smooth sine sweep,
## yelp = quick saw-tooth sweep. The pitch is nudged so the loop holds a whole number
## of cycles (no click at the loop point).
static func _siren(lo: float, hi: float, period: float, smooth: bool) -> AudioStreamWAV:
	var n := int(RATE * period)
	var freqs := PackedFloat32Array()
	freqs.resize(n)
	var total := 0.0
	for i in n:
		var k := float(i) / n
		var shape := 0.5 - 0.5 * cos(TAU * k) if smooth else k
		freqs[i] = lerpf(lo, hi, shape)
		total += freqs[i] / RATE
	var fix := roundf(total) / total
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		ph += freqs[i] * fix / RATE
		var x := sin(TAU * ph)
		out[i] = (tanh(x * 2.2) * 0.75 + sin(TAU * ph * 2.0) * 0.12) * 0.5
	return _wav(_pack(out), true)


## Waves on the beach: noise swelling and breaking, two waves per loop.
static func _surf() -> AudioStreamWAV:
	var n := int(RATE * 8.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var k := float(i) / n
		var x := rng.randf_range(-1.0, 1.0)
		lp = lerpf(x, lp, 0.82)
		lp2 = lerpf(x, lp2, 0.97)
		# each wave: quick build, crash, long hiss as it runs up the sand
		var w := fposmod(k * 2.0, 1.0)
		var env := smoothstep(0.0, 0.25, w) * (1.0 - smoothstep(0.3, 1.0, w)) * 0.8 + 0.25
		out[i] = (lp * 0.55 + lp2 * 1.6) * env * 0.5
	# cross-fade the end into the start so the loop is seamless
	var fade := int(RATE * 0.3)
	for i in fade:
		var k := float(i) / fade
		out[i] = out[i] * k + out[n - fade + i] * (1.0 - k)
	out = out.slice(0, n - fade)
	return _wav(_pack(out), true)


## Seagull: a falling, nasal "kee-ow".
static func _gull() -> AudioStreamWAV:
	var n := int(RATE * 0.55)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / 0.55
		var f := 1500.0 + 900.0 * sin(PI * minf(k * 1.6, 1.0)) - 600.0 * k
		ph += f / RATE
		var v := sin(TAU * ph) * 0.6 + sin(TAU * ph * 2.0) * 0.3 + sin(TAU * ph * 3.0) * 0.18
		var env := minf(1.0, t * 60.0) * (1.0 - k) * (0.8 + 0.2 * sin(t * 90.0))
		out[i] = v * env * 0.4
	return _wav(_pack(out))


## Kookaburra: a run of "koo-koo-KA-KA-ka" hoots that rise, then tumble back down.
static func _kooka() -> AudioStreamWAV:
	var notes := []
	var t := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for k in 16:
		var rise := sin(PI * float(k) / 15.0)
		notes.append([t, 0.09 + rng.randf() * 0.03, 700.0 + 900.0 * rise + rng.randf_range(-80, 80)])
		t += 0.13 + rng.randf() * 0.05
	var n := int(RATE * (t + 0.2))
	var out := PackedFloat32Array()
	out.resize(n)
	for nt in notes:
		var s0 := int(float(nt[0]) * RATE)
		var ln := int(float(nt[1]) * RATE)
		var f0: float = nt[2]
		var ph := 0.0
		for j in ln:
			var i := s0 + j
			if i >= n:
				break
			var k := float(j) / ln
			ph += f0 * (1.15 - 0.3 * k) / RATE   # each "ha" drops in pitch
			var v := sin(TAU * ph) * 0.7 + sin(TAU * ph * 2.0) * 0.25 + sin(TAU * ph * 3.0) * 0.12
			out[i] += v * sin(PI * k) * 0.45
	return _wav(_pack(out))


static func _click() -> AudioStreamWAV:
	var n := int(RATE * 0.05)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 1800.0 * t) * exp(-t * 120.0) * 0.5
	return _wav(_pack(out))


## Little rising "bup" when a bot says something.
static func _blip() -> AudioStreamWAV:
	var n := int(RATE * 0.14)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += (520.0 + 380.0 * minf(t / 0.06, 1.0)) / RATE
		out[i] = sin(TAU * ph) * minf(1.0, t * 300.0) * exp(-t * 22.0) * 0.5
	return _wav(_pack(out))


## Sad trombone for a speeding fine: four notes stepping down, the last one wobbling.
static func _wahwah() -> AudioStreamWAV:
	var seq := [[0.0, 0.42, 311.1], [0.45, 0.42, 293.7], [0.9, 0.42, 277.2], [1.35, 1.2, 261.6]]
	var n := int(RATE * 2.7)
	var out := PackedFloat32Array()
	out.resize(n)
	for nt in seq:
		var s0 := int(float(nt[0]) * RATE)
		var dur: float = nt[1]
		var ln := int(dur * RATE)
		var ph := 0.0
		for j in ln:
			var i := s0 + j
			if i >= n:
				break
			var t := float(j) / RATE
			var wob := 0.025 * sin(TAU * 6.0 * t) if dur > 1.0 else 0.0
			ph += float(nt[2]) * (1.0 + wob - 0.02 * t) / RATE
			# brassy: the "wah" is the brightness opening up then closing
			var bright := sin(PI * minf(t / (dur * 0.9), 1.0))
			var v := sin(TAU * ph) + bright * (0.6 * sin(TAU * ph * 2.0) + 0.4 * sin(TAU * ph * 3.0) + 0.2 * sin(TAU * ph * 4.0))
			var env := minf(1.0, t * 30.0) * minf(1.0, (dur - t) * 12.0)
			out[i] += v * env * 0.28
	return _wav(_pack(out))


## Police radio: squelch burst, then chirp-chirp.
static func _radio() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		if t < 0.25:
			prev = lerpf(rng.randf_range(-1, 1), prev, 0.3)
			v = prev * 0.35 * (1.0 - t / 0.25)
		elif t < 0.36 or (t > 0.42 and t < 0.53):
			v = sin(TAU * 1250.0 * t) * 0.3
		out[i] = v
	return _wav(_pack(out))


## Fishing reel ratchet, looped while winding in.
static func _ratchet() -> AudioStreamWAV:
	var n := int(RATE * 0.25)
	var out := PackedFloat32Array()
	out.resize(n)
	for c in 6:
		var s0 := int(c * n / 6.0)
		for j in int(RATE * 0.012):
			var t := float(j) / RATE
			out[s0 + j] += sin(TAU * 3200.0 * t) * exp(-t * 500.0) * 0.4
	return _wav(_pack(out), true)


## Cartoon "BONK": a hollow woodblock knock with the pitch dropping away.
static func _bonk() -> AudioStreamWAV:
	var n := int(RATE * 0.35)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += 620.0 * (1.0 - 0.45 * minf(t / 0.25, 1.0)) / RATE
		out[i] = (sin(TAU * ph) + 0.5 * sin(TAU * ph * 1.51) + 0.25 * sin(TAU * ph * 2.7)) * exp(-t * 13.0) * 0.5
	return _wav(_pack(out))


## Slide whistle from f0 to f1 (breathy sine with a wobble).
static func _slide(f0: float, f1: float, dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var f := lerpf(f0, f1, k * k * (3.0 - 2.0 * k)) * (1.0 + 0.015 * sin(TAU * 7.0 * t))
		ph += f / RATE
		var env := minf(1.0, t * 25.0) * minf(1.0, (dur - t) * 10.0)
		out[i] = (sin(TAU * ph) * 0.9 + rng.randf_range(-1, 1) * 0.06) * env * 0.38
	return _wav(_pack(out))


## Spring "boooiing" for popping back up.
static func _boing() -> AudioStreamWAV:
	var n := int(RATE * 0.6)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := (180.0 + 260.0 * minf(t / 0.12, 1.0)) * (1.0 + 0.18 * sin(TAU * 16.0 * t) * exp(-t * 3.0))
		ph += f / RATE
		out[i] = (sin(TAU * ph) + 0.3 * sin(TAU * ph * 2.0)) * minf(1.0, t * 60.0) * exp(-t * 4.5) * 0.45
	return _wav(_pack(out))


## A dingo howl: a long rising then falling "aroooo" with a wavering voice.
static func _howl() -> AudioStreamWAV:
	var dur := 2.6
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var f := 430.0 + 330.0 * sin(PI * minf(k * 1.6, 1.0)) - 120.0 * maxf(k - 0.62, 0.0) / 0.38
		f *= 1.0 + 0.02 * sin(TAU * 5.5 * t)
		ph += f / RATE
		var env := minf(1.0, t * 4.0) * minf(1.0, (dur - t) * 2.2)
		out[i] = (sin(TAU * ph) + 0.35 * sin(TAU * ph * 2.0) + 0.12 * sin(TAU * ph * 3.0)) * env * 0.3
	return _wav(_pack(out))


## Short sharp yip.
static func _yip() -> AudioStreamWAV:
	var n := int(RATE * 0.16)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += (1100.0 - 2600.0 * t) / RATE
		out[i] = (sin(TAU * ph) + 0.3 * sin(TAU * ph * 2.0) + rng.randf_range(-1, 1) * 0.15) * minf(1.0, t * 200.0) * exp(-t * 18.0) * 0.5
	return _wav(_pack(out))


## A two-note "fweet-FWEEEET!" whistle to call your pet back.
static func _whistle() -> AudioStreamWAV:
	var dur := 0.95
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 0.0
		var env := 0.0
		if t < 0.22:
			f = 1700.0 + 500.0 * (t / 0.22)
			env = minf(1.0, t * 80.0) * minf(1.0, (0.22 - t) * 60.0)
		elif t > 0.3:
			var k := (t - 0.3) / (dur - 0.3)
			f = 1500.0 + 1300.0 * minf(k * 3.0, 1.0) - 250.0 * maxf(k - 0.6, 0.0)
			env = minf(1.0, (t - 0.3) * 80.0) * minf(1.0, (dur - t) * 12.0)
		ph += f * (1.0 + 0.012 * sin(TAU * 7.0 * t)) / RATE
		out[i] = (sin(TAU * ph) * 0.85 + rng.randf_range(-1, 1) * 0.06) * env * 0.42
	return _wav(_pack(out))


## A cheerful "woof!".
static func _woof() -> AudioStreamWAV:
	var dur := 0.26
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 260.0 + 160.0 * sin(PI * minf(t / dur, 1.0)) - 120.0 * t
		ph += f / RATE
		var v := sin(TAU * ph) + 0.6 * sin(TAU * ph * 2.0) + 0.3 * sin(TAU * ph * 3.0) + rng.randf_range(-1, 1) * 0.35
		out[i] = v * minf(1.0, t * 120.0) * exp(-t * 9.0) * 0.38
	return _wav(_pack(out))


## A lazy "mrrow".
static func _meow() -> AudioStreamWAV:
	var dur := 0.55
	var n := int(RATE * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / dur
		var f := 560.0 + 300.0 * sin(PI * minf(k * 1.4, 1.0)) - 180.0 * k
		ph += f / RATE
		var env := minf(1.0, t * 25.0) * minf(1.0, (dur - t) * 8.0)
		out[i] = (sin(TAU * ph) + 0.45 * sin(TAU * ph * 2.0) + 0.2 * sin(TAU * ph * 3.0)) * env * 0.3
	return _wav(_pack(out))

class_name Music
extends Node
## Light, bouncy island music, composed and synthesised in code (no audio files):
## ukulele strum, marimba / steel-drum tunes, plucky bass, shaker and finger snaps.
## Two songs are written from fixed seeds on a worker thread at start-up, then
## played one after the other on the "Music" bus. N toggles it.

const RATE := 22050
const SCALE := [0, 2, 4, 7, 9]   ## major pentatonic (degrees above the key)

var enabled := true
var volume_db := -11.0
var _player: AudioStreamPlayer
var _songs: Array[AudioStreamWAV] = []
var _task := -1
var _which := 0
var _rng := RandomNumberGenerator.new()
var _cache := {}


## Music and SFX buses so each can be turned down on its own.
static func setup_buses() -> void:
	for nm in ["Music", "SFX"]:
		if AudioServer.get_bus_index(nm) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, nm)
			AudioServer.set_bus_send(i, "Master")


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	_player.volume_db = -60.0
	add_child(_player)
	_player.finished.connect(_next_song)
	if DisplayServer.get_name() == "headless":
		return   # tests: nobody's listening
	_task = WorkerThreadPool.add_task(_compose_all, false, "compose music")


func _process(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if not _songs.is_empty():
			_player.stream = _songs[0]
			if enabled:
				_player.play()
	var want := volume_db if enabled else -60.0
	_player.volume_db = move_toward(_player.volume_db, want, delta * 25.0)
	if not enabled and _player.playing and _player.volume_db <= -59.0:
		_player.stream_paused = true
	elif enabled and _player.stream_paused:
		_player.stream_paused = false


func toggle() -> bool:
	enabled = not enabled
	if enabled and _player.stream and not _player.playing:
		_player.play()
	return enabled


func _next_song() -> void:
	if _songs.is_empty():
		return
	_which = (_which + 1) % _songs.size()
	_player.stream = _songs[_which]
	_player.play()


# ------------------------------------------------------------- composing
func _compose_all() -> void:
	var t0 := Time.get_ticks_msec()
	var a := _compose(1, 0, 116.0, "marimba", "steel")
	var b := _compose(7, 5, 100.0, "steel", "marimba")
	_songs = [a, b]
	print("music composed in %d ms" % (Time.get_ticks_msec() - t0))


## One song: 32 bars (A B A' B'), key = semitones above C.
func _compose(seed: int, key: int, bpm: float, lead_a: String, lead_b: String) -> AudioStreamWAV:
	_rng.seed = seed
	var step := 60.0 / bpm / 2.0                 # one 8th note
	var bar_len := step * 8.0
	# chords: root (semitones above the key) and quality
	var prog_a := [[0, "M"], [7, "M"], [9, "m"], [5, "M"], [0, "M"], [7, "M"], [5, "M"], [0, "M"]]
	var prog_b := [[5, "M"], [7, "M"], [4, "m"], [9, "m"], [5, "M"], [7, "M"], [0, "M"], [0, "M"]]
	var sections := [[prog_a, lead_a, false], [prog_b, lead_b, false], [prog_a, lead_a, true], [prog_b, lead_b, true]]
	var total := int((bar_len * 32.0 + 3.0) * RATE)
	var out := PackedFloat32Array()
	out.resize(total)
	var bar := 0
	var tune_a := _write_tune(prog_a)
	var tune_b := _write_tune(prog_b)
	for sec in sections:
		var prog: Array = sec[0]
		var lead: String = sec[1]
		var extra: bool = sec[2]
		var tune: Array = tune_a if prog == prog_a else tune_b
		for b in 8:
			var t_bar := bar * bar_len
			var root: int = key + int(prog[b][0])
			var minor: bool = prog[b][1] == "m"
			# ukulele "island strum": D . D U . U D U
			for s in [0, 2, 3, 5, 6, 7]:
				var down: bool = s in [0, 2, 6]
				_mix(out, _strum(root, minor, down), t_bar + s * step, 0.22 if down else 0.15)
			# bass: root on 1, fifth on the "and" of 2, root on 3, walk up on 4
			var bass_notes := [[0, root], [3, root + 7], [4, root], [6, root + (2 if minor else 4)]]
			for bn in bass_notes:
				_mix(out, _note("bass", 36 + int(bn[1]) % 12, step * 2.0), t_bar + int(bn[0]) * step, 0.5)
			# percussion
			for s in 8:
				_mix(out, _note("shaker", 0, step), t_bar + s * step + (0.012 if s % 2 == 1 else 0.0), 0.10 if s % 2 == 0 else 0.07)
			_mix(out, _note("kick", 0, step), t_bar, 0.42)
			_mix(out, _note("kick", 0, step), t_bar + 4 * step, 0.34)
			for s in [2, 6]:
				_mix(out, _note("snap", 0, step), t_bar + s * step, 0.22)
			# the tune
			for n in tune[b]:
				var midi: int = 60 + key + int(n[1])
				_mix(out, _note(lead, midi, float(n[2]) * step), t_bar + int(n[0]) * step, 0.30)
			# second time round: a soft whistle holds the chord's third over the top
			if extra and b % 2 == 0:
				var third: int = 72 + (root + (3 if minor else 4)) % 12
				_mix(out, _note("whistle", third, step * 7.0), t_bar + step * 0.5, 0.10)
			bar += 1
	# wrap the ringing tail back onto the start so the song loops seamlessly
	var n_song := int(bar_len * 32.0 * RATE)
	for i in total - n_song:
		out[i] += out[n_song + i]
	out = out.slice(0, n_song)
	var peak := 0.001
	for v in out:
		peak = maxf(peak, absf(v))
	var data := PackedByteArray()
	data.resize(out.size() * 2)
	var g := 0.85 / peak
	for i in out.size():
		data.encode_s16(i * 2, int(clampf(out[i] * g, -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


## Eight bars of melody over a progression: a two-bar idea, answered, then repeated
## with a different ending. Notes are [8th-step, semitones above the key, length in 8ths].
func _write_tune(prog: Array) -> Array:
	var rhythms := [
		[0, 2, 3, 4, 6], [0, 1, 2, 4, 5, 6], [0, 3, 4, 6, 7], [0, 2, 4, 5, 6],
		[1, 2, 4, 6], [0, 2, 3, 5, 6], [0, 4, 5, 6, 7],
	]
	var r1: Array = rhythms[_rng.randi() % rhythms.size()]
	var r2: Array = rhythms[_rng.randi() % rhythms.size()]
	var bars := []
	var last := 12 + 4   # start around E5
	for b in 8:
		var chord_root: int = prog[b][0]
		var minor: bool = prog[b][1] == "m"
		var tones := [chord_root, chord_root + (3 if minor else 4), chord_root + 7]
		var rhythm: Array = r1 if b % 2 == 0 else r2
		var notes := []
		var phrase_end := b == 3 or b == 7
		if phrase_end:
			rhythm = [0, 2, 4] if b == 3 else [0, 4]
		for i in rhythm.size():
			var s: int = rhythm[i]
			var nxt: int = rhythm[i + 1] if i + 1 < rhythm.size() else 8
			var ln := mini(nxt - s, 3)
			var p: int
			if s == 0 or s == 4 or (phrase_end and i == rhythm.size() - 1):
				p = _nearest_tone(last, tones)   # strong beats land on the chord
			else:
				p = _scale_step(last, _rng.randi_range(-2, 2))
			if phrase_end and i == rhythm.size() - 1:
				p = _nearest_tone(last, [chord_root])
				ln = 8 - s
			p = clampi(p, 7, 24)
			notes.append([s, p, ln])
			last = p
		bars.append(notes)
	return bars


func _nearest_tone(from: int, tones: Array) -> int:
	var best := from
	var bd := 99
	for t in tones:
		for o in [0, 12, 24]:
			var c: int = int(t) % 12 + o
			if absi(c - from) < bd and c >= 7 and c <= 24:
				bd = absi(c - from)
				best = c
	return best


func _scale_step(from: int, steps: int) -> int:
	var degs := []
	for o in [0, 12, 24]:
		for d in SCALE:
			degs.append(int(d) + o)
	var i := 0
	var bd := 99
	for k in degs.size():
		if absi(int(degs[k]) - from) < bd:
			bd = absi(int(degs[k]) - from)
			i = k
	return int(degs[clampi(i + steps, 0, degs.size() - 1)])


# ------------------------------------------------------------- instruments
func _mix(out: PackedFloat32Array, snd: PackedFloat32Array, at: float, gain: float) -> void:
	var s0 := int(at * RATE)
	var n := mini(snd.size(), out.size() - s0)
	for i in n:
		out[s0 + i] += snd[i] * gain


static func _hz(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## A rendered note, cached by instrument / pitch / length.
func _note(inst: String, midi: int, dur: float) -> PackedFloat32Array:
	var key := "%s_%d_%.3f" % [inst, midi, dur]
	if _cache.has(key):
		return _cache[key]
	var f := _hz(midi)
	var ring := dur + 0.25
	match inst:
		"bass", "kick", "shaker", "snap":
			ring = dur
		"steel":
			ring = dur + 0.5
	var n := int(ring * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = midi * 31 + inst.length()
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		match inst:
			"marimba":
				v = (sin(TAU * f * t) + 0.35 * sin(TAU * f * 4.0 * t) * exp(-t * 25.0)) * exp(-t * 5.0)
			"steel":
				v = (sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.0 * t) * exp(-t * 3.0) + 0.3 * sin(TAU * f * 3.01 * t) * exp(-t * 6.0)) * exp(-t * 3.2)
			"whistle":
				var vib := 1.0 + 0.006 * sin(TAU * 5.5 * t) * minf(t * 2.0, 1.0)
				v = sin(TAU * f * vib * t) * minf(t * 6.0, 1.0) * minf(1.0, (ring - t) * 5.0)
			"bass":
				v = (sin(TAU * f * t) + 0.3 * sin(TAU * f * 2.0 * t)) * exp(-t * 3.0) * minf(1.0, (ring - t) * 30.0)
			"kick":
				v = sin(TAU * (55.0 + 90.0 * exp(-t * 30.0)) * t) * exp(-t * 14.0)
			"shaker":
				var x := rng.randf_range(-1.0, 1.0)
				v = (x - prev) * exp(-t * 45.0) * 0.6
				prev = x
			"snap":
				var x2 := rng.randf_range(-1.0, 1.0)
				prev = lerpf(x2, prev, 0.4)
				v = (x2 - prev) * exp(-t * 60.0) + sin(TAU * 1800.0 * t) * exp(-t * 90.0) * 0.4
		out[i] = v * minf(1.0, t * 400.0)
	_cache[key] = out
	return out


## Four-string uke strum (Karplus-Strong plucks, staggered across the strings).
func _strum(root: int, minor: bool, down: bool) -> PackedFloat32Array:
	var key := "strum_%d_%s_%s" % [root, minor, down]
	if _cache.has(key):
		return _cache[key]
	# voicing: chord tones squeezed into the uke's G4..A5 range
	var tones := [root % 12, (root + (3 if minor else 4)) % 12, (root + 7) % 12, root % 12]
	var strings := []
	for k in 4:
		var m: int = 67 + (int(tones[k]) - 7 + 12) % 12
		if k == 3:
			m += 0 if m >= 72 else 12
		strings.append(m)
	if not down:
		strings.reverse()
	var ring := 0.7
	var n := int(ring * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = root * 7 + (1 if down else 2)
	for k in 4:
		var f := _hz(strings[k])
		var period := int(RATE / f)
		var buf := PackedFloat32Array()
		buf.resize(period)
		var lp := 0.0
		for j in period:
			lp = lerpf(rng.randf_range(-1.0, 1.0), lp, 0.5)   # softer pick
			buf[j] = lp
		var s0 := int(k * 0.011 * RATE)
		var idx := 0
		for i in range(s0, n):
			var a := buf[idx]
			var b := buf[(idx + 1) % period]
			buf[idx] = (a + b) * 0.5 * 0.994
			out[i] += a * 0.5
			idx = (idx + 1) % period
	for i in n:
		out[i] *= minf(1.0, (ring - float(i) / RATE) * 6.0)
	_cache[key] = out
	return out

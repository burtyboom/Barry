extends SceneTree
## Voice chat checks.
##   godot --headless --path . -s res://tests/_voice.gd -- unit
##   godot --headless --path . -s res://tests/_voice.gd -- host     (and in a 2nd process)
##   godot --headless --path . -s res://tests/_voice.gd -- client
## The client plays a 440 Hz tone into the send path twice: once parked next to the
## host (should be heard) and once after the host drives off 1 km (should not be relayed).
var main
var voice: Voice
var role := ""
const PORT := 7791
var Net: Node


func _initialize() -> void:
	role = OS.get_cmdline_user_args()[0]
	if role == "unit":
		_unit()
		quit()
		return
	Net = get_root().get_node("Net")
	main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(0.3).timeout
	voice = main.get_node_or_null("Voice")
	if voice == null:
		voice = Voice.new()
		voice.name = "Voice"
		main.add_child(voice)
	if role == "solo":
		await main._start("solo")
		await create_timer(3.0).timeout
		voice.inject_frames(PackedVector2Array([Vector2(0.3, 0.3)]))
		await create_timer(0.5).timeout
		print("[solo] talking_local=%s sent=%d devices=%s (offline: nothing sent)" % [voice.talking_local, voice.sent_packets, voice.list_devices()])
	elif role == "host":
		# own port, so other tests running at the same time don't collide
		main._select_island("moreton")
		main._take_name()
		main._clear_showcase()
		Net.island_id = "moreton"
		await main._load_island("moreton")
		var peer := ENetMultiplayerPeer.new()
		print("[host] create_server: ", peer.create_server(PORT, 4))
		main.multiplayer.multiplayer_peer = peer
		Net.mode = "host"
		Net.session_ready.emit(1)
		await create_timer(2.0).timeout
		_park(0.0)
		var cid := 0
		for k in 30:
			await create_timer(0.5).timeout
			if main.multiplayer.get_peers().size() > 0:
				cid = main.multiplayer.get_peers()[0]
				break
		print("[host] client id ", cid)
		await create_timer(9.0).timeout   # t ~ 11.5: client has talked once
		var st: Dictionary = voice.speaker_stats(cid)
		print("[host] near: in_range=%s received=%d pushed=%d peak=%.2f" % [voice.in_range(1, cid), voice.received_packets, st["pushed"], st["peak"]])
		var ok1: bool = voice.received_packets >= 20 and st["peak"] > 0.3 and st["peak"] < 0.7
		# drive away 1 km and listen again
		main.local_car.teleport(main.local_car.global_position + Vector3(0, 0, 1000), Vector3.FORWARD)
		await create_timer(1.0).timeout
		var before: int = voice.received_packets
		await create_timer(8.0).timeout   # client talks again around t ~ 16-18
		print("[host] far: in_range=%s received after moving away=%d" % [voice.in_range(1, cid), voice.received_packets - before])
		var ok2: bool = voice.received_packets == before
		print("[host] RESULT near_heard=%s far_silent=%s" % [ok1, ok2])
	else:
		await create_timer(2.0).timeout
		var peer := ENetMultiplayerPeer.new()
		peer.create_client("127.0.0.1", PORT)
		main.multiplayer.multiplayer_peer = peer
		Net.mode = "client"
		await create_timer(4.0).timeout
		_park(6.0)
		await create_timer(1.5).timeout
		await _talk(2.0)   # t ~ 7.5 .. 9.5
		print("[client] sent %d packets" % voice.sent_packets)
		await create_timer(6.0).timeout
		await _talk(2.0)   # t ~ 15.5 .. 17.5, host is far away by now
		print("[client] sent %d packets" % voice.sent_packets)
		await create_timer(3.0).timeout
	quit()


func _park(dz: float) -> void:
	for pl in main.island.places:
		if pl["name"] == "Tangalooma Wrecks":
			main.local_car.teleport(pl["pos"] + Vector3(0, 0, dz), Vector3.FORWARD)


## Feed 40 ms of 440 Hz (amplitude 0.5) per frame for `secs`.
func _talk(secs: float) -> void:
	var rate := AudioServer.get_mix_rate()
	var n := int(rate * 0.04)
	var ph := 0.0
	var t := 0.0
	while t < secs:
		var f := PackedVector2Array()
		f.resize(n)
		for i in n:
			var s := 0.5 * sin(ph)
			ph += TAU * 440.0 / rate
			f[i] = Vector2(s, s)
		voice.inject_frames(f)
		await create_timer(0.04).timeout
		t += 0.04


func _unit() -> void:
	# mu-law round trip on a 16 kHz sine
	var src := PackedFloat32Array()
	for i in 1600:
		src.append(0.5 * sin(TAU * 440.0 * i / 16000.0))
	var dec := Voice.decode(Voice.encode(src))
	var sig := 0.0
	var err := 0.0
	for i in src.size():
		sig += src[i] * src[i]
		err += (src[i] - dec[i]) * (src[i] - dec[i])
	var snr := 10.0 * log(sig / maxf(err, 1e-12)) / log(10.0)
	print("[unit] mu-law SNR %.1f dB  (silence -> %.4f, full -> %.3f)" % [snr, Voice.decode(Voice.encode(PackedFloat32Array([0.0])))[0], Voice.decode(Voice.encode(PackedFloat32Array([-1.0])))[0]])
	# resampler: 1 s of 440 Hz at the mix rate fed in 40 ms pieces
	var v := Voice.new()
	v._mix_rate = 48000.0
	var out := PackedFloat32Array()
	var ph := 0.0
	for k in 25:
		var f := PackedVector2Array()
		for i in 1920:
			f.append(Vector2(0.5 * sin(ph), 0.5 * sin(ph)))
			ph += TAU * 440.0 / 48000.0
		v._resample_into(f, out)
	var zc := 0
	var peak := 0.0
	for i in range(1, out.size()):
		if (out[i - 1] < 0.0) != (out[i] < 0.0):
			zc += 1
		peak = maxf(peak, absf(out[i]))
	print("[unit] resampled %d samples (want 16000), ~%.0f Hz (want 440), peak %.3f (want 0.5)" % [out.size(), zc / 2.0, peak])
	var ok := snr > 30.0 and absi(out.size() - 16000) <= 2 and absf(zc / 2.0 - 440.0) <= 2.0 and absf(peak - 0.5) < 0.02
	print("[unit] RESULT ", "PASS" if ok else "FAIL")
	v.free()

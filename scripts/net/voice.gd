class_name Voice
extends Node
## Proximity voice chat. Hold V (push-to-talk) or turn on open mic.
##
## Mic -> "Mic" bus with an AudioEffectCapture -> downsample to 16 kHz mono ->
## mu-law (8 bit) -> ~40 ms packets -> the server. The server (a player host or
## the dedicated server, which has no player of its own) relays each packet to
## the players standing within RANGE of the speaker. Each listener plays it from
## the speaker's Player_<id> node through an AudioStreamPlayer3D, so voices come
## from where people are (in their ute too) and fade out by ~35 m.
##
## About 16 KB/s (128 kbit/s) per talker each way, plus the server's relay copies.
##
## Radios (later): every packet carries a channel byte. 0 = proximity. A radio
## channel N > 0 would route through _route() to everyone tuned to N instead of
## by distance, hold a one-talker-at-a-time lock per channel on the server, and
## the listener would mix static into _decode()'s output. The encoder, decoder
## and jitter buffer don't need to change.

const RATE := 16000            ## wire sample rate (mono)
const CHUNK := 640             ## samples per packet = 40 ms
const RANGE := 40.0            ## server relays to listeners this close (m)
const HEAR_RANGE := 35.0       ## playback falls silent by here
const JITTER := 0.1            ## seconds buffered before a speaker starts playing
const GATE := 0.02             ## open mic: RMS level that counts as talking
const GATE_HOLD := 0.35        ## open mic: keep sending this long after you stop
const CFG := "user://voice.cfg"
const CH_PROXIMITY := 0

var open_mic := false          ## talk whenever the mic hears you (instead of holding V)
var enabled := true
var talking_local := false     ## HUD: we're sending right now
var mic_level := 0.0           ## 0..1, smoothed, for a meter
var channel := CH_PROXIMITY    ## what we transmit on (radios later)

var _mic: AudioStreamPlayer
var _capture: AudioEffectCapture
var _mix_rate := 44100.0
var _rs_pos := 0.0             ## resampler: fractional read position carried between chunks
var _rs_prev := 0.0
var _out := PackedFloat32Array()   ## 16 kHz samples waiting to fill a packet
var _gate_t := 0.0
var _injected := PackedVector2Array()  ## test hook: frames fed instead of the mic
var _speakers := {}            ## peer id -> {player, playback, buf, started, last}
var sent_packets := 0          ## stats (tests / debug)
var relayed_packets := 0
var received_packets := 0

static var _mulaw_table := PackedFloat32Array()


func _ready() -> void:
	_mix_rate = AudioServer.get_mix_rate()
	_load_cfg()
	multiplayer.peer_disconnected.connect(func(id: int) -> void: _drop_speaker(id))


# ------------------------------------------------------------- settings
func list_devices() -> PackedStringArray:
	return AudioServer.get_input_device_list()


func set_device(dev: String) -> void:
	if dev in AudioServer.get_input_device_list():
		AudioServer.input_device = dev
		_save_cfg()


func set_open_mic(on: bool) -> void:
	open_mic = on
	if on:
		_start_mic()
	_save_cfg()


func _load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG) != OK:
		return
	open_mic = bool(cf.get_value("voice", "open_mic", false))
	enabled = bool(cf.get_value("voice", "enabled", true))
	var dev := String(cf.get_value("voice", "device", ""))
	if dev != "" and dev in AudioServer.get_input_device_list():
		AudioServer.input_device = dev


func _save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("voice", "open_mic", open_mic)
	cf.set_value("voice", "enabled", enabled)
	cf.set_value("voice", "device", AudioServer.input_device)
	cf.save(CFG)


# ------------------------------------------------------------- capture
## The mic only opens the first time you talk (or turn on open mic), so the
## Windows "mic in use" light isn't on for people who never use voice.
func _start_mic() -> void:
	if _mic != null or DisplayServer.get_name() == "headless":
		return
	if AudioServer.get_bus_index("Mic") < 0:
		# Mic (capture, not heard) -> MicSink (muted). Muting the sink rather than
		# Mic itself keeps the capture effect running.
		AudioServer.add_bus()
		var sink := AudioServer.bus_count - 1
		AudioServer.set_bus_name(sink, "MicSink")
		AudioServer.set_bus_mute(sink, true)
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		AudioServer.set_bus_name(b, "Mic")
		AudioServer.set_bus_send(b, "MicSink")
		_capture = AudioEffectCapture.new()
		_capture.buffer_length = 0.5
		AudioServer.add_bus_effect(b, _capture)
	_mic = AudioStreamPlayer.new()
	_mic.stream = AudioStreamMicrophone.new()
	_mic.bus = "Mic"
	add_child(_mic)
	_mic.play()


## Tests: feed stereo frames at the mix rate as if the mic heard them.
func inject_frames(frames: PackedVector2Array) -> void:
	_injected.append_array(frames)


func _online() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _process(delta: float) -> void:
	_play_speakers(delta)
	var frames := PackedVector2Array()
	var injected := not _injected.is_empty()
	if injected:
		frames = _injected
		_injected = PackedVector2Array()
	elif _capture:
		var n := _capture.get_frames_available()
		if n > 0:
			frames = _capture.get_buffer(n)
	var ptt := enabled and InputMap.has_action("talk") and Input.is_action_pressed("talk") and not _typing()
	if ptt or (open_mic and enabled):
		_start_mic()
	# level meter (always, so the settings screen can show it)
	var rms := 0.0
	for f in frames:
		rms += f.x * f.x
	if frames.size() > 0:
		rms = sqrt(rms / frames.size())
		mic_level = lerpf(mic_level, clampf(rms * 6.0, 0.0, 1.0), 0.5)
	else:
		mic_level = move_toward(mic_level, 0.0, delta * 2.0)
	if open_mic and rms > GATE:
		_gate_t = GATE_HOLD
	_gate_t -= delta
	var send := enabled and (ptt or (open_mic and _gate_t > 0.0) or injected)
	talking_local = send and _online()
	if not talking_local:
		_out.clear()
		_rs_pos = 0.0
		return
	_resample_into(frames, _out)
	while _out.size() >= CHUNK:
		var pkt := encode(_out.slice(0, CHUNK))
		_out = _out.slice(CHUNK)
		_send(pkt)


func _typing() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit


## Box-filtered linear resampler: mix rate stereo -> RATE mono.
func _resample_into(frames: PackedVector2Array, out: PackedFloat32Array) -> void:
	var step := _mix_rate / float(RATE)
	var n := frames.size()
	var pos := _rs_pos
	while pos < n:
		var i := int(pos)
		var a := _rs_prev if i == 0 else (frames[i - 1].x + frames[i - 1].y) * 0.5
		var b := (frames[i].x + frames[i].y) * 0.5
		# average the window this output sample covers (cheap anti-alias)
		var acc := 0.0
		var cnt := 0
		var j := maxi(0, i - int(step) + 1)
		while j <= i:
			acc += (frames[j].x + frames[j].y) * 0.5
			cnt += 1
			j += 1
		var lin := lerpf(a, b, pos - i)
		out.append(lerpf(lin, acc / cnt, 0.5) if cnt > 1 else lin)
		pos += step
	_rs_pos = pos - n
	if n > 0:
		_rs_prev = (frames[n - 1].x + frames[n - 1].y) * 0.5


# ------------------------------------------------------------- mu-law
static func encode(samples: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(samples.size())
	for i in samples.size():
		var s := clampf(samples[i], -1.0, 1.0)
		var m := log(1.0 + 255.0 * absf(s)) / log(256.0)   # 0..1
		var q := int(round(m * 127.0))
		out[i] = (q | 128) if s < 0.0 else q
	return out


static func decode(data: PackedByteArray) -> PackedFloat32Array:
	if _mulaw_table.is_empty():
		_mulaw_table.resize(256)
		for b in 256:
			var m := float(b & 127) / 127.0
			var mag := (pow(256.0, m) - 1.0) / 255.0
			_mulaw_table[b] = -mag if b & 128 else mag
	var out := PackedFloat32Array()
	out.resize(data.size())
	for i in data.size():
		out[i] = _mulaw_table[data[i]]
	return out


# ------------------------------------------------------------- network
func _send(pkt: PackedByteArray) -> void:
	sent_packets += 1
	if multiplayer.is_server():
		_relay(multiplayer.get_unique_id(), channel, pkt)
	else:
		_rpc_up.rpc_id(1, channel, pkt)


## Client -> server.
@rpc("any_peer", "call_remote", "unreliable_ordered", 2)
func _rpc_up(ch: int, pkt: PackedByteArray) -> void:
	if not multiplayer.is_server() or pkt.size() > CHUNK * 2:
		return
	_relay(multiplayer.get_remote_sender_id(), ch, pkt)


## Server: pass a packet on to whoever should hear it.
func _relay(from: int, ch: int, pkt: PackedByteArray) -> void:
	for to in _route(from, ch):
		relayed_packets += 1
		if to == multiplayer.get_unique_id():
			_hear(from, ch, pkt)
		else:
			_rpc_down.rpc_id(to, from, ch, pkt)


## Who hears `from` on channel `ch`. Proximity: players within RANGE.
## (Radio channels would return everyone tuned in, once only one can talk.)
func _route(from: int, ch: int) -> Array[int]:
	var out: Array[int] = []
	if ch != CH_PROXIMITY:
		return out
	var src := _pos_of(from)
	if src == Vector3.INF:
		return out
	var ids: Array = Array(multiplayer.get_peers())
	ids.append(multiplayer.get_unique_id())   # a player host listens too (no-op on a dedicated server)
	for id in ids:
		if id == from:
			continue
		var p := _pos_of(id)
		if p != Vector3.INF and p.distance_to(src) <= RANGE:
			out.append(id)
	return out


func in_range(a: int, b: int) -> bool:
	var pa := _pos_of(a)
	var pb := _pos_of(b)
	return pa != Vector3.INF and pb != Vector3.INF and pa.distance_to(pb) <= RANGE


func _player_node(id: int) -> Node3D:
	var main := get_parent()
	if main == null or not ("players" in main) or main.players == null:
		return null
	return main.players.get_node_or_null("Player_%d" % id) as Node3D


func _pos_of(id: int) -> Vector3:
	var p := _player_node(id)
	return p.global_position if p and p.is_inside_tree() else Vector3.INF


## Server -> listener.
@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _rpc_down(from: int, ch: int, pkt: PackedByteArray) -> void:
	_hear(from, ch, pkt)


# ------------------------------------------------------------- playback
func _hear(from: int, _ch: int, pkt: PackedByteArray) -> void:
	received_packets += 1
	var sp := _speaker(from)
	if sp.is_empty():
		return
	var buf: PackedFloat32Array = sp["buf"]
	buf.append_array(decode(pkt))
	if buf.size() > RATE:   # more than a second behind: drop the oldest
		buf = buf.slice(buf.size() - int(RATE * JITTER * 2.0))
	sp["buf"] = buf
	sp["last"] = Time.get_ticks_msec()


func _speaker(id: int) -> Dictionary:
	var person := _player_node(id)
	if person == null:
		return {}
	var sp: Dictionary = _speakers.get(id, {})
	if not sp.is_empty() and is_instance_valid(sp["player"]) and sp["player"].get_parent() == person:
		return sp
	_drop_speaker(id)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.4
	var pl := AudioStreamPlayer3D.new()
	pl.name = "Voice"
	pl.stream = gen
	pl.position = Vector3(0, 1.6, 0)
	pl.unit_size = 6.0
	pl.max_distance = HEAR_RANGE
	pl.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	pl.volume_db = 4.0
	pl.panning_strength = 0.6
	person.add_child(pl)
	pl.play()
	var icon := Sprite3D.new()
	icon.name = "TalkIcon"
	icon.texture = _talk_texture()
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	icon.no_depth_test = true
	icon.pixel_size = 0.012
	icon.position = Vector3(0, 2.75, 0)
	icon.visible = false
	person.add_child(icon)
	sp = {"player": pl, "playback": pl.get_stream_playback(), "buf": PackedFloat32Array(),
		"started": false, "last": 0, "icon": icon}
	_speakers[id] = sp
	return sp


func _drop_speaker(id: int) -> void:
	var sp: Dictionary = _speakers.get(id, {})
	for k in ["player", "icon"]:
		if sp.has(k) and is_instance_valid(sp[k]):
			sp[k].queue_free()
	_speakers.erase(id)


func _play_speakers(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	for id in _speakers.keys():
		var sp: Dictionary = _speakers[id]
		if not is_instance_valid(sp["player"]):
			_speakers.erase(id)
			continue
		var talking: bool = now - int(sp["last"]) < 300
		sp["icon"].visible = talking
		var buf: PackedFloat32Array = sp["buf"]
		if not sp["started"]:
			if buf.size() < int(RATE * JITTER):
				continue
			sp["started"] = true
		var pb := sp["playback"] as AudioStreamGeneratorPlayback
		if pb == null:
			continue
		var n := mini(pb.get_frames_available(), buf.size())
		if n > 0:
			var frames := PackedVector2Array()
			frames.resize(n)
			for i in n:
				frames[i] = Vector2(buf[i], buf[i])
			pb.push_buffer(frames)
			sp["buf"] = buf.slice(n)
			sp["pushed"] = int(sp.get("pushed", 0)) + n
			sp["peak"] = maxf(float(sp.get("peak", 0.0)), _peak(frames))
		elif buf.is_empty():
			sp["started"] = false   # ran dry: re-buffer before the next sentence


static func _peak(frames: PackedVector2Array) -> float:
	var m := 0.0
	for f in frames:
		m = maxf(m, absf(f.x))
	return m


## For tests / debug: how much of a speaker's audio reached the generator.
func speaker_stats(id: int) -> Dictionary:
	var sp: Dictionary = _speakers.get(id, {})
	return {"pushed": int(sp.get("pushed", 0)), "peak": float(sp.get("peak", 0.0)), "buffered": (sp["buf"] as PackedFloat32Array).size() if sp.has("buf") else 0}


static var _icon_tex: ImageTexture


## A little cartoon speaker with sound waves, drawn once.
static func _talk_texture() -> ImageTexture:
	if _icon_tex:
		return _icon_tex
	var s := 32
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var white := Color(1, 1, 1)
	var dark := Color(0.08, 0.1, 0.15)
	for y in s:
		for x in s:
			var c := Vector2(x + 0.5, y + 0.5)
			var on := false
			# speaker box + cone
			if x >= 5 and x < 10 and y >= 12 and y < 20:
				on = true
			if x >= 10 and x < 16 and absf(c.y - 16.0) < 4.0 + (c.x - 10.0) * 1.1:
				on = true
			# two arcs
			var d := c.distance_to(Vector2(14, 16))
			var ang := absf(atan2(c.y - 16.0, c.x - 14.0))
			if ang < 0.9 and ((d > 7.0 and d < 9.5) or (d > 11.5 and d < 14.0)):
				on = true
			if on:
				img.set_pixel(x, y, white)
	# dark outline so it reads on sand and sky
	var out := img.duplicate() as Image
	for y in s:
		for x in s:
			if img.get_pixel(x, y).a > 0.5:
				continue
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < s and q.y < s and img.get_pixelv(q).a > 0.5:
					out.set_pixel(x, y, dark)
					break
	_icon_tex = ImageTexture.create_from_image(out)
	return _icon_tex

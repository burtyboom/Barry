extends Node
## Autoload "Net". Thin wrapper around ENet.
##
## Model: every player simulates their OWN car (authority) and streams its state
## to everyone else at 20 Hz. Simple, low-latency, perfect for co-op with family.
## The island is generated from a fixed seed so nothing big is sent over the wire:
## the host just tells each joining player which island it is.
##
## Joining goes through SceneMultiplayer's auth step first: the client sends its game
## version (and, for the online server, its account token). Wrong version = turned away
## with a "download the new one" message. A dedicated server (`-- --dedicated`) has no
## player of its own; it checks tokens with the website backend and reports who's online
## and their stats back to it.

signal session_ready(local_id: int)
signal session_failed(reason: String)
signal player_joined(id: int)
signal player_left(id: int)
signal island_received(island_id: String)
signal progress_received(achievements: Array, stats: Dictionary)   ## your saved account progress, on login

const PORT := 7777
const MAX_PLAYERS := 16

var mode := "none"   # none / solo / host / client / dedicated
var site_url := GameVersion.SITE_URL      ## website (accounts); -- --site=http://... overrides (testing)
var server_host := GameVersion.SERVER_HOST   ## -- --server=host[:port] overrides
var host_port := PORT                         ## -- --port=N: host on another port (tests)
var island_id := "fraser"
var dedicated := false            ## this process is the dedicated server
var server_dedicated := false     ## (client) the server we joined has no player of its own
var backend := ""                 ## (server) backend base URL, e.g. http://127.0.0.1:8080
var _server_key := ""
var _turned_away := {}            ## (server) peers we said no to, hung up on shortly
var accounts := {}                ## (server) peer id -> {"username", "since"}

# client: what we present when joining
var join_name := "Mate"
var join_token := ""
var _reject_reason := ""

var _pending_stats := {}          ## (server) username -> {"add": {}, "achievements": []}
var _beat_t := 0.0
var _flush_t := 0.0
var _local_stats := {}            ## (client) stat increments not sent yet
var _local_achs: Array[String] = []
var _send_t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--site="):
			site_url = a.substr(7).trim_suffix("/")
		elif a.begins_with("--server="):
			server_host = a.substr(9)
		elif a.begins_with("--port="):
			host_port = int(a.substr(7))   # tests running side by side
	multiplayer.peer_connected.connect(func(id: int) -> void:
		if multiplayer.is_server():
			_island_info.rpc_id(id, island_id)
		player_joined.emit(id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		if accounts.has(id):
			print("[server] %s left" % accounts[id]["username"])
			if dedicated and backend != "":
				var secs := int(Time.get_unix_time_from_system()) - int(accounts[id].get("counted", accounts[id]["since"]))
				_queue_stat(String(accounts[id]["username"]), "play_seconds", clampi(secs, 0, 15))
				_flush_stats()
			accounts.erase(id)
		player_left.emit(id))
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void:
		multiplayer.multiplayer_peer = null
		session_failed.emit("Could not connect"))
	multiplayer.server_disconnected.connect(func() -> void:
		var why := _reject_reason if _reject_reason != "" else "Lost connection to the server"
		_reject_reason = ""
		multiplayer.multiplayer_peer = null
		session_failed.emit(why))
	var sm := multiplayer as SceneMultiplayer
	sm.auth_callback = _on_auth
	sm.auth_timeout = 20.0
	sm.peer_authenticating.connect(_on_peer_authenticating)
	sm.peer_authentication_failed.connect(func(id: int) -> void:
		if not multiplayer.is_server():
			multiplayer.multiplayer_peer = null
			session_failed.emit(_reject_reason if _reject_reason != "" else "The server didn't let us in")
			_reject_reason = ""
		else:
			_turned_away.erase(id)   # already gone
			print("[server] peer %d failed to log in" % id))


func start_solo() -> void:
	mode = "solo"
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	session_ready.emit(1)


func host() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(host_port, MAX_PLAYERS)
	if err != OK:
		session_failed.emit("Could not host on port %d (error %d)" % [host_port, err])
		return
	multiplayer.multiplayer_peer = peer
	mode = "dedicated" if dedicated else "host"
	session_ready.emit(1)


func join(address: String, port := PORT) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		session_failed.emit("Could not start client (error %d)" % err)
		return
	_reject_reason = ""
	server_dedicated = false
	multiplayer.multiplayer_peer = peer
	mode = "client"


## Send any stats / achievements still waiting (before leaving).
func flush_local() -> void:
	if mode == "client" and server_dedicated and multiplayer.multiplayer_peer != null 			and (not _local_stats.is_empty() or not _local_achs.is_empty()):
		_report.rpc_id(1, _local_stats, _local_achs)
		_local_stats = {}
		_local_achs = []


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	mode = "none"
	server_dedicated = false


func _on_connected() -> void:
	pass   # wait for the host to say which island (_island_info)


@rpc("authority", "call_remote", "reliable")
func _island_info(which: String) -> void:
	island_id = which
	island_received.emit(which)


func local_ips() -> Array[String]:
	var out: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			out.append(ip)
	return out


# ------------------------------------------------------------- joining (auth)
func _on_peer_authenticating(id: int) -> void:
	if multiplayer.is_server():
		return
	# client: introduce ourselves to the server (peer 1)
	var ver := GameVersion.VERSION
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fake-version="):   # tests: pretend to be an old client
			ver = a.substr(15)
	var hello := {"version": ver, "name": join_name, "token": join_token}
	(multiplayer as SceneMultiplayer).send_auth(id, JSON.stringify(hello).to_utf8_buffer())


func _on_auth(id: int, data: PackedByteArray) -> void:
	var msg = JSON.parse_string(data.get_string_from_utf8())
	if typeof(msg) != TYPE_DICTIONARY:
		return
	var sm := multiplayer as SceneMultiplayer
	if not multiplayer.is_server():
		# the server's answer
		if msg.get("ok", false):
			server_dedicated = bool(msg.get("dedicated", false))
			if String(msg.get("name", "")) != "":
				join_name = String(msg["name"])
			sm.complete_auth(id)
			if msg.has("achievements"):
				progress_received.emit(msg.get("achievements", []), msg.get("stats", {}))
		else:
			# turned away: hang up ourselves and say why
			var why := String(msg.get("reason", "The server said no"))
			_reject_reason = ""
			(func() -> void:
				multiplayer.multiplayer_peer = null
				mode = "none"
				session_failed.emit(why)).call_deferred()
		return
	_check_hello(id, msg)


## Server: is this player allowed in?
func _check_hello(id: int, msg: Dictionary) -> void:
	var sm := multiplayer as SceneMultiplayer
	var reply := {"ok": false}
	if String(msg.get("version", "")) != GameVersion.VERSION:
		var site := site_url
		reply["reason"] = "Your game is out of date (you have %s, the server runs %s).\nDownload the latest version%s" % [
			msg.get("version", "?"), GameVersion.VERSION, " at " + site if site != "" else ""]
	elif dedicated and backend != "":
		var r := await _backend_post("/api/game/verify", {"token": String(msg.get("token", ""))})
		if r.get("ok", false):
			var uname := String(r.get("username", "Mate"))
			for other in accounts:
				if String(accounts[other]["username"]).to_lower() == uname.to_lower():
					# logged in again somewhere else: tell the old one why, then hang it up
					_kicked.rpc_id(other, "Someone else just logged in as %s.
Each person needs their own account - make one on the Play online screen." % uname)
					var old: int = other
					get_tree().create_timer(0.5).timeout.connect(func() -> void:
						if multiplayer.multiplayer_peer and old in multiplayer.get_peers():
							multiplayer.multiplayer_peer.disconnect_peer(old))
			accounts[id] = {"username": uname, "since": int(Time.get_unix_time_from_system())}
			reply = {"ok": true, "name": uname, "dedicated": true,
				"achievements": r.get("achievements", []), "stats": r.get("stats", {})}
			print("[server] %s logged in (peer %d)" % [uname, id])
		else:
			reply["reason"] = "Please log in again (%s)" % r.get("error", "login expired")
	else:
		var nm := String(msg.get("name", "Mate")).strip_edges().left(16)
		accounts[id] = {"username": nm if nm != "" else "Mate", "since": int(Time.get_unix_time_from_system())}
		reply = {"ok": true, "dedicated": dedicated}
	if multiplayer.multiplayer_peer == null:
		return
	sm.send_auth(id, JSON.stringify(reply).to_utf8_buffer())
	if reply["ok"]:
		sm.complete_auth(id)
	else:
		# give the "why" a moment to arrive before hanging up
		_turned_away[id] = true
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			if multiplayer.multiplayer_peer and _turned_away.has(id):
				_turned_away.erase(id)
				multiplayer.multiplayer_peer.disconnect_peer(id))


## Client: the server is about to hang up on us - this is the reason to show.
@rpc("authority", "call_remote", "reliable")
func _kicked(why: String) -> void:
	_reject_reason = why


## Server: the account name a peer logged in with.
func username_of(id: int) -> String:
	return String(accounts.get(id, {}).get("username", ""))


# ------------------------------------------------------------- stats + achievements
## Count something towards your stats on the website (times bogged, fish caught...).
## Batched and sent to the server every 20 s; does nothing offline / on LAN games.
func stat(key: String, n := 1) -> void:
	if n == 0:
		return
	_local_stats[key] = int(_local_stats.get(key, 0)) + n


func achievement(id: String) -> void:
	if not _local_achs.has(id):
		_local_achs.append(id)


func _process(delta: float) -> void:
	if mode == "client" and server_dedicated and multiplayer.multiplayer_peer != null:
		_send_t += delta
		if _send_t > 10.0 and (not _local_stats.is_empty() or not _local_achs.is_empty()):
			_send_t = 0.0
			_report.rpc_id(1, _local_stats, _local_achs)
			_local_stats = {}
			_local_achs = []
	if dedicated and backend != "":
		_beat_t += delta
		_flush_t += delta
		if _beat_t >= 15.0:
			_heartbeat(_beat_t)
			_beat_t = 0.0
		if _flush_t >= 15.0:
			_flush_t = 0.0
			_flush_stats()


@rpc("any_peer", "call_remote", "reliable")
func _report(add: Dictionary, achs: Array) -> void:
	if not multiplayer.is_server():
		return
	var uname := username_of(multiplayer.get_remote_sender_id())
	if uname == "":
		return
	for k in add:
		_queue_stat(uname, String(k), int(add[k]))
	var p: Dictionary = _pending_for(uname)
	for a in achs:
		if not (p["achievements"] as Array).has(String(a)):
			(p["achievements"] as Array).append(String(a))


func _pending_for(uname: String) -> Dictionary:
	if not _pending_stats.has(uname):
		_pending_stats[uname] = {"add": {}, "achievements": []}
	return _pending_stats[uname]


func _queue_stat(uname: String, key: String, n: int) -> void:
	var add: Dictionary = _pending_for(uname)["add"]
	add[key] = int(add.get(key, 0)) + n


func _heartbeat(secs: float) -> void:
	var list := []
	for id in accounts:
		var a: Dictionary = accounts[id]
		list.append({"username": a["username"], "since_unix": a["since"]})
		var now := int(Time.get_unix_time_from_system())
		_queue_stat(String(a["username"]), "play_seconds", clampi(now - int(a.get("counted", a["since"])), 0, int(round(secs)) + 1))
		a["counted"] = now
	# how the server itself is coping (shown on the website's server stats page)
	var bots := 0
	var main := get_tree().root.get_node_or_null("Main")
	if main and main.get("cars"):
		for c in main.cars.get_children():
			if c.has_meta("bot"):
				bots += 1
	var perf := {
		"fps": Engine.get_frames_per_second(),
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"static_mem_mb": OS.get_static_memory_usage() / 1048576.0,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"bots": bots,
		"uptime_s": Time.get_ticks_msec() / 1000.0,
	}
	_backend_post("/api/game/heartbeat", {"version": GameVersion.VERSION, "island": island_id, "players": list, "perf": perf})


func _flush_stats() -> void:
	if _pending_stats.is_empty():
		return
	var reports := []
	for u in _pending_stats:
		reports.append({"username": u, "add": _pending_stats[u]["add"], "achievements": _pending_stats[u]["achievements"]})
	_pending_stats = {}
	_backend_post("/api/game/stats", {"reports": reports})


## Server boot: tell the website the names of all the achievements.
func send_catalog() -> void:
	var cat := {}
	for id in Achievements.DEFS:
		var d: Array = Achievements.DEFS[id]
		cat[id] = {"title": d[0], "desc": d[1], "badge": d[2], "color": "#" + (d[3] as Color).to_html(false)}
	_backend_post("/api/game/catalog", {"achievements": cat})


func _backend_post(path: String, body: Dictionary) -> Dictionary:
	return await http_json(backend + path, body, ["X-Server-Key: " + _server_key])


func setup_dedicated(backend_url: String) -> void:
	dedicated = true
	backend = backend_url.trim_suffix("/")
	_server_key = OS.get_environment("BARRY_SERVER_KEY")
	if backend != "" and _server_key == "":
		push_warning("BARRY_SERVER_KEY isn't set - the backend will refuse us")


# ------------------------------------------------------------- website account (client)
## POST some JSON, get JSON back (or {"ok": false, "error": ...}). GET when body is null.
func http_json(url: String, body, headers: Array = []) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 12.0
	add_child(req)
	var h := PackedStringArray(["Content-Type: application/json", "Accept: application/json"])
	h.append_array(PackedStringArray(headers))
	var err: int
	if body == null:
		err = req.request(url, h, HTTPClient.METHOD_GET)
	else:
		err = req.request(url, h, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		req.queue_free()
		return {"ok": false, "error": "couldn't reach %s" % url}
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "no answer from the server"}
	var parsed = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if typeof(parsed) == TYPE_DICTIONARY:
		if int(res[1]) >= 400 and not parsed.has("ok"):
			parsed["ok"] = false
		return parsed
	if typeof(parsed) == TYPE_ARRAY:
		return {"ok": true, "list": parsed}
	return {"ok": false, "error": "server error %d" % int(res[1])}

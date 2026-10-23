extends SceneTree
## Dev: end-to-end online test against a local backend + dedicated server.
##   backend:  node server.js --memory   (PORT=8099 GAME_SERVER_KEY=localtestkey)
##   server:   BARRY_SERVER_KEY=localtestkey godot --headless --path . -- --dedicated --backend=http://127.0.0.1:8099
##   client:   godot --headless --path . -s res://tests/_online.gd -- --site=http://127.0.0.1:8099 <user> [--fake-version=0.0.1]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var user := "tester"
	for a in args:
		if not a.begins_with("--"):
			user = a
	var net = root.get_node("Net")
	var main = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	await create_timer(1.0).timeout
	var r: Dictionary = await net.http_json(net.site_url + "/api/register", {"username": user, "password": "sandy123"})
	if not r.get("ok", false):
		r = await net.http_json(net.site_url + "/api/login", {"username": user, "password": "sandy123"})
	print("LOGIN ", r.get("ok"), " ", r.get("username", r.get("error", "")))
	var failed := [""]
	net.session_failed.connect(func(why: String) -> void: failed[0] = why)
	main.join_online("127.0.0.1", 7777, String(r.get("username", user)), String(r.get("token", "")))
	for i in 120:
		await create_timer(0.25).timeout
		if main.local_car != null or failed[0] != "":
			break
	if failed[0] != "":
		print("REJECTED: ", failed[0].replace("\n", " | "))
		quit()
		return
	print("JOINED as ", main.player_name, " server_dedicated=", net.server_dedicated, " cars=", main.cars.get_child_count())
	main.achievements.unlock("bogged")
	net.stat("fish_caught", 3)
	main.send_chat("hello from " + user)
	await create_timer(24.0).timeout   # stats go every 20 s
	print("PLAYERS ", main.player_names, " balls=", main.world.get_children().filter(func(n): return n is SoccerBall).size())
	await create_timer(16.0).timeout   # server flushes every 30 s
	var pl: Dictionary = await net.http_json(net.site_url + "/api/players", null)
	print("SITE ", JSON.stringify(pl).left(600))
	var on: Dictionary = await net.http_json(net.site_url + "/api/online", null)
	print("ONLINE ", JSON.stringify(on))
	quit()

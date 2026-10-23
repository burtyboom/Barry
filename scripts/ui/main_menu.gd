class_name MainMenu
extends Control
## The front menu: the logo top-left, a card of big buttons down the left, and a
## panel on the right that changes with what you picked (online login, LAN, customise,
## what's new). The beach scene with your ute shows through behind.

var main: Node
var status: Label
var island_buttons: Array[Button] = []
var name_edit: LineEdit
var ip_edit: LineEdit
var logo: Logo
var current := ""

var _right: PanelContainer
var _panels := {}
var _hello: Label
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _remember: CheckBox
var _login_box: VBoxContainer
var _logged_box: VBoxContainer
var _logged_label: Label
var _server_label: Label
var _login_msg: Label
var _news: RichTextLabel
var _join_btn: Button
var _server_edit: LineEdit
var _busy := false

const ACCOUNT := "user://account.cfg"
var account_name := ""
var account_token := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# we sit in a CanvasLayer, so size to the window by hand
	_fit()
	get_viewport().size_changed.connect(_fit)
	_load_account()

	logo = Logo.new()
	logo.position = Vector2(26, 4)
	logo.scale = Vector2(0.78, 0.78)
	add_child(logo)

	# ---- left: the big buttons
	var left := PanelContainer.new()
	left.theme = UiTheme.make_card()
	left.position = Vector2(40, 282)   # clear of the logo's ribbon
	left.custom_minimum_size = Vector2(400, 0)
	add_child(left)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	left.add_child(vb)
	_hello = Label.new()
	_hello.add_theme_font_override("font", UiTheme.font(true))
	_hello.add_theme_font_size_override("font_size", 24)
	_hello.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_hello)
	var items := [
		["online", "Play online", UiTheme.ORANGE, 26],
		["solo", "Solo drive", UiTheme.GREEN, 22],
		["lan", "Play on LAN", UiTheme.SURF, 20],
		["custom", "Customise", UiTheme.PURPLE, 20],
		["news", "What's new", UiTheme.TEAL, 20],
	]
	for it in items:
		var b := Button.new()
		b.text = it[1]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 62 if it[0] == "online" else 52)
		UiTheme.style_button(b, it[2], it[3])
		var id: String = it[0]
		b.pressed.connect(func() -> void:
			Sfx.play_ui(self, "click", -4.0)
			if id == "solo":
				main._start("solo")
			else:
				show_panel(id))
		vb.add_child(b)
	# island picker
	var isl := HBoxContainer.new()
	isl.add_theme_constant_override("separation", 8)
	vb.add_child(isl)
	var il := Label.new()
	il.text = "Island"
	isl.add_child(il)
	var group := ButtonGroup.new()
	for key in IslandData.ISLANDS:
		var b := Button.new()
		b.text = String(IslandData.ISLANDS[key]).replace(" Island", "")
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("island", key)
		b.tooltip_text = "Solo and LAN games use this island (the online server picks its own)"
		b.pressed.connect(func() -> void:
			# swap the backdrop to the island you picked
			if visible and main.local_car == null and main.island != null and main.island.id != key and not OS.get_cmdline_user_args().size() > 0:
				main._menu_backdrop())
		isl.add_child(b)
		island_buttons.append(b)
	island_buttons[0].button_pressed = true
	var pve := CheckBox.new()
	pve.text = "PvE mode (no ute bonks or lassos between players)"
	pve.tooltip_text = "Nobody can skittle or lasso you, and you can't do it to other players - bots are still fair game"
	pve.add_theme_font_size_override("font_size", 15)
	pve.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pve.custom_minimum_size = Vector2(360, 0)
	pve.button_pressed = bool(main.pve)
	pve.toggled.connect(func(on: bool) -> void: main.set_pve(on))
	vb.add_child(pve)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 15)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(360, 0)
	status.modulate = Color(1, 1, 1, 0.8)
	vb.add_child(status)
	var quit := Button.new()
	quit.text = "Quit"
	quit.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(quit, Color(0.55, 0.55, 0.6), 16, 10, 3)
	quit.pressed.connect(func() -> void: get_tree().quit())
	vb.add_child(quit)

	# ---- right: the panel for whatever's picked
	_right = PanelContainer.new()
	_right.theme = UiTheme.make_card()
	add_child(_right)
	_right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_right.offset_left = -600
	_right.offset_right = -40
	_right.offset_top = 40
	_right.offset_bottom = -40
	_right.visible = false
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(500, 0)
	_right.add_child(stack)
	_panels["online"] = _build_online()
	_panels["lan"] = _build_lan()
	_panels["custom"] = _build_custom()
	_panels["news"] = _build_news()
	for k in _panels:
		var p: Control = _panels[k]
		p.visible = false
		stack.add_child(p)
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var ver := Label.new()
	ver.text = "v%s" % GameVersion.VERSION
	ver.add_theme_font_size_override("font_size", 14)
	ver.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	ver.add_theme_constant_override("outline_size", 4)
	add_child(ver)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	refresh_hello()
	_refresh_account()


func _fit() -> void:
	position = Vector2.ZERO
	size = get_viewport().get_visible_rect().size


func refresh_hello() -> void:
	var n: String = account_name if account_name != "" else String(main.player_name)
	_hello.text = "G'day, %s!" % (n if n != "" else "mate")


func show_panel(id: String) -> void:
	if current == id and _right.visible:
		id = ""   # click again to close
	current = id
	_right.visible = id != ""
	for k in _panels:
		(_panels[k] as Control).visible = k == id
	if id == "online":
		_check_server()
	main.menu_panel_changed(id)


func _heading(parent: Control, text: String, sub := "") -> void:
	var h := Label.new()
	h.text = text
	h.add_theme_font_override("font", UiTheme.title_font())
	h.add_theme_font_size_override("font_size", 40)
	h.add_theme_color_override("font_color", UiTheme.ORANGE)
	h.add_theme_color_override("font_outline_color", Color(0.45, 0.15, 0.05))
	h.add_theme_constant_override("outline_size", 6)
	parent.add_child(h)
	if sub != "":
		var s := Label.new()
		s.text = sub
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s.modulate = Color(1, 1, 1, 0.75)
		parent.add_child(s)


func _label(parent: Control, text: String, size := 18) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


# ------------------------------------------------------------- online
func _build_online() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_heading(vb, "Play online", "Hop on the server with your mates. Your stats and achievements show up on the website.")
	_server_label = _label(vb, "", 16)
	_server_label.add_theme_color_override("font_color", UiTheme.SURF.darkened(0.2))

	_login_box = VBoxContainer.new()
	_login_box.add_theme_constant_override("separation", 10)
	vb.add_child(_login_box)
	_user_edit = LineEdit.new()
	_user_edit.placeholder_text = "Username"
	_user_edit.max_length = 16
	_login_box.add_child(_user_edit)
	_pass_edit = LineEdit.new()
	_pass_edit.placeholder_text = "Password"
	_pass_edit.secret = true
	_pass_edit.text_submitted.connect(func(_t: String) -> void: _login(false))
	_login_box.add_child(_pass_edit)
	_remember = CheckBox.new()
	_remember.text = "Remember me on this PC"
	_remember.button_pressed = true
	_login_box.add_child(_remember)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_login_box.add_child(row)
	var li := Button.new()
	li.text = "Log in"
	li.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(li, UiTheme.ORANGE, 20)
	li.pressed.connect(_login.bind(false))
	row.add_child(li)
	var ca := Button.new()
	ca.text = "Create account"
	ca.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UiTheme.style_button(ca, UiTheme.SURF, 18)
	ca.pressed.connect(_login.bind(true))
	row.add_child(ca)
	var site := LinkButton.new()
	site.text = "Or make one on the website"
	site.add_theme_color_override("font_color", UiTheme.SURF.darkened(0.25))
	site.pressed.connect(func() -> void:
		if _net().site_url != "":
			OS.shell_open(_net().site_url + "/account.html"))
	_login_box.add_child(site)

	_logged_box = VBoxContainer.new()
	_logged_box.add_theme_constant_override("separation", 10)
	vb.add_child(_logged_box)
	_logged_label = _label(_logged_box, "", 22)
	_join_btn = Button.new()
	_join_btn.text = "Join the server"
	_join_btn.custom_minimum_size = Vector2(0, 64)
	UiTheme.style_button(_join_btn, UiTheme.GREEN, 26)
	_join_btn.pressed.connect(_join_online)
	_logged_box.add_child(_join_btn)
	var lo := Button.new()
	lo.text = "Log out"
	UiTheme.style_button(lo, Color(0.6, 0.6, 0.65), 16, 10, 3)
	lo.pressed.connect(_logout)
	_logged_box.add_child(lo)

	_login_msg = _label(vb, "", 16)
	_login_msg.add_theme_color_override("font_color", UiTheme.RED)

	var adv := HBoxContainer.new()
	vb.add_child(adv)
	var al := Label.new()
	al.text = "Server"
	al.modulate = Color(1, 1, 1, 0.6)
	adv.add_child(al)
	_server_edit = LineEdit.new()
	_server_edit.placeholder_text = _net().server_host if _net().server_host != "" else "address"
	_server_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_server_edit.tooltip_text = "Leave blank for the usual server"
	adv.add_child(_server_edit)
	return vb


func _load_account() -> void:
	var cf := ConfigFile.new()
	if cf.load(ACCOUNT) == OK:
		account_name = String(cf.get_value("account", "username", ""))
		account_token = String(cf.get_value("account", "token", ""))


func _save_account(remember: bool) -> void:
	var cf := ConfigFile.new()
	if remember:
		cf.set_value("account", "username", account_name)
		cf.set_value("account", "token", account_token)
	cf.save(ACCOUNT)


func _refresh_account() -> void:
	var logged := account_token != ""
	_login_box.visible = not logged
	_logged_box.visible = logged
	_logged_label.text = "Logged in as %s" % account_name
	if account_name != "" and _user_edit.text == "":
		_user_edit.text = account_name
	refresh_hello()


func _login(create: bool) -> void:
	if _busy:
		return
	var u := _user_edit.text.strip_edges()
	var p := _pass_edit.text
	if u == "" or p == "":
		_login_msg.text = "Type a username and password first"
		return
	if _net().site_url == "":
		_login_msg.text = "The online server isn't set up yet"
		return
	_busy = true
	_login_msg.text = "Creating your account..." if create else "Logging in..."
	var r: Dictionary = await _net().http_json(_net().site_url + ("/api/register" if create else "/api/login"), {"username": u, "password": p})
	_busy = false
	if r.get("ok", false):
		account_name = String(r.get("username", u))
		account_token = String(r.get("token", ""))
		_pass_edit.text = ""
		_login_msg.text = ""
		_save_account(_remember.button_pressed)
		_refresh_account()
	else:
		_login_msg.text = String(r.get("error", "That didn't work"))


func _logout() -> void:
	if _net().site_url != "" and account_token != "":
		_net().http_json(_net().site_url + "/api/logout", {}, ["Authorization: Bearer " + account_token])
	account_token = ""
	_save_account(false)
	_refresh_account()


## Called when the server turned our token down.
func token_rejected() -> void:
	account_token = ""
	_save_account(false)
	_refresh_account()
	show_panel("online")


func _join_online() -> void:
	var host := _server_edit.text.strip_edges()
	if host == "":
		host = _net().server_host
	if host == "":
		_login_msg.text = "The online server isn't set up yet"
		return
	var port := GameVersion.SERVER_PORT
	if ":" in host:
		port = int(host.get_slice(":", 1))
		host = host.get_slice(":", 0)
	status.text = "Connecting to the server..."
	main.join_online(host, port, account_name, account_token)


func _check_server() -> void:
	if _net().site_url == "":
		_server_label.text = "The online server isn't set up yet - try Solo or LAN for now."
		return
	_server_label.text = "Checking the server..."
	var r: Dictionary = await _net().http_json(_net().site_url + "/api/online", null)
	if not is_instance_valid(_server_label):
		return
	if not r.has("server"):
		_server_label.text = "Couldn't reach the server website."
		return
	var srv: Dictionary = r["server"]
	var names := []
	for p in r.get("players", []):
		names.append(String(p.get("username", "?")))
	if not srv.get("up", false):
		_server_label.text = "The server is down right now."
	elif names.is_empty():
		_server_label.text = "Server's up - nobody on yet. Be the first!"
	else:
		_server_label.text = "Server's up - %d on: %s" % [names.size(), ", ".join(names)]
	if String(srv.get("version", GameVersion.VERSION)) != GameVersion.VERSION and srv.get("up", false):
		_server_label.text += "\nThe server runs v%s - download the new version from the website." % srv["version"]


# ------------------------------------------------------------- LAN
func _build_lan() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	_heading(vb, "Play on LAN", "Everyone on the same Wi-Fi. One PC hosts, the others join with its IP. Everyone needs the same game version.")
	var host := Button.new()
	host.text = "Host a game (port %d)" % _net().PORT
	host.custom_minimum_size = Vector2(0, 56)
	UiTheme.style_button(host, UiTheme.SURF, 22)
	host.pressed.connect(func() -> void: main._start("host"))
	vb.add_child(host)
	var ips: Array = _net().local_ips()
	_label(vb, "This PC: %s" % (", ".join(ips) if ips.size() > 0 else "unknown IP"), 16)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	vb.add_child(hb)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Host IP e.g. 192.168.1.20"
	ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(ip_edit)
	var join := Button.new()
	join.text = "Join"
	join.custom_minimum_size = Vector2(110, 0)
	UiTheme.style_button(join, UiTheme.ORANGE, 20)
	join.pressed.connect(func() -> void:
		var ip := ip_edit.text.strip_edges()
		if ip == "":
			ip = "127.0.0.1"
		status.text = "Connecting to %s..." % ip
		main.join_lan(ip))
	hb.add_child(join)
	_label(vb, "Joining uses the host's island.", 15).modulate = Color(1, 1, 1, 0.6)
	return vb


# ------------------------------------------------------------- customise
func _build_custom() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vb)
	_heading(vb, "Customise")
	var name_row := HBoxContainer.new()
	vb.add_child(name_row)
	var nl := Label.new()
	nl.text = "Name (solo / LAN)  "
	name_row.add_child(nl)
	name_edit = LineEdit.new()
	name_edit.text = main.player_name
	name_edit.max_length = 16
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_changed.connect(func(_t: String) -> void:
		main._take_name()
		refresh_hello())
	name_row.add_child(name_edit)
	_choices(vb, "Body", {"blocky": "Blocky", "bean": "Bean"}, main.avatar_style, func(k: String) -> void: main.set_look("body", k), 2)
	_choices(vb, "Hat", Avatar.HATS, main.avatar_hat, func(k: String) -> void: main.set_look("hat", k), 4)
	_choices(vb, "Shirt", Avatar.SHIRTS, main.avatar_shirt, func(k: String) -> void: main.set_look("shirt", k), 4)
	_swatches(vb, main.CAR_PAINTS, main.shirt_color, func(c: Color) -> void: main.set_look("shirt_color", c))
	_choices(vb, "Shoes", Avatar.SHOES, main.avatar_shoes, func(k: String) -> void: main.set_look("shoes", k), 3)
	_choices(vb, "Pet", Pet.MENU, main.pet_kind, func(k: String) -> void:
		main.set_look("pet", k)
		_refresh_custom.call_deferred(), 3)
	if Pet.KINDS.has(main.pet_kind):
		var pcols := []
		for c in Pet.KINDS[main.pet_kind]["cols"]:
			pcols.append(c[1])
		_swatches(vb, pcols, Pet.colour_of(main.pet_kind, main.pet_col), func(c: Color) -> void:
			main.set_look("pet_col", pcols.find(c)))
	_choices(vb, "Ride", SandVehicle.KIND_NAMES, main.vehicle_kind, func(k: String) -> void: main.set_look("vehicle", k), 2)
	var ul := Label.new()
	ul.text = "Paint"
	ul.add_theme_font_override("font", UiTheme.font(true))
	vb.add_child(ul)
	_swatches(vb, main.CAR_PAINTS, main.car_color, func(c: Color) -> void: main.set_look("car_color", c))
	var rnd := Button.new()
	rnd.text = "Surprise me!"
	UiTheme.style_button(rnd, UiTheme.PURPLE, 18)
	rnd.pressed.connect(func() -> void:
		main.randomise_look()
		_refresh_custom())
	vb.add_child(rnd)
	return scroll


## Rebuild the Customise panel so its buttons show the current picks (keeps the scroll spot).
func _refresh_custom() -> void:
	var old: Control = _panels["custom"]
	var scroll_v := (old as ScrollContainer).scroll_vertical if old is ScrollContainer else 0
	var fresh := _build_custom()
	fresh.visible = old.visible
	old.get_parent().add_child(fresh)
	fresh.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panels["custom"] = fresh
	old.queue_free()
	if fresh is ScrollContainer:
		await get_tree().process_frame
		(fresh as ScrollContainer).scroll_vertical = scroll_v


func _choices(parent: Control, title: String, opts: Dictionary, cur: String, pick: Callable, cols: int) -> void:
	var l := Label.new()
	l.text = title
	l.add_theme_font_override("font", UiTheme.font(true))
	parent.add_child(l)
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	parent.add_child(g)
	var group := ButtonGroup.new()
	for k in opts:
		var b := Button.new()
		b.text = opts[k]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.button_pressed = k == cur
		b.pressed.connect(func() -> void:
			Sfx.play_ui(self, "click", -6.0)
			pick.call(k))
		g.add_child(b)


func _swatches(parent: Control, cols: Array, cur: Color, pick: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var group := ButtonGroup.new()
	for c in cols:
		var sw := Button.new()
		sw.toggle_mode = true
		sw.button_group = group
		sw.custom_minimum_size = Vector2(34, 34)
		sw.focus_mode = Control.FOCUS_NONE
		var off := StyleBoxFlat.new()
		off.bg_color = c
		off.set_corner_radius_all(17)
		off.set_border_width_all(2)
		off.border_color = Color(0, 0, 0, 0.35)
		var on := off.duplicate() as StyleBoxFlat
		on.set_border_width_all(5)
		on.border_color = UiTheme.ORANGE
		for k in ["normal", "hover", "focus"]:
			sw.add_theme_stylebox_override(k, off)
		for k in ["pressed", "hover_pressed"]:
			sw.add_theme_stylebox_override(k, on)
		sw.button_pressed = (c as Color).is_equal_approx(cur)
		sw.pressed.connect(func() -> void: pick.call(c))
		row.add_child(sw)


# ------------------------------------------------------------- what's new
func _build_news() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	_heading(vb, "What's new")
	_news = RichTextLabel.new()
	_news.bbcode_enabled = true
	_news.fit_content = false
	_news.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_news.add_theme_font_size_override("normal_font_size", 17)
	_news.add_theme_font_override("bold_font", UiTheme.font(true))
	_news.add_theme_font_size_override("bold_font_size", 20)
	vb.add_child(_news)
	_fill_news(_local_changelog())
	if _net().site_url != "":
		_fetch_news()
	return vb


func _local_changelog() -> Array:
	var f := FileAccess.open("res://CHANGELOG.json", FileAccess.READ)
	if f == null:
		return []
	var data = JSON.parse_string(f.get_as_text())
	return data if typeof(data) == TYPE_ARRAY else []


func _fetch_news() -> void:
	var r: Dictionary = await _net().http_json(_net().site_url + "/api/changelog", null)
	if r.has("list") and is_instance_valid(_news):
		_fill_news(r["list"])


func _fill_news(entries: Array) -> void:
	var t := ""
	for e in entries:
		t += "[b]v%s[/b]  [color=#888]%s[/color]\n" % [e.get("version", "?"), e.get("date", "")]
		for n in e.get("notes", []):
			t += "  •  %s\n" % n
		t += "\n"
	_news.text = t if t != "" else "Nothing yet!"


## The Net autoload, looked up at runtime (naming it directly breaks scripts that load this class early).
func _net() -> Node:
	return get_node("/root/Net")

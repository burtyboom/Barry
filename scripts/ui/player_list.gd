class_name PlayerList
extends PanelContainer
## Hold Tab: who's on the server. You, everyone else (with convoy mates marked),
## how many of the slots are taken, and your ping to the server.

var main: Node
var _title: Label
var _rows: VBoxContainer
var _foot: Label
var _refresh_t := 0.0


func _ready() -> void:
	add_theme_stylebox_override("panel", UiTheme.panel(Color(0.04, 0.08, 0.14, 0.88), 18, 18))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	custom_minimum_size = Vector2(380, 0)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", UiTheme.title_font())
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	vb.add_child(_title)
	vb.add_child(HSeparator.new())
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	vb.add_child(_rows)
	_foot = Label.new()
	_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_foot.add_theme_font_size_override("font_size", 13)
	_foot.modulate = Color(1, 1, 1, 0.6)
	vb.add_child(_foot)


func _process(delta: float) -> void:
	var want: bool = Input.is_key_pressed(KEY_TAB) and not Hud.typing() and get_parent().get_parent().visible
	if want and not visible:
		_refresh_t = 0.0
	visible = want
	if not visible:
		return
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.5
		_fill()
		reset_size()
	# top middle of the screen (the HUD's root has no size to anchor to)
	position = Vector2((get_viewport_rect().size.x - size.x) * 0.5, 90.0)


func _fill() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var net := get_node("/root/Net")
	var mp := main.multiplayer
	var online: bool = net.mode == "client" or net.mode == "host"
	var ids: Array = [mp.get_unique_id()]
	if online:
		for p in mp.get_peers():
			if p == 1 and net.server_dedicated:
				continue   # the online server itself, not a player
			ids.append(p)
	var convoy: Convoy = main.get("convoy")
	var names: Array = []
	for id in ids:
		names.append([String(main.name_of(id)), id])
	var me: int = mp.get_unique_id()
	names.sort_custom(func(a: Array, b: Array) -> bool:
		if (a[1] == me) != (b[1] == me):
			return a[1] == me
		return a[0].naturalnocasecmp_to(b[0]) < 0)
	for n in names:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = n[0]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_override("font", UiTheme.font(true))
		l.add_theme_font_size_override("font_size", 18)
		row.add_child(l)
		var tag := Label.new()
		tag.add_theme_font_size_override("font_size", 14)
		if n[1] == me:
			tag.text = "you"
			tag.modulate = Color(0.55, 0.85, 1.0)
		elif convoy and convoy.in_my_convoy(n[1]):
			tag.text = "convoy"
			tag.modulate = Color(0.55, 1.0, 0.6)
		elif not net.server_dedicated and n[1] == 1:
			tag.text = "host"
			tag.modulate = Color(1.0, 0.78, 0.3)
		row.add_child(tag)
		_rows.add_child(row)
	var island := IslandData.instance.display_name if IslandData.instance else ""
	if not online:
		_title.text = "Just you - solo"
		_foot.text = island
		return
	_title.text = "On the island  %d / %d" % [ids.size(), net.MAX_PLAYERS]
	var ping := ""
	var enet := mp.multiplayer_peer as ENetMultiplayerPeer
	if enet and net.mode == "client":
		var pp := enet.get_peer(1)
		if pp:
			ping = "  ·  ping %d ms" % int(pp.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	_foot.text = ("Online server" if net.server_dedicated else "LAN game") + ("  ·  " + island if island != "" else "") + ping

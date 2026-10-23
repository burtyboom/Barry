class_name ChatBox
extends PanelContainer
## Chat, bottom-left. Tabs: Players (everyone on the server sees it), Bots (what the bots
## are nattering about) and Convoy (only shows while you're in one - just your convoy).
## Enter opens the box to type (to whichever of Players / Convoy you're on), Enter
## sends, Esc closes. Click a name, or the People button, to invite someone to a convoy.
## It stays on screen, dimmed when things are quiet.

const MAX_LINES := 80
const TABS := [["players", "Players"], ["bots", "Bots"], ["convoy", "Convoy"]]

var input: LineEdit
var send_cb: Callable      ## main's send function (Players tab)
var main: Node
var _logs := {}            ## tab -> RichTextLabel
var _tab_btns := {}
var _tab := "players"
var _unread := {"players": 0, "bots": 0, "convoy": 0}
var _idle := 0.0           ## seconds since anything happened
var _open := false
var _hover := false
var _people: PanelContainer
var _people_list: VBoxContainer
var _invite_box: PanelContainer
var _name_menu: PopupMenu
var _menu_peer := 0


func _ready() -> void:
	custom_minimum_size = Vector2(290, 200)
	add_theme_stylebox_override("panel", UiTheme.panel(Color(0.04, 0.08, 0.14, 0.72), 14, 10))
	mouse_entered.connect(func() -> void: _hover = true)
	mouse_exited.connect(func() -> void: _hover = false)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 5)
	vb.add_child(tabs)
	for t in TABS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(0, 26)
		var id: String = t[0]
		b.pressed.connect(func() -> void: show_tab(id))
		tabs.add_child(b)
		_tab_btns[id] = b
		var log := RichTextLabel.new()
		log.bbcode_enabled = true
		log.scroll_following = true
		log.size_flags_vertical = Control.SIZE_EXPAND_FILL
		log.add_theme_font_size_override("normal_font_size", 15)
		log.add_theme_font_override("bold_font", UiTheme.font(true))
		log.add_theme_font_size_override("bold_font_size", 15)
		log.add_theme_constant_override("outline_size", 4)
		log.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
		log.meta_underlined = false
		log.meta_clicked.connect(_on_name_clicked)
		vb.add_child(log)
		_logs[id] = log
	_tab_btns["convoy"].visible = false
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(sp)
	var people := Button.new()
	people.text = "People"
	people.focus_mode = Control.FOCUS_NONE
	people.add_theme_font_size_override("font_size", 13)
	people.tooltip_text = "Who's on - click a name to invite them to a convoy"
	people.pressed.connect(_toggle_people)
	tabs.add_child(people)
	input = LineEdit.new()
	input.max_length = 160
	input.visible = false
	input.text_submitted.connect(_submit)
	vb.add_child(input)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "Enter to chat · click a name for a convoy"
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.5)
	vb.add_child(hint)

	# People list (pops up above the chat)
	_people = PanelContainer.new()
	_people.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.04, 0.08, 0.14, 0.92), 12, 10))
	_people.visible = false
	_people.top_level = true
	add_child(_people)
	_people_list = VBoxContainer.new()
	_people.add_child(_people_list)
	# name menu
	_name_menu = PopupMenu.new()
	_name_menu.id_pressed.connect(_on_menu)
	add_child(_name_menu)
	show_tab("players")
	add_line("players", "", "[color=#9ad]G'day! Press Enter to chat with everyone on the island.[/color]")


func _convoy() -> Convoy:
	return main.get("convoy") if main else null


func show_tab(id: String) -> void:
	_tab = id
	_unread[id] = 0
	for k in _logs:
		(_logs[k] as Control).visible = k == id
		(_tab_btns[k] as Button).set_pressed_no_signal(k == id)
	_refresh_tab_names()
	_idle = 0.0
	input.placeholder_text = "Message your convoy..." if id == "convoy" else "Say something to everyone... (Esc cancels)"


func _refresh_tab_names() -> void:
	for t in TABS:
		var k: String = t[0]
		(_tab_btns[k] as Button).text = t[1] + (" (%d)" % _unread[k] if _unread[k] > 0 else "")


## The Convoy tab comes and goes with your membership.
func convoy_changed() -> void:
	var c := _convoy()
	var on := c != null and c.my_id != ""
	_tab_btns["convoy"].visible = on
	if not on and _tab == "convoy":
		show_tab("players")
	if _people.visible:
		_fill_people()


## who = "" for system lines; text is plain (escaped here) unless who is "".
## peer > 0 makes the name clickable (convoy invite).
func add_line(tab: String, who: String, text: String, col := Color(0.55, 0.85, 1.0), peer := 0) -> void:
	var log: RichTextLabel = _logs[tab]
	var name_bb := "[b][color=#%s]%s:[/color][/b]" % [col.to_html(false), _esc(who)]
	if peer > 0 and main and peer != main.multiplayer.get_unique_id():
		name_bb = "[url=%d]%s[/url]" % [peer, name_bb]
	var line := text if who == "" else "%s %s" % [name_bb, _esc(text)]
	log.append_text(line + "\n")
	if log.get_paragraph_count() > MAX_LINES:
		log.remove_paragraph(0)
	if tab != _tab:
		_unread[tab] += 1
		_refresh_tab_names()
	if tab == _tab or tab != "bots":
		_idle = 0.0


func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func open() -> void:
	_open = true
	input.visible = true
	input.text = ""
	input.grab_focus()
	if _tab == "bots":
		show_tab("players")
	_idle = 0.0


func close() -> void:
	_open = false
	input.release_focus()
	input.visible = false
	_idle = 0.0


func is_open() -> bool:
	return _open


func _submit(t: String) -> void:
	t = t.strip_edges()
	if t != "":
		if _tab == "convoy" and _convoy():
			_convoy().send_chat(t)
		elif send_cb.is_valid():
			send_cb.call(t)
	close()


# ------------------------------------------------------------- names, people, invites
func _on_name_clicked(meta) -> void:
	_menu_for(int(str(meta)))


func _menu_for(peer: int) -> void:
	var c := _convoy()
	if c == null or not c._online():
		main.hud.show_toast("Convoys are for online games")
		return
	_menu_peer = peer
	_name_menu.clear()
	var nm: String = main.name_of(peer)
	if c.in_my_convoy(peer):
		_name_menu.add_item("%s is in your convoy" % nm, 9)
		_name_menu.set_item_disabled(0, true)
	elif c.my_id == "":
		_name_menu.add_item("Start a convoy with %s" % nm, 1)
	else:
		_name_menu.add_item("Invite %s to your convoy" % nm, 1)
	if c.my_id != "":
		_name_menu.add_item("Leave my convoy", 2)
	_name_menu.position = Vector2i(get_viewport().get_mouse_position()) + Vector2i(8, -20)
	_name_menu.popup()


func _on_menu(id: int) -> void:
	var c := _convoy()
	if c == null:
		return
	if id == 1:
		c.invite(_menu_peer)
	elif id == 2:
		c.leave()


func _toggle_people() -> void:
	_people.visible = not _people.visible
	if _people.visible:
		_fill_people()


func _fill_people() -> void:
	for ch in _people_list.get_children():
		ch.queue_free()
	var t := Label.new()
	t.text = "On the island"
	t.add_theme_font_override("font", UiTheme.title_font())
	t.add_theme_font_size_override("font_size", 18)
	t.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
	_people_list.add_child(t)
	var c := _convoy()
	var peers: Array = main.multiplayer.get_peers() if c and c._online() else []
	var any := false
	for p in peers:
		if p == 1 and main.get_node("/root/Net").server_dedicated:
			continue   # the server itself
		any = true
		var b := Button.new()
		var tag := "   (convoy)" if c.in_my_convoy(p) else ""
		b.text = String(main.name_of(p)) + tag
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 14)
		var peer: int = p
		b.pressed.connect(func() -> void: _menu_for(peer))
		_people_list.add_child(b)
	if not any:
		var l := Label.new()
		l.text = "Just you for now"
		l.modulate = Color(1, 1, 1, 0.6)
		_people_list.add_child(l)
	if c and c.my_id != "":
		var lv := Button.new()
		lv.text = "Leave my convoy"
		lv.focus_mode = Control.FOCUS_NONE
		lv.pressed.connect(func() -> void:
			c.leave()
			_people.visible = false)
		_people_list.add_child(lv)
	await get_tree().process_frame
	_people.reset_size()
	_people.global_position = global_position + Vector2(size.x - _people.size.x, -_people.size.y - 8)


## Someone wants you in their convoy: a little Join / No thanks card above the chat.
func show_invite(from_name: String, convoy_id: String) -> void:
	if _invite_box and is_instance_valid(_invite_box):
		_invite_box.queue_free()
	_invite_box = PanelContainer.new()
	_invite_box.add_theme_stylebox_override("panel", UiTheme.panel(Color(0.10, 0.35, 0.2, 0.95), 12, 12))
	_invite_box.top_level = true
	add_child(_invite_box)
	var vb := VBoxContainer.new()
	_invite_box.add_child(vb)
	var l := Label.new()
	l.text = "%s wants you in their convoy!" % from_name
	l.add_theme_font_override("font", UiTheme.font(true))
	vb.add_child(l)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vb.add_child(row)
	var yes := Button.new()
	yes.text = "Join"
	yes.focus_mode = Control.FOCUS_NONE
	UiTheme.style_button(yes, UiTheme.GREEN, 15, 10, 3)
	var box := _invite_box
	yes.pressed.connect(func() -> void:
		if _convoy():
			_convoy().accept(convoy_id)
			show_tab("convoy")
		box.queue_free())
	row.add_child(yes)
	var no := Button.new()
	no.text = "No thanks"
	no.focus_mode = Control.FOCUS_NONE
	no.pressed.connect(func() -> void: box.queue_free())
	row.add_child(no)
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		if is_instance_valid(box):
			box.queue_free())
	Sfx.play_ui(self, "blip", -4.0, 1.4)
	await get_tree().process_frame
	if is_instance_valid(box):
		box.reset_size()
		box.global_position = global_position + Vector2(0, -box.size.y - 10)


func _input(event: InputEvent) -> void:
	if _open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_idle += delta
	# always on screen, but dimmed when it's quiet so the beach shows through
	var a := 1.0 if _open or _hover or _idle < 10.0 or _people.visible else 0.55
	modulate.a = move_toward(modulate.a, a, delta * 2.0)

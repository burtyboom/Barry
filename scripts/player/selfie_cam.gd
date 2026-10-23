class_name SelfieCam
extends Node
## The phone on the hotbar (P). Click: arm up, phone out, a second to pose, then SNAP -
## the shot is taken from the phone itself (so you're off to one side with your arm
## reaching in from the corner and the island behind you), with a white flash and a
## polaroid preview. Saved in user://selfies/, and posted to the website's selfie wall
## when you're logged in online.

const POSE_TIME := 0.9
const SHOT_W := 1280

var player: PlayerCharacter
var busy := false
var _main: Node


func _ready() -> void:
	_main = get_tree().root.get_node_or_null("Main")


func take() -> void:
	if busy or player == null or not player.is_on_foot():
		return
	busy = true
	player.pose_override = "selfie"
	Sfx.play_ui(self, "click", -10.0, 1.6)
	await get_tree().create_timer(POSE_TIME).timeout
	if not is_instance_valid(player):
		busy = false
		return
	var img := await _capture()
	player.pose_override = "hold"
	busy = false
	if img == null:
		return
	_flash()
	Sfx.play_ui(self, "click", 0.0, 0.7)
	var buf := img.save_jpg_to_buffer(0.82)
	if buf.size() > 900_000:
		buf = img.save_jpg_to_buffer(0.6)
	DirAccess.make_dir_recursive_absolute("user://selfies")
	var fname := "user://selfies/selfie_%s.jpg" % Time.get_datetime_string_from_system().replace(":", "-")
	var f := FileAccess.open(fname, FileAccess.WRITE)
	if f:
		f.store_buffer(buf)
		f.close()
	if _main and _main.get("achievements"):
		_main.achievements.unlock("say_cheese")
	var posted := await _upload(buf)
	_preview(ImageTexture.create_from_image(img), posted)


## Render one frame from where the phone is, looking back over your shoulder.
func _capture() -> Image:
	var vp := get_viewport()
	var old_cam := vp.get_camera_3d()
	var av := player.avatar
	var head := av.head.global_position + Vector3.UP * 0.25
	var fwd := -player.global_basis.z
	var right := player.global_basis.x
	# the phone: at arm's length out front, up a little and off to your right (your arm
	# reaches in from that corner of the shot)
	var phone := head + fwd * 1.55 + right * 0.55 + Vector3.UP * 0.22
	var cam := Camera3D.new()
	cam.fov = 76.0
	add_child(cam)
	cam.global_position = phone
	# aim off to the side and a touch high, so you're down in one corner and the island
	# fills the rest of the shot
	var look := (head - phone).normalized().rotated(Vector3.UP, -0.48)
	look.y += 0.14
	cam.look_at(phone + look * 10.0, Vector3.UP)
	cam.current = true
	var hidden: Array[CanvasLayer] = []
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := n as CanvasLayer
		if cl.visible:
			cl.visible = false
			hidden.append(cl)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	for cl in hidden:
		if is_instance_valid(cl):
			cl.visible = true
	cam.current = false
	cam.queue_free()
	if old_cam and is_instance_valid(old_cam):
		old_cam.current = true
	if img == null or img.is_empty():
		return null
	if img.get_width() > SHOT_W:
		img.resize(SHOT_W, int(img.get_height() * float(SHOT_W) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	return img


## Post it to the website's selfie wall (only on the online server, logged in).
func _upload(buf: PackedByteArray) -> bool:
	var net := get_node("/root/Net")
	if _main == null or not net.server_dedicated or net.site_url == "":
		return false
	var token: String = _main.menu.account_token if _main.menu else ""
	if token == "":
		return false
	var where := ""
	if IslandData.instance:
		where = IslandData.instance.nearest_place(player.global_position)
	var r: Dictionary = await net.http_json(net.site_url + "/api/selfies",
		{"image": Marshalls.raw_to_base64(buf), "island": IslandData.instance.id if IslandData.instance else "", "place": where},
		["Authorization: Bearer " + token])
	if not r.get("ok", false) and _main.hud:
		_main.hud.show_toast("Couldn't post your selfie: %s" % r.get("error", "server said no"))
	return bool(r.get("ok", false))


func _flash() -> void:
	if _main == null or _main.hud == null:
		return
	var w := ColorRect.new()
	w.color = Color(1, 1, 1, 0.9)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	_main.hud.add_child(w)
	var tw := w.create_tween()
	tw.tween_property(w, "color:a", 0.0, 0.45)
	tw.tween_callback(w.queue_free)


## A little tilted polaroid that drops in at the right, then slides away.
func _preview(tex: Texture2D, posted: bool) -> void:
	if _main == null or _main.hud == null:
		return
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.99, 0.98, 0.95)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 10
	sb.content_margin_bottom = 34
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 10
	card.add_theme_stylebox_override("panel", sb)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	card.add_child(vb)
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.custom_minimum_size = Vector2(300, 170)
	vb.add_child(pic)
	var cap := Label.new()
	cap.text = "Posted to the selfie wall!" if posted else ("Saved! Log in online to post it" if not get_node("/root/Net").server_dedicated else "Saved to your PC")
	cap.add_theme_font_override("font", UiTheme.font(true))
	cap.add_theme_font_size_override("font_size", 15)
	cap.add_theme_color_override("font_color", UiTheme.INK)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cap)
	_main.hud.add_child(card)
	var vs := get_viewport().get_visible_rect().size
	card.rotation_degrees = 4.0
	card.position = Vector2(vs.x + 20, vs.y * 0.42)
	var tw := card.create_tween()
	tw.tween_property(card, "position:x", vs.x - 360.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.5)
	tw.tween_property(card, "position:x", vs.x + 40.0, 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(card.queue_free)

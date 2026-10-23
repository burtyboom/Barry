class_name InputSetup
extends RefCounted
## Registers all input actions in code so project.godot stays simple.
## Keyboard + Xbox-style gamepad.


static func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.2)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


static func _joy_axis(action: String, axis: int, dir: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = dir
	InputMap.action_add_event(action, e)


static func _joy_btn(action: String, btn: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	InputMap.action_add_event(action, e)


static func setup() -> void:
	_key("throttle", [KEY_W, KEY_UP])
	_key("brake", [KEY_S, KEY_DOWN])
	_key("steer_left", [KEY_A, KEY_LEFT])
	_key("steer_right", [KEY_D, KEY_RIGHT])
	_key("handbrake", [KEY_SPACE])
	_key("range_toggle", [KEY_L])
	_key("rear_locker", [KEY_X])
	_key("front_locker", [KEY_Z])
	_key("psi_road", [KEY_1])
	_key("psi_sand", [KEY_2])
	_key("psi_soft", [KEY_3])
	_key("psi_stuck", [KEY_4])
	_key("psi_down", [KEY_BRACKETLEFT, KEY_MINUS])
	_key("psi_up", [KEY_BRACKETRIGHT, KEY_EQUAL])
	_key("recover", [KEY_R])
	_key("teleport", [KEY_T])
	_key("camera", [KEY_C])
	_key("help", [KEY_F1])
	_key("debug", [KEY_F3])
	_key("sand_softer", [KEY_F5])
	_key("sand_harder", [KEY_F6])
	_key("map", [KEY_M])
	_key("fullscreen", [KEY_F11])
	_key("admin", [KEY_F2])
	_key("interact", [KEY_E])
	_key("winch_in", [KEY_G])
	_key("winch_out", [KEY_H])
	_key("horn", [KEY_F])
	_key("music", [KEY_N])
	_key("talk", [KEY_V])
	_key("wave", [KEY_Y])
	_key("chat", [KEY_ENTER, KEY_KP_ENTER])   # push-to-talk (proximity voice)
	var alt_enter := InputEventKey.new()
	alt_enter.physical_keycode = KEY_ENTER
	alt_enter.alt_pressed = true
	InputMap.action_add_event("fullscreen", alt_enter)

	_joy_axis("throttle", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_joy_axis("brake", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_joy_axis("steer_left", JOY_AXIS_LEFT_X, -1.0)
	_joy_axis("steer_right", JOY_AXIS_LEFT_X, 1.0)
	_joy_btn("handbrake", JOY_BUTTON_A)
	_joy_btn("range_toggle", JOY_BUTTON_Y)
	_joy_btn("rear_locker", JOY_BUTTON_X)
	_joy_btn("recover", JOY_BUTTON_BACK)
	_joy_btn("camera", JOY_BUTTON_RIGHT_STICK)
	_joy_btn("psi_down", JOY_BUTTON_DPAD_DOWN)
	_joy_btn("psi_up", JOY_BUTTON_DPAD_UP)
	_joy_btn("psi_road", JOY_BUTTON_DPAD_RIGHT)
	_joy_btn("psi_sand", JOY_BUTTON_DPAD_LEFT)
	_joy_btn("map", JOY_BUTTON_START)
	_joy_btn("talk", JOY_BUTTON_LEFT_STICK)
	# on foot
	_joy_btn("interact", JOY_BUTTON_B)
	if not InputMap.has_action("use_item"):
		InputMap.add_action("use_item", 0.2)
	_joy_btn("use_item", JOY_BUTTON_X)
	if not InputMap.has_action("hotbar_prev"):
		InputMap.add_action("hotbar_prev", 0.2)
	if not InputMap.has_action("hotbar_next"):
		InputMap.add_action("hotbar_next", 0.2)
	_joy_btn("hotbar_prev", JOY_BUTTON_LEFT_SHOULDER)
	_joy_btn("hotbar_next", JOY_BUTTON_RIGHT_SHOULDER)
	if not InputMap.has_action("look_left"):
		InputMap.add_action("look_left", 0.2)
	if not InputMap.has_action("look_right"):
		InputMap.add_action("look_right", 0.2)
	_joy_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_joy_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)

class_name FoldControls
extends Node

signal binding_changed
signal action_pressed(action: String)
signal status_changed(message: String)
var config_path := "user://controls.cfg"
const ACTIONS := ["accelerate", "brake", "left", "right", "boost", "straight", "up", "down", "marker", "spawn", "remove_ball", "delete", "pause", "mode", "reset", "jump_start", "zoom_in", "zoom_out"]
var bindings := {
	"accelerate": {"kind": "key", "code": KEY_W}, "brake": {"kind": "key", "code": KEY_S},
	"left": {"kind": "key", "code": KEY_A}, "right": {"kind": "key", "code": KEY_D},
	"boost": {"kind": "key", "code": KEY_SHIFT}, "straight": {"kind": "mouse", "code": MOUSE_BUTTON_LEFT},
	"up": {"kind": "mouse", "code": MOUSE_BUTTON_RIGHT}, "down": {"kind": "mouse", "code": MOUSE_BUTTON_RIGHT, "shift": true},
	"marker": {"kind": "mouse", "code": MOUSE_BUTTON_LEFT, "shift": true}, "spawn": {"kind": "key", "code": KEY_B},
	"remove_ball": {"kind": "key", "code": KEY_B, "shift": true}, "delete": {"kind": "key", "code": KEY_DELETE},
	"pause": {"kind": "key", "code": KEY_ESCAPE}, "mode": {"kind": "key", "code": KEY_M},
	"reset": {"kind": "key", "code": KEY_R, "ctrl": true}, "jump_start": {"kind": "key", "code": KEY_HOME},
	"zoom_in": {"kind": "mouse", "code": MOUSE_BUTTON_WHEEL_UP}, "zoom_out": {"kind": "mouse", "code": MOUSE_BUTTON_WHEEL_DOWN}
}
var secondary_bindings := {}
var held := {}
var listening := ""
var listening_slot := 0
var axis_listening := ""
var axis_baseline := {}
var wheel_buttons := {}
var wheel: Variant
var manager: Variant
var device_name := "Disconnected"
var device_path := ""
var steer_code := 0
var throttle_code := 2
var brake_code := 5
var steer_inverted := false
var throttle_inverted := false
var brake_inverted := false
var force_inverted := true
var ffb_enabled := true
var gain := 0.35
var impact_strength := 0.85
var deadzone := 0.02
var wheel_range_deg := 2540.0
var steering_lock_deg := 540.0
var steering := 0.0
var steering_rate := 0.0
var throttle := 0.0
var brake := 0.0
var constant_started := false
var forces_allowed := false
var input_valid := true
var axis_error := ""

func _ready() -> void:
	load_config()

func load_config() -> void:
	var config := ConfigFile.new()
	var result := config.load(config_path)
	if result == ERR_FILE_NOT_FOUND:
		return
	if result != OK:
		status_changed.emit("Could not load controls: " + error_string(result))
		return
	for action in ACTIONS:
		var binding = config.get_value("bindings", action, bindings[action])
		if valid_binding(binding):
			bindings[action] = binding
		var alternate = config.get_value("bindings_secondary", action, {})
		if valid_binding(alternate):
			secondary_bindings[action] = alternate
	for property in ["device_path", "steer_code", "throttle_code", "brake_code", "steer_inverted", "throttle_inverted", "brake_inverted", "force_inverted", "ffb_enabled", "gain", "impact_strength", "deadzone", "wheel_range_deg", "steering_lock_deg"]:
		var value = config.get_value("wheel", property, get(property))
		if typeof(value) == typeof(get(property)):
			set(property, value)
	gain = clampf(gain, 0, 1)
	impact_strength = clampf(impact_strength, 0, 1)
	deadzone = clampf(deadzone, 0, 0.3)
	wheel_range_deg = clampf(wheel_range_deg, 90, 3000)
	steering_lock_deg = clampf(steering_lock_deg, 90, 3000)

func save_config() -> void:
	var config := ConfigFile.new()
	for action in ACTIONS:
		config.set_value("bindings", action, bindings[action])
		config.set_value("bindings_secondary", action, secondary_bindings.get(action, {}))
	for property in ["device_path", "steer_code", "throttle_code", "brake_code", "steer_inverted", "throttle_inverted", "brake_inverted", "force_inverted", "ffb_enabled", "gain", "impact_strength", "deadzone", "wheel_range_deg", "steering_lock_deg"]:
		config.set_value("wheel", property, get(property))
	var result := config.save(config_path)
	if result != OK:
		status_changed.emit("Could not save controls: " + error_string(result))

func connect_wheel() -> void:
	close_wheel()
	if not ClassDB.class_exists("FFBManager"):
		status_changed.emit("FFB extension missing; build it using docker compose run --rm ffb-build")
		return
	if device_path.is_empty() and not DirAccess.dir_exists_absolute("/dev/input"):
		device_name = "Wheel input unavailable: /dev/input is not accessible"
		status_changed.emit(device_name)
		return
	manager = ClassDB.instantiate("FFBManager")
	wheel = manager.open_moza() if device_path.is_empty() else manager.open_device(device_path)
	if wheel == null or not wheel.is_open():
		device_name = "No accessible Moza FFB device"
		status_changed.emit(device_name)
		return
	device_name = wheel.get_device_name()
	wheel.set_inverted(force_inverted)
	wheel.set_gain(1.0)
	wheel.set_autocenter(0.0)
	status_changed.emit(device_name + " connected")

func listen(action: String, slot: int = 0) -> void:
	listening_slot = slot
	listening = action
	axis_listening = ""
	held.clear()
	binding_changed.emit()

func listen_axis(axis: String) -> void:
	if wheel == null or not wheel.is_open():
		status_changed.emit("Connect the wheel first")
		return
	listening = ""
	axis_listening = axis
	axis_baseline.clear()
	for code in wheel.get_axes():
		axis_baseline[int(code)] = wheel.get_axis_normalized(int(code))
	status_changed.emit("Move only the " + axis + " axis through its travel")

static func valid_binding(binding: Variant) -> bool:
	return binding is Dictionary and (binding.is_empty() or (binding.get("kind") in ["key", "mouse", "joy_button", "wheel_button"] and binding.get("code") is int))

func get_binding(action: String, slot: int = 0) -> Dictionary:
	return bindings[action] if slot == 0 else secondary_bindings.get(action, {})

func assign_binding(action: String, binding: Dictionary, slot: int = 0) -> void:
	var destination: Dictionary = bindings if slot == 0 else secondary_bindings
	destination[action] = binding
	held.erase(action)
	listening = ""
	save_config()
	binding_changed.emit()

func describe(action: String, slot: int = 0) -> String:
	if listening == action and listening_slot == slot:
		return "Press input… (Esc cancels)"
	var b := get_binding(action, slot)
	if b.is_empty():
		return "Unassigned"
	var prefix := "Shift + " if b.get("shift", false) else ""
	if b.get("ctrl", false):
		prefix += "Ctrl + "
	if b.kind == "key":
		return prefix + OS.get_keycode_string(b.code)
	return prefix + b.kind.replace("_", " ") + " " + str(b.code)

func set_held(action: String, slot: int, pressed: bool) -> void:
	if pressed:
		if not held.has(action):
			held[action] = {}
		held[action][slot] = true
		return
	if not held.has(action):
		return
	held[action].erase(slot)
	if held[action].is_empty():
		held.erase(action)

static func same_input(event: InputEvent, b: Dictionary) -> bool:
	if b.is_empty():
		return false
	if event is InputEventKey and b.kind == "key":
		return event.physical_keycode == b.code
	if event is InputEventMouseButton and b.kind == "mouse":
		return event.button_index == b.code
	if event is InputEventJoypadButton and b.kind == "joy_button":
		return event.button_index == b.code and event.device == b.get("device", event.device)
	return false

func match_event(event: InputEvent, b: Dictionary) -> bool:
	if b.is_empty():
		return false
	if event is InputEventKey and b.kind == "key":
		return event.physical_keycode == b.code and (b.code == KEY_SHIFT or event.shift_pressed == b.get("shift", false)) and event.ctrl_pressed == b.get("ctrl", false)
	if event is InputEventMouseButton and b.kind == "mouse":
		return event.button_index == b.code and event.shift_pressed == b.get("shift", false) and event.ctrl_pressed == b.get("ctrl", false)
	if event is InputEventJoypadButton and b.kind == "joy_button":
		return event.button_index == b.code and event.device == b.get("device", event.device)
	return false

func handle_event(event: InputEvent) -> bool:
	if not listening.is_empty():
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			listening = ""
			binding_changed.emit()
			return true
		var binding := {}
		if event is InputEventKey and event.pressed and not event.echo:
			binding = {"kind": "key", "code": event.physical_keycode, "shift": event.shift_pressed and event.physical_keycode != KEY_SHIFT, "ctrl": event.ctrl_pressed and event.physical_keycode != KEY_CTRL}
		if event is InputEventMouseButton and event.pressed:
			binding = {"kind": "mouse", "code": event.button_index, "shift": event.shift_pressed, "ctrl": event.ctrl_pressed}
		if event is InputEventJoypadButton and event.pressed:
			binding = {"kind": "joy_button", "code": event.button_index, "device": event.device}
		if not binding.is_empty():
			assign_binding(listening, binding, listening_slot)
		return true
	if event is InputEventKey and event.echo:
		return false
	# Each slot owns its held state, so releasing one input preserves the other.
	if not event.is_pressed():
		for action in ACTIONS:
			for slot in range(2):
				var binding := get_binding(action, slot)
				var modifier_released := false
				if event is InputEventKey and event.physical_keycode in [KEY_SHIFT, KEY_CTRL]:
					var modifier := "shift" if event.physical_keycode == KEY_SHIFT else "ctrl"
					modifier_released = binding.get(modifier, false)
				if same_input(event, binding) or modifier_released:
					set_held(action, slot, false)
		return false
	var matched := false
	var wheel_tick: bool = event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]
	for action in ACTIONS:
		var matched_action := false
		for slot in range(2):
			if match_event(event, get_binding(action, slot)):
				if not wheel_tick:
					set_held(action, slot, true)
				matched_action = true
		if matched_action:
			action_pressed.emit(action)
			matched = true
	return matched

func value(action: String) -> float:
	return 1.0 if held.has(action) and not held[action].is_empty() else 0.0

func poll(dt: float) -> void:
	if wheel == null or not wheel.is_open():
		steering = 0
		throttle = 0
		brake = 0
		return
	wheel.poll()
	if not axis_listening.is_empty():
		for code in axis_baseline:
			if absf(wheel.get_axis_normalized(code) - axis_baseline[code]) > 0.2:
				set(axis_listening + "_code", code)
				axis_listening = ""
				save_config()
				binding_changed.emit()
				break
	var available: Array = wheel.get_axes()
	input_valid = steer_code in available and throttle_code in available and brake_code in available
	if not input_valid:
		steering = 0
		steering_rate = 0
		throttle = 0
		brake = 0
		stop_force()
		var message := "Selected ABS axis is unavailable; assign the wheel axes in Setup"
		if axis_error != message:
			axis_error = message
			status_changed.emit(message)
		return
	axis_error = ""
	var previous := steering
	var raw: float = wheel.get_axis_centered(steer_code)
	if steer_inverted:
		raw = -raw
	raw = clampf(raw * wheel_range_deg / maxf(steering_lock_deg, 90.0), -1, 1)
	steering = signf(raw) * maxf(0, (absf(raw) - deadzone) / (1.0 - deadzone))
	steering_rate = (steering - previous) / maxf(dt, 0.0001)
	throttle = wheel.get_axis_normalized(throttle_code)
	brake = wheel.get_axis_normalized(brake_code)
	if throttle_inverted:
		throttle = 1.0 - throttle
	if brake_inverted:
		brake = 1.0 - brake
	for code in range(256, 768):
		var pressed: bool = wheel.is_button_pressed(code)
		if pressed == wheel_buttons.get(code, false):
			continue
		wheel_buttons[code] = pressed
		if pressed and not listening.is_empty():
			assign_binding(listening, {"kind": "wheel_button", "code": code}, listening_slot)
			continue
		for action in ACTIONS:
			var matched_action := false
			for slot in range(2):
				var binding := get_binding(action, slot)
				if binding.get("kind") == "wheel_button" and binding.code == code:
					set_held(action, slot, pressed)
					matched_action = true
			if pressed and matched_action:
				action_pressed.emit(action)

func apply_force(torque: float) -> void:
	if wheel == null or not wheel.is_open():
		return
	if not forces_allowed or not ffb_enabled or not input_valid:
		stop_force()
		return
	if not constant_started:
		constant_started = wheel.start_constant_force()
		if not constant_started:
			status_changed.emit("Failed to start constant force")
			ffb_enabled = false
			return
	wheel.set_inverted(force_inverted)
	wheel.update_constant_force(clampf(torque, -gain, gain))

func stop_force() -> void:
	if wheel != null and wheel.is_open() and constant_started:
		wheel.update_constant_force(0.0)
		wheel.stop_constant_force()
	constant_started = false

func close_wheel() -> void:
	stop_force()
	if wheel != null and wheel.is_open():
		wheel.close()
	wheel = null
	wheel_buttons.clear()
	steering = 0
	steering_rate = 0
	throttle = 0
	brake = 0

func _exit_tree() -> void:
	close_wheel()

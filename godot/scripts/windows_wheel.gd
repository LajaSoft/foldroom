extends RefCounted

# Windows input comes from Godot; motor output comes from SDL3 haptics.
# Button codes occupy the same adapter range as the Linux controls interface.
var haptics: Variant
var joy_id := -1
var inverted := false
var running := false
var next_keep_alive_ms := 0
var connection_error := ""

func open(name_filter: String = "") -> bool:
	close()
	connection_error = ""
	if not ClassDB.class_exists("ForceFeedback"):
		return fail_connection("Windows FFB extension is missing")
	var needle := name_filter.to_lower()
	var input_names := []
	for id in Input.get_connected_joypads():
		var name := Input.get_joy_name(id)
		input_names.append(name)
		var lower_name := name.to_lower()
		var matches := lower_name.contains(needle)
		if needle.is_empty():
			matches = lower_name.contains("moza") or lower_name.contains("gudsen")
		if not matches:
			continue
		haptics = ClassDB.instantiate("ForceFeedback")
		var names: PackedStringArray = haptics.list_devices()
		var index := matching_haptic_index(name, names)
		if index < 0:
			haptics = null
			return fail_connection("No unique FFB match for " + name + "; haptic devices: " + str(names))
		if not haptics.open(index):
			haptics = null
			return fail_connection("Cannot open Windows FFB device: " + names[index] + "; see Godot log for SDL error")
		joy_id = id
		Input.joy_connection_changed.connect(_on_joy_connection_changed)
		haptics.stop_all()
		return true
	return fail_connection("No matching Windows wheel input; connected devices: " + str(input_names))

func fail_connection(message: String) -> bool:
	connection_error = message
	push_error(message)
	return false

static func canonical_device_name(name: String) -> String:
	return name.trim_prefix("SDL ").strip_edges().to_lower()

static func matching_haptic_index(input_name: String, names: PackedStringArray) -> int:
	var identity := canonical_device_name(input_name)
	var matched := -1
	for index in range(names.size()):
		if canonical_device_name(names[index]) != identity:
			continue
		if matched >= 0:
			return -1
		matched = index
	return matched

func _on_joy_connection_changed(id: int, connected: bool) -> void:
	if id == joy_id and not connected:
		close()

func is_open() -> bool:
	return haptics != null and haptics.is_open() and joy_id in Input.get_connected_joypads()

func get_device_name() -> String:
	return haptics.get_device_name() if is_open() else "Disconnected"

func poll() -> void:
	if not is_open():
		close()

func get_axes() -> Array:
	return range(JOY_AXIS_MAX) if is_open() else []

func get_axis_centered(code: int) -> float:
	return Input.get_joy_axis(joy_id, code) if is_open() and code >= 0 and code < JOY_AXIS_MAX else 0.0

func get_axis_normalized(code: int) -> float:
	return (get_axis_centered(code) + 1.0) * 0.5

func is_button_pressed(code: int) -> bool:
	return is_open() and code >= 256 and code < 256 + JOY_BUTTON_MAX and Input.is_joy_button_pressed(joy_id, code - 256)

func set_inverted(value: bool) -> void:
	inverted = value

func set_gain(value: float) -> void:
	if is_open():
		haptics.set_gain(value)

func set_autocenter(value: float) -> void:
	if is_open():
		haptics.set_autocenter(value)

func start_constant_force() -> bool:
	running = is_open() and haptics.supports_constant()
	return running

func update_constant_force(value: float) -> void:
	if not is_open() or not running:
		return
	haptics.set_constant_force(-value if inverted else value)
	var now := Time.get_ticks_msec()
	if now >= next_keep_alive_ms:
		haptics.keep_alive()
		next_keep_alive_ms = now + 1000

func stop_constant_force() -> void:
	if haptics != null:
		haptics.stop_all()
	running = false
	next_keep_alive_ms = 0

func close() -> void:
	if Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.disconnect(_on_joy_connection_changed)
	stop_constant_force()
	if haptics != null:
		haptics.close()
	haptics = null
	joy_id = -1

# Diagnostic entry point also works in release exports; never opens hardware.
static func verify_extension() -> bool:
	if not ClassDB.class_exists("ForceFeedback"):
		push_error("Windows FFB class was not registered")
		return false
	for method in ["list_devices", "open", "open_by_name", "is_open", "supports_constant", "set_gain", "set_autocenter", "set_constant_force", "keep_alive", "stop_all", "close"]:
		if not ClassDB.class_has_method("ForceFeedback", method):
			push_error("Windows FFB method missing: " + method)
			return false
	var device = ClassDB.instantiate("ForceFeedback")
	if device.is_open():
		push_error("Windows FFB device unexpectedly open")
		return false
	device.stop_all()
	device.close()
	device.close()
	print("WINDOWS FFB DLL TEST PASSED; no hardware opened")
	return true

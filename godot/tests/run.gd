extends SceneTree

const Maze = preload("res://scripts/maze.gd")
const Motion = preload("res://scripts/motion.gd")
const State = preload("res://scripts/state.gd")
const Gyro = preload("res://scripts/gyro.gd")
const Controls = preload("res://scripts/controls.gd")
const Renderer = preload("res://scripts/renderer.gd")
class FakeWheel extends RefCounted:
	var open := true
	var started := false
	var values := {0: 0.5, 2: 0.0, 5: 0.0}
	var buttons := {}
	var forces := []
	var stops := 0
	var reject_force := false
	func is_open() -> bool: return open
	func poll() -> void: pass
	func get_axes() -> Array: return [0, 2, 5]
	func get_axis_normalized(code: int) -> float: return values.get(code, 0.0)
	func get_axis_centered(code: int) -> float: return get_axis_normalized(code) * 2.0 - 1.0
	func is_button_pressed(code: int) -> bool: return buttons.get(code, false)
	func start_constant_force() -> bool:
		started = not reject_force
		return started
	func update_constant_force(value: float) -> void: forces.append(value)
	func stop_constant_force() -> void:
		started = false
		stops += 1
	func set_inverted(_value: bool) -> void: pass
	func close() -> void: open = false

class FakeHaptics extends RefCounted:
	var forces := []
	var stops := 0
	var closed := false
	func supports_constant() -> bool: return true
	func set_constant_force(value: float) -> void: forces.append(value)
	func keep_alive() -> void: pass
	func stop_all() -> void: stops += 1
	func close() -> void: closed = true

class FakeWindowsWheel extends "res://scripts/windows_wheel.gd":
	var connected := true
	func is_open() -> bool: return connected and haptics != null

var failures: Array = []
var checks := 0
var largest_error := 0.0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func near_vec(actual: Vector3, expected: Variant, message: String, tolerance: float = 0.004) -> void:
	var target := expected as Vector3 if expected is Vector3 else State.vec(expected)
	var difference := actual.distance_to(target)
	largest_error = maxf(largest_error, difference)
	check(difference <= tolerance, "%s difference %.8f > %.8f" % [message, difference, tolerance])

func decode_actor(source: Dictionary) -> Dictionary:
	var actor := source.duplicate(true)
	for key in ["p", "up", "velocity", "forward", "omega", "motorAxis", "cameraForward", "cameraUp"]:
		if actor.has(key):
			actor[key] = State.vec(actor[key])
	if actor.has("spin"):
		var q: Array = actor.spin
		actor.spin = Quaternion(q[0], q[1], q[2], q[3])
	actor.room = int(actor.room)
	return actor

func compare_actor(actor: Dictionary, expected: Dictionary, context: String) -> void:
	check(actor.room == int(expected.room), context + " room")
	for key in ["p", "up", "velocity", "forward", "omega", "motorAxis", "cameraForward", "cameraUp"]:
		if expected.has(key):
			near_vec(actor[key], expected[key], context + " " + key)
	if expected.has("spin"):
		var q: Array = expected.spin
		check(absf(actor.spin.dot(Quaternion(q[0], q[1], q[2], q[3]))) > 0.999, context + " spin")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var file := FileAccess.open("res://tests/reference.json", FileAccess.READ)
	check(file != null, "Reference fixtures exist")
	if file == null:
		quit(1)
		return
	var reference: Dictionary = JSON.parse_string(file.get_as_text())
	test_tube_sample_cache()
	test_tube_third_person_camera()
	test_third_person_camera()
	test_portals(reference.transport)
	test_portal_images(reference.transport)
	test_trajectories(reference.trajectories)
	test_powered_balls(reference.balls)
	test_contacts(reference.contact)
	test_state(reference.state)
	test_tubes(reference.transport)
	test_tube_fillets()
	test_pipe_catalog_classes()
	test_pipe_scale_migration()
	test_tube_control()
	test_tube_sphere_support_and_motor()
	test_straight_tube_radius()
	test_tube_rollback_skid()
	test_round_tube_junctions()
	test_hall_corner_clearance()
	test_open_cycle_corners()
	test_open_hall_columns()
	test_shared_hall_support_planes()
	test_shared_hall_has_no_inner_rim()
	test_pipe_hall_flare()
	test_topology()
	test_corner_rules_and_pruning()
	test_paired_folded_corner_rule()
	test_single_fold_square_rule()
	test_two_fold_square_rule()
	test_stability()
	test_asphalt()
	test_gyro()
	test_controls()
	test_windows_output()
	test_native_ffb()
	test_wheel()
	test_secondary_bindings()
	test_impact_vibration()
	print("NATIVE TESTS: ", checks, " checks; ", failures.size(), " failures; largest JS trajectory error ", largest_error)
	if not failures.is_empty():
		print(JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)

func test_native_ffb() -> void:
	for native_class in ["FFBManager", "FFBDevice"]:
		check(ClassDB.class_exists(native_class), "GitHub FFB registers " + native_class)
		if not ClassDB.class_exists(native_class):
			return
	for method in ["open_moza", "open_device", "list_devices"]:
		check(ClassDB.class_has_method("FFBManager", method), "FFBManager API: " + method)
	for method in ["poll", "get_axes", "get_axis_normalized", "get_axis_centered", "is_button_pressed", "start_constant_force", "update_constant_force", "stop_constant_force", "set_gain", "set_inverted", "set_autocenter", "close"]:
		check(ClassDB.class_has_method("FFBDevice", method), "FoldRoom wheel API: " + method)
	var device = ClassDB.instantiate("FFBDevice")
	check(not device.is_open(), "Native device starts closed; no hardware opened")
	device.close()
	check(not device.is_open(), "Closing an unused native device is idempotent")
	check(FileAccess.file_exists("res://addons/ffb/bin/libffb.linux.template_release.x86_64.so"), "Release library installed alongside debug")
	check(FileAccess.get_file_as_string("res://addons/ffb/VERSION").strip_edges() == "0.1.0", "Installed FFB version matches pinned GitHub source")

func test_portals(cases: Array) -> void:
	for i in range(cases.size()):
		var c: Dictionary = cases[i]
		var maze := Maze.new()
		var link := maze.create(0, int(c.face), c.kind, State.vec(c.up))
		check(not link.is_empty(), "Portal %d create" % i)
		var vectors := []
		for v in c.vectors:
			vectors.append(State.vec(v))
		var result := maze.transport(0, int(c.face), State.vec(c.p), vectors)
		check(result.room == int(c.result.room), "Portal %d destination" % i)
		near_vec(result.p, c.result.p, "Portal %d position" % i, 0.00001)
		for j in range(vectors.size()):
			near_vec(result.vectors[j], c.result.vectors[j], "Portal %d vector %d" % [i, j], 0.00001)
		var back := maze.transport(result.room, link.face, result.p, result.vectors)
		near_vec(back.p, c.p, "Portal %d inverse position" % i, 0.00001)
		for j in range(vectors.size()):
			near_vec(back.vectors[j], vectors[j], "Portal %d inverse vector %d" % [i, j], 0.00001)
		check(maze.remove(0, int(c.face)) and maze.passage_count() == 0 and maze.walls.is_empty(), "Portal %d symmetric removal" % i)

func test_trajectories(cases: Array) -> void:
	for i in range(cases.size()):
		var c: Dictionary = cases[i]
		var maze := Maze.new()
		maze.create(0, int(c.face), c.kind, State.vec(c.up))
		var player := decode_actor(c.initial)
		var frame_index := 0
		for tick in range(360):
			var throttle := 1.0 if tick < 180 else (-1.0 if tick < 240 else 0.0)
			var side := 0.4 if tick > 270 else 0.0
			if c.mode == "ball":
				Motion.drive(maze, player, 1.0 / 120, throttle, side)
				Motion.update_camera(player, 1.0 / 120)
			if c.mode == "walk":
				Motion.move_player(maze, player, 1.0 / 120, throttle, side)
			if tick % 30 == 29:
				compare_actor(player, c.frames[frame_index].player, "Trajectory %d tick %d" % [i, tick + 1])
				frame_index += 1

func test_powered_balls(cases: Array) -> void:
	for i in range(cases.size()):
		var c: Dictionary = cases[i]
		var maze := Maze.new()
		var ball := decode_actor(c.initial)
		var frame_index := 0
		for tick in range(600):
			Motion.move_ball(maze, ball, 1.0 / 120)
			if tick % 60 == 59:
				compare_actor(ball, c.frames[frame_index].ball, "Powered ball %d tick %d" % [i, tick + 1])
				frame_index += 1

func test_contacts(c: Dictionary) -> void:
	var actors := []
	for value in c.initial:
		actors.append(decode_actor(value))
	Motion.resolve_contacts(actors, Maze.new())
	for i in range(actors.size()):
		compare_actor(actors[i], c.expected[i], "Sphere contact %d" % i)

func test_state(source: String) -> void:
	var state := State.new()
	var result := state.import_json(source)
	check(not result.is_empty(), "Web JSON imports: " + state.error)
	if result.is_empty():
		return
	var exported := State.export_json(result.maze, result.player, result.balls, result.marks)
	check(exported.contains("\n  \"rooms\": ["), "Native export uses indented lines")
	var second := state.import_json(exported)
	check(not second.is_empty(), "Native JSON reimports: " + state.error)
	check(second.maze.passage_count() == result.maze.passage_count(), "JSON preserves passage count")
	near_vec(second.player.p, result.player.p, "JSON preserves player")
	var data: Dictionary = JSON.parse_string(source)
	data.passages.append(data.passages[0].duplicate(true))
	check(state.import_json(JSON.stringify(data)).is_empty(), "Reject occupied endpoints")
	check(not state.error.is_empty(), "Invalid state has explicit error")
	check(state.import_json("{bad json").is_empty(), "Reject malformed JSON")
	data = JSON.parse_string(source)
	data.player.up = [0.1, 0.9, 0]
	check(state.import_json(JSON.stringify(data)).is_empty(), "Reject invalid gravity")
	data = JSON.parse_string(source)
	data.balls[0].p = [900, 0, 0]
	data.balls[0].omega = [9999, 0, 0]
	result = state.import_json(JSON.stringify(data))
	check(not result.is_empty(), "Recover legacy escaped free sphere")
	check(result.balls[0].velocity == Vector3.ZERO and result.balls[0].omega == Vector3.ZERO, "Recovery stops invalid ball motion")
	var example := FileAccess.get_file_as_string("res://example.json")
	check(not state.import_json(example).is_empty(), "Bundled web example imports: " + state.error)
	# Native output is consumed by the original web importer in the verification script.
	var out := FileAccess.open("res://tests/native-export.json", FileAccess.WRITE)
	out.store_string(exported)

func test_topology() -> void:
	var maze := Maze.new()
	var link := maze.create(0, 0, "up", Vector3.UP)
	var opposite := maze.room(Vector3i.RIGHT)
	check(maze.create(opposite.id, 1, "straight", Vector3.UP).is_empty(), "Fold boundary blocks straight from backside")
	check(not maze.create(opposite.id, 1, "up", Vector3.UP).is_empty(), "Backside permits own fold")
	var count := maze.rooms.size()
	check(maze.create(0, 0, "up", Vector3.UP).is_empty() and maze.rooms.size() == count, "Rejected passage adds no orphan room")
	check(link.q.is_normalized(), "Portal rotation normalized")
	maze = Maze.new()
	for i in range(1, 10000):
		maze.room(Vector3i(i, 0, 0))
	check(maze.rooms.size() == 10000, "10,000 rooms supported")
	check(maze.room(Vector3i(10000, 0, 0)).is_empty(), "Room 10,001 rejected")
	check(maze.room(Vector3i(5, 0, 0)).id == 5, "Grid reuses existing cell")
	var player := Motion.initial_player()
	check(player.mode == "ball" and player.velocity == Vector3.ZERO, "Ball default, no automatic acceleration")
	var original: Vector3 = player.p
	Motion.set_mode(player, "walk")
	Motion.set_mode(player, "ball")
	near_vec(player.p, original, "Mode switching preserves center")

func test_stability() -> void:
	var maze := Maze.new()
	maze.create(0, 0, "up", Vector3.UP)
	maze.create(1, 3, "down", Vector3.RIGHT)
	var player := Motion.initial_player()
	player.velocity = Vector3(1100, -100, 0)
	for tick in range(1200):
		Motion.drive(maze, player, 1.0 / 120, 0, 0)
		Motion.update_camera(player, 1.0 / 120)
		var p: Vector3 = player.p
		check(p.is_finite() and absf(p.x) <= 3.6 and absf(p.y) <= 3.6 and absf(p.z) <= 3.6, "High speed stays bounded tick %d" % tick)
		check(player.velocity.length() <= 1200.01, "Hard speed cap tick %d" % tick)
		check(absf(player.cameraForward.dot(player.cameraUp)) < 0.0001, "Camera frame orthogonal tick %d" % tick)

func test_gyro() -> void:
	var model := Gyro.new()
	model.strength = 0.7
	var idle := model.compute(0, 0, 0, 0, 1, 0, 0.02)
	check(idle == 0, "Gyro neutral produces zero force")
	var left := model.compute(0.5, 0, 5, 0, 1, 0, 1)
	model.reset()
	var right := model.compute(-0.5, 0, 5, 0, 1, 0, 1)
	check(left < 0 and right > 0 and absf(left + right) < 1e-6, "Gyro restoring force symmetric")
	model.reset()
	var slow := absf(model.compute(0, 1, 0, 0, 1, 0, 1))
	model.reset()
	var fast := absf(model.compute(0, 1, 12, 0, 1, 0, 1))
	check(fast > slow, "Rotor angular momentum increases steering resistance")
	model.reset()
	check(model.compute(0, 0, 0, 5, 1, 0, 1) < 0, "Lateral load has direction")
	model.reset()
	check(model.compute(0, 0, 0, 5, 0, 0, 1) == 0, "No tire load in free fall")
	model.impact(8, -1)
	check(absf(model.compute(0, 0, 0, 0, 1, 0, 0.001)) > 0, "Collision creates force pulse")
	for i in range(1000):
		var output := model.compute(sin(i), cos(i) * 20, 48, 900, 1, 1, 0.01)
		check(is_finite(output) and absf(output) <= 0.70001, "FFB bounded tick %d" % i)
	model.reset()
	check(model.output == 0 and model.pulse == 0, "Pause reset clears all force state")

func test_controls() -> void:
	var controls := Controls.new()
	var pressed := []
	controls.action_pressed.connect(func(action): pressed.append(action))
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	controls.handle_event(key)
	check(controls.value("accelerate") == 1 and pressed.has("accelerate"), "Keyboard accelerate")
	key.pressed = false
	controls.handle_event(key)
	check(controls.value("accelerate") == 0, "Keyboard release")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_RIGHT
	mouse.pressed = true
	mouse.shift_pressed = true
	pressed.clear()
	controls.handle_event(mouse)
	check(pressed == ["down"], "Shift right click does not also carve upward")
	mouse.shift_pressed = false
	mouse.pressed = false
	controls.handle_event(mouse)
	check(controls.value("down") == 0, "Release clears action even when Shift released first")
	var marker := InputEventMouseButton.new()
	marker.button_index = MOUSE_BUTTON_LEFT
	marker.shift_pressed = true
	marker.pressed = true
	controls.handle_event(marker)
	key.physical_keycode = KEY_SHIFT
	key.pressed = false
	controls.handle_event(key)
	check(controls.value("marker") == 0, "Releasing Shift ends wall drawing immediately")
	controls.listening = "spawn"
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	controls.handle_event(key)
	check(controls.listening.is_empty(), "Escape cancels binding")
	# Remap without writing a user's config: listener is exercised with Escape above;
	# matching a custom binding is tested directly here.
	var custom := {"kind": "key", "code": KEY_F, "shift": false}
	key.physical_keycode = KEY_F
	check(controls.match_event(key, custom), "Custom key binding matches")
	check(not controls.match_event(key, {"kind": "key", "code": KEY_G}), "Different binding rejected")
	controls.free()

func test_wheel() -> void:
	var controls := Controls.new()
	controls.config_path = "user://test-controls.cfg"
	var wheel := FakeWheel.new()
	controls.wheel = wheel
	controls.forces_allowed = false
	controls.ffb_enabled = true
	controls.apply_force(0.5)
	check(not wheel.started and wheel.forces.is_empty(), "Menus never start FFB")
	controls.forces_allowed = true
	controls.apply_force(0.9)
	check(wheel.started and wheel.forces[-1] == controls.gain, "Physical FFB output clamps to configured strength")
	controls.forces_allowed = false
	controls.apply_force(0.9)
	check(not wheel.started and wheel.forces[-1] == 0.0 and wheel.stops == 1, "Pause zeros and stops the effect")
	controls.poll(0.01)
	check(controls.steering == 0 and controls.throttle == 0 and controls.brake == 0, "Neutral wheel and pedals")
	wheel.values[0] = 0.55
	controls.poll(0.01)
	check(controls.steering > 0.4 and controls.steering < 0.5, "Physical steering range maps to game lock")
	controls.listen_axis("throttle")
	wheel.values[5] = 0.7
	controls.poll(0.01)
	check(controls.throttle_code == 5 and controls.axis_listening.is_empty(), "Axis movement captures ABS code")
	controls.listening = "spawn"
	wheel.buttons[300] = true
	controls.poll(0.01)
	check(controls.bindings.spawn == {"kind": "wheel_button", "code": 300}, "Wheel button can be assigned")
	wheel.buttons[300] = false
	controls.poll(0.01)
	wheel.buttons[300] = true
	controls.poll(0.01)
	check(controls.value("spawn") == 1, "Assigned wheel button drives action")
	controls.gain = 0.53
	controls.save_config()
	var restored := Controls.new()
	restored.config_path = controls.config_path
	restored.load_config()
	check(restored.bindings.spawn == controls.bindings.spawn and restored.throttle_code == 5 and restored.gain == controls.gain, "Bindings, axes and gain persist")
	restored.free()
	controls.steer_code = 63
	controls.poll(0.01)
	controls.forces_allowed = true
	controls.apply_force(0.5)
	check(not controls.input_valid and controls.steering == 0 and not wheel.started, "Missing ABS axis never becomes full steering or torque")
	controls.steer_code = 0
	controls.poll(0.01)
	check(controls.input_valid, "Valid axis selection restores input")
	controls.close_wheel()
	check(not wheel.open and controls.wheel == null and controls.throttle == 0, "Disconnect clears wheel and inputs")
	wheel = FakeWheel.new()
	wheel.reject_force = true
	controls.wheel = wheel
	controls.forces_allowed = true
	controls.apply_force(0.5)
	check(not controls.ffb_enabled and wheel.forces.is_empty(), "Failed effect creation disables FFB and reports failure")
	controls.close_wheel()
	controls.free()

func test_portal_images(cases: Array) -> void:
	for i in range(cases.size()):
		var c: Dictionary = cases[i]
		var maze := Maze.new()
		var normal: Vector3 = Maze.NORMALS[int(c.face)]
		var link := maze.create(0, int(c.face), c.kind, State.vec(c.up))
		var actor := Motion.create_ball(0.7)
		actor.up = State.vec(c.up)
		actor.p = normal * 2.8
		actor.spin = Quaternion(actor.up, 0.7)
		var snapshot: Dictionary = State.encode(actor)
		var images := Renderer.portal_images(maze, [actor])
		check(images.size() == 2, "Crossing sphere has two render records %d" % i)
		check(State.encode(actor) == snapshot and maze.rooms.size() == 2, "Portal image never mutates physical state %d" % i)
		var moved := maze.transport(0, int(c.face), actor.p, [actor.up])
		near_vec(images[1].p, moved.p, "Sphere portal image position %d" % i, 0.00001)
		near_vec(images[1].up, moved.vectors[0], "Sphere portal image gravity %d" % i, 0.00001)
		check(absf(images[1].spin.dot(link.q * actor.spin)) > 0.99999, "Sphere spin transforms at portal %d" % i)
		var back := Renderer.portal_images(maze, [images[1]])
		check(back.size() == 2 and back[1].room == 0, "Sphere visible from both sides %d" % i)
		near_vec(back[1].p, actor.p, "Sphere portal image inverse %d" % i, 0.00001)
		actor.p = normal * 2.0
		check(Renderer.portal_images(maze, [actor]).size() == 1, "Non-overlapping sphere has no portal image %d" % i)

func test_secondary_bindings() -> void:
	var controls := Controls.new()
	controls.config_path = "user://test-secondary-controls.cfg"
	var wheel := FakeWheel.new()
	controls.wheel = wheel
	var pressed: Array = []
	controls.action_pressed.connect(func(action): pressed.append(action))
	for pair in [["straight", 301], ["up", 302], ["down", 303]]:
		var original: Dictionary = controls.bindings[pair[0]].duplicate()
		controls.listen(pair[0], 1)
		wheel.buttons[pair[1]] = true
		controls.poll(0.01)
		check(controls.get_binding(pair[0], 1) == {"kind": "wheel_button", "code": pair[1]}, "Secondary wheel binding captured " + pair[0])
		check(controls.bindings[pair[0]] == original, "Primary mouse binding retained " + pair[0])
		wheel.buttons[pair[1]] = false
		controls.poll(0.01)
		pressed.clear()
		wheel.buttons[pair[1]] = true
		controls.poll(0.01)
		check(pressed == [pair[0]], "Assigned wheel button carves exactly one passage " + pair[0])
		wheel.buttons[pair[1]] = false
		controls.poll(0.01)
	controls.assign_binding("accelerate", {"kind": "wheel_button", "code": 305}, 1)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	controls.handle_event(key)
	wheel.buttons[305] = true
	controls.poll(0.01)
	key.pressed = false
	controls.handle_event(key)
	check(controls.value("accelerate") == 1, "Releasing primary preserves held secondary")
	wheel.buttons[305] = false
	controls.poll(0.01)
	check(controls.value("accelerate") == 0, "Action ends when both inputs released")
	controls.assign_binding("spawn", {"kind": "key", "code": KEY_B}, 1)
	key.physical_keycode = KEY_B
	key.pressed = true
	pressed.clear()
	controls.handle_event(key)
	check(pressed == ["spawn"], "Identical primary and secondary dispatch once")
	controls.impact_strength = 0.62
	controls.save_config()
	var restored := Controls.new()
	restored.config_path = controls.config_path
	restored.load_config()
	check(restored.get_binding("up", 1) == controls.get_binding("up", 1), "Secondary wheel binding persists")
	check(restored.bindings.up == controls.bindings.up, "Primary binding persists with secondary")
	check(restored.impact_strength == controls.impact_strength, "Impact strength persists")
	controls.assign_binding("up", {}, 1)
	check(controls.get_binding("up", 1).is_empty() and not controls.bindings.up.is_empty(), "Clearing secondary preserves primary")
	var legacy := ConfigFile.new()
	legacy.set_value("bindings", "up", {"kind": "key", "code": KEY_U})
	legacy.save("user://legacy-bindings.cfg")
	restored.config_path = "user://legacy-bindings.cfg"
	restored.secondary_bindings.clear()
	restored.load_config()
	check(restored.bindings.up.code == KEY_U and restored.get_binding("up", 1).is_empty(), "Old single-binding config remains compatible")
	restored.free()
	controls.close_wheel()
	controls.free()

func test_impact_vibration() -> void:
	var model := Gyro.new()
	model.impact(8, 1)
	var signs := []
	var peak := 0.0
	for i in range(30):
		var value := model.compute(0, 0, 0, 0, 1, 0, 1.0 / 120)
		peak = maxf(peak, absf(value))
		if absf(value) > 0.005:
			var sign_value := signf(value)
			if signs.is_empty() or signs[-1] != sign_value:
				signs.append(sign_value)
		check(absf(value) <= model.strength, "Impact vibration respects total gain cap %d" % i)
	check(peak > 0.12, "Impact tap remains distinct instead of being lost in steering smoothing")
	check(signs.size() >= 5, "Collision creates several alternating vibration cycles")
	check(model.output == 0 and model.pulse == 0, "Vibration stops within 220 milliseconds")
	model.impact(8, -1)
	check(model.compute(0, 0, 0, 0, 1, 0, 1.0 / 120) < 0, "First tap follows impact direction")
	model.reset()
	model.impact_strength = 0
	model.impact(8, 1)
	check(model.compute(0, 0, 0, 0, 1, 0, 0.01) == 0, "Impact setting can disable vibration")

func test_corner_rules_and_pruning() -> void:
	for up in Maze.NORMALS:
		for face in range(6):
			if up.dot(Maze.NORMALS[face]) != 0:
				continue
			var maze := Maze.new()
			maze.room(Vector3i(Maze.NORMALS[face]))
			check(maze.create(0, face, "up", up).is_empty(), "Solid backside rejects fold")
			check(maze.rooms.size() == 2 and maze.passage_count() == 0 and maze.next_link == 1, "Rejected fold leaves topology intact")
			maze = Maze.new()
			maze.create(0, face, "up", up)
			var approach: Dictionary = maze.create(0, Maze.face_of(-up), "straight", Maze.NORMALS[face])
			var around: Dictionary = maze.create(approach.target, face, "straight", up)
			check(maze.create(around.target, Maze.face_of(up), "straight", Maze.NORMALS[face]).is_empty(), "Adding a solid backside is rejected")
			check(maze.rooms.size() == 4 and maze.passage_count() == 3, "Rejected backside leaves no orphan")
	var maze := Maze.new()
	maze.create(0, 0, "up", Vector3.UP)
	var opposite := maze.room(Vector3i.RIGHT)
	maze.create(opposite.id, 1, "down", Vector3.UP)
	var counts := maze.walls.duplicate()
	check(not maze.remove(opposite.id, 1), "Cannot close one side of paired fold")
	check(maze.passage_count() == 2 and maze.walls == counts, "Rejected deletion is atomic")
	maze = Maze.new()
	for index in range(4):
		maze.create(index, 0, "straight", Vector3.UP)
	maze.remove(1, 0)
	var actor := {"room": 4}
	var ball := {"room": 2}
	var lost := {"room": 0}
	var result := maze.prune(actor.room, [actor, ball, lost])
	check(result.removed == 2 and result.actors.size() == 2, "Prunes detached group and its actors")
	check(actor.room == 2 and ball.room == 0, "Retained actors remapped")
	check(maze.rooms[0].cell == Vector3i.ZERO and maze.rooms[0].links[0].target == 1, "Origin and links remapped")
	check(maze.passage_count() == 2 and maze.walls.size() == 2, "Wall counts rebuilt")
	maze.remove(0, 0)
	check(maze.prune(actor.room, [actor]).removed == 1, "Prunes a single detached room")

func test_paired_folded_corner_rule() -> void:
	# All orientations and up/down combinations of the Quick Save's final
	# action: room 7's +Z fold next to room 9's +X fold around room 8.
	for a in range(6):
		for b in range((int(a / 2) + 1) * 2, 6):
			var axis := 3 - int(a / 2) - int(b / 2)
			var up: Vector3 = Maze.NORMALS[axis * 2]
			for first_kind in ["up", "down"]:
				for second_kind in ["up", "down"]:
					for reversed_order in [false, true]:
						var maze := Maze.new()
						var first := maze.create(0, a, "straight", up)
						var second := maze.create(0, b, "straight", up)
						var from: int = first.target if reversed_order else second.target
						var to: int = second.target if reversed_order else first.target
						var first_face: int = b if reversed_order else a
						var second_face: int = a if reversed_order else b
						check(not maze.create(from, first_face, first_kind, up).is_empty(), "A single folded mouth beside an ordinary corner remains valid")
						var before := State.export_json(maze, Motion.initial_player(), [], [])
						var walls := maze.walls.duplicate()
						var next_link := maze.next_link
						check(maze.create(to, second_face, second_kind, up).is_empty(), "Second folded mouth at an exposed diagonal is rejected")
						check(maze.last_error.contains("corner"), "Rejected folded corner explains the constraint")
						check(State.export_json(maze, Motion.initial_player(), [], []) == before, "Rejected last action preserves rooms and passages")
						check(maze.walls == walls and maze.next_link == next_link, "Rejected last action preserves wall ownership and link IDs")

func test_single_fold_square_rule() -> void:
	# Quick Save: 47 -> 37 -> 49 -> 48 are straight; 48 -> 47 is folded.
	for face in range(6):
		for direction in range(6):
			if int(face / 2) == int(direction / 2):
				continue
			for side in range(6):
				if int(side / 2) in [int(direction / 2), int(face / 2)]:
					continue
				for last_edge in range(4):
					var maze := Maze.new()
					var up: Vector3 = Maze.NORMALS[direction]
					var cells := [Vector3i.ZERO, Vector3i(Maze.NORMALS[side]), Vector3i(Maze.NORMALS[side] + up), Vector3i(up)]
					var edges := [[0, side, "straight"], [1, direction, "straight"], [2, side ^ 1, "straight"], [0, face, "up"]]
					for cell in cells:
						maze.room(cell)
					for index in range(4):
						if index == last_edge:
							continue
						var edge: Array = edges[index]
						var edge_up: Vector3 = up if index == 3 else Maze.NORMALS[((int(edge[1] / 2) + 1) % 3) * 2]
						check(not maze.create(edge[0], edge[1], edge[2], edge_up).is_empty(), "Each incomplete folded square can be constructed")
					var before := State.export_json(maze, Motion.initial_player(), [], [])
					var edge: Array = edges[last_edge]
					var edge_up: Vector3 = up if last_edge == 3 else Maze.NORMALS[((int(edge[1] / 2) + 1) % 3) * 2]
					check(maze.create(edge[0], edge[1], edge[2], edge_up).is_empty(), "A square with one folded and three straight passages cannot close")
					check(State.export_json(maze, Motion.initial_player(), [], []) == before, "Rejected folded square preserves its topology regardless of insertion order")

func test_two_fold_square_rule() -> void:
	# Quick Save square 37 -> 47 -> 50 -> 53: two straight edges and
	# two folds whose rotations disagree at the exposed shared edge.
	for a in range(6):
		for b in range(6):
			if int(a / 2) == int(b / 2):
				continue
			var third := 3 - int(a / 2) - int(b / 2)
			for sign_index in range(2):
				var fold_face := third * 2 + sign_index
				for last_edge in range(4):
					var maze := Maze.new()
					for cell in [Vector3i.ZERO, Vector3i(Maze.NORMALS[a]), Vector3i(Maze.NORMALS[a] + Maze.NORMALS[b]), Vector3i(Maze.NORMALS[b])]:
						maze.room(cell)
					var edges := [[0, a, "straight", Maze.NORMALS[b]], [1, fold_face, "up", Maze.NORMALS[b]], [2, fold_face ^ 1, "up", -Maze.NORMALS[a]], [3, b ^ 1, "straight", Maze.NORMALS[a]]]
					for index in range(4):
						if index == last_edge:
							continue
						var edge: Array = edges[index]
						check(not maze.create(edge[0], edge[1], edge[2], edge[3]).is_empty(), "Incomplete two-fold square remains constructible")
					var before := State.export_json(maze, Motion.initial_player(), [], [])
					var edge: Array = edges[last_edge]
					check(maze.create(edge[0], edge[1], edge[2], edge[3]).is_empty(), "Two-fold square cannot close with inconsistent transported frames")
					check(State.export_json(maze, Motion.initial_player(), [], []) == before, "Rejecting the two-fold square is atomic in every orientation and insertion order")

func test_tubes(cases: Array) -> void:
	for c in cases:
		var maze := Maze.new()
		# Reference fixtures cover all orientations of both portal mouths.
		var face: int = int(c.get("face", 0))
		var link := maze.create(0, face, c.kind, State.vec(c.up))
		check(not link.is_empty(), "Tube mouth can be created")
		maze.tubes = true
		var mouth: Vector3 = Maze.NORMALS[face] * 3.0
		check(absf(maze.tube_sample(0, mouth).clearance - Maze.TUBE_RADIUS) < 0.00001, "Tube mouth centered")
		for offset in [Vector3.ZERO, Maze.NORMALS[(int(face / 2) + 1) % 3 * 2] * 1.9]:
			var entry: Vector3 = mouth + offset
			var moved := maze.transport(0, face, entry)
			check(absf(maze.tube_sample(0, entry).clearance - maze.tube_sample(moved.room, moved.p).clearance) < 0.00001, "Round mouths match across straight/up/down portal")
		var actor := Motion.initial_player()
		actor.p = Vector3(2.49, -2.49, 2.49)
		actor.velocity = actor.p.normalized() * 10.0
		maze.set_tubes(true, [actor])
		check(maze.tube_sphere_sample(0, actor.p, actor.radius).clearance >= actor.radius, "Switch keeps sphere inside tube")
		for i in range(100):
			Motion.move_ball(maze, actor, 0.02)
			check(maze.tube_sphere_sample(actor.room, actor.p, actor.radius).clearance >= actor.radius - 0.003, "Tube bounds during motion")
		var saved := State.export_json(maze, actor, [], [])
		var restored := State.new().import_json(saved)
		check(not restored.is_empty() and restored.maze.tubes, "Tube geometry survives JSON round trip")

func test_tube_fillets() -> void:
	# A right-angle junction used to switch normals abruptly at x == z.
	var maze := Maze.new()
	maze.create(0, 0, "straight", Vector3.UP)
	maze.create(0, 4, "straight", Vector3.UP)
	maze.tubes = true
	var corner := Vector3(2.0, 0, 2.0)
	var before := maze.tube_sample(0, corner + Vector3(0.001, 0, -0.001))
	var after := maze.tube_sample(0, corner + Vector3(-0.001, 0, 0.001))
	check(before.normal.dot(after.normal) > 0.99, "Fillet normals stay continuous across old sharp junction")
	check(maze.tube_clearance(0, corner) > 0.02, "Fillet opens the former sharp corner")
	for axis in [0, 2]:
		var mouth := Vector3.ZERO
		mouth[axis] = 3.0
		var edge := mouth + Vector3.UP * Maze.TUBE_RADIUS
		check(absf(maze.tube_clearance(0, edge)) < 0.012, "Fillets preserve circular portal edge")
	var actor := Motion.initial_player()
	actor.p = Vector3(2.49, 2.49, 2.49)
	actor.velocity = Vector3.ONE * 25
	maze.set_tubes(true, [actor])
	check(maze.tube_sphere_sample(0, actor.p, actor.radius).clearance >= actor.radius, "Iterative projection keeps actor within rounded junction")

func test_tube_control() -> void:
	var maze := Maze.new()
	maze.tubes = true
	var player := Motion.initial_player()
	maze.constrain_actor(player)
	var quiet := player.duplicate(true)
	for i in range(120):
		player.velocity = Vector3(0.15 * sin(i), 0.03, 0.15 * cos(i))
		Motion.update_tube_camera(maze, player, 1.0 / 120)
		Motion.update_tube_camera(maze, quiet, 1.0 / 120)
	check(player.cameraForward.dot(quiet.cameraForward) > 0.999, "Low-speed tube rebounds do not change heading")
	player.velocity = Vector3.ZERO
	var start: Vector3 = player.p
	for i in range(120):
		Motion.drive(maze, player, 1.0 / 120, 1, 0)
		Motion.update_tube_camera(maze, player, 1.0 / 120)
	check(player.p.distance_to(start) > 0.5, "Tube throttle escapes rest and makes progress")
	check(absf(player.cameraForward.dot(player.cameraUp)) < 0.00001, "Tube surface camera stays orthogonal")
	var slow := Motion.initial_player()
	var fast := slow.duplicate(true)
	slow.velocity = Vector3.FORWARD * 0.11
	fast.velocity = Vector3.FORWARD * 0.13
	Motion.steer_tube(slow, 0.5, 0.02)
	Motion.steer_tube(fast, 0.5, 0.02)
	check(slow.cameraForward.distance_to(fast.cameraForward) < 0.00001, "Tube steering has no low-speed threshold discontinuity")

func test_tube_sphere_support_and_motor() -> void:
	for kind in ["straight", "up", "down"]:
		var maze := Maze.new()
		maze.create(0, 0, kind, Vector3.UP)
		maze.create(0, 4, "straight", Vector3.UP)
		maze.tubes = true
		for position in [Vector3(2.4, -2.0, 2.4), Vector3(0.6, -2.3, 0.4), Vector3(2.6, -1.5, 0.1)]:
			var actor := Motion.create_ball(0)
			actor.p = position
			maze.constrain_actor(actor)
			var minimum := INF
			for i in range(256):
				var y := 1.0 - 2.0 * (i + 0.5) / 256.0
				var angle := i * 2.3999632297
				var radial := sqrt(1.0 - y * y)
				var direction := Vector3(cos(angle) * radial, y, sin(angle) * radial)
				minimum = minf(minimum, maze.tube_clearance(actor.room, actor.p + direction * actor.radius))
			check(minimum > -0.003, "Full sphere clears rendered fillet surface " + kind)
		var ball := Motion.create_ball(0)
		maze.constrain_actor(ball)
		var escaped := false
		for step in range(1200):
			Motion.move_ball(maze, ball, 1.0 / 120)
			if ball.room != 0:
				escaped = true
				break
		check(escaped, "Powered tube sphere escapes bowl through " + kind + " exit")
		var airborne := Motion.create_ball(0)
		airborne.radius = Maze.Pipes.BALL_RADIUS
		airborne.p = Maze.Pipes.spine(maze.tube_shape_mask(0), Vector3.ZERO)
		var velocity: Vector3 = airborne.velocity
		Motion.drive_tube_motor(maze, airborne, 0.05)
		near_vec(airborne.velocity, [velocity.x, velocity.y, velocity.z], "Tube motor needs surface traction", 0.00001)

func test_straight_tube_radius() -> void:
	for axis in range(3):
		var maze := Maze.new()
		var up: Vector3 = Maze.NORMALS[((axis + 1) % 3) * 2]
		maze.create(0, axis * 2, "straight", up)
		maze.create(0, axis * 2 + 1, "straight", up)
		maze.tubes = true
		for step in range(25):
			for sector in range(16):
				var angle := TAU * sector / 16.0
				var p := Vector3.ZERO
				p[axis] = -3.0 + step * 0.25
				p[(axis + 1) % 3] = cos(angle) * Maze.TUBE_RADIUS
				p[(axis + 2) % 3] = sin(angle) * Maze.TUBE_RADIUS
				check(absf(maze.tube_clearance(0, p)) < 0.012, "Straight tube radius stays constant across room and mouths")
				var sample := maze.tube_sample(0, p)
				check(absf(sample.normal[axis]) < 0.0001, "Straight tube normal has no axial component")

func test_tube_rollback_skid() -> void:
	var normal := Vector3(0.6, -0.8, 0)
	var uphill := Vector3(0.8, 0.6, 0)
	var ball := Motion.create_ball(0)
	ball.velocity = uphill * 2.0
	Motion.tube_rollback_direction(ball, uphill, normal, 0.01)
	check(ball.get("tubeSkidCount", 0) == 0, "NPC climb alone produces no skid")
	ball.velocity = -uphill * 2.0
	var speed: float = ball.velocity.length()
	var into_wall: float = ball.velocity.dot(normal)
	var heading := Motion.tube_rollback_direction(ball, uphill, normal, 0.01)
	check(absf(ball.velocity.z) > 0.1 and absf(heading.z) > 0.05, "NPC rollback changes the swing plane and briefly biases traction")
	check(absf(ball.velocity.length() - speed) < 0.00001, "Rollback skid adds no kinetic energy")
	check(absf(ball.velocity.dot(normal) - into_wall) < 0.00001, "Rollback skid adds no velocity into wall")
	for step in range(20):
		Motion.tube_rollback_direction(ball, uphill, normal, 0.01)
	check(ball.tubeSkidCount == 1, "One rollback cannot trigger a skid each physics step")
	for step in range(500):
		heading = Motion.tube_rollback_direction(ball, uphill, normal, 0.01)
	check(heading.dot(uphill) > 0.99999, "Skid steering bias decays after rollback")
	var player := Motion.initial_player()
	player.velocity = uphill * 2
	Motion.tube_rollback_direction(player, uphill, normal, 0.01)
	player.velocity = -uphill * 2
	var before: Vector3 = player.velocity
	heading = Motion.tube_rollback_direction(player, uphill, normal, 0.01)
	check(player.velocity == before and heading == uphill and not player.has("tubeSkidRoom"), "Player receives no automatic rollback skid")
	var downhill := Motion.create_ball(0)
	downhill.velocity = -uphill * 2
	Motion.tube_rollback_direction(downhill, uphill, normal, 0.01)
	check(downhill.get("tubeSkidCount", 0) == 0, "Descent without a previous climb does not trigger skid")

func test_round_tube_junctions() -> void:
	var maze := Maze.new()
	for face in [0, 1, 4, 5]:
		maze.create(0, face, "straight", Vector3.UP)
	maze.tubes = true
	for x in range(-4, 5):
		for z in range(-4, 5):
			var point := Vector3(x * 0.3, 0, z * 0.3)
			check(maze.tube_clearance(0, point) > 0.0, "Four-way fitting has one connected central volume")
			check(maze.tube_sample(0, point + Vector3.DOWN * Maze.TUBE_RADIUS).normal.is_finite(), "Four-way fitting surface normals remain finite")
	var elbow := Maze.new()
	elbow.create(0, 1, "straight", Vector3.UP)
	elbow.create(0, 5, "straight", Vector3.UP)
	elbow.tubes = true
	check(elbow.tube_clearance(0, Vector3(-3, 0, -3)) < 0.0, "Inner elbow corner cannot form a false opening")
	for step in range(1, 16):
		var angle := PI * 0.5 * step / 16.0
		var centerline := Vector3(-3, 0, -3) + Vector3(cos(angle), 0, sin(angle)) * 3.0
		var radial := Vector3(cos(angle), 0, sin(angle))
		for sector in range(16):
			var phase := TAU * sector / 16.0
			var point := centerline + (radial * cos(phase) + Vector3.UP * sin(phase)) * Maze.TUBE_RADIUS
			check(absf(elbow.tube_clearance(0, point)) < 0.012, "Bent pipe has a circular section of constant radius along the arc")
		check(absf(elbow.tube_clearance(0, centerline + Vector3.DOWN * Maze.TUBE_RADIUS)) < 0.012, "Horizontal elbow floor keeps constant height along its bend")
	var ball := Motion.create_ball(0)
	ball.up = Vector3.FORWARD
	ball.motorAxis = Vector3.LEFT
	ball.omega = Vector3(-12.6767, -0.004, -0.00026)
	ball.p = Vector3(0.000789, -1.146737, 1.449232)
	ball.velocity = Vector3(0.000121, 0.424947, 9.27245)
	elbow.constrain_actor(ball)
	var escaped := false
	for step in range(3600):
		Motion.move_ball(elbow, ball, 1.0 / 120)
		if ball.room != 0:
			escaped = true
			break
	check(escaped, "NPC from saved Room 02 leaves the elbow instead of repeating its swing")

func test_hall_corner_clearance() -> void:
	# Exact mouth arrangements from Quick Save rooms 13 and 14.
	for faces in [[0, 2, 3], [0, 2, 4]]:
		var maze := Maze.new()
		for face in faces:
			var up: Vector3 = Maze.NORMALS[((int(face / 2) + 1) % 3) * 2]
			maze.create(0, face, "straight", up)
		maze.tubes = true
		for first in range(faces.size()):
			for second in range(first + 1, faces.size()):
				var a: Vector3 = Maze.NORMALS[faces[first]]
				var b: Vector3 = Maze.NORMALS[faces[second]]
				if absf(a.dot(b)) > 0.5:
					continue
				for step in range(1, 16):
					var angle := PI * 0.5 * step / 16.0
					var centerline := (a + b) * 3.0 - (a * cos(angle) + b * sin(angle)) * 3.0
					check(maze.tube_sphere_sample(0, centerline, Maze.Pipes.BALL_RADIUS).clearance > Maze.Pipes.BALL_RADIUS, "Saved hall gives every pair of mouths an unobstructed rounded turn")
				var removed_rib := (a + b) * (3.0 - 3.0 / sqrt(2.0))
				check(maze.tube_clearance(0, removed_rib) > 0.0, "Saved hall corner rib is removed from physical geometry")

func test_open_cycle_corners() -> void:
	var maze := Maze.new()
	var east := maze.create(0, 0, "straight", Vector3.UP)
	var north := maze.create(0, 2, "straight", Vector3.BACK)
	maze.create(east.target, 2, "straight", Vector3.BACK)
	var before := maze.tube_shape_mask(0)
	maze.create(north.target, 0, "straight", Vector3.UP)
	maze.tubes = true
	check(maze.tube_shape_mask(0) == before, "Adding a remote cycle cannot deform a local fitting")
	for room in maze.rooms:
		check(maze.tube_clearance(room.id, Vector3.ZERO) > 0, "Each cycle fitting has an open center")
	var old := maze.tube_shape_mask(north.target)
	maze.remove(north.target, 0)
	check(maze.tube_shape_mask(north.target) != old, "Removing an opening invalidates the local shape cache")

func test_open_hall_columns() -> void:
	for a in range(6):
		for b in range((int(a / 2) + 1) * 2, 6):
			var maze := Maze.new()
			var axis := 3 - int(a / 2) - int(b / 2)
			var up: Vector3 = Maze.NORMALS[axis * 2]
			var first := maze.create(0, a, "straight", up)
			var second := maze.create(0, b, "straight", up)
			maze.create(first.target, b, "straight", up)
			var corner: Vector3 = (Maze.NORMALS[a] + Maze.NORMALS[b]) * 3.0
			check(maze.tube_clearance(0, corner) < 0, "Incomplete square retains its column")
			maze.create(second.target, a, "straight", up)
			check(maze.tube_corner_mask(0) != 0, "Complete square opens its shared corner in every orientation")
			check(maze.tube_sphere_sample(0, corner, Maze.Pipes.BALL_RADIUS).clearance > Maze.Pipes.BALL_RADIUS, "Sphere crosses the former column")
			for step in range(21):
				var point: Vector3 = Maze.NORMALS[a] * 3.0 + Maze.NORMALS[b] * (step * 0.15) + up * 1.2
				var other := maze.transport(0, a, point)
				check(absf(maze.tube_clearance(0, point) - maze.tube_clearance(other.room, other.p)) < 0.0001, "Expanded hall surfaces match across each shared mouth")
			# Former slab edges at either local axis cut through the floor.
			# Check actual sphere support, not just empty space at mid-height.
			for height_sign in [-1.0, 1.0]:
				for step in range(11):
					var tangent: Vector3 = Maze.NORMALS[a] * (step * 0.15) + Maze.NORMALS[b] * 0.9
					for point in [tangent, Maze.NORMALS[b] * (step * 0.15) + Maze.NORMALS[a] * 0.9]:
						var center: Vector3 = point + up * height_sign * (Maze.TUBE_RADIUS - Maze.Pipes.BALL_RADIUS - 0.02)
						var support := maze.tube_sphere_sample(0, center, Maze.Pipes.BALL_RADIUS)
						check(support.clearance > Maze.Pipes.BALL_RADIUS, "Hall floor and ceiling have no residual elbow fin at quadrant edges")
						check(support.normal.dot(up * height_sign) > 0.99, "Hall support normal follows the floor instead of an inward elbow wall")
			var outer: Vector3 = -Maze.NORMALS[a] * 0.75 - Maze.NORMALS[b] * 0.75
			check(maze.tube_clearance(0, outer) > 0.5, "Outer hall corner rounds toward the walls instead of folding inward")
			check(maze.tube_clearance(0, outer * 2.0) < 0, "Rounded outer corner retains a solid boundary")
			maze.remove(second.target, a)
			check(maze.tube_corner_mask(0) == 0 and maze.tube_clearance(0, corner) < 0, "Removing a square edge restores its solid corner")
			check(maze.tube_sphere_sample(0, corner, Maze.Pipes.BALL_RADIUS).clearance < 0, "Sphere cache invalidates when only the hall corner changes")
	var hall := Maze.new()
	for y in range(3):
		for x in range(3):
			hall.room(Vector3i(x, y, 0))
	for y in range(3):
		for x in range(3):
			var id: int = hall.cells[Vector3i(x, y, 0)]
			if x < 2:
				hall.create(id, 0, "straight", Vector3.BACK)
			if y < 2:
				hall.create(id, 2, "straight", Vector3.BACK)
	var center: int = hall.cells[Vector3i(1, 1, 0)]
	for x in range(-10, 11):
		for y in range(-10, 11):
			check(hall.tube_clearance(center, Vector3(x * 0.3, y * 0.3, 0)) > Maze.Pipes.BALL_RADIUS, "3x3 hall has no internal columns")
	check(hall.tube_clearance(center, Vector3(2.8, 2.8, 1.8)) < 0, "Merged hall retains its ceiling and floor")

func test_shared_hall_support_planes() -> void:
	var maze := Maze.new()
	var east := maze.create(0, 0, "straight", Vector3.UP)
	maze.create(0, 2, "straight", Vector3.BACK)
	maze.create(east.target, 4, "straight", Vector3.UP)
	maze.tubes = true
	for y in range(-12, 13):
		for z in range(-12, 13):
			var point := Vector3(3, y * 0.15, z * 0.15)
			var other := maze.transport(0, 0, point)
			check(absf(maze.tube_clearance(0, point) - maze.tube_clearance(other.room, other.p)) < 0.0001, "Different branches cannot introduce a step across a shared collar")

func test_shared_hall_has_no_inner_rim() -> void:
	for mask in [7, 15, 21, 23, 31, 63]:
		var maze := Maze.new()
		for face in range(6):
			if mask & (1 << face):
				maze.create(0, face, "straight", Maze.NORMALS[((int(face / 2) + 1) % 3) * 2])
		for face in range(6):
			if not mask & (1 << face):
				continue
			var normal: Vector3 = Maze.NORMALS[face]
			for step in range(10):
				var point := normal * (2.1 + step * 0.1)
				check(maze.tube_clearance(0, point) >= Maze.TUBE_RADIUS - 0.012, "Round straight collars contain no inner ring or raised threshold")

func test_pipe_hall_flare() -> void:
	var maze := Maze.new()
	var pipe := maze.create(0, 4, "straight", Vector3.UP)
	maze.create(0, 5, "straight", Vector3.UP)
	maze.create(0, 0, "straight", Vector3.UP)
	maze.tubes = true
	for x in range(-10, 11):
		for y in range(-10, 11):
			var mouth := Vector3(x * 0.18, y * 0.18, 3)
			var other := maze.transport(0, 4, mouth)
			check(absf(maze.tube_clearance(0, mouth) - maze.tube_clearance(pipe.target, other.p)) < 0.0001, "Pipe and tee have the same aperture, independent of adjoining hall branches")


func test_pipe_catalog_classes() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/pipes/catalog.json"))
	check(manifest.classes.size() == 10 and manifest.masks.size() == 64, "All 64 masks reduce to ten symmetry classes including isolated room")
	for mask in range(64):
		var maze := Maze.new()
		for face in range(6):
			if mask & (1 << face):
				maze.create(0, face, "straight", Maze.NORMALS[((int(face / 2) + 1) % 3) * 2])
		maze.tubes = true
		check(maze.tube_shape_mask(0) == mask, "Local opening mask selects the fitting")
		for direction in [Vector3(1,1,1).normalized(), Vector3(1,-1,1).normalized(), Vector3(-1,1,-1).normalized()]:
			var actor := Motion.initial_player()
			actor.p = direction * 2.6
			actor.velocity = direction * 4
			maze.constrain_actor(actor)
			check(actor.p.is_finite() and absf(actor.radius - 0.33) < 0.00001, "All fitting types accept smaller spheres")
			check(maze.tube_sphere_sample(0, actor.p, actor.radius).clearance >= actor.radius - 0.01, "Sphere support stays inside baked fitting")

func test_pipe_scale_migration() -> void:
	var maze := Maze.new()
	maze.create(0, 4, "straight", Vector3.UP)
	maze.create(0, 5, "straight", Vector3.UP)
	var ball := Motion.initial_player()
	ball.p = Vector3(0, -2, 2.8)
	ball.velocity = Vector3(0, 0, 6)
	maze.set_tubes(true, [ball])
	check(absf(ball.radius - 0.33) < 0.00001, "Tube sphere radius scales to 0.33")
	check(absf(ball.p.z - 2.8) < 0.00001 and absf(ball.p.y + 1.32) < 0.015, "Scaling preserves axial progress and scales transverse position")
	check(absf(ball.velocity.z - 3.96) < 0.00001, "Linear velocity scales proportionally")
	var saved := State.export_json(maze, ball, [], [])
	var importer := State.new()
	var imported := importer.import_json(saved)
	check(not imported.is_empty(), "Small sphere JSON round trip: " + importer.error)
	if not imported.is_empty():
		near_vec(imported.player.p, [ball.p.x, ball.p.y, ball.p.z], "New saves are not rescaled twice", 0.001)
	maze.set_tubes(false, [ball])
	check(absf(ball.radius - 0.5) < 0.00001 and absf(ball.p.z - 2.8) < 0.00001, "Room mode restores radius without moving along the passage")
	var legacy := Motion.initial_player()
	legacy.p = Vector3(0, -2, 2.8)
	maze.tubes = true
	var migrated := State.new().import_json(State.export_json(maze, legacy, [], []))
	check(not migrated.is_empty(), "Legacy tube quick saves remain readable")
	if not migrated.is_empty():
		check(absf(migrated.player.radius - 0.33) < 0.00001 and absf(migrated.player.p.z - 2.8) < 0.00001, "Legacy saves migrate around the pipe spine")

func test_third_person_camera() -> void:
	var renderer := Renderer.new()
	var maze := Maze.new()
	var player := Motion.initial_player()
	player.p = Vector3.ZERO
	player.cameraForward = Vector3.FORWARD
	renderer.camera_distance = 3.9
	var frame := renderer.view(maze, player)
	check(not frame.outside and frame.room == 0, "Close camera stays in actor space")
	check(frame.p.distance_to(Vector3(0, 0, 2.99)) < 0.00001, "Third person camera stops at solid wall")
	for kind in ["straight", "up", "down"]:
		maze = Maze.new()
		maze.create(0, 4, kind, Vector3.UP)
		frame = renderer.view(maze, player)
		var expected := maze.transport(0, 4, Vector3(0, 0, 3.9), [Vector3.FORWARD, Vector3.UP])
		check(not frame.outside and frame.room == expected.room, "Third person camera crosses %s portal" % kind)
		check(frame.p.distance_to(expected.p) < 0.00001, "Third person camera position through %s portal" % kind)
		check(frame.forward.distance_to(expected.vectors[0]) < 0.00001, "Third person camera orientation through %s portal" % kind)
	renderer.camera_distance = 4.0
	check(renderer.view(maze, player).outside, "Map starts at two thirds of room size even inside lattice")
	renderer.camera_distance = 0.0
	frame = renderer.view(maze, player)
	check(not frame.outside and frame.p == player.p and frame.room == player.room, "First person camera keeps actor frame")
	renderer.free()

func test_tube_third_person_camera() -> void:
	var renderer := Renderer.new()
	renderer.camera_distance = 3.9
	for kind in ["straight", "up", "down"]:
		var maze := Maze.new()
		maze.create(0, 5, kind, Vector3.UP)
		maze.create(0, 4, "straight", Vector3.UP)
		maze.tubes = true
		for z in [-3.05, -2.5, 0.0, 2.95]:
			for tick in range(72):
				var angle := TAU * tick / 72.0
				var player := Motion.initial_player()
				player.p = Vector3(cos(angle) * 1.0, sin(angle) * 1.0, z)
				player.cameraForward = Vector3(-sin(angle) * 0.7, cos(angle) * 0.7, -1).normalized()
				player.cameraUp = Vector3(cos(angle), sin(angle), 0)
				# Check both owning frames at the folded seam.
				if z < -2.9:
					var moved := maze.transport(0, 5, player.p, [player.cameraForward, player.cameraUp])
					player.room = moved.room
					player.p = moved.p
					player.cameraForward = moved.vectors[0]
					player.cameraUp = moved.vectors[1]
				var frame := renderer.view(maze, player)
				check(not frame.outside, "Spiralling tube camera stays in third person")
				check(maze.tube_clearance(frame.room, frame.p) >= Renderer.CAMERA_MARGIN - 0.0002, "Spiralling camera stays inside tube through %s portal" % kind)
	renderer.free()

func test_tube_sample_cache() -> void:
	var maze := Maze.new()
	maze.create(0, 5, "straight", Vector3.UP)
	var p := Vector3(0.3, -1.1, 0.5)
	var first := maze.tube_sphere_sample(0, p, 0.33)
	check(first.is_read_only(), "Cached sphere query cannot be changed by callers")
	check(maze.tube_sphere_sample(0, p, 0.33) == first, "Exact repeated sphere query reuses result")
	for query in [[p + Vector3.RIGHT * 0.1, 0.33], [p, 0.4]]:
		var cached := maze.tube_sphere_sample(0, query[0], query[1])
		maze.sphere_sample_mask = -1
		check(cached == maze.tube_sphere_sample(0, query[0], query[1]), "Position and radius changes invalidate sphere query")
	maze.create(0, 0, "straight", Vector3.UP)
	var changed := maze.tube_sphere_sample(0, p, 0.33)
	maze.sphere_sample_mask = -1
	check(changed == maze.tube_sphere_sample(0, p, 0.33), "Topology changes invalidate sphere query")

func test_asphalt() -> void:
	var ball := Motion.initial_player()
	Motion.asphalt_contact(ball, Vector3.UP, 1.0 / 120.0)
	check(ball.surfaceResponse == 0.0 and ball.velocity == Vector3.ZERO, "Stationary asphalt contact produces no vibration")
	ball.velocity = Vector3(0, 0, -3)
	Motion.asphalt_contact(ball, Vector3.UP, 1.0 / 120.0)
	check(absf(ball.surfaceResponse) > 0.01, "Rolling asphalt contact produces aggregate response")
	check(absf(ball.velocity.y) > 0.0 and ball.velocity.is_finite(), "Asphalt response reaches sphere dynamics")
	var gyro := Gyro.new()
	gyro.surface_response = ball.surfaceResponse
	gyro.compute(0, 0, 0, 0, 1, 0, 1.0 / 120.0)
	check(absf(gyro.components.surface) > 0.0, "Asphalt response reaches loaded wheel")
	check(absf(gyro.output) <= gyro.strength, "Surface torque respects wheel gain cap")
	gyro.compute(0, 0, 0, 0, 0, 0, 1.0 / 120.0)
	check(gyro.components.surface == 0.0, "Airborne wheel has no asphalt vibration")
	gyro.reset()
	check(gyro.surface_response == 0.0, "Wheel reset clears surface response")

func test_windows_output() -> void:
	var api = preload("res://scripts/windows_wheel.gd")
	var names := PackedStringArray(["Other wheel", "Gudsen R3 Racing Wheel and Pedals"])
	check(api.matching_haptic_index("SDL Gudsen R3 Racing Wheel and Pedals", names) == 1, "Proton SDL name prefix matches the actual haptic wheel")
	check(api.matching_haptic_index("Gudsen R3 Racing Wheel and Pedals", names) == 1, "Native Windows wheel identity matches directly")
	check(api.matching_haptic_index("Other", names) == -1, "Partial device names do not select a different wheel")
	check(api.matching_haptic_index("Other wheel", PackedStringArray(["Other wheel", "Other wheel"])) == -1, "Ambiguous haptic identities are rejected")
	var wheel := FakeWindowsWheel.new()
	var motor := FakeHaptics.new()
	wheel.haptics = motor
	wheel.update_constant_force(0.3)
	check(motor.forces.is_empty(), "Windows FFB remains off until started")
	check(wheel.start_constant_force(), "Windows adapter accepts constant-force capability")
	wheel.update_constant_force(0.3)
	check(motor.forces == [0.3], "Windows adapter forwards torque")
	wheel.set_inverted(true)
	wheel.update_constant_force(0.2)
	check(motor.forces[-1] == -0.2, "Windows adapter applies configured direction")
	wheel.stop_constant_force()
	wheel.update_constant_force(0.6)
	check(motor.stops == 1 and motor.forces.size() == 2, "Windows pause stops output and blocks further torque")
	wheel.start_constant_force()
	wheel.connected = false
	wheel.poll()
	check(motor.closed and wheel.haptics == null and not wheel.running, "Windows USB loss closes effects and clears output")
	wheel.close()
	check(motor.stops == 2, "Windows close after disconnect is idempotent")

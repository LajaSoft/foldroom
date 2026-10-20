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
	test_portals(reference.transport)
	test_portal_images(reference.transport)
	test_trajectories(reference.trajectories)
	test_powered_balls(reference.balls)
	test_contacts(reference.contact)
	test_state(reference.state)
	test_topology()
	test_corner_rules_and_pruning()
	test_stability()
	test_gyro()
	test_controls()
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

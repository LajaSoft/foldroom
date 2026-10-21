extends Node

const Maze = preload("res://scripts/maze.gd")
const Motion = preload("res://scripts/motion.gd")
const State = preload("res://scripts/state.gd")
const Renderer = preload("res://scripts/renderer.gd")
const Controls = preload("res://scripts/controls.gd")
const Gyro = preload("res://scripts/gyro.gd")
const Sound = preload("res://scripts/sound.gd")
const FACE_NAMES := ["+X / CORAL", "−X / MINT", "+Y / IVORY", "−Y / BLUE", "+Z / LILAC", "−Z / OCHRE"]
var maze := Maze.new()
var player := Motion.initial_player()
var balls: Array = []
var renderer: FoldRenderer
var controls: FoldControls
var gyro := Gyro.new()
var sound: FoldSound
var active := false
var dirty := true
var drawing := false
var marker_cursor := Vector2.ZERO
var root: Control
var hud: Label
var target: Label
var crosshair: Label
var gravity_pointer: Line2D
var notice: Label
var menu: PanelContainer
var menu_content: VBoxContainer
var setup_panel: PanelContainer
var setup_content: VBoxContainer
var wheel_live: Label
var binding_buttons := {}
var setup_status: Label
var json_dialog: ConfirmationDialog
var json_text: TextEdit
var json_error: Label
var importing := true
var file_dialog: FileDialog
var current_json := ""
var toast_time := 0.0
var started := false
var last_lateral := 0.0
var smoke_frames := -1
var smoke_failed := false

func _ready() -> void:
	controls = Controls.new()
	if "--smoke-test" in OS.get_cmdline_user_args():
		controls.config_path = "user://smoke-controls.cfg"
	add_child(controls)
	controls.action_pressed.connect(on_action)
	controls.status_changed.connect(show_message)
	controls.binding_changed.connect(refresh_bindings)
	renderer = Renderer.new()
	var background := CanvasLayer.new()
	add_child(background)
	background.add_child(renderer)
	sound = Sound.new()
	add_child(sound)
	var ui := CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(root)
	apply_theme()
	build_hud()
	build_menu()
	load_audio_settings()
	build_setup()
	build_json_dialog()
	controls.connect_wheel()
	set_active(false)
	if "--smoke-test" in OS.get_cmdline_user_args():
		smoke_frames = 0
		load_example()
		set_active(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		call_deferred("run_smoke_checks")

func apply_theme() -> void:
	var theme := Theme.new()
	theme.default_font_size = 17
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("101c24f5")
	panel.border_color = Color("667b73")
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(12)
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	theme.set_stylebox("panel", "PanelContainer", panel)
	var button := StyleBoxFlat.new()
	button.bg_color = Color("243b40")
	button.set_corner_radius_all(5)
	button.content_margin_left = 14
	button.content_margin_right = 14
	button.content_margin_top = 9
	button.content_margin_bottom = 9
	theme.set_stylebox("normal", "Button", button)
	var hover := button.duplicate()
	hover.bg_color = Color("45625d")
	theme.set_stylebox("hover", "Button", hover)
	theme.set_color("font_color", "Label", Color("f3f2df"))
	root.theme = theme

func label(text: String, parent: Node, font_size: int = 17) -> Label:
	var value := Label.new()
	value.text = text
	value.add_theme_font_size_override("font_size", font_size)
	parent.add_child(value)
	return value

func button(text: String, parent: Node, callback: Callable) -> Button:
	var value := Button.new()
	value.text = text
	value.pressed.connect(callback)
	parent.add_child(value)
	return value

func build_hud() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 26
	top.offset_top = 20
	top.offset_right = -26
	root.add_child(top)
	var brand := label("FOLDROOM  /  GYRO LAB", top, 24)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button("+ Ball", top, spawn_ball)
	button("Controls", top, open_setup)
	button("Pause", top, func(): set_active(false))
	hud = label("", root)
	hud.position = Vector2(28, 100)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target = label("", root, 14)
	target.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	target.offset_left = -160
	target.offset_right = 160
	target.offset_top = 34
	target.offset_bottom = 80
	target.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	target.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair = label("+", root, 24)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -9
	crosshair.offset_top = -17
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gravity_pointer = Line2D.new()
	gravity_pointer.width = 2.0
	gravity_pointer.default_color = Color("ffdf38")
	gravity_pointer.antialiased = true
	gravity_pointer.visible = false
	root.add_child(gravity_pointer)
	notice = label("", root, 16)
	notice.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	notice.offset_top = -100
	notice.offset_bottom = -60
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var footer := label("WASD — drive / brake / steer     Mouse — look     LMB — straight     RMB — up     Shift+RMB — down     Esc — pause", root, 13)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -38
	footer.offset_bottom = -12
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE

func centered_panel(width: float, height: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -width / 2
	panel.offset_right = width / 2
	panel.offset_top = -height / 2
	panel.offset_bottom = height / 2
	root.add_child(panel)
	return panel

func build_menu() -> void:
	menu = centered_panel(620, 570)
	var scroll := ScrollContainer.new()
	menu.add_child(scroll)
	menu_content = VBoxContainer.new()
	menu_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_content.add_theme_constant_override("separation", 10)
	scroll.add_child(menu_content)
	label("EVERYONE HAS THEIR OWN DOWN.", menu_content, 28)
	label("Carve rooms. Turn gravity. Drive the sphere.", menu_content)
	button("Enter / Resume", menu_content, func(): set_active(true))
	var row := HBoxContainer.new()
	menu_content.add_child(row)
	button("Ball ↔ Walk", row, switch_mode)
	button("Rooms ↔ Tubes", row, switch_geometry)
	button("+ Ball", row, spawn_ball)
	button("Jump to start", row, jump_start)
	row = HBoxContainer.new()
	menu_content.add_child(row)
	button("Example", row, load_example)
	button("Reset maze", row, reset_maze)
	button("Controls / Wheel / Audio", menu_content, open_setup)
	row = HBoxContainer.new()
	menu_content.add_child(row)
	button("Export JSON", row, func(): open_json(false))
	button("Import JSON", row, func(): open_json(true))
	button("Quick save", row, quick_save)
	button("Quick load", row, quick_load)
	label("The sphere starts in Ball mode. W accelerates, S brakes.\nA / D steer relative to the camera. Shift boosts ×5.\nB adds a powered ball; Shift+B removes the oldest.\nShift+LMB draws on walls; Delete closes a passage.\nScroll pulls the camera outside the cubic lattice.\nM switches mode. Wheel bindings are configured in Setup.", menu_content, 15)
	button("Quit", menu_content, quit_game)

func setting_row(parent: Node, text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var title := label(text, row)
	title.custom_minimum_size.x = 190
	return row

func toggle(parent: Node, text: String, value: bool, callback: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.text = text
	check.button_pressed = value
	check.toggled.connect(callback)
	parent.add_child(check)
	return check

func slider(parent: Node, text: String, value: float, callback: Callable) -> void:
	var row := setting_row(parent, text)
	var range_slider := HSlider.new()
	range_slider.min_value = 0
	range_slider.max_value = 1
	range_slider.step = 0.01
	range_slider.value = value
	range_slider.custom_minimum_size.x = 230
	row.add_child(range_slider)
	var number := label("%d%%" % roundi(value * 100), row)
	range_slider.value_changed.connect(func(next: float):
		number.text = "%d%%" % roundi(next * 100)
		callback.call(next))

func build_setup() -> void:
	setup_panel = centered_panel(830, 650)
	setup_panel.visible = false
	var outer := VBoxContainer.new()
	setup_panel.add_child(outer)
	var heading := HBoxContainer.new()
	outer.add_child(heading)
	var title := label("SETUP / CONTROLS", heading, 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button("Back", heading, close_setup)
	setup_status = label("Select an action, then press a key, mouse or wheel button.", outer, 14)
	setup_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	setup_content = VBoxContainer.new()
	setup_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	setup_content.add_theme_constant_override("separation", 8)
	scroll.add_child(setup_content)
	label("MOZA / GYROSCOPE", setup_content, 22)
	wheel_live = label("", setup_content, 14)
	wheel_live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var path_row := setting_row(setup_content, "Device path (blank = Moza)")
	var path := LineEdit.new()
	path.text = controls.device_path
	path.placeholder_text = "/dev/input/eventN"
	path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(path)
	button("Connect", path_row, func():
		controls.device_path = path.text.strip_edges()
		controls.save_config()
		controls.connect_wheel())
	for axis in ["steer", "throttle", "brake"]:
		var row := setting_row(setup_content, axis.capitalize() + " axis")
		button("Assign axis", row, func(): controls.listen_axis(axis))
		var code := SpinBox.new()
		code.min_value = 0
		code.max_value = 63
		code.value = controls.get(axis + "_code")
		row.add_child(code)
		code.value_changed.connect(func(value: float):
			controls.set(axis + "_code", int(value))
			controls.save_config())
		controls.binding_changed.connect(func(): code.set_value_no_signal(controls.get(axis + "_code")))
		toggle(row, "Invert", controls.get(axis + "_inverted"), func(value: bool):
			controls.set(axis + "_inverted", value)
			controls.save_config())
	for property in ["wheel_range_deg", "steering_lock_deg"]:
		var row := setting_row(setup_content, "Physical wheel range °" if property == "wheel_range_deg" else "Game steering lock °")
		var degrees := SpinBox.new()
		degrees.min_value = 90
		degrees.max_value = 3000
		degrees.step = 10
		degrees.value = controls.get(property)
		row.add_child(degrees)
		degrees.value_changed.connect(func(value: float): controls.set(property, value); controls.save_config())
	toggle(setup_content, "Force feedback enabled", controls.ffb_enabled, func(value: bool):
		controls.ffb_enabled = value
		controls.save_config()
		if not value:
			controls.stop_force())
	toggle(setup_content, "Invert force direction (Moza default)", controls.force_inverted, func(value: bool):
		controls.force_inverted = value
		controls.save_config())
	slider(setup_content, "FFB strength", controls.gain, func(value: float): controls.gain = value; controls.save_config())
	slider(setup_content, "Impact vibration", controls.impact_strength, func(value: float): controls.impact_strength = value; controls.save_config())
	slider(setup_content, "Steering deadzone", controls.deadzone, func(value: float): controls.deadzone = minf(value, 0.3); controls.save_config())
	label("Force is zero while menus are open. No test force is sent here.\nThe model combines rotor resistance, centering, side loads and collision kicks.", setup_content, 14)
	label("BUTTON MAPPING · PRIMARY / SECONDARY", setup_content, 22)
	for action in controls.ACTIONS:
		var row := setting_row(setup_content, action.replace("_", " ").capitalize())
		row.add_theme_constant_override("separation", 4)
		binding_buttons[action] = []
		for slot in range(2):
			var assign := button(controls.describe(action, slot), row, func(): controls.listen(action, slot))
			assign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			assign.custom_minimum_size.x = 145
			assign.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			assign.tooltip_text = "Primary" if slot == 0 else "Secondary"
			binding_buttons[action].append(assign)
			var clear := button("×", row, func(): controls.assign_binding(action, {}, slot))
			clear.tooltip_text = "Clear this assignment"
	label("AUDIO", setup_content, 22)
	slider(setup_content, "Generative music volume", sound.music.volume, func(value: float): sound.music.volume = value; save_audio_settings())
	slider(setup_content, "Motor / impact volume", sound.volume, func(value: float): sound.volume = value; save_audio_settings())
	label("A synthesized electric motor follows rolling speed, rotor spin and throttle.\nWall and sphere impacts produce short mechanical transients.", setup_content, 14)

func refresh_bindings() -> void:
	for action in binding_buttons:
		for slot in range(2):
			binding_buttons[action][slot].text = controls.describe(action, slot)

func open_setup() -> void:
	set_active(false)
	menu.hide()
	setup_panel.show()
	refresh_bindings()

func close_setup() -> void:
	controls.listening = ""
	controls.axis_listening = ""
	setup_panel.hide()
	menu.show()

func build_json_dialog() -> void:
	json_dialog = ConfirmationDialog.new()
	json_dialog.title = "FOLDROOM JSON"
	json_dialog.min_size = Vector2i(760, 500)
	root.add_child(json_dialog)
	var content := VBoxContainer.new()
	json_dialog.add_child(content)
	json_text = TextEdit.new()
	json_text.custom_minimum_size = Vector2(720, 340)
	json_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(json_text)
	json_error = label("", content, 14)
	json_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var row := HBoxContainer.new()
	content.add_child(row)
	button("Open file", row, func(): show_file(false))
	button("Save file", row, func(): show_file(true))
	button("Copy", row, func(): DisplayServer.clipboard_set(json_text.text))
	json_dialog.confirmed.connect(func():
		if importing and not load_json(json_text.text):
			json_dialog.popup_centered())
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; FoldRoom state"])
	file_dialog.size = Vector2i(900, 600)
	root.add_child(file_dialog)
	file_dialog.file_selected.connect(func(path: String):
		if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
			write_state_file(path, json_text.text)
			return
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			json_error.text = "Open failed: " + error_string(FileAccess.get_open_error())
			return
		if file.get_length() > 16 * 1024 * 1024:
			json_error.text = "JSON too large: maximum 16 MB"
			return
		json_text.text = file.get_as_text())

func show_file(save: bool) -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if save else FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.current_file = "foldroom.json" if save else ""
	file_dialog.popup_centered()

func open_json(is_import: bool) -> void:
	set_active(false)
	importing = is_import
	json_dialog.title = "Import web / Godot JSON" if importing else "Export web-compatible JSON"
	json_dialog.get_ok_button().text = "Import" if importing else "Close"
	json_text.text = "" if importing else State.export_json(maze, player, balls, renderer.export_marks())
	json_error.text = ""
	json_dialog.popup_centered()

func load_json(text: String) -> bool:
	var importer := State.new()
	var result := importer.import_json(text)
	if result.is_empty():
		json_error.text = importer.error
		show_message(importer.error)
		return false
	maze = result.maze
	player = result.player
	balls = result.balls
	renderer.load_marks(result.marks)
	renderer.camera_distance = 0
	dirty = true
	gyro.reset()
	controls.held.clear()
	show_message("State imported")
	return true

func write_state_file(path: String, text: String) -> bool:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		show_message("Save failed: " + error_string(FileAccess.get_open_error()))
		return false
	file.store_string(text)
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK:
		show_message("Save failed: " + error_string(result))
		return false
	result = DirAccess.rename_absolute(path + ".tmp", path)
	if result != OK:
		show_message("Save rename failed: " + error_string(result))
		return false
	show_message("Saved: " + path)
	return true

func quick_save() -> void:
	write_state_file("user://foldroom.json", State.export_json(maze, player, balls, renderer.export_marks()))

func quick_load() -> void:
	if not FileAccess.file_exists("user://foldroom.json"):
		show_message("No quick save yet")
		return
	var file := FileAccess.open("user://foldroom.json", FileAccess.READ)
	if file == null:
		show_message("Load failed: " + error_string(FileAccess.get_open_error()))
		return
	load_json(file.get_as_text())

func load_example() -> void:
	var file := FileAccess.open("res://example.json", FileAccess.READ)
	if file == null:
		show_message("Example missing: " + error_string(FileAccess.get_open_error()))
		return
	if load_json(file.get_as_text()) and player.mode != "ball":
		Motion.set_mode(player, "ball")

func reset_maze() -> void:
	maze = Maze.new()
	player = Motion.initial_player()
	balls.clear()
	renderer.load_marks([])
	renderer.camera_distance = 0
	dirty = true
	gyro.reset()
	show_message("Maze reset · Ball mode")

func jump_start() -> void:
	var mode: String = player.mode
	player = Motion.initial_player()
	if mode == "walk":
		Motion.set_mode(player, "walk")
	maze.constrain_actor(player)
	renderer.camera_distance = 0
	gyro.reset()

func switch_geometry() -> void:
	maze.set_tubes(not maze.tubes, balls + [player])
	renderer.camera_distance = 0
	gyro.reset()
	controls.stop_force()
	dirty = true
	show_message("Geometry: " + ("Tubes" if maze.tubes else "Rooms"))

func switch_mode() -> void:
	Motion.set_mode(player, "walk" if player.mode == "ball" else "ball", Maze.Pipes.BALL_RADIUS if maze.tubes else 0.5)
	maze.constrain_actor(player)
	renderer.camera_distance = 0
	gyro.reset()
	controls.stop_force()
	show_message("Mode: " + player.mode.capitalize())

func spawn_ball() -> void:
	if balls.size() >= 16:
		show_message("Ball limit reached: 16")
		return
	var ball := Motion.create_ball(randf() * TAU)
	maze.constrain_actor(ball)
	balls.append(ball)
	show_message("Powered ball spawned")

func set_active(value: bool) -> void:
	active = value
	started = started or active
	menu.visible = not active
	setup_panel.hide()
	crosshair.visible = active
	target.visible = active
	controls.held.clear()
	controls.forces_allowed = active and player.mode == "ball" and smoke_frames < 0
	controls.stop_force()
	gyro.reset()
	drawing = false
	marker_cursor = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE
	sound.active = active
	if not active:
		sound.silence()

func show_message(message: String) -> void:
	if notice != null:
		notice.text = message
		toast_time = 4
	if setup_status != null and setup_panel.visible:
		setup_status.text = message
	print(message)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and controls != null:
		set_active(false)
	if what == NOTIFICATION_WM_CLOSE_REQUEST and controls != null:
		quit_game()

func _input(event: InputEvent) -> void:
	if controls == null:
		return
	if not controls.listening.is_empty():
		controls.handle_event(event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE and not json_dialog.visible and not file_dialog.visible:
		if setup_panel.visible:
			close_setup()
			get_viewport().set_input_as_handled()
			return
		set_active(not active)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ENTER and not json_dialog.visible and not setup_panel.visible:
			set_active(true)
		return
	if event is InputEventMouseMotion:
		if drawing and controls.value("marker") > 0:
			marker_cursor += event.relative
			var viewport_size := get_viewport().get_visible_rect().size
			marker_cursor.x = clampf(marker_cursor.x, -viewport_size.x * 0.46, viewport_size.x * 0.46)
			marker_cursor.y = clampf(marker_cursor.y, -viewport_size.y * 0.43, viewport_size.y * 0.43)
			mark_wall()
			return
		look(event.relative)
		return
	controls.handle_event(event)
	if drawing and controls.value("marker") == 0:
		drawing = false
		marker_cursor = Vector2.ZERO
		renderer.last_slot = -1

func look(delta: Vector2) -> void:
	if player.mode == "ball":
		Motion.steer(player, signf(delta.x), minf(0.15, absf(delta.x) * 0.0024 / 1.8))
		player.pitch = clampf(player.pitch - delta.y * 0.0024, -deg_to_rad(89), deg_to_rad(89))
		return
	player.forward = (Quaternion(player.up, -delta.x * 0.0024) * player.forward).normalized()
	player.pitch = clampf(player.pitch - delta.y * 0.0024, -deg_to_rad(89), deg_to_rad(89))

func on_action(action: String) -> void:
	if not active:
		if action == "pause" and not setup_panel.visible:
			set_active(true)
		return
	var actions := {
		"pause": func(): set_active(false), "mode": switch_mode, "spawn": spawn_ball,
		"remove_ball": func():
			if not balls.is_empty(): balls.pop_front(),
		"reset": reset_maze, "jump_start": jump_start,
		"straight": func(): carve("straight"), "up": func(): carve("up"), "down": func(): carve("down"),
		"delete": remove_passage, "marker": func(): drawing = true; mark_wall(),
		"zoom_in": func(): renderer.zoom(-100), "zoom_out": func(): renderer.zoom(100)
	}
	if actions.has(action):
		actions[action].call()

func carve(kind: String) -> void:
	if renderer.camera_distance > 0:
		show_message("Return to first-person view to edit")
		return
	var hit := renderer.aim(maze, player)
	var link := maze.create(hit.room, hit.face, kind, hit.up)
	if link.is_empty():
		show_message(maze.last_error)
		return
	dirty = true
	show_message(kind.capitalize() + " passage · room " + str(link.target + 1))

func remove_passage() -> void:
	if renderer.camera_distance > 0:
		show_message("Return to first-person view to edit")
		return
	var hit := renderer.aim(maze, player)
	if maze.remove(hit.room, hit.face):
		var result := maze.prune(player.room, [player] + balls)
		balls = result.actors.filter(func(actor): return actor != player)
		dirty = true
		show_message("Passage closed · %d disconnected rooms removed" % result.removed)
		return
	if not maze.last_error.is_empty():
		show_message(maze.last_error)

func mark_wall() -> void:
	if renderer.camera_distance > 0:
		return
	var hit := renderer.aim(maze, player, marker_cursor)
	var new_slot: bool = hit.face >= 0 and maze.rooms[hit.room].markers[hit.face] < 0
	if renderer.mark(maze, hit) and new_slot:
		dirty = true

func step_world(dt: float, forward: float, side: float, boost: float) -> void:
	var actors := balls.duplicate()
	if player.mode == "ball":
		actors.append(player)
	var fastest := 0.0
	for actor in actors:
		fastest = maxf(fastest, actor.velocity.length())
	var count := maxi(1, ceili((fastest + 20.0 * dt) * dt / 0.2))
	var part := dt / count
	for i in range(count):
		if player.mode == "ball":
			Motion.drive(maze, player, part, forward, side, boost)
		if player.mode != "ball":
			Motion.move_player(maze, player, part, forward, side, boost)
		for ball in balls:
			Motion.move_ball(maze, ball, part)
		Motion.resolve_contacts(actors, maze)
		if player.mode == "ball":
			if maze.tubes:
				Motion.update_tube_camera(maze, player, part)
			if not maze.tubes:
				Motion.update_camera(player, part)

func _physics_process(dt: float) -> void:
	controls.poll(dt)
	gyro.strength = controls.gain
	gyro.impact_strength = controls.impact_strength
	if not active:
		controls.stop_force()
		return
	var forward := clampf(controls.value("accelerate") - controls.value("brake") + controls.throttle - controls.brake, -1, 1)
	var side := clampf(controls.value("right") - controls.value("left") + controls.steering, -1, 1)
	# Arrow keys are the web game's secondary keyboard bindings.
	if Input.is_physical_key_pressed(KEY_UP): forward = 1
	if Input.is_physical_key_pressed(KEY_DOWN): forward = -1
	if Input.is_physical_key_pressed(KEY_LEFT): side = -1
	if Input.is_physical_key_pressed(KEY_RIGHT): side = 1
	var boost := 5.0 if controls.value("boost") > 0 else 1.0
	var before_room: int = player.room
	var before_velocity: Vector3 = player.velocity
	maze.impacts.clear()
	maze.player_rotation = Quaternion.IDENTITY
	step_world(minf(dt, 0.05), forward, side, boost)
	if player.room != before_room:
		sound.music.event(&"passage")
	var camera_right: Vector3 = player.get("cameraForward", player.forward).cross(player.get("cameraUp", player.up)).normalized()
	# A portal rotates the velocity basis without causing acceleration.
	last_lateral = (player.velocity - maze.player_rotation * before_velocity).dot(camera_right) / dt
	var grounded := 0.0
	var floor_face := Maze.face_of(-player.up)
	if maze.rooms[player.room].links[floor_face] == null and player.p.dot(player.up) < -2.48:
		grounded = 1.0
	for hit in maze.impacts:
		if hit.controlled and player.mode == "ball":
			gyro.impact(hit.impulse, hit.normal.dot(hit.right))
		if hit.room == player.room:
			sound.impact(hit.impulse, 1.0 / (1.0 + hit.p.distance_to(player.p) * 0.3))
	controls.forces_allowed = active and player.mode == "ball" and smoke_frames < 0
	if player.mode == "ball":
		var rolling: Vector3 = player.omega - player.up * player.omega.dot(player.up)
		var torque := gyro.compute(controls.steering, controls.steering_rate, rolling.length(), last_lateral, grounded, maxf(0, forward), dt)
		controls.apply_force(torque)
		sound.spin = rolling.length()
	if player.mode != "ball":
		controls.stop_force()
		sound.spin = 0
	sound.speed = player.velocity.length()
	sound.throttle = maxf(0, forward)

func update_gravity_pointer() -> void:
	gravity_pointer.visible = active and maze.tubes and renderer.camera_distance == 0
	crosshair.modulate = Color.WHITE
	if not gravity_pointer.visible:
		return
	var frame := Motion.camera_frame(maze, player)
	var down: Vector3 = -frame.gravityUp
	var right: Vector3 = frame.forward.cross(frame.up).normalized()
	var projected := Vector2(down.dot(right), -down.dot(frame.up))
	gravity_pointer.position = root.size / 2.0 + marker_cursor
	gravity_pointer.points = PackedVector2Array([Vector2.ZERO, projected.limit_length(1.0) * 18.0])
	var alignment := clampf(down.dot(frame.forward), -1.0, 1.0)
	var tint := Color("55ed78") if alignment >= 0.0 else Color("ff5050")
	crosshair.modulate = Color.WHITE.lerp(tint, absf(alignment))

func _process(dt: float) -> void:
	if dirty:
		renderer.rebuild(maze)
		dirty = false
	renderer.sync(maze, player, balls)
	var room: Dictionary = maze.rooms[player.room]
	hud.text = "ROOM  %03d\n%s\n\nRooms      %d\nPassages   %d\nBalls      %d\n\nLOCAL DOWN  %s\nMODE        %s\nSpeed       %.2f\nFFB         %+.3f" % [player.room + 1, Maze.cell_key(room.cell), maze.rooms.size(), maze.passage_count(), balls.size(), FACE_NAMES[Maze.face_of(-player.up)].split(" / ")[0], player.mode.to_upper(), player.velocity.length(), gyro.output]
	if active:
		var hit := renderer.aim(maze, player, marker_cursor)
		var link = maze.rooms[hit.room].links[hit.face]
		target.text = "OVERVIEW" if renderer.camera_distance > 0 else ("PASSAGE · DEL TO REMOVE" if link != null else "WALL") + "\n" + FACE_NAMES[hit.face]
		crosshair.position = root.size / 2.0 + marker_cursor - Vector2(9, 17)
		crosshair.text = "⊙" if drawing else "+"
		crosshair.visible = renderer.camera_distance == 0
	update_gravity_pointer()
	if setup_panel.visible:
		wheel_live.text = "%s\nSteer %+.3f · throttle %.3f · brake %.3f\nABS codes: steer %d / throttle %d / brake %d\nAssigning axis: %s" % [controls.device_name, controls.steering, controls.throttle, controls.brake, controls.steer_code, controls.throttle_code, controls.brake_code, controls.axis_listening]
	toast_time = maxf(0, toast_time - dt)
	notice.visible = toast_time > 0
	if smoke_frames >= 0:
		smoke_frames += 1
		if smoke_frames == 30:
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			var result := image.save_png("res://tests/native-smoke.png")
			print("SMOKE screenshot: ", error_string(result))
			renderer.camera_distance = 20
		if smoke_frames == 60:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/overview-smoke.png")
			set_active(false)
			open_setup()
		if smoke_frames == 90:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/setup-smoke.png")
			var scroll: ScrollContainer = setup_content.get_parent()
			scroll.scroll_vertical = maxi(0, roundi(binding_buttons["straight"][0].get_parent().position.y) - 60)
		if smoke_frames == 120:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/bindings-smoke.png")
			close_setup()
			switch_geometry()
			set_active(true)
			smoke_check(maze.tubes and maze.tube_sample(player.room, player.p).clearance >= player.radius, "Tube switch places player inside geometry")
		if smoke_frames == 140:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("res://tests/tubes-smoke.png")
			quit_game(1 if smoke_failed else 0)

func save_audio_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "volume", sound.volume)
	config.set_value("audio", "music_volume", sound.music.volume)
	var result := config.save("user://audio.cfg")
	if result != OK:
		show_message("Audio settings save failed: " + error_string(result))

func load_audio_settings() -> void:
	var config := ConfigFile.new()
	var result := config.load("user://audio.cfg")
	if result == ERR_FILE_NOT_FOUND:
		return
	if result != OK:
		show_message("Audio settings load failed: " + error_string(result))
		return
	sound.music.volume = clampf(float(config.get_value("audio", "music_volume", 0.45)), 0, 1)
	sound.volume = clampf(float(config.get_value("audio", "volume", 0.55)), 0, 1)

func smoke_check(condition: bool, message: String) -> void:
	if not condition:
		smoke_failed = true
		push_error("SMOKE FAIL: " + message)
	print("SMOKE ", "PASS " if condition else "FAIL ", message)

func run_smoke_checks() -> void:
	# Exercise application wiring, persistence and ink without applying wheel torque.
	smoke_check(player.mode == "ball", "Ball mode after loading web example")
	var original := player.duplicate(true)
	var before: Vector3 = player.p
	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.pressed = true
	controls.handle_event(event)
	step_world(1.0 / 120, controls.value("accelerate"), 0, 1)
	event.pressed = false
	controls.handle_event(event)
	smoke_check(player.p.distance_to(before) > 0, "Keyboard mapping drives native physics")
	player = original
	var hit := {"room": 0, "face": 0, "point": Vector3(3, 0, 0)}
	for face in range(6):
		if maze.rooms[0].links[face] == null:
			hit.face = face
			hit.point = Maze.NORMALS[face] * 3.0
			break
	smoke_check(renderer.mark(maze, hit), "Native wall marker paints")
	var exported := State.export_json(maze, player, balls, renderer.export_marks())
	var importer := State.new()
	smoke_check(not importer.import_json(exported).is_empty(), "Ink PNG survives web-compatible JSON: " + importer.error)
	var output := FileAccess.open("res://tests/native-export.json", FileAccess.WRITE)
	output.store_string(exported)
	output.close()
	set_active(false)
	smoke_check(not controls.forces_allowed and not controls.constant_started, "Pause stops physical FFB")
	open_setup()
	controls.listen("spawn")
	event = InputEventKey.new()
	event.physical_keycode = KEY_F11
	event.pressed = true
	_input(event)
	smoke_check(controls.bindings.spawn.code == KEY_F11 and controls.listening.is_empty(), "Setup captures key")
	var restored := Controls.new()
	restored.config_path = controls.config_path
	restored.load_config()
	smoke_check(restored.bindings.spawn.code == KEY_F11, "Setup binding persists across sessions")
	restored.free()
	controls.bindings.spawn = {"kind": "key", "code": KEY_B}
	for pair in [["straight", 301], ["up", 302], ["down", 303]]:
		controls.assign_binding(pair[0], {"kind": "wheel_button", "code": pair[1]}, 1)
	controls.save_config()
	close_setup()
	set_active(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	dirty = true

func quit_game(code: int = 0) -> void:
	set_active(false)
	set_process(false)
	set_physics_process(false)
	controls.close_wheel()
	sound.shutdown()
	# Let the audio mixer release its stopped generator before the tree is freed.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(code)

extends SceneTree
const State = preload("res://scripts/state.gd")
const Renderer = preload("res://scripts/renderer.gd")
const Maze = preload("res://scripts/maze.gd")
const Motion = preload("res://scripts/motion.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var path := "user://foldroom.json"
	if not FileAccess.file_exists(path):
		path = "res://example.json"
	var importer := State.new()
	var state := importer.import_json(FileAccess.get_file_as_string(path))
	assert(not state.is_empty(), importer.error)
	if "--straight-tube" in OS.get_cmdline_user_args():
		state.maze = Maze.new()
		state.player = Motion.initial_player()
		state.player.p = Vector3.ZERO
		state.player.cameraForward = Vector3.FORWARD
		state.player.cameraUp = Vector3.UP
		state.balls = []
		state.maze.create(0, 4, "straight", Vector3.UP)
		var current := 0
		for step in range(24):
			current = state.maze.create(current, 5, "straight", Vector3.UP).target
	if not "--keep-geometry" in OS.get_cmdline_user_args():
		state.maze.tubes = true
	if "--subdivision" in OS.get_cmdline_user_args():
		state.maze.subdivision_tubes = true
		state.maze.prepare_subdivision()
	for actor in state.balls + [state.player]:
		state.maze.constrain_actor(actor)
	var renderer := Renderer.new()
	root.add_child(renderer)
	renderer.rebuild(state.maze)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--reference-shader="):
			var shader := Shader.new()
			shader.code = FileAccess.get_file_as_string(argument.trim_prefix("--reference-shader="))
			assert(not shader.code.is_empty(), "Reference shader must exist")
			renderer.material_ray.shader = shader
	if "--march-tubes" in OS.get_cmdline_user_args():
		renderer.material_ray.set_shader_parameter("tube_fast_trace", false)
	for warmup in range(6):
		await process_frame
		renderer.sync(state.maze, state.player, state.balls)
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/pipe-catalog-save-smoke.png")
	var frames := []
	for sample in range(30):
		var before := Time.get_ticks_usec()
		await process_frame
		renderer.sync(state.maze, state.player, state.balls)
		await RenderingServer.frame_post_draw
		# Readback waits for GPU completion; submission time alone understates cost.
		var completed := root.get_texture().get_image()
		assert(completed.get_width() == 1280)
		frames.append((Time.get_ticks_usec() - before) / 1000.0)
	frames.sort()
	var before := Time.get_ticks_usec()
	var sum := 0.0
	for sample in range(10000):
		sum += state.maze.tube_clearance(state.player.room, Vector3(sin(sample) * 1.2, cos(sample) * 1.2, 1.0))
	print("PIPE PERFORMANCE 1280x720, 30 frames: synchronised_median_ms=", frames[15], " p95_ms=", frames[28], " CPU field_us=", (Time.get_ticks_usec() - before) / 10000.0, " checksum=", sum)
	print("PIPE SCALE sphere=",state.player.get("radius",0)," position=",state.player.p," save=",path)
	print("PIPE OPTIONS ", OS.get_cmdline_user_args())
	quit()

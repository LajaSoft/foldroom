extends SceneTree
const State = preload("res://scripts/state.gd")
const Renderer = preload("res://scripts/renderer.gd")
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
	state.maze.tubes = true
	for actor in state.balls + [state.player]:
		state.maze.constrain_actor(actor)
	var renderer := Renderer.new()
	root.add_child(renderer)
	renderer.rebuild(state.maze)
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
	quit()

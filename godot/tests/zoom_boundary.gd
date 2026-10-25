extends SceneTree
const State = preload("res://scripts/state.gd")
const Renderer = preload("res://scripts/renderer.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	root.size = Vector2i(1272, 719)
	var importer := State.new()
	var state := importer.import_json(FileAccess.get_file_as_string("res://tests/fixtures/zoom-boundary.json"))
	assert(not state.is_empty(), importer.error)
	var renderer := Renderer.new()
	root.add_child(renderer)
	renderer.rebuild(state.maze)
	renderer.sync(state.maze, state.player, state.balls)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://tests/zoom-boundary-smoke.png")
	var highlighted := 0
	for x in range(450, 1000):
		for y in range(500, 520):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.65 and pixel.g > 0.55 and pixel.b < 0.55:
				highlighted += 1
	print("ZOOM BOUNDARY highlighted floor pixels: ", highlighted)
	if highlighted > 0:
		printerr("FAIL: Portal frame remains visible in quicksave regression")
		quit(1)
		return
	renderer.queue_free()
	await process_frame
	quit()

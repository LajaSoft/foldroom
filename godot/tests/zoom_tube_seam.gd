extends SceneTree
const State = preload("res://scripts/state.gd")
const Renderer = preload("res://scripts/renderer.gd")
func _initialize() -> void:
	call_deferred("run")
func fixture_path() -> String:
	return "res://tests/fixtures/zoom-tube-seam.json"

func verify_geometry(_renderer: FoldRenderer, _state: Dictionary) -> bool:
	return true

func run() -> void:
	root.size = Vector2i(1272, 719)
	var importer := State.new()
	var state := importer.import_json(FileAccess.get_file_as_string(fixture_path()))
	assert(not state.is_empty(), importer.error)
	var renderer := Renderer.new()
	root.add_child(renderer)
	renderer.rebuild(state.maze)
	# Make undefined shading observable: an RGBA8 capture alone turns NaNs black.
	var shader := Shader.new()
	shader.code = renderer.material_ray.shader.code.replace(" COLOR=vec4", " if(any(isnan(color)) || any(isinf(color)))color=vec3(1.,0.,1.);\n COLOR=vec4")
	renderer.material_ray.shader = shader
	renderer.sync(state.maze, state.player, state.balls)
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://tests/%s-smoke.png" % fixture_path().get_file().get_basename())
	var invalid := 0
	for x in range(image.get_width()):
		for y in range(image.get_height()):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.95 and pixel.g < 0.05 and pixel.b > 0.95:
				invalid += 1
	print("ZOOM TUBE SEAM invalid shaded pixels: ", invalid)
	if invalid > 0:
		printerr("FAIL: Undefined shading at zoom tube seam")
		quit(1)
		return
	if not await verify_geometry(renderer, state):
		quit(1)
		return
	renderer.queue_free()
	await process_frame
	quit()

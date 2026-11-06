extends SceneTree

const Maze = preload("res://scripts/maze.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var app = load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	app.maze = Maze.new()
	app.maze.tubes = true
	app.maze.subdivision_tubes = true
	app.maze.create(0, 0, "straight", Vector3.UP)
	app.maze.create(0, 4, "straight", Vector3.UP)
	var keys: Array = app.maze.subdivision_symbol_keys()
	for key: Vector2i in keys:
		Maze.Subdivision.symbols.erase(key)
	app.dirty = true
	app.start_subdivision_job()
	assert(app.subdivision_thread != null, "A subdivision worker starts")
	app.maze.create(0, 1, "straight", Vector3.UP)
	var current_keys: Array = app.maze.subdivision_symbol_keys()
	var frames := 0
	while app.subdivision_thread != null:
		await process_frame
		frames += 1
		assert(frames < 10000, "Worker finishes")
	assert(frames > 1, "Frames continue while a new symbol is built")
	assert(not app.dirty, "Completed geometry is installed")
	for key: Vector2i in current_keys:
		assert(Maze.Subdivision.symbols.has(key), "Worker publishes every symbol")
		assert(app.renderer.subdivision_gpu_data.roots.has(key), "GPU geometry contains every symbol")
	print("SUBDIVISION WORKER: passed; responsive frames=", frames)
	app.queue_free()
	await process_frame
	quit()

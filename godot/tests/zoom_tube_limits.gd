extends SceneTree

const Maze = preload("res://scripts/maze.gd")
const Motion = preload("res://scripts/motion.gd")
const Renderer = preload("res://scripts/renderer.gd")
var failed := false
var renderer: FoldRenderer

func _initialize() -> void:
	call_deferred("run")

func capture(maze: FoldMaze, player: Dictionary) -> Image:
	renderer.rebuild(maze)
	renderer.sync(maze, player, [])
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func mean_difference(a: Image, b: Image) -> float:
	var total := 0.0
	for x in range(a.get_width()):
		for y in range(a.get_height()):
			var first := a.get_pixel(x, y)
			var second := b.get_pixel(x, y)
			total += absf(first.r - second.r) + absf(first.g - second.g) + absf(first.b - second.b)
	return total / (a.get_width() * a.get_height() * 3.0)

func run() -> void:
	root.size = Vector2i(640, 360)
	renderer = Renderer.new()
	root.add_child(renderer)
	for kind in ["straight", "up", "down"]:
		for step in [-1, 1]:
			for partial in [false, true]:
				var maze := Maze.new()
				maze.tubes = true
				maze.subdivision_tubes = "--subdivision" in OS.get_cmdline_user_args()
				maze.zoom_coefficient = 1.25
				maze.create(0, 4, "straight", Vector3.UP)
				var link := maze.create(0, 5, kind, Vector3.UP)
				maze.adjust_zoom(0, 5, step)
				var direction: Vector3 = link.q * Vector3.FORWARD
				var up: Vector3 = link.q * Vector3.UP
				var current: int = link.target
				# All three following rooms must be evaluated along this ray's path.
				for index in range(3):
					var face := Maze.face_of(direction)
					var next := maze.create(current, face, "straight", up)
					maze.adjust_zoom(current, face, step)
					current = next.target
				var limit: float = Maze.MIN_ZOOM if step < 0 else Maze.MAX_ZOOM
				var scale_value: float = limit
				if partial:
					scale_value = limit * (1.05 if step < 0 else 1.0 / 1.05)
				var player := Motion.initial_player()
				player.p = Vector3(0, -0.4, -2.5)
				player.cameraForward = Vector3.FORWARD
				player.cameraUp = Vector3.UP
				player.zoomScale = scale_value
				player.radius = Maze.Pipes.BALL_RADIUS * scale_value
				var actual: Image = await capture(maze, player)
				if partial:
					# A clipped step must look like a genuinely smaller zoom step.
					maze.zoom_coefficient = 1.05
				if not partial:
					for room in maze.rooms:
						for passage in room.links:
							if passage != null:
								passage.zoom = 0
				var expected: Image = await capture(maze, player)
				var difference := mean_difference(actual, expected)
				var passed := difference < 0.0001
				failed = failed or not passed
				print("ZOOM TUBE LIMIT ", "PASS " if passed else "FAIL ", kind, " step=", step, " scale=", scale_value, " partial=", partial, " image difference=", difference)
				if not passed:
					actual.save_png("res://tests/zoom-tube-limit-%s-%d-%s-actual.png" % [kind, step, partial])
					expected.save_png("res://tests/zoom-tube-limit-%s-%d-%s-expected.png" % [kind, step, partial])
				if not partial:
					maze.rooms[0].links[5].zoom = step
					maze.rooms[link.target].links[link.face].zoom = -step
					var reverse := maze.passage_ratio(link.target, link.face, limit)
					var reverse_works := reverse > 1.0 if step < 0 else reverse < 1.0
					failed = failed or not reverse_works
					print("ZOOM TUBE REVERSE ", "PASS " if reverse_works else "FAIL ", kind, " step=", step, " ratio=", reverse)
	renderer.queue_free()
	await process_frame
	quit(1 if failed else 0)

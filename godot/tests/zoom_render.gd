extends SceneTree

const Maze = preload("res://scripts/maze.gd")
const Motion = preload("res://scripts/motion.gd")
const Renderer = preload("res://scripts/renderer.gd")
var failed := false

func _initialize() -> void:
	call_deferred("run")

func capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func run() -> void:
	root.size = Vector2i(640, 360)
	var renderer := Renderer.new()
	root.add_child(renderer)
	for tubes in [false, true]:
		for kind in ["straight", "up", "down"]:
			var maze := Maze.new()
			maze.tubes = tubes
			maze.zoom_coefficient = 1.25
			var link := maze.create(0, 5, kind, Vector3.UP)
			maze.adjust_zoom(0, 5, 1)
			var player := Motion.initial_player()
			player.p = Vector3(0, -0.5, 0)
			player.forward = Vector3.FORWARD
			player.cameraForward = Vector3.FORWARD
			var ball := Motion.create_ball(0)
			ball.radius = Maze.Pipes.BALL_RADIUS if tubes else 0.5
			ball.p = Vector3(0, -0.5, -3)
			renderer.rebuild(maze)
			renderer.sync(maze, player, [ball])
			var before: Image = await capture()
			var moved := maze.zoom_transport(0, 5, ball.p, ball.up, 1.0)
			ball.room = moved.room
			ball.p = moved.p
			ball.up = link.q * ball.up
			ball.spin = link.q * ball.spin
			ball.radius *= moved.ratio
			ball.zoomScale = moved.ratio
			renderer.sync(maze, player, [ball])
			var after: Image = await capture()
			var difference := 0.0
			var total_difference := 0.0
			for x in range(280, 360):
				for y in range(140, 220):
					var a := before.get_pixel(x, y)
					var b := after.get_pixel(x, y)
					total_difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
					difference = maxf(difference, maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))))
			var mean := total_difference / (80.0 * 80.0 * 3.0)
			print("ZOOM RENDER ", tubes, " ", kind, " crossing mean ", mean, " max ", difference)
			if mean > 0.005:
				failed = true
				printerr("FAIL: Zoom sphere image changes at portal")
			if kind == "straight":
				after.save_png("res://tests/zoom-%s-smoke.png" % ("tubes" if tubes else "rooms"))
	renderer.queue_free()
	await process_frame
	quit(1 if failed else 0)

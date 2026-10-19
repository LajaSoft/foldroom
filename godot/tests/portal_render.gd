extends SceneTree

const Maze = preload("res://scripts/maze.gd")
const Motion = preload("res://scripts/motion.gd")
const Renderer = preload("res://scripts/renderer.gd")
var failed := false
var renderer: FoldRenderer

func _initialize() -> void:
	call_deferred("run")

func capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func run() -> void:
	renderer = Renderer.new()
	root.add_child(renderer)
	for kind in ["straight", "up", "down"]:
		var maze := Maze.new()
		var link := maze.create(0, 5, kind, Vector3.UP)
		var player := Motion.initial_player()
		player.p = Vector3.ZERO
		player.forward = Vector3.FORWARD
		player.cameraForward = Vector3.FORWARD
		player.cameraUp = Vector3.UP
		var ball := Motion.create_ball(0)
		ball.p = Vector3(0, 0, -3)
		ball.spin = Quaternion(Vector3.FORWARD, 0.7)
		renderer.rebuild(maze)
		renderer.sync(maze, player, [])
		var background: Image = await capture()
		renderer.sync(maze, player, [ball])
		var before: Image = await capture()
		before.save_png("res://tests/portal-%s-source-smoke.png" % kind)
		var moved := maze.transport(0, 5, ball.p, [ball.up])
		ball.room = moved.room
		ball.p = moved.p
		ball.up = moved.vectors[0]
		ball.spin = link.q * ball.spin
		renderer.sync(maze, player, [ball])
		var after: Image = await capture()
		after.save_png("res://tests/portal-%s-destination-smoke.png" % kind)
		var center := Vector2i(after.get_width() / 2, after.get_height() / 2)
		var difference := 0.0
		var pixels := 0
		var opaque_pixels := 0
		for x in range(center.x - 45, center.x + 45):
			for y in range(center.y - 45, center.y + 45):
				var a := before.get_pixel(x, y)
				var b := after.get_pixel(x, y)
				var empty := background.get_pixel(x, y)
				difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
				if absf(b.r - empty.r) + absf(b.g - empty.g) + absf(b.b - empty.b) > 0.04:
					opaque_pixels += 1
				pixels += 1
		var mean := difference / (pixels * 3.0)
		var coverage := float(opaque_pixels) / pixels
		var passed := mean < 0.005 and coverage > 0.95
		failed = failed or not passed
		print("PORTAL RENDER ", "PASS " if passed else "FAIL ", kind, " same-pose mean pixel difference=", mean, " opaque coverage=", coverage)
	quit(1 if failed else 0)

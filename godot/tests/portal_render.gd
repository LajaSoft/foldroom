extends SceneTree

const Maze = preload("res://scripts/maze.gd")
const Motion = preload("res://scripts/motion.gd")
const Renderer = preload("res://scripts/renderer.gd")
const CATALOGUE_REFERENCE := "\nfloat referenceVoxel(int mask,ivec3 p){\n int slice=mask*49+p.z;\n return texelFetch(pipe_catalog,ivec2(slice%64,slice/64)*49+p.xy,0).r;\n}\nfloat referenceCatalogue(int room,vec3 p){\n int mask=int(texelFetch(room_shapes,ivec2(room%1024,room/1024),0).r+.5);\n vec3 grid=clamp((p+vec3(3.6))/7.2*48.,vec3(0.),vec3(47.99999));\n ivec3 b=ivec3(floor(grid));vec3 t=fract(grid);\n float a=mix(referenceVoxel(mask,b),referenceVoxel(mask,b+ivec3(1,0,0)),t.x);\n float c=mix(referenceVoxel(mask,b+ivec3(0,1,0)),referenceVoxel(mask,b+ivec3(1,1,0)),t.x);\n float d=mix(referenceVoxel(mask,b+ivec3(0,0,1)),referenceVoxel(mask,b+ivec3(1,0,1)),t.x);\n float e=mix(referenceVoxel(mask,b+ivec3(0,1,1)),referenceVoxel(mask,b+ivec3(1,1,1)),t.x);\n return mix(mix(a,c,t.y),mix(d,e,t.y),t.z);\n}\n"
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
	await test_tube_seams()
	await test_straight_tube_render()
	await test_flat_junction_render()
	await test_bent_tube_render()
	await test_open_corner_render()
	await test_shared_corner_floor_render()
	await test_pipe_hall_flare_render()
	quit(1 if failed else 0)

func test_tube_seams() -> void:
	for kind in ["straight", "up", "down"]:
		var maze := Maze.new()
		maze.create(0, 5, kind, Vector3.UP)
		maze.tubes = true
		var player := Motion.initial_player()
		player.p = Vector3(0, 1.60, -3)
		player.cameraForward = Vector3.FORWARD
		player.cameraUp = Vector3.UP
		renderer.rebuild(maze)
		renderer.sync(maze, player, [])
		var before: Image = await capture()
		var moved := maze.transport(0, 5, player.p, [player.cameraForward, player.cameraUp])
		player.room = moved.room
		player.p = moved.p
		player.cameraForward = moved.vectors[0]
		player.cameraUp = moved.vectors[1]
		renderer.sync(maze, player, [])
		var after: Image = await capture()
		after.save_png("res://tests/tube-seam-%s-smoke.png" % kind)
		var difference := 0.0
		var center := Vector2i(after.get_width() / 2, after.get_height() / 2)
		for x in range(center.x - 45, center.x + 45):
			for y in range(center.y - 45, center.y + 45):
				var a := before.get_pixel(x, y)
				var b := after.get_pixel(x, y)
				difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		var mean := difference / (90.0 * 90.0 * 3.0)
		var passed := mean < 0.025
		failed = failed or not passed
		print("TUBE SEAM ", "PASS " if passed else "FAIL ", kind, " near-wall camera ownership difference=", mean)

func test_straight_tube_render() -> void:
	var maze := Maze.new()
	maze.create(0, 4, "straight", Vector3.UP)
	maze.create(0, 5, "straight", Vector3.UP)
	maze.tubes = true
	var player := Motion.initial_player()
	player.p = Vector3.ZERO
	player.cameraForward = Vector3.FORWARD
	player.cameraUp = Vector3.UP
	renderer.rebuild(maze)
	renderer.sync(maze, player, [])
	var actual: Image = await capture()
	actual.save_png("res://tests/straight-tube-smoke.png")
	var original: Shader = renderer.material_ray.shader
	var reference := Shader.new()
	reference.code = original.code.replace("float tubeClearance(int room, vec3 p){", "float tubeClearance(int room, vec3 p){ if(room==0)return 1.65-length(p.xy);")
	renderer.material_ray.shader = reference
	var expected: Image = await capture()
	var difference := 0.0
	for x in range(0, actual.get_width(), 4):
		for y in range(0, actual.get_height(), 4):
			var a := actual.get_pixel(x, y)
			var b := expected.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	var mean := difference / (ceilf(actual.get_width() / 4.0) * ceilf(actual.get_height() / 4.0) * 3.0)
	var passed := mean < 0.01
	failed = failed or not passed
	print("STRAIGHT TUBE RENDER ", "PASS " if passed else "FAIL ", " analytic cylinder difference=", mean)
	renderer.material_ray.shader = original

func test_flat_junction_render() -> void:
	var maze := Maze.new()
	for face in [0, 1, 4, 5]:
		maze.create(0, face, "straight", Vector3.UP)
	maze.tubes = true
	var player := Motion.initial_player()
	player.p = Vector3.ZERO
	player.cameraForward = Vector3.DOWN
	player.cameraUp = Vector3.FORWARD
	renderer.rebuild(maze)
	renderer.sync(maze, player, [])
	var actual: Image = await capture()
	var original: Shader = renderer.material_ray.shader
	var reference := Shader.new()
	reference.code = original.code.replace("float tubeClearance(int room, vec3 p){", CATALOGUE_REFERENCE + "float tubeClearance(int room, vec3 p){ return referenceCatalogue(room,p);")
	renderer.material_ray.shader = reference
	var expected: Image = await capture()
	var difference := 0.0
	var center := Vector2i(actual.get_width() / 2, actual.get_height() / 2)
	for x in range(center.x - 100, center.x + 100):
		for y in range(center.y - 100, center.y + 100):
			var a := actual.get_pixel(x, y)
			var b := expected.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	var mean := difference / 120000.0
	var passed := mean < 0.01
	failed = failed or not passed
	print("FLAT JUNCTION RENDER ", "PASS " if passed else "FAIL ", " CPU/GPU catalogue floor difference=", mean)
	renderer.material_ray.shader = original
	player.cameraForward = Vector3(0, -0.25, -1).normalized()
	player.cameraUp = Vector3.RIGHT.cross(player.cameraForward).normalized()
	renderer.sync(maze, player, [])
	var overview: Image = await capture()
	overview.save_png("res://tests/flat-junction-smoke.png")

func test_bent_tube_render() -> void:
	var maze := Maze.new()
	maze.create(0, 0, "straight", Vector3.UP)
	maze.create(0, 4, "straight", Vector3.UP)
	maze.tubes = true
	var player := Motion.initial_player()
	player.p = Vector3.ONE * 0.878679656
	player.p.y = 0
	player.cameraForward = Vector3(1, 0, -1).normalized()
	player.cameraUp = Vector3.UP
	renderer.rebuild(maze)
	renderer.sync(maze, player, [])
	var actual: Image = await capture()
	actual.save_png("res://tests/bent-tube-smoke.png")
	var original: Shader = renderer.material_ray.shader
	var reference := Shader.new()
	reference.code = original.code.replace("float tubeClearance(int room, vec3 p){", "float tubeClearance(int room, vec3 p){ if(room==0)return 1.65-length(vec2(length(p.xz-vec2(3.))-3.,p.y));")
	renderer.material_ray.shader = reference
	var expected: Image = await capture()
	var difference := 0.0
	for x in range(0, actual.get_width(), 4):
		for y in range(0, actual.get_height(), 4):
			var a := actual.get_pixel(x, y)
			var b := expected.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	var mean := difference / (ceilf(actual.get_width() / 4.0) * ceilf(actual.get_height() / 4.0) * 3.0)
	var passed := mean < 0.01
	failed = failed or not passed
	print("BENT TUBE RENDER ", "PASS " if passed else "FAIL ", " analytic torus difference=", mean)
	renderer.material_ray.shader = original

func test_open_corner_render() -> void:
	var maze := Maze.new()
	var east := maze.create(0, 0, "straight", Vector3.UP)
	var north := maze.create(0, 2, "straight", Vector3.BACK)
	maze.create(east.target, 2, "straight", Vector3.BACK)
	maze.create(north.target, 0, "straight", Vector3.UP)
	maze.tubes = true
	var player := Motion.initial_player()
	player.p = Vector3(3, 0.8, 0)
	player.cameraForward = Vector3.RIGHT
	player.cameraUp = Vector3.BACK
	renderer.rebuild(maze)
	renderer.sync(maze, player, [])
	var before: Image = await capture()
	var moved := maze.transport(0, 0, player.p)
	player.room = moved.room
	player.p = moved.p
	renderer.sync(maze, player, [])
	var after: Image = await capture()
	after.save_png("res://tests/open-corner-smoke.png")
	var difference := 0.0
	var center := Vector2i(after.get_width() / 2, after.get_height() / 2)
	for x in range(center.x - 45, center.x + 45):
		for y in range(center.y - 45, center.y + 45):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	var mean := difference / 24300.0
	var passed := mean < 0.005
	failed = failed or not passed
	print("OPEN CORNER RENDER ", "PASS " if passed else "FAIL ", " shared corner ownership difference=", mean)

func test_shared_corner_floor_render() -> void:
	var maze := Maze.new()
	var east := maze.create(0, 0, "straight", Vector3.UP)
	var north := maze.create(0, 2, "straight", Vector3.BACK)
	maze.create(east.target, 2, "straight", Vector3.BACK)
	maze.create(north.target, 0, "straight", Vector3.UP)
	maze.create(east.target, 4, "straight", Vector3.UP)
	maze.tubes = true
	var player := Motion.initial_player()
	player.p = Vector3(0.7, 0.7, -0.4)
	player.cameraForward = Vector3(-1, -1, -0.4).normalized()
	player.cameraUp = Vector3.BACK
	renderer.rebuild(maze)
	renderer.sync(maze, player, [])
	var actual: Image = await capture()
	actual.save_png("res://tests/shared-corner-floor-smoke.png")
	var original: Shader = renderer.material_ray.shader
	var reference := Shader.new()
	# Independent world-space rounded rectangle, including the outer corner.
	var hall_reference := "float tubeClearance(int room, vec3 p){ float field=referenceCatalogue(room,p); if(room>3)return field; vec2 offset=vec2(room==1||room==3?6.:0.,room>=2?6.:0.); vec2 outside=max(abs(p.xy+offset-vec2(3.))-vec2(3.),vec2(0.)); return max(field,1.65-length(vec3(outside,p.z)));"
	reference.code = original.code.replace("float tubeClearance(int room, vec3 p){", CATALOGUE_REFERENCE + hall_reference)
	renderer.material_ray.shader = reference
	var expected: Image = await capture()
	var difference := 0.0
	var center := Vector2i(actual.get_width() / 2, actual.get_height() / 2)
	for x in range(center.x - 100, center.x + 100):
		for y in range(center.y - 100, center.y + 100):
			var a := actual.get_pixel(x, y)
			var b := expected.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	var mean := difference / 120000.0
	var passed := mean < 0.01
	failed = failed or not passed
	print("SHARED CORNER FLOOR RENDER ", "PASS " if passed else "FAIL ", " CPU/GPU shared field difference=", mean)
	renderer.material_ray.shader = original

func test_pipe_hall_flare_render() -> void:
	var maze := Maze.new()
	var pipe := maze.create(0, 4, "straight", Vector3.UP)
	maze.create(0, 5, "straight", Vector3.UP)
	maze.create(0, 0, "straight", Vector3.UP)
	maze.tubes = true
	var player := Motion.initial_player()
	player.room = pipe.target
	player.p = Vector3(0.8, 0.5, -3)
	player.cameraForward = Vector3.FORWARD
	player.cameraUp = Vector3.UP
	renderer.rebuild(maze)
	renderer.sync(maze, player, [])
	var before: Image = await capture()
	var moved := maze.transport(pipe.target, 5, player.p)
	player.room = moved.room
	player.p = moved.p
	renderer.sync(maze, player, [])
	var after: Image = await capture()
	after.save_png("res://tests/pipe-hall-flare-smoke.png")
	var difference := 0.0
	var center := Vector2i(after.get_width() / 2, after.get_height() / 2)
	for x in range(center.x - 45, center.x + 45):
		for y in range(center.y - 45, center.y + 45):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			difference += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
	var mean := difference / 24300.0
	var passed := mean < 0.005
	failed = failed or not passed
	print("PIPE HALL FLARE RENDER ", "PASS " if passed else "FAIL ", " shared aperture ownership difference=", mean)

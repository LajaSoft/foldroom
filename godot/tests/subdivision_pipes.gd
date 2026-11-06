extends SceneTree
const Maze = preload("res://scripts/maze.gd")
const Motion = preload("res://scripts/motion.gd")
const State = preload("res://scripts/state.gd")
const Subdivision = preload("res://scripts/subdivision_pipes.gd")
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var before := Time.get_ticks_msec()
	for axis in range(3):
		var up: Vector3 = Maze.NORMALS[((axis + 1) % 3) * 2]
		var maze := Maze.new()
		maze.tubes = true
		maze.subdivision_tubes = true
		maze.create(0, axis * 2, "straight", up)
		maze.create(0, axis * 2 + 1, "straight", up)
		maze.adjust_zoom(0, axis * 2, 1)
		maze.prepare_subdivision()
		var builds := Subdivision.topology_builds
		for coefficient in [1.1, 1.5, 2.0]:
			maze.zoom_coefficient = coefficient
			for scale_value in [0.2, 1.0, 4.5]:
				for progress in [-2.8, -2.0, -1.0, 0.0, 1.0, 2.0, 2.8]:
					var floor_point: Vector3 = -up * Maze.TUBE_RADIUS
					floor_point[axis] = progress
					var sample := maze.tube_sample(0, floor_point, up, scale_value)
					check(absf(sample.clearance) < 0.0001, "Zoom keeps floor height")
					check(sample.normal.dot(-up) > 0.999, "Floor has no longitudinal slope")
					check(maze.tube_clearance(0, floor_point + up * 0.5, up, scale_value) > 0.0, "Interior remains open")
		check(Subdivision.topology_builds == builds, "Coefficient updates reuse topology stencils")
		var side: Vector3 = Maze.NORMALS[((axis + 2) % 3) * 2]
		for progress in [-2.8, 0.0, 2.8]:
			for angle_step in range(64):
				var angle := TAU * angle_step / 64.0
				var p: Vector3 = (up * cos(angle) + side * sin(angle)) * Maze.TUBE_RADIUS
				p[axis] = progress
				check(absf(maze.tube_clearance(0, p, up, Maze.MAX_ZOOM)) < 0.012, "Straight subdivision sections approximate a circle, not a beveled square")
	for mask in range(64):
		var base := Subdivision.symbol(mask, 0)
		var surface := Subdivision.profile(base, PackedFloat32Array([1, 1, 1, 1, 1, 1]), Vector3.UP)
		check(Subdivision.sample(surface, Vector3.ZERO).clearance > 0.0, "Every opening mask has an open center")
		for feature: PackedVector4Array in base.vertices:
			check(Subdivision.base_position(feature).is_finite(), "All subdivided vertices are finite")
	var cube := Maze.new()
	cube.tubes = true
	cube.subdivision_tubes = true
	for z in range(2):
		for y in range(2):
			for x in range(2):
				var source := cube.room(Vector3i(x, y, z))
				for axis in range(3):
					if source.cell[axis] == 0:
						cube.create(source.id, axis * 2, "straight", Maze.NORMALS[((axis + 1) % 3) * 2])
	check(cube.subdivision_corners(0) & (1 << 12) != 0, "Complete 2x2x2 erases its shared volume")
	check(cube.tube_clearance(0, Vector3(2.7, 2.7, 2.7)) > 0.1, "Former central solid is open")
	var corner_before := cube.subdivision_corners(0)
	cube.remove(cube.cells[Vector3i(1, 1, 0)], 4)
	check(cube.subdivision_corners(0) != corner_before, "Topology edits invalidate volume signatures")
	var importer := State.new()
	var saved := importer.import_json(FileAccess.get_file_as_string("res://tests/fixtures/zoom-straight-taper.json"))
	check(not saved.is_empty(), "Saved passage imports")
	if not saved.is_empty():
		var maze: FoldMaze = saved.maze
		maze.subdivision_tubes = true
		maze.prepare_subdivision()
		var player: Dictionary = saved.player
		var origin: int = player.room
		var target: int = maze.rooms[origin].links[5].target
		var expected: float = player.zoomScale * maze.passage_ratio(origin, 5, player.zoomScale)
		player.forward = Vector3.FORWARD
		player.cameraForward = Vector3.FORWARD
		player.velocity = Vector3.ZERO
		player.omega = Vector3.ZERO
		player.p = Vector3(0, -Maze.TUBE_RADIUS + player.radius, 0)
		for tick in range(240):
			Motion.step_ball(maze, player, 1.0 / 120.0)
		check(absf(player.p.z) < 0.00001 and absf(player.p.x) < 0.003, "A stationary sphere does not roll along the zoom floor")
		check(absf(player.p.y + Maze.TUBE_RADIUS - player.radius) < 0.003, "Stationary sphere retains floor contact")
		maze.constrain_actor(player)
		for tick in range(900):
			Motion.drive(maze, player, 1.0 / 120.0, 1.0, 0.0)
			if player.room != origin:
				break
		check(player.room == target, "Sphere crosses the saved subdivided passage")
		check(is_equal_approx(player.zoomScale, expected), "Crossing applies one scale step")
		var restored := importer.import_json(State.export_json(maze, player, [], []))
		check(not restored.is_empty() and restored.maze.subdivision_tubes, "Subdivision mode survives JSON round trip")
	print("SUBDIVISION TESTS: ", checks, " checks; ", failures, " failures; ", Time.get_ticks_msec()-before, " ms")
	quit(1 if failures else 0)

extends SceneTree
const Maze = preload("res://scripts/maze.gd")
const Motion = preload("res://scripts/motion.gd")
const Renderer = preload("res://scripts/renderer.gd")
const State = preload("res://scripts/state.gd")
var renderer: FoldRenderer
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
	renderer = Renderer.new()
	root.add_child(renderer)
	for mask in [48, 17, 49, 63]:
		var maze := Maze.new()
		maze.tubes = true
		maze.subdivision_tubes = true
		maze.zoom_coefficient = 1.5
		var zoom_face := -1
		for face in range(6):
			if mask & (1 << face):
				maze.create(0, face, "straight", Maze.NORMALS[((int(face / 2) + 1) % 3) * 2])
				zoom_face = face
		maze.adjust_zoom(0, zoom_face, 1)
		for scale_value in [Maze.MIN_ZOOM, 1.0, Maze.MAX_ZOOM]:
			var player := Motion.initial_player()
			player.p = Vector3(0, -0.3, 0)
			player.zoomScale = scale_value
			player.radius = Maze.Pipes.BALL_RADIUS * scale_value
			renderer.rebuild(maze)
			renderer.sync(maze, player, [])
			var surface := maze.subdivision_profile(0, Vector3.UP, scale_value)
			var faces := PackedVector3Array()
			for triangle: Vector3i in surface.symbol.triangles:
				faces.append(surface.vertices[triangle.x])
				faces.append(surface.vertices[triangle.y])
				faces.append(surface.vertices[triangle.z])
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(faces)
			var world := World3D.new()
			PhysicsServer3D.space_set_active(world.space, true)
			var body := PhysicsServer3D.body_create()
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
			PhysicsServer3D.body_add_shape(body, shape.get_rid())
			PhysicsServer3D.body_set_space(body, world.space)
			await physics_frame
			await process_frame
			var reference := PhysicsServer3D.space_get_direct_state(world.space)
			var queries := Image.create(64, 36, false, Image.FORMAT_RGBAF)
			for y in range(36):
				for x in range(64):
					var direction := Vector3((x + 0.5 - 32.0) / 18.0 * 0.72, (y + 0.5 - 18.0) / 18.0 * 0.72, -1).normalized()
					var limit: float = Maze.intersect(player.p, direction).distance
					var query := PhysicsRayQueryParameters3D.create(player.p, player.p + direction * (limit + 0.01))
					query.hit_back_faces = true
					var hit: Dictionary = reference.intersect_ray(query)
					var expected := limit
					if not hit.is_empty():
						expected = minf(expected, player.p.distance_to(hit.position))
					queries.set_pixel(x, y, Color(direction.x, direction.y, direction.z, expected))
			PhysicsServer3D.free_rid(body)
			var shader := Shader.new()
			shader.code = renderer.material_ray.shader.code.get_slice("void fragment(){", 0) + """
uniform sampler2D audit_rays : filter_nearest, repeat_disable;
void fragment(){
 vec4 q=texture(audit_rays,UV);
 vec3 positiveRatio,negativeRatio;
 for(int axis=0;axis<3;axis++){
  positiveRatio[axis]=passageRatio(roomId,axis*2,actor_scale);
  negativeRatio[axis]=passageRatio(roomId,axis*2+1,actor_scale);
 }
 vec3 times=(sign(q.xyz)*3.-eye)/q.xyz;
 float limit=min(times.x,min(times.y,times.z));
 int root=int(texelFetch(room_shapes,ivec2(roomId%1024,roomId/1024),0).a+.5);
 vec3 n;float distance=subdivisionTrace(root,eye,q.xyz,limit,gravityUp,positiveRatio,negativeRatio,n);
 bool valid=!isnan(distance)&&!isinf(distance)&&abs(distance-q.a)<.0002;
 COLOR=valid?vec4(0.,1.,0.,1.):vec4(1.,0.,1.,1.);
}
"""
			renderer.material_ray.shader = shader
			renderer.material_ray.set_shader_parameter("audit_rays", ImageTexture.create_from_image(queries))
			var actual: Image = await capture()
			var invalid := 0
			for y in range(actual.get_height()):
				for x in range(actual.get_width()):
					if actual.get_pixel(x, y).g < 0.95:
						invalid += 1
			failed = failed or invalid > 0
			print("SUBDIVISION GPU ", "PASS " if invalid == 0 else "FAIL ", " mask=", mask, " scale=", scale_value, " mismatched pixels=", invalid)
	var importer := State.new()
	var saved := importer.import_json(FileAccess.get_file_as_string("res://tests/fixtures/zoom-straight-taper.json"))
	assert(not saved.is_empty(), importer.error)
	saved.maze.subdivision_tubes = true
	saved.maze.constrain_actor(saved.player)
	renderer.rebuild(saved.maze)
	renderer.sync(saved.maze, saved.player, [])
	var image: Image = await capture()
	image.save_png("res://tests/subdivision-save-smoke.png")
	renderer.queue_free()
	await process_frame
	quit(1 if failed else 0)

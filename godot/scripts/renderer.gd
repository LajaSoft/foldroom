class_name FoldRenderer
extends Control

const Maze = preload("res://scripts/maze.gd")
const Motion = preload("res://scripts/motion.gd")
const MAX_RENDER_BALLS := 128
var surface: ColorRect
var material_ray: ShaderMaterial
var topology_image: Image
var shape_texture: ImageTexture
var topology_texture: ImageTexture
var ball_image: Image
var ball_texture: ImageTexture
var marks_image: Image
var marks_texture: ImageTexture
var marks: Array = []
var overview_container: SubViewportContainer
var overview_viewport: SubViewport
var overview_camera: Camera3D
var overview_root: Node3D
var face_instances: Array = []
var sphere_instances: MultiMeshInstance3D
var camera_distance := 0.0
var outside := false
var frame: Dictionary
var last_marker := Vector2(-1, -1)
var last_slot := -1
var map_radius := 6.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	material_ray = ShaderMaterial.new()
	material_ray.shader = load("res://shaders/maze.gdshader")
	surface = ColorRect.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.material = material_ray
	add_child(surface)
	topology_image = Image.create(1024, 1, false, Image.FORMAT_RGBAF)
	topology_texture = ImageTexture.create_from_image(topology_image)
	shape_texture = ImageTexture.create_from_image(Image.create(1024, 1, false, Image.FORMAT_RGBAF))
	ball_image = Image.create(3, MAX_RENDER_BALLS, false, Image.FORMAT_RGBAF)
	ball_texture = ImageTexture.create_from_image(ball_image)
	marks_image = Image.create(2048, 1024, false, Image.FORMAT_RGBA8)
	marks_image.fill(Color.TRANSPARENT)
	marks_texture = ImageTexture.create_from_image(marks_image)
	material_ray.set_shader_parameter("topology", topology_texture)
	material_ray.set_shader_parameter("room_shapes", shape_texture)
	material_ray.set_shader_parameter("pipe_catalog", Maze.Pipes.texture())
	material_ray.set_shader_parameter("balls", ball_texture)
	material_ray.set_shader_parameter("markings", marks_texture)
	setup_overview()

func setup_overview() -> void:
	overview_container = SubViewportContainer.new()
	overview_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overview_container.stretch = true
	add_child(overview_container)
	overview_viewport = SubViewport.new()
	overview_viewport.world_3d = World3D.new()
	overview_viewport.size = Vector2i(1280, 720)
	overview_container.add_child(overview_viewport)
	overview_root = Node3D.new()
	overview_viewport.add_child(overview_root)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.035, 0.055, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.8
	world_environment.environment = environment
	overview_root.add_child(world_environment)
	overview_camera = Camera3D.new()
	overview_camera.current = true
	overview_camera.fov = rad_to_deg(2.0 * atan(0.72))
	overview_camera.far = 1620000.0
	overview_root.add_child(overview_camera)
	for face in range(6):
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
			var corner: Vector2 = (uv - Vector2.ONE * 0.5) * 6.0
			var sign_value := 1.0 if face % 2 == 0 else -1.0
			var p := Vector3(sign_value * 3.0, corner.y, corner.x)
			if face >= 2 and face < 4:
				p = Vector3(corner.x, sign_value * 3.0, corner.y)
			if face >= 4:
				p = Vector3(corner.x, corner.y, sign_value * 3.0)
			vertices.append(p)
			uvs.append(uv)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/overview.gdshader")
		mat.set_shader_parameter("face", face)
		mat.set_shader_parameter("markings", marks_texture)
		mesh.surface_set_material(0, mat)
		var instance := MultiMeshInstance3D.new()
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = mesh
		instance.multimesh = multi
		overview_root.add_child(instance)
		face_instances.append(instance)
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var sphere_material := ShaderMaterial.new()
	sphere_material.shader = load("res://shaders/sphere.gdshader")
	sphere.material = sphere_material
	var spheres := MultiMesh.new()
	spheres.transform_format = MultiMesh.TRANSFORM_3D
	spheres.use_colors = true
	spheres.mesh = sphere
	spheres.instance_count = 17
	sphere_instances = MultiMeshInstance3D.new()
	sphere_instances.multimesh = spheres
	overview_root.add_child(sphere_instances)

func rebuild(maze: FoldMaze) -> void:
	map_radius = 6.0
	for room in maze.rooms:
		map_radius = maxf(map_radius, Vector3(room.cell).length() * 6.0 + 6.0)
	var height := maxi(1, ceili(maze.rooms.size() * 12.0 / 1024.0))
	topology_image = Image.create(1024, height, false, Image.FORMAT_RGBAF)
	topology_image.fill(Color(0, 0, 0, 0))
	for face in range(6):
		face_instances[face].multimesh.instance_count = maze.rooms.size()
	for room in maze.rooms:
		for face in range(6):
			var index: int = room.id * 12 + face * 2
			var link = room.links[face]
			var data := Color(0, 0, room.markers[face] + 1, 0)
			if link != null:
				data.r = link.target + 1
				data.g = link.face
				data.a = 1 if link.kind == "straight" else 2
				var q: Quaternion = link.q
				topology_image.set_pixel((index + 1) % 1024, (index + 1) / 1024, Color(q.x, q.y, q.z, q.w))
			topology_image.set_pixel(index % 1024, index / 1024, data)
			var multi: MultiMesh = face_instances[face].multimesh
			multi.set_instance_transform(room.id, Transform3D(Basis.IDENTITY, Vector3(room.cell) * 6.0))
			multi.set_instance_custom_data(room.id, Color(data.a, data.b, 0, 0))
	topology_texture.set_image(topology_image)
	var shape_image := Image.create(1024, maxi(1, ceili(maze.rooms.size() / 1024.0)), false, Image.FORMAT_RGBAF)
	for room in maze.rooms:
		shape_image.set_pixel(room.id % 1024, room.id / 1024, Color(maze.tube_shape_mask(room.id), 0, 0, 0))
	shape_texture.set_image(shape_image)

func view(maze: FoldMaze, player: Dictionary) -> Dictionary:
	var result := Motion.camera_frame(maze, player)
	var anchor: Vector3 = Vector3(maze.rooms[result.room].cell) * 6.0 + result.p
	# At a folded mouth the actor's owning frame is authoritative. A lattice
	# lookup at an exact positive boundary can select the wrong side of a fold.
	if camera_distance <= 0.00001:
		result.worldEye = anchor
		result.outside = false
		return result
	var eye: Vector3 = anchor - result.forward * camera_distance
	var cell: Vector3i
	# Explicit floor matters for negative lattice coordinates.
	cell = Vector3i(floori((eye.x + 3.0) / 6.0), floori((eye.y + 3.0) / 6.0), floori((eye.z + 3.0) / 6.0))
	result.worldEye = eye
	result.outside = not maze.cells.has(cell)
	if not result.outside:
		result.room = maze.cells[cell]
		result.p = eye - Vector3(cell) * 6.0
	return result

# Draw the two clipped portions of a crossing sphere in their own room frames.
# These are render records only; no actor or collision body is duplicated.
static func portal_images(maze: FoldMaze, actors: Array) -> Array:
	var records: Array = []
	for actor in actors:
		records.append(actor)
		for face in range(6):
			var link = maze.rooms[actor.room].links[face]
			if link == null or absf(3.0 - actor.p.dot(Maze.NORMALS[face])) > actor.radius + 0.00001:
				continue
			var moved := maze.transport(actor.room, face, actor.p, [actor.up])
			records.append({"room": moved.room, "p": moved.p, "up": moved.vectors[0], "radius": actor.radius, "spin": (link.q * actor.spin).normalized()})
	assert(records.size() <= MAX_RENDER_BALLS, "Render buffer must hold all 17 actors and six portal images each")
	return records

func sync(maze: FoldMaze, player: Dictionary, balls: Array) -> void:
	material_ray.set_shader_parameter("tubes", maze.tubes)
	frame = view(maze, player)
	outside = frame.outside
	surface.visible = not outside
	overview_container.visible = outside
	overview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if outside else SubViewport.UPDATE_DISABLED
	var right: Vector3 = frame.forward.cross(frame.up).normalized()
	material_ray.set_shader_parameter("resolution", size)
	material_ray.set_shader_parameter("eye", frame.p)
	material_ray.set_shader_parameter("forward", frame.forward)
	material_ray.set_shader_parameter("up", frame.up)
	material_ray.set_shader_parameter("right", right)
	material_ray.set_shader_parameter("roomId", frame.room)
	var visible_balls := balls.duplicate()
	if player.mode == "ball" and camera_distance > player.radius + 0.001:
		visible_balls.append(player)
	visible_balls = portal_images(maze, visible_balls)
	ball_image.fill(Color(0, 0, 0, 0))
	for i in range(visible_balls.size()):
		var ball: Dictionary = visible_balls[i]
		ball_image.set_pixel(0, i, Color(ball.p.x, ball.p.y, ball.p.z, ball.radius))
		ball_image.set_pixel(1, i, Color(ball.up.x, ball.up.y, ball.up.z, ball.room))
		ball_image.set_pixel(2, i, Color(ball.spin.x, ball.spin.y, ball.spin.z, ball.spin.w))
	ball_texture.update(ball_image)
	material_ray.set_shader_parameter("ballCount", visible_balls.size())
	if not outside:
		return
	overview_camera.near = maxf(0.03, camera_distance * 0.0001)
	overview_camera.far = maxf(1000.0, frame.worldEye.length() + map_radius + 100.0)
	overview_camera.position = frame.worldEye
	overview_camera.basis = Basis(right, frame.up, -frame.forward).orthonormalized()
	var all_balls := balls.duplicate()
	all_balls.append(player)
	sphere_instances.multimesh.visible_instance_count = all_balls.size()
	for i in range(all_balls.size()):
		var actor: Dictionary = all_balls[i]
		var scale_value: float = actor.get("radius", 0.28) / 0.5
		var spin: Quaternion = actor.get("spin", Quaternion.IDENTITY)
		sphere_instances.multimesh.set_instance_transform(i, Transform3D(Basis(spin).scaled(Vector3.ONE * scale_value), Vector3(maze.rooms[actor.room].cell) * 6.0 + actor.p))
		sphere_instances.multimesh.set_instance_color(i, Color(1, 0.85, 0.4) if i == all_balls.size() - 1 else Color(0.84, 0.89, 0.87))

func zoom(delta: float) -> void:
	var next := clampf((camera_distance + 3.0) * exp(clampf(delta * 0.002, -1, 1)) - 3.0, 0, 300000)
	camera_distance = 0 if next < 0.03 else next

func aim(maze: FoldMaze, player: Dictionary, marker_cursor: Vector2 = Vector2.ZERO) -> Dictionary:
	var current := view(maze, player)
	var right: Vector3 = current.forward.cross(current.up).normalized()
	var direction: Vector3 = (current.forward + right * marker_cursor.x * 2.0 / size.y * 0.72 - current.up * marker_cursor.y * 2.0 / size.y * 0.72).normalized()
	var hit := Maze.intersect(current.p, direction)
	hit.room = current.room
	hit.up = current.gravityUp
	return hit

func mark(maze: FoldMaze, hit: Dictionary) -> bool:
	if hit.face < 0 or maze.rooms[hit.room].links[hit.face] != null:
		last_slot = -1
		return false
	var slot: int = maze.rooms[hit.room].markers[hit.face]
	if slot < 0:
		if marks.size() >= 128:
			return false
		slot = marks.size()
		maze.rooms[hit.room].markers[hit.face] = slot
		var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		marks.append(image)
	var point := Maze.face_uv(hit.point, hit.face) * 127.0
	var previous := last_marker if last_slot == slot else point
	var count := maxi(1, ceili(previous.distance_to(point) * 2.0))
	var image: Image = marks[slot]
	for step in range(count + 1):
		var p := previous.lerp(point, float(step) / count)
		for x in range(maxi(0, floori(p.x - 2)), mini(127, ceili(p.x + 2)) + 1):
			for y in range(maxi(0, floori(p.y - 2)), mini(127, ceili(p.y + 2)) + 1):
				var distance := Vector2(x, y).distance_to(p)
				if distance <= 2:
					image.set_pixel(x, y, Color("f4f09c") if distance <= 1 else Color("20251b"))
	marks_image.blit_rect(image, Rect2i(0, 0, 128, 128), Vector2i((slot % 16) * 128, (slot / 16) * 128))
	marks_texture.update(marks_image)
	last_slot = slot
	last_marker = point
	return true

func export_marks() -> Array:
	var result := []
	for image in marks:
		result.append("data:image/png;base64," + Marshalls.raw_to_base64(image.save_png_to_buffer()))
	return result

func load_marks(values: Array) -> void:
	marks.clear()
	marks_image.fill(Color.TRANSPARENT)
	for value in values:
		var image := Image.new()
		var result := image.load_png_from_buffer(Marshalls.base64_to_raw(value.substr(22)))
		assert(result == OK, "State importer must validate mark PNGs")
		image.convert(Image.FORMAT_RGBA8)
		var slot := marks.size()
		marks.append(image)
		marks_image.blit_rect(image, Rect2i(0, 0, 128, 128), Vector2i((slot % 16) * 128, (slot / 16) * 128))
	marks_texture.update(marks_image)
	last_slot = -1

extends "res://tests/zoom_tube_seam.gd"

const Maze = preload("res://scripts/maze.gd")

func fixture_path() -> String:
	return "res://tests/fixtures/zoom-straight-taper.json"

func verify_geometry(renderer: FoldRenderer, state: Dictionary) -> bool:
	var maze: FoldMaze = state.maze
	var player: Dictionary = state.player
	var queries := Image.create(64, 32, false, Image.FORMAT_RGBAF)
	var negative_width := 1.0 / maxf(1.0, maze.passage_ratio(player.room, 5, player.zoomScale))
	var positive_width := 1.0 / maxf(1.0, maze.passage_ratio(player.room, 4, player.zoomScale))
	for index in range(64 * 32):
		var t := (int(index / 12) % 31) / 30.0
		var angle := TAU * (index % 12) / 12.0
		var width := lerpf(negative_width, positive_width, Maze.smooth_taper(t))
		var center: Vector3 = -player.up * Maze.TUBE_RADIUS * (1.0 - width)
		var radial: Vector3 = (player.up * cos(angle) + Vector3.RIGHT * sin(angle)) * Maze.TUBE_RADIUS * width
		var radius_factor: float = [0.9, 1.0, 1.1][int(index / (31 * 12)) % 3]
		var p: Vector3 = Vector3(0, 0, lerpf(-Maze.HALF, Maze.HALF, t)) + center + radial * radius_factor
		var gap := maze.tube_clearance(player.room, p, player.up, player.zoomScale)
		queries.set_pixel(index % 64, int(index / 64), Color(p.x, p.y, p.z, gap))
	var shader := Shader.new()
	shader.code = renderer.material_ray.shader.code.get_slice("void fragment(){", 0) + """
uniform sampler2D surface_queries : filter_nearest, repeat_disable;
void fragment(){
 vec4 query=texelFetch(surface_queries,ivec2(UV*vec2(64.,32.)),0);
 vec4 shape=texelFetch(room_shapes,ivec2(roomId%1024,roomId/1024),0);
 vec3 positiveRatio,negativeRatio;
 for(int axis=0;axis<3;axis++){
  positiveRatio[axis]=passageRatio(roomId,axis*2,actor_scale);
  negativeRatio[axis]=passageRatio(roomId,axis*2+1,actor_scale);
 }
 float gap=deformedTubeClearance(roomId,query.xyz,gravityUp,shape,positiveRatio,negativeRatio);
 bool valid=!isnan(gap)&&!isinf(gap)&&abs(gap-query.a)<.00002;
 COLOR=valid?vec4(0.,1.,0.,1.):vec4(1.,0.,1.,1.);
}
"""
	renderer.material_ray.shader = shader
	renderer.material_ray.set_shader_parameter("surface_queries", ImageTexture.create_from_image(queries))
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var invalid := 0
	for x in range(image.get_width()):
		for y in range(image.get_height()):
			if image.get_pixel(x, y).g < 0.95:
				invalid += 1
	print("STRAIGHT TAPER CPU/GPU: 2048 queries, mismatched pixels=", invalid)
	return invalid == 0

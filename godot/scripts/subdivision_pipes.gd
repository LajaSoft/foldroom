class_name SubdivisionPipes
extends RefCounted

# A subdivided symbol is affine in its six mouth widths. Those seven stencil
# channels are shared by CPU contacts and GPU ray intersections.
const RADIUS := 1.65
# Two passes on a regular eight-point circular control ring.
const ROUND_SHRINK := 0.9084708691207961
const LEVELS := 2
const LEAF_SIZE := 4
const NODE_STRIDE := 15
const NORMALS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
const GRID := [-3.9, -3.3, -3.0, -2.4, -RADIUS, 0.0, RADIUS, 2.4, 3.0, 3.3, 3.9]
static var symbols := {}
static var topology_builds := 0
static var profile_builds := 0

static func add_features(a: PackedVector4Array, b: PackedVector4Array, factor: float = 1.0) -> PackedVector4Array:
	var result := a.duplicate()
	for channel in range(7):
		result[channel] += b[channel] * factor
	return result

static func scaled(a: PackedVector4Array, factor: float) -> PackedVector4Array:
	var result := a.duplicate()
	for channel in range(7):
		result[channel] *= factor
	return result

static func average(indices: Array, vertices: Array) -> PackedVector4Array:
	var result := PackedVector4Array()
	result.resize(7)
	for index in indices:
		result = add_features(result, vertices[index], 1.0 / indices.size())
	return result

static func occupied(p: Vector3, mask: int, corners: int) -> bool:
	if p.abs()[p.abs().max_axis_index()] < RADIUS:
		return true
	for face in range(6):
		if not mask & (1 << face):
			continue
		var axis := int(face / 2)
		if p.dot(NORMALS[face]) > 0 and absf(p[(axis + 1) % 3]) < RADIUS and absf(p[(axis + 2) % 3]) < RADIUS:
			return true
	for octant in range(8):
		if not corners & (1 << (12 + octant)):
			continue
		var direction := Vector3(1 if octant & 1 == 0 else -1, 1 if octant & 2 == 0 else -1, 1 if octant & 4 == 0 else -1)
		if p.x * direction.x > 0 and p.y * direction.y > 0 and p.z * direction.z > 0:
			return true
	var bit := 0
	for a in range(6):
		for b in range((int(a / 2) + 1) * 2, 6):
			if corners & (1 << bit) and p.dot(NORMALS[a]) > 0 and p.dot(NORMALS[b]) > 0 and absf(p[3 - int(a / 2) - int(b / 2)]) < RADIUS:
				return true
			bit += 1
	return false

static func circular_position(p: Vector3, mask: int, corners: int) -> Vector3:
	if corners != 0:
		return p
	var axis := -1
	for candidate in range(3):
		if mask == (3 << (candidate * 2)):
			axis = candidate
	if axis < 0:
		var candidate := p.abs().max_axis_index()
		if absf(p[candidate]) > RADIUS + 0.00001:
			axis = candidate
	if axis < 0:
		return p
	var transverse := p
	transverse[axis] = 0.0
	assert(transverse.length_squared() > 0.0, "Tube cages contain perimeter vertices")
	transverse = transverse.normalized() * (RADIUS / ROUND_SHRINK)
	transverse[axis] = p[axis]
	return transverse

static func features(cage_position: Vector3, mask: int, corners: int) -> PackedVector4Array:
	var p := circular_position(cage_position, mask, corners)
	var result := PackedVector4Array([Vector4(p.x, p.y, p.z, 0)])
	var weights := PackedFloat32Array([0, 0, 0, 0, 0, 0])
	var straight_axis := -1
	for axis in range(3):
		if mask == (3 << (axis * 2)):
			straight_axis = axis
	if straight_axis >= 0:
		var t := clampf((cage_position[straight_axis] + RADIUS) / (2.0 * RADIUS), 0.0, 1.0)
		t = t * t * t * (10.0 + t * (-15.0 + 6.0 * t))
		weights[straight_axis * 2] = t
		weights[straight_axis * 2 + 1] = 1.0 - t
	if straight_axis < 0:
		var total := 0.0
		var exterior := cage_position.abs()[cage_position.abs().max_axis_index()] > RADIUS + 0.00001
		for face in range(6):
			if mask & (1 << face):
				weights[face] = maxf(0.0, cage_position.dot(NORMALS[face]) - (RADIUS if exterior else 0.0))
				total += weights[face]
		if total > 0:
			for face in range(6):
				weights[face] /= total
	for face in range(6):
		var transverse: Vector3 = p - NORMALS[face] * p.dot(NORMALS[face])
		result.append(Vector4(transverse.x, transverse.y, transverse.z, 1.0) * weights[face])
	return result

static func cage(mask: int, corners: int) -> Dictionary:
	var filled := {}
	var size := GRID.size() - 1
	for z in range(size):
		for y in range(size):
			for x in range(size):
				var p := Vector3((GRID[x] + GRID[x + 1]) * 0.5, (GRID[y] + GRID[y + 1]) * 0.5, (GRID[z] + GRID[z + 1]) * 0.5)
				if occupied(p, mask, corners):
					filled[Vector3i(x, y, z)] = true
	var indices := {}
	var vertices := []
	var faces := []
	for cell: Vector3i in filled:
		for face in range(6):
			var axis := int(face / 2)
			var sign_value := 1 if face % 2 == 0 else -1
			var neighbor := cell + Vector3i(NORMALS[face])
			if filled.has(neighbor):
				continue
			# Ghost collars end beyond the logical cell, not in visible caps.
			if neighbor[axis] < 0 or neighbor[axis] >= size:
				continue
			var polygon := []
			for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var key := cell
				key[axis] += 1 if sign_value > 0 else 0
				key[(axis + 1) % 3] += offset.x
				key[(axis + 2) % 3] += offset.y
				if not indices.has(key):
					indices[key] = vertices.size()
					vertices.append(features(Vector3(GRID[key.x], GRID[key.y], GRID[key.z]), mask, corners))
				polygon.append(indices[key])
			if sign_value < 0:
				polygon.reverse()
			faces.append(polygon)
	return {"vertices": vertices, "faces": faces}

static func subdivide(mesh: Dictionary) -> Dictionary:
	var vertices: Array = mesh.vertices
	var faces: Array = mesh.faces
	var edges := {}
	var vertex_faces := []
	var vertex_edges := []
	var face_points := []
	for index in range(vertices.size()):
		vertex_faces.append([])
		vertex_edges.append([])
	for face_index in range(faces.size()):
		var face: Array = faces[face_index]
		face_points.append(average(face, vertices))
		for index in range(face.size()):
			var a: int = face[index]
			var b: int = face[(index + 1) % face.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if not edges.has(key):
				edges[key] = {"faces": [], "index": -1}
				vertex_edges[a].append(key)
				vertex_edges[b].append(key)
			edges[key].faces.append(face_index)
			vertex_faces[a].append(face_index)
	var result := []
	for index in range(vertices.size()):
		var boundary := []
		var edge_midpoints := []
		for key: Vector2i in vertex_edges[index]:
			edge_midpoints.append(scaled(add_features(vertices[key.x], vertices[key.y]), 0.5))
			if edges[key].faces.size() == 1:
				boundary.append(key.y if key.x == index else key.x)
		if boundary.size() == 2:
			result.append(add_features(scaled(vertices[index], 0.75), scaled(add_features(vertices[boundary[0]], vertices[boundary[1]]), 0.125)))
			continue
		assert(boundary.is_empty(), "Subdivision cages must be manifold")
		var face_average := average(vertex_faces[index], face_points)
		var midpoint_indices := range(edge_midpoints.size())
		var edge_average := average(midpoint_indices, edge_midpoints)
		var n: float = vertex_edges[index].size()
		result.append(scaled(add_features(add_features(face_average, edge_average, 2.0), vertices[index], n - 3.0), 1.0 / n))
	for key: Vector2i in edges:
		var edge: Dictionary = edges[key]
		var point := add_features(vertices[key.x], vertices[key.y])
		if edge.faces.size() == 2:
			for face_index in edge.faces:
				point = add_features(point, face_points[face_index])
		edge.index = result.size()
		result.append(scaled(point, 0.25 if edge.faces.size() == 2 else 0.5))
	var face_base := result.size()
	result.append_array(face_points)
	var quads := []
	for face_index in range(faces.size()):
		var face: Array = faces[face_index]
		for index in range(face.size()):
			var a: int = face[index]
			var b: int = face[(index + 1) % face.size()]
			var c: int = face[(index + face.size() - 1) % face.size()]
			quads.append([a, edges[Vector2i(mini(a, b), maxi(a, b))].index, face_base + face_index, edges[Vector2i(mini(a, c), maxi(a, c))].index])
	return {"vertices": result, "faces": quads}

static func triangle_vertices(triangle: Vector3i) -> Array:
	return [triangle.x, triangle.y, triangle.z]

static func base_position(feature: PackedVector4Array) -> Vector3:
	return Vector3(feature[0].x, feature[0].y, feature[0].z)

static func build_node(symbol: Dictionary, triangle_ids: Array) -> int:
	var index: int = symbol.nodes.size()
	var minimum := Vector3(INF, INF, INF)
	var maximum := -minimum
	var displacement := 0.0
	var coefficient_min := []
	var coefficient_max := []
	for channel in range(6):
		coefficient_min.append(Vector4(INF, INF, INF, INF))
		coefficient_max.append(Vector4(-INF, -INF, -INF, -INF))
	var centers := {}
	for id in triangle_ids:
		var center := Vector3.ZERO
		for vertex in triangle_vertices(symbol.triangles[id]):
			var feature: PackedVector4Array = symbol.vertices[vertex]
			var p := base_position(feature)
			minimum = minimum.min(p)
			maximum = maximum.max(p)
			center += p / 3.0
			var bound := 0.0
			for channel in range(1, 7):
				var c := feature[channel]
				for component in range(4):
					coefficient_min[channel - 1][component] = minf(coefficient_min[channel - 1][component], c[component])
					coefficient_max[channel - 1][component] = maxf(coefficient_max[channel - 1][component], c[component])
				bound += Vector3(c.x, c.y, c.z).length() + RADIUS * absf(c.w)
			displacement = maxf(displacement, bound)
		centers[id] = center
	var node := {"min": minimum, "max": maximum, "coefficient_min": coefficient_min, "coefficient_max": coefficient_max, "displacement": displacement, "escape": -1, "start": -1, "count": 0}
	symbol.nodes.append(node)
	if triangle_ids.size() <= LEAF_SIZE:
		node.start = symbol.ordered.size()
		node.count = triangle_ids.size()
		symbol.ordered.append_array(triangle_ids)
		node.escape = symbol.nodes.size()
		return index
	var axis := (maximum - minimum).max_axis_index()
	triangle_ids.sort_custom(func(a, b): return centers[a][axis] < centers[b][axis])
	var middle := int(triangle_ids.size() / 2)
	build_node(symbol, triangle_ids.slice(0, middle))
	build_node(symbol, triangle_ids.slice(middle))
	node.escape = symbol.nodes.size()
	return index

static func symbol(mask: int, corners: int) -> Dictionary:
	var key := Vector2i(mask, corners)
	if symbols.has(key):
		return symbols[key]
	var mesh := cage(mask, corners)
	for level in range(LEVELS):
		mesh = subdivide(mesh)
	var triangles := []
	for face: Array in mesh.faces:
		triangles.append(Vector3i(face[0], face[1], face[2]))
		triangles.append(Vector3i(face[0], face[2], face[3]))
	var normals := PackedVector3Array()
	normals.resize(mesh.vertices.size())
	for triangle: Vector3i in triangles:
		var a := base_position(mesh.vertices[triangle.x])
		var b := base_position(mesh.vertices[triangle.y])
		var c := base_position(mesh.vertices[triangle.z])
		var normal := (b - a).cross(c - a)
		for vertex in [triangle.x, triangle.y, triangle.z]:
			normals[vertex] += normal
	for index in range(normals.size()):
		normals[index] = normals[index].normalized()
	var result := {"key": key, "vertices": mesh.vertices, "triangles": triangles, "normals": normals, "nodes": [], "ordered": [], "gpu_root": -1}
	build_node(result, range(triangles.size()))
	symbols[key] = result
	topology_builds += 1
	return result

static func position(feature: PackedVector4Array, widths: PackedFloat32Array, up: Vector3) -> Vector3:
	var p := base_position(feature)
	for face in range(6):
		var delta := widths[face] - 1.0
		if is_zero_approx(delta):
			continue
		var c := feature[face + 1]
		var projected: Vector3 = up - NORMALS[face] * up.dot(NORMALS[face])
		p += delta * (Vector3(c.x, c.y, c.z) + projected * RADIUS * c.w)
	return p

static func profile(base: Dictionary, widths: PackedFloat32Array, up: Vector3) -> Dictionary:
	var vertices := PackedVector3Array()
	for feature: PackedVector4Array in base.vertices:
		vertices.append(position(feature, widths, up))
	var minimum := []
	var maximum := []
	minimum.resize(base.nodes.size())
	maximum.resize(base.nodes.size())
	for index in range(base.nodes.size() - 1, -1, -1):
		var node: Dictionary = base.nodes[index]
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		if node.count > 0:
			for slot in range(node.start, node.start + node.count):
				for vertex in triangle_vertices(base.triangles[base.ordered[slot]]):
					lo = lo.min(vertices[vertex])
					hi = hi.max(vertices[vertex])
		if node.count == 0:
			var left := index + 1
			var right: int = base.nodes[left].escape
			lo = minimum[left].min(minimum[right])
			hi = maximum[left].max(maximum[right])
		minimum[index] = lo
		maximum[index] = hi
	profile_builds += 1
	return {"symbol": base, "vertices": vertices, "min": minimum, "max": maximum, "samples": {}}

static func closest_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * d1 / (d1 - d3)
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * d2 / (d2 - d6)
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and d4 - d3 >= 0.0 and d5 - d6 >= 0.0:
		return b + (c - b) * (d4 - d3) / (d4 - d3 + d5 - d6)
	var inverse := 1.0 / (va + vb + vc)
	return a + ab * vb * inverse + ac * vc * inverse

static func sample(surface: Dictionary, p: Vector3) -> Dictionary:
	if surface.samples.has(p):
		return surface.samples[p]
	var best := INF
	var closest := Vector3.ZERO
	var normal := Vector3.UP
	var normal_sum := Vector3.ZERO
	var normal_score := INF
	var straight_axis := -1
	for axis in range(3):
		if surface.symbol.key.x == (3 << (axis * 2)):
			straight_axis = axis
	var symbol_data: Dictionary = surface.symbol
	var pending: Array[int] = [0]
	while not pending.is_empty():
		var index: int = pending.pop_back()
		var node: Dictionary = symbol_data.nodes[index]
		var nearest: Vector3 = p.clamp(surface.min[index], surface.max[index])
		if p.distance_squared_to(nearest) > best + maxf(0.0000000001, best * 0.00001):
			continue
		if node.count > 0:
			for slot in range(node.start, node.start + node.count):
				var triangle: Vector3i = symbol_data.triangles[symbol_data.ordered[slot]]
				var a: Vector3 = surface.vertices[triangle.x]
				var b: Vector3 = surface.vertices[triangle.y]
				var c: Vector3 = surface.vertices[triangle.z]
				var point := closest_triangle(p, a, b, c)
				var distance := p.distance_squared_to(point)
				var tolerance := maxf(0.0000000001, best * 0.00001)
				if distance > best + tolerance:
					continue
				var candidate := (b - a).cross(c - a).normalized()
				var score := absf(candidate[straight_axis]) if straight_axis >= 0 else 0.0
				if not is_finite(best) or distance < best - tolerance:
					best = distance
					closest = point
					normal = candidate
					normal_sum = candidate
					normal_score = score
					continue
				best = minf(best, distance)
				# At a shared edge, both supporting facets contribute. Prefer
				# longitudinally tangent supports to avoid diagonal-triangle bias.
				if score < normal_score - 0.000001:
					normal_sum = candidate
					normal_score = score
					continue
				if absf(score - normal_score) <= 0.000001:
					normal_sum += candidate
		if node.count == 0:
			var left := index + 1
			var right: int = symbol_data.nodes[left].escape
			var left_distance := p.distance_squared_to(p.clamp(surface.min[left], surface.max[left]))
			var right_distance := p.distance_squared_to(p.clamp(surface.min[right], surface.max[right]))
			if left_distance < right_distance:
				pending.append(right)
				pending.append(left)
			if left_distance >= right_distance:
				pending.append(left)
				pending.append(right)
	assert(is_finite(best), "A subdivision symbol must have a surface")
	if normal_sum.length_squared() > 0.0000000001:
		normal = normal_sum.normalized()
	var gap := sqrt(best)
	if (p - closest).dot(normal) > 0.0:
		gap = -gap
	var result := {"clearance": gap, "normal": normal, "gradientLength": 1.0}
	result.make_read_only()
	if surface.samples.size() >= 128:
		surface.samples.clear()
	surface.samples[p] = result
	return result

static func texture(records: Array) -> ImageTexture:
	var height := maxi(1, ceili(records.size() / 1024.0))
	var values := PackedFloat32Array()
	values.resize(1024 * height * 4)
	for index in range(records.size()):
		var record: Vector4 = records[index]
		for channel in range(4):
			values[index * 4 + channel] = record[channel]
	return ImageTexture.create_from_image(Image.create_from_data(1024, height, false, Image.FORMAT_RGBAF, values.to_byte_array()))

static func gpu_data(bases: Array) -> Dictionary:
	var vertices := []
	var triangles := []
	var nodes := []
	var roots := {}
	for base: Dictionary in bases:
		var vertex_base := int(vertices.size() / 8)
		var triangle_base := triangles.size()
		var node_base := int(nodes.size() / NODE_STRIDE)
		roots[base.key] = node_base
		for index in range(base.vertices.size()):
			vertices.append_array(Array(base.vertices[index]))
			var normal: Vector3 = base.normals[index]
			vertices.append(Vector4(normal.x, normal.y, normal.z, 0))
		for id in base.ordered:
			var t: Vector3i = base.triangles[id]
			triangles.append(Vector4(t.x + vertex_base, t.y + vertex_base, t.z + vertex_base, 0))
		for node: Dictionary in base.nodes:
			nodes.append(Vector4(node.min.x, node.min.y, node.min.z, node.displacement))
			nodes.append(Vector4(node.max.x, node.max.y, node.max.z, 0))
			nodes.append(Vector4(node.escape + node_base, node.start + triangle_base, node.count, 0))
			for channel in range(6):
				nodes.append(node.coefficient_min[channel])
				nodes.append(node.coefficient_max[channel])
	return {"vertices": texture(vertices), "triangles": texture(triangles), "nodes": texture(nodes), "roots": roots}

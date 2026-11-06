class_name FoldMaze
extends RefCounted

const HALF := 3.0
const MAX_ROOMS := 10000
const NORMALS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
const Pipes = preload("res://scripts/pipe_catalog.gd")
const Subdivision = preload("res://scripts/subdivision_pipes.gd")
const TUBE_RADIUS := Pipes.RADIUS
const MIN_ZOOM := 0.2
const MAX_ZOOM := 4.5
class ExactMemo extends RefCounted:
	var values := {}
	var slots: Array = []
	var cursor := 0
	var capacity: int

	func _init(limit: int) -> void:
		capacity = limit

	func has(key: Variant) -> bool:
		return values.has(key)

	func fetch(key: Variant) -> Variant:
		return values[key]

	func size() -> int:
		return values.size()

	func put(key: Variant, value: Variant) -> void:
		if values.has(key):
			values[key] = value
			return
		if slots.size() < capacity:
			slots.append(key)
		else:
			values.erase(slots[cursor])
			slots[cursor] = key
			cursor = (cursor + 1) % capacity
		values[key] = value

const GEOMETRY_PROFILE_LIMIT := 64
const FIELD_CACHE_LIMIT := 128
const SAMPLE_CACHE_LIMIT := 64
const SPHERE_CACHE_LIMIT := 16
var geometry_memo_enabled := true
var geometry_profiles := {}
var box_profiles := {}
var geometry_cache_revision := -1
var geometry_cache_coefficient := -1.0
var geometry_last_room := -1
var geometry_last_up := Vector3.ZERO
var geometry_last_scale := 0.0
var geometry_last_profile := {}
var geometry_cache_hits := 0
var geometry_cache_misses := 0
var geometry_sample_hits := 0
var geometry_sphere_hits := 0
var geometry_profile_builds := 0
var zoom_coefficient := 1.1
var tubes := false
var subdivision_tubes := false
var subdivision_profiles := {}
var subdivision_corners_cache := {}
var subdivision_revision := -1
var subdivision_coefficient := -1.0
var topology_revision := 0
var pipe_revision := -1
var pipe_masks := PackedByteArray()
var zoom_masks := PackedByteArray()
var geometry_signatures: Array[Vector3i] = []
var hall_corners := PackedInt32Array()
var rooms: Array = []
var cells: Dictionary = {}
var walls: Dictionary = {}
var next_link := 1
var last_error := ""
var impacts: Array = []
var player_rotation := Quaternion.IDENTITY
# Only the latest exact sphere query is retained; memory does not grow with travel.
var sphere_sample_mask := -1
var sphere_sample_corners := -1
var sphere_sample_position := Vector3.ZERO
var sphere_sample_radius := 0.0
var sphere_sample_result: Dictionary = {}

func _init() -> void:
	room(Vector3i.ZERO)

static func face_of(v: Vector3) -> int:
	var best := 0
	for i in range(1, 6):
		if NORMALS[i].dot(v) > NORMALS[best].dot(v):
			best = i
	return best

static func rotation_between(a: Vector3, b: Vector3) -> Quaternion:
	if a.dot(b) > 0.999:
		return Quaternion.IDENTITY
	var axis := a.cross(b)
	return Quaternion(axis.x * sqrt(0.5), axis.y * sqrt(0.5), axis.z * sqrt(0.5), sqrt(0.5))

func room(cell: Vector3i) -> Dictionary:
	if cells.has(cell):
		return rooms[cells[cell]]
	if rooms.size() >= MAX_ROOMS:
		last_error = "Room limit reached: 10,000"
		return {}
	var value := {"id": rooms.size(), "cell": cell, "links": [null, null, null, null, null, null], "markers": [-1, -1, -1, -1, -1, -1]}
	cells[cell] = value.id
	rooms.append(value)
	topology_revision += 1
	return value

static func cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]

static func boundary_key(cell: Vector3i, face: int) -> String:
	var pair := [cell_key(cell), cell_key(cell + Vector3i(NORMALS[face]))]
	pair.sort()
	return "|".join(pair)

func thin_walls() -> Dictionary:
	var result := {}
	# A zoom mouth needs a closed perimeter on both ends. Evaluate directly
	# from links: edits call this before the topology cache is invalidated.
	for source in rooms:
		var corners := open_hall_corners(source.id)
		var bit := 0
		for a in range(6):
			for b in range((int(a / 2) + 1) * 2, 6):
				if corners & (1 << bit):
					for face in [a, b]:
						var link = source.links[face]
						if link != null and link.get("zoom", 0) != 0:
							result["zoom-corner:%d:%d:%d" % [source.id, a, b]] = true
				bit += 1
	for source in rooms:
		for face in range(6):
			var link = source.links[face]
			if link == null or link.kind == "straight":
				continue
			var direction: Vector3i = rooms[link.target].cell - source.cell
			if Vector3(direction).dot(NORMALS[face]) != 0:
				continue
			var opposite: Vector3i = source.cell + Vector3i(NORMALS[face])
			if cells.has(opposite) and rooms[cells[opposite]].links[face ^ 1] == null:
				result[boundary_key(source.cell, face)] = true
	# Two folded mouths can expose the same empty diagonal through an
	# ordinary L-shaped approach, even though neither has a room opposite.
	# Crossing that edge then selects unrelated transported room frames.
	for source in rooms:
		for a in range(6):
			var first := straight_neighbor(source.id, a)
			if first < 0:
				continue
			for b in range((int(a / 2) + 1) * 2, 6):
				var second := straight_neighbor(source.id, b)
				if second < 0:
					continue
				var first_fold = rooms[first].links[b]
				var second_fold = rooms[second].links[a]
				if first_fold == null or second_fold == null:
					continue
				if first_fold.kind == "straight" or second_fold.kind == "straight":
					continue
				var edges := [boundary_key(rooms[first].cell, b), boundary_key(rooms[second].cell, a)]
				edges.sort()
				result["corner:" + " / ".join(edges)] = true
	# Validate transported position and orientation around every complete
	# lattice square, including squares with several folded passages.
	for source in rooms:
		for a in range(6):
			for b in range((int(a / 2) + 1) * 2, 6):
				var current: int = source.id
				var position := Vector3.ZERO
				var rotation := Quaternion.IDENTITY
				var square: Array[String] = []
				for direction in [a, b, a ^ 1, b ^ 1]:
					var face := lattice_face(current, direction)
					if face < 0:
						break
					square.append(cell_key(rooms[current].cell))
					var link: Dictionary = rooms[current].links[face]
					position = link.q * (position - NORMALS[face] * HALF) + NORMALS[link.face] * HALF
					rotation = link.q * rotation
					current = link.target
				if square.size() != 4:
					continue
				if position.length_squared() < 0.000001 and absf(rotation.w) > 0.99999:
					continue
				square.sort()
				result["folded-loop:" + " / ".join(square)] = true
	return result

# A neighboring cell may be reached through a rotated portal mouth.
func lattice_face(room_id: int, direction: int) -> int:
	var cell: Vector3i = rooms[room_id].cell + Vector3i(NORMALS[direction])
	if not cells.has(cell):
		return -1
	for face in range(6):
		var link = rooms[room_id].links[face]
		if link != null and link.target == cells[cell]:
			return face
	return -1

func introduces_thin_wall(previous: Dictionary) -> bool:
	for key in thin_walls():
		if not previous.has(key):
			return true
	return false

func create(room_id: int, face: int, kind: String, up: Vector3) -> Dictionary:
	last_error = ""
	if face < 0 or face > 5 or room_id < 0 or room_id >= rooms.size():
		last_error = "Invalid passage endpoint"
		return {}
	var source: Dictionary = rooms[room_id]
	if source.links[face] != null:
		last_error = "A passage already exists here · Delete removes it"
		return {}
	var n: Vector3 = NORMALS[face]
	if absf(n.dot(up)) > 0.01:
		last_error = "Choose a side wall"
		return {}
	var key := boundary_key(source.cell, face)
	if kind == "straight" and walls.has(key):
		last_error = "This side only allows an upward or downward passage"
		return {}
	var direction := n if kind == "straight" else up * (1.0 if kind == "up" else -1.0)
	var cell: Vector3i = source.cell + Vector3i(direction)
	var target_face := face_of(-direction)
	if cells.has(cell) and rooms[cells[cell]].links[target_face] != null:
		last_error = "Another passage occupies the exit"
		return {}
	var target_key := boundary_key(cell, target_face)
	if kind == "straight" and walls.has(target_key):
		last_error = "This wall already contains a folded passage"
		return {}
	var previous := thin_walls()
	var previous_count := rooms.size()
	var target := room(cell)
	if target.is_empty():
		return {}
	var q := rotation_between(n, direction)
	var keys := [key]
	if target_key != key:
		keys.append(target_key)
	var link := {"id": next_link, "target": target.id, "face": target_face, "q": q, "kind": kind, "keys": keys}
	source.links[face] = link
	target.links[target_face] = {"id": next_link, "target": room_id, "face": face, "q": q.inverse(), "kind": kind, "keys": keys}
	if introduces_thin_wall(previous):
		source.links[face] = null
		target.links[target_face] = null
		if rooms.size() > previous_count:
			rooms.pop_back()
			cells.erase(cell)
		last_error = "Passages cannot leave a folded or zoom corner exposed"
		return {}
	topology_revision += 1
	next_link += 1
	for wall in keys:
		walls[wall] = walls.get(wall, 0) + 1
	return link

func remove(room_id: int, face: int) -> bool:
	last_error = ""
	if face < 0 or face > 5:
		return false
	var link = rooms[room_id].links[face]
	if link == null:
		return false
	var previous := thin_walls()
	var reverse = rooms[link.target].links[link.face]
	rooms[link.target].links[link.face] = null
	rooms[room_id].links[face] = null
	if introduces_thin_wall(previous):
		rooms[room_id].links[face] = link
		rooms[link.target].links[link.face] = reverse
		last_error = "Closing this passage would leave a folded corner open on one side"
		return false
	topology_revision += 1
	for key in link.keys:
		walls[key] -= 1
		if walls[key] == 0:
			walls.erase(key)
	return true

func prune(anchor: int, actors: Array = []) -> Dictionary:
	topology_revision += 1
	var reachable := {anchor: true}
	var queue := [anchor]
	var cursor := 0
	while cursor < queue.size():
		for link in rooms[queue[cursor]].links:
			if link == null or reachable.has(link.target):
				continue
			reachable[link.target] = true
			queue.append(link.target)
		cursor += 1
	var retained: Array = rooms.filter(func(value): return reachable.has(value.id))
	var ids := {}
	for index in range(retained.size()):
		ids[retained[index].id] = index
	var offset: Vector3i = retained[0].cell
	var removed := rooms.size() - retained.size()
	rooms = retained
	cells.clear()
	walls.clear()
	impacts.clear()
	for value in rooms:
		value.id = ids[value.id]
		value.cell -= offset
		cells[value.cell] = value.id
	for value in rooms:
		for link in value.links:
			if link != null:
				link.target = ids[link.target]
	var seen := {}
	for value in rooms:
		for face in range(6):
			var link = value.links[face]
			if link == null:
				continue
			var key := boundary_key(value.cell, face)
			var target_key := boundary_key(rooms[link.target].cell, link.face)
			link.keys = [key] if key == target_key else [key, target_key]
			if seen.has(link.id):
				continue
			seen[link.id] = true
			for wall in link.keys:
				walls[wall] = walls.get(wall, 0) + 1
	var surviving: Array = actors.filter(func(actor): return ids.has(actor.room))
	for actor in surviving:
		actor.room = ids[actor.room]
	return {"removed": removed, "actors": surviving}

func transport(room_id: int, face: int, p: Vector3, vectors: Array = []) -> Dictionary:
	var link: Dictionary = rooms[room_id].links[face]
	var rotated: Array = []
	for v in vectors:
		rotated.append(link.q * v)
	return {"room": link.target, "p": link.q * (p - NORMALS[face] * HALF) + NORMALS[link.face] * HALF, "vectors": rotated}

# Scale is actor history, never a property shared by all visits to a room.
func passage_ratio(room_id: int, face: int, scale_value: float = 1.0) -> float:
	var link = rooms[room_id].links[face]
	if link == null:
		return 1.0
	return clampf(scale_value * pow(zoom_coefficient, link.get("zoom", 0)), MIN_ZOOM, MAX_ZOOM) / scale_value

func adjust_zoom(room_id: int, face: int, delta: int) -> bool:
	last_error = ""
	var link = rooms[room_id].links[face]
	if link == null:
		last_error = "Aim at an existing passage"
		return false
	var previous := thin_walls()
	var old_zoom: int = link.get("zoom", 0)
	var reverse: Dictionary = rooms[link.target].links[link.face]
	var old_reverse_zoom: int = reverse.get("zoom", 0)
	link.zoom = clampi(old_zoom + delta, -1, 1)
	reverse.zoom = -link.zoom
	if introduces_thin_wall(previous):
		link.zoom = old_zoom
		reverse.zoom = old_reverse_zoom
		last_error = "Zoom passages cannot have an open corner"
		return false
	topology_revision += 1
	return true

func zoom_anchor(face: int, up: Vector3) -> Vector3:
	var transverse: Vector3 = up - NORMALS[face] * up.dot(NORMALS[face])
	return -transverse * (TUBE_RADIUS if tubes else HALF)

func zoom_transport(room_id: int, face: int, p: Vector3, up: Vector3, scale_value: float) -> Dictionary:
	var ratio := passage_ratio(room_id, face, scale_value)
	var link: Dictionary = rooms[room_id].links[face]
	var offset: Vector3 = p - NORMALS[face] * HALF
	var mapped: Vector3 = zoom_anchor(face, up) + (offset - zoom_anchor(face, up)) * ratio
	return {"room": link.target, "p": link.q * mapped + NORMALS[link.face] * HALF, "ratio": ratio}

# Intersect all active mouth constraints. Selecting the dominant axis creates
# discontinuous walls where two coordinates exchange order near a corner.
func local_zoom_clearance(room_id: int, p: Vector3, up: Vector3, scale_value: float) -> float:
	var gap := 100.0
	var radius := HALF
	for face in range(6):
		var along: float = p.dot(NORMALS[face])
		var ratio := passage_ratio(room_id, face, scale_value)
		if ratio <= 1.000001 or along <= 1.5:
			continue
		var width := lerpf(1.0, 1.0 / ratio, clampf((along - 1.5) / 1.5, 0, 1))
		var anchor := zoom_anchor(face, up)
		var center := anchor * (1.0 - width)
		var taper := (1.0 - 1.0 / ratio) / 1.5
		for axis in range(3):
			if axis == int(face / 2):
				continue
			var upper_slope: float = (radius - anchor[axis]) * taper
			var lower_slope: float = (-radius - anchor[axis]) * taper
			gap = minf(gap, (center[axis] + radius * width - p[axis]) / sqrt(1.0 + upper_slope * upper_slope))
			gap = minf(gap, (p[axis] - center[axis] + radius * width) / sqrt(1.0 + lower_slope * lower_slope))
	return gap

# A portal section belongs to both rooms. Reflect the neighbor's fitting into
# the approach, so a cut caused by its perpendicular exit also has a front wall.
func zoom_clearance(room_id: int, p: Vector3, up: Vector3, scale_value: float) -> float:
	var gap := local_zoom_clearance(room_id, p, up, scale_value)
	var face := face_of(p)
	var along: float = p.dot(NORMALS[face])
	var link = rooms[room_id].links[face]
	if along > 1.5 and link != null:
		var moved := zoom_transport(room_id, face, p, up, scale_value)
		var normal: Vector3 = NORMALS[link.face]
		var mirrored: Vector3 = moved.p - normal * 2.0 * (moved.p.dot(normal) - HALF)
		var neighbor_up: Vector3 = link.q * up
		var neighbor_scale := clampf(scale_value * moved.ratio, MIN_ZOOM, MAX_ZOOM)
		gap = minf(gap, local_zoom_clearance(link.target, mirrored, neighbor_up, neighbor_scale) / moved.ratio)
		for plane: Plane in box_wall_planes(link.target, neighbor_up, neighbor_scale):
			gap = minf(gap, -plane.distance_to(mirrored) / moved.ratio)
	for plane: Plane in box_wall_planes(room_id, up, scale_value):
		gap = minf(gap, -plane.distance_to(p))
	return gap

# Bounds of a wall edge at a mouth, in that room's coordinates.
func local_mouth_bound(room_id: int, mouth: int, wall: int, up: Vector3, scale_value: float) -> float:
	var ratio := passage_ratio(room_id, mouth, scale_value)
	var bound := HALF
	if ratio > 1.000001:
		bound = HALF / ratio + NORMALS[wall].dot(zoom_anchor(mouth, up)) * (1.0 - 1.0 / ratio)
	if passage_ratio(room_id, wall, scale_value) > 1.000001 and HALF - NORMALS[mouth].dot(zoom_anchor(wall, up)) > 0.000001:
		bound = minf(bound, 1.5)
	return bound

func shared_mouth_bound(room_id: int, mouth: int, wall: int, up: Vector3, scale_value: float, propagated: bool = true) -> float:
	var bound := local_mouth_bound(room_id, mouth, wall, up, scale_value)
	var link = rooms[room_id].links[mouth]
	if link == null:
		return bound
	var ratio := passage_ratio(room_id, mouth, scale_value)
	var neighbor_wall := face_of(link.q * NORMALS[wall])
	var neighbor_bound := local_mouth_bound(link.target, link.face, neighbor_wall, link.q * up, clampf(scale_value * ratio, MIN_ZOOM, MAX_ZOOM))
	var shift: float = NORMALS[wall].dot(zoom_anchor(mouth, up)) * (1.0 - ratio)
	bound = minf(bound, (neighbor_bound - shift) / ratio)
	if not propagated:
		return bound
	var neighbor_up: Vector3 = link.q * up
	var neighbor_scale := clampf(scale_value * ratio, MIN_ZOOM, MAX_ZOOM)
	for plane: Plane in box_wall_planes(link.target, neighbor_up, neighbor_scale, false, neighbor_wall):
		var rate := plane.normal.dot(NORMALS[neighbor_wall])
		if rate <= 0.000001:
			continue
		var cross_axis := 3 - int(neighbor_wall / 2) - int(link.face / 2)
		var edge := (plane.d - plane.normal.dot(NORMALS[link.face] * HALF) - absf(plane.normal[cross_axis]) * HALF) / rate
		bound = minf(bound, (edge - shift) / ratio)
	return bound

# A closed wall connects its two end sections as one plane, not a cube wall
# followed by a bevel. In a horizontal slice these are trapezoid edges.
func box_wall_planes(room_id: int, up: Vector3, scale_value: float, propagated: bool = true, wall_filter: int = -1) -> Array:
	ensure_geometry_cache()
	var key := [room_id, up, scale_value, propagated, wall_filter]
	if box_profiles.has(key):
		return box_profiles[key]
	var planes := []
	for wall in range(6):
		if wall_filter >= 0 and wall != wall_filter:
			continue
		if rooms[room_id].links[wall] != null:
			continue
		for axis in range(3):
			if axis == int(wall / 2):
				continue
			var plane := box_wall_plane(room_id, wall, axis, up, scale_value, propagated)
			if plane.normal.length_squared() > 0.5:
				planes.append(plane)
	planes.make_read_only()
	remember(box_profiles, key, planes, GEOMETRY_PROFILE_LIMIT)
	return planes

func box_wall_plane(room_id: int, wall: int, axis: int, up: Vector3, scale_value: float, propagated: bool = true) -> Plane:
	var positive := shared_mouth_bound(room_id, axis * 2, wall, up, scale_value, propagated)
	var negative := shared_mouth_bound(room_id, axis * 2 + 1, wall, up, scale_value, propagated)
	var own_positive := local_mouth_bound(room_id, axis * 2, wall, up, scale_value)
	var own_negative := local_mouth_bound(room_id, axis * 2 + 1, wall, up, scale_value)
	if positive >= own_positive - 0.000001 and negative >= own_negative - 0.000001:
		return Plane()
	if minf(positive, negative) >= HALF - 0.000001:
		return Plane()
	var slope := (negative - positive) / (2.0 * HALF)
	var normal: Vector3 = NORMALS[wall] + NORMALS[axis * 2] * slope
	return Plane(normal.normalized(), (positive + negative) * 0.5 / normal.length())

func constrain_zoom(actor: Dictionary) -> void:
	var radius: float = actor.get("radius", 0.32)
	for iteration in range(8):
		var gap := zoom_clearance(actor.room, actor.p, actor.up, actor.get("zoomScale", 1.0))
		if gap >= radius - 0.00001:
			return
		var gradient := Vector3.ZERO
		for axis in range(3):
			var offset := Vector3.ZERO
			offset[axis] = 0.001
			gradient[axis] = (zoom_clearance(actor.room, actor.p + offset, actor.up, actor.get("zoomScale", 1.0)) - zoom_clearance(actor.room, actor.p - offset, actor.up, actor.get("zoomScale", 1.0))) / 0.002
		if gradient.length_squared() < 0.000001:
			return
		var normal := gradient.normalized()
		actor.p += normal * (radius - gap + 0.001)
		var inward: float = actor.velocity.dot(normal)
		if inward < 0:
			actor.velocity -= normal * inward

func passage_count() -> int:
	var count := 0
	for r in rooms:
		for link in r.links:
			if link != null:
				count += 1
	return count / 2

static func intersect(p: Vector3, direction: Vector3) -> Dictionary:
	var distance := INF
	var face := -1
	for axis in range(3):
		if absf(direction[axis]) < 1e-8:
			continue
		var sign_value := 1.0 if direction[axis] > 0.0 else -1.0
		var t := (sign_value * HALF - p[axis]) / direction[axis]
		if t >= -1e-6 and t < distance:
			distance = maxf(0.0, t)
			face = axis * 2 + int(sign_value < 0)
	return {"distance": distance, "face": face, "point": p + direction * distance}

static func face_uv(p: Vector3, face: int) -> Vector2:
	if face < 2:
		return Vector2(p.z, p.y) / 6.0 + Vector2.ONE * 0.5
	if face < 4:
		return Vector2(p.x, p.z) / 6.0 + Vector2.ONE * 0.5
	return Vector2(p.x, p.y) / 6.0 + Vector2.ONE * 0.5

# The local six-face mask selects one of ten prebuilt fitting families.
# Portal targets, kinds and rotations do not participate in surface evaluation.
func tube_shape_mask(room_id: int) -> int:
	if pipe_revision != topology_revision:
		pipe_masks.resize(rooms.size())
		zoom_masks.resize(rooms.size())
		geometry_signatures.resize(rooms.size())
		hall_corners.resize(rooms.size())
		for source in rooms:
			var mask := 0
			var zoom_mask := 0
			var growing_mask := 0
			for face in range(6):
				if source.links[face] != null:
					mask |= 1 << face
					if source.links[face].get("zoom", 0) != 0:
						zoom_mask |= 1 << face
					if source.links[face].get("zoom", 0) > 0:
						growing_mask |= 1 << face
			pipe_masks[source.id] = mask
			zoom_masks[source.id] = zoom_mask
			hall_corners[source.id] = open_hall_corners(source.id)
			geometry_signatures[source.id] = Vector3i(mask, hall_corners[source.id], growing_mask)
		pipe_revision = topology_revision
	return pipe_masks[room_id]

# Only a complete square of ordinary passages can erase its shared column.
# Folded mouths never establish physical adjacency in the lattice.
func straight_neighbor(room_id: int, face: int) -> int:
	var source: Dictionary = rooms[room_id]
	var link = source.links[face]
	if link == null or link.kind != "straight" or link.face != (face ^ 1):
		return -1
	if rooms[link.target].cell != source.cell + Vector3i(NORMALS[face]):
		return -1
	return link.target

func open_hall_corners(room_id: int) -> int:
	var result := 0
	var bit := 0
	for a in range(6):
		for b in range((int(a / 2) + 1) * 2, 6):
			var first := straight_neighbor(room_id, a)
			var second := straight_neighbor(room_id, b)
			if first >= 0 and second >= 0:
				var diagonal := straight_neighbor(first, b)
				if diagonal >= 0 and diagonal == straight_neighbor(second, a):
					result |= 1 << bit
			bit += 1
	return result

func tube_corner_mask(room_id: int) -> int:
	tube_shape_mask(room_id)
	return hall_corners[room_id]

static func smooth_taper(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * t * (t * (6.0 * t - 15.0) + 10.0)

func room_has_zoom(room_id: int) -> bool:
	tube_shape_mask(room_id)
	return zoom_masks[room_id] != 0

# Exact FIFO memo tables have hard bounds; no spatial rounding changes the wall.
static func remember(cache: Dictionary, key: Variant, value: Variant, limit: int) -> void:
	if cache.size() >= limit and not cache.has(key):
		cache.erase(cache.keys()[0])
	cache[key] = value

func ensure_geometry_cache() -> void:
	if geometry_cache_revision != topology_revision or geometry_cache_coefficient != zoom_coefficient:
		geometry_profiles.clear()
		geometry_last_profile = {}
		geometry_cache_revision = topology_revision
		geometry_cache_coefficient = zoom_coefficient
		box_profiles.clear()

func geometry_profile(room_id: int, up: Vector3, scale_value: float) -> Dictionary:
	ensure_geometry_cache()
	if not geometry_last_profile.is_empty() and geometry_last_room == room_id and geometry_last_up == up and geometry_last_scale == scale_value:
		return geometry_last_profile
	tube_shape_mask(room_id)
	var signature := geometry_signatures[room_id]
	var ratio := clampf(scale_value * zoom_coefficient, MIN_ZOOM, MAX_ZOOM) / scale_value
	var key := [signature, up, ratio]
	if geometry_profiles.has(key):
		geometry_last_profile = geometry_profiles[key]
	if not geometry_profiles.has(key):
		var warps := []
		if ratio > 1.000001:
			for face in range(6):
				if signature.z & (1 << face):
					warps.append({"normal": NORMALS[face], "axis": int(face / 2), "factor": 1.0 / ratio, "anchor": zoom_anchor(face, up)})
		var straight_axis := -1
		for axis in range(3):
			if signature.x == (3 << (axis * 2)) and signature.y == 0:
				straight_axis = axis
		var profile := {"warps": warps, "straight_axis": straight_axis, "fields": ExactMemo.new(FIELD_CACHE_LIMIT), "samples": ExactMemo.new(SAMPLE_CACHE_LIMIT), "spheres": ExactMemo.new(SPHERE_CACHE_LIMIT)}
		remember(geometry_profiles, key, profile, GEOMETRY_PROFILE_LIMIT)
		geometry_profile_builds += 1
		geometry_last_profile = profile
	geometry_last_room = room_id
	geometry_last_up = up
	geometry_last_scale = scale_value
	return geometry_last_profile

# One prepared deformation is shared by equivalent rooms and all actors.
static func deform_tube(profile: Dictionary, p: Vector3) -> Vector4:
	var mapped := p
	var metric := 1.0
	if profile.straight_axis >= 0 and not profile.warps.is_empty():
		var axis: int = profile.straight_axis
		var negative_width := 1.0
		var positive_width := 1.0
		for warp: Dictionary in profile.warps:
			if warp.normal[axis] > 0:
				positive_width = warp.factor
			if warp.normal[axis] < 0:
				negative_width = warp.factor
		var width := lerpf(negative_width, positive_width, smooth_taper((p[axis] + HALF) / (2.0 * HALF)))
		var anchor: Vector3 = profile.warps[0].anchor
		var axial := Vector3.ZERO
		axial[axis] = p[axis]
		mapped = axial + anchor + (p - axial - anchor) / width
		metric = width / (1.0 + 4.0 * TUBE_RADIUS * (1.0 - minf(negative_width, positive_width)))
		return Vector4(mapped.x, mapped.y, mapped.z, metric)
	for warp: Dictionary in profile.warps:
		var weight := smooth_taper((p.dot(warp.normal) - 1.5) / 1.5)
		for axis in range(3):
			if axis != warp.axis:
				weight *= 1.0 - smooth_taper((absf(p[axis]) - TUBE_RADIUS) / (HALF - TUBE_RADIUS))
		if weight <= 0.0:
			continue
		var width := lerpf(1.0, warp.factor, weight)
		var axial: Vector3 = warp.normal * mapped.dot(warp.normal)
		mapped = axial + warp.anchor + (mapped - axial - warp.anchor) / width
		metric *= width / (1.0 + 4.0 * TUBE_RADIUS * (1.0 - width))
	return Vector4(mapped.x, mapped.y, mapped.z, metric)

func tube_deformation(room_id: int, p: Vector3, up: Vector3, scale_value: float) -> Vector4:
	if not room_has_zoom(room_id):
		return Vector4(p.x, p.y, p.z, 1.0)
	return deform_tube(geometry_profile(room_id, up, scale_value), p)

func tube_clearance(room_id: int, p: Vector3, up: Vector3 = Vector3.UP, scale_value: float = 1.0) -> float:
	if subdivision_tubes:
		return Subdivision.sample(subdivision_profile(room_id, up, scale_value), p).clearance
	if not room_has_zoom(room_id):
		return base_tube_clearance(room_id, p)
	var profile := geometry_profile(room_id, up, scale_value)
	if geometry_memo_enabled and profile.fields.has(p):
		geometry_cache_hits += 1
		return profile.fields.fetch(p)
	geometry_cache_misses += 1
	var query := deform_tube(profile, p)
	var clearance := base_tube_clearance(room_id, Vector3(query.x, query.y, query.z)) * query.w
	if geometry_memo_enabled:
		profile.fields.put(p, clearance)
	return clearance

func base_tube_clearance(room_id: int, p: Vector3) -> float:
	var mask := tube_shape_mask(room_id)
	var clearance := Pipes.analytic_clearance(mask, p) if room_has_zoom(room_id) else Pipes.clearance(mask, p)
	var corners := hall_corners[room_id]
	if corners == 0:
		return clearance
	var bit := 0
	for a in range(6):
		for b in range((int(a / 2) + 1) * 2, 6):
			if corners & (1 << bit):
				var axis := 3 - int(a / 2) - int(b / 2)
				# Dilate the open quadrant, including its approach to the outer
				# wall. A clipped slab leaves the old elbow as a solid fin.
				var offset := Vector3(minf(p.dot(NORMALS[a]), 0.0), minf(p.dot(NORMALS[b]), 0.0), p[axis])
				clearance = maxf(clearance, TUBE_RADIUS - offset.length())
			bit += 1
	return clearance

func rescale_actor(actor: Dictionary, radius: float) -> void:
	if not actor.has("radius") or absf(actor.radius - radius) < 0.00001:
		return
	var factor: float = radius / actor.radius
	var centerline := Pipes.spine(tube_shape_mask(actor.room), actor.p)
	actor.p = centerline + (actor.p - centerline) * factor
	actor.velocity *= factor
	actor.radius = radius

func tube_sample(room_id: int, p: Vector3, up: Vector3 = Vector3.UP, scale_value: float = 1.0) -> Dictionary:
	if subdivision_tubes:
		return Subdivision.sample(subdivision_profile(room_id, up, scale_value), p)
	var profile := geometry_profile(room_id, up, scale_value) if room_has_zoom(room_id) else {}
	if geometry_memo_enabled and not profile.is_empty() and profile.samples.has(p):
		geometry_sample_hits += 1
		return profile.samples.fetch(p)
	var gradient := Vector3.ZERO
	for axis in range(3):
		var offset := Vector3.ZERO
		offset[axis] = 0.015
		gradient[axis] = (tube_clearance(room_id, p - offset, up, scale_value) - tube_clearance(room_id, p + offset, up, scale_value)) / 0.03
	var result := {"clearance": tube_clearance(room_id, p, up, scale_value), "normal": gradient.normalized(), "gradientLength": gradient.length()}

	result.make_read_only()
	if geometry_memo_enabled and not profile.is_empty():
		profile.samples.put(p, result)
	return result

# The fillet field is not an exact signed distance. Test the sphere's support
# against the actual surface instead of treating center clearance as its radius.
func tube_sphere_sample(room_id: int, p: Vector3, radius: float, up: Vector3 = Vector3.UP, scale_value: float = 1.0) -> Dictionary:
	if subdivision_tubes:
		return tube_sample(room_id, p, up, scale_value)
	var mask := tube_shape_mask(room_id)
	var corners := hall_corners[room_id]
	var cacheable := not room_has_zoom(room_id)
	var profile := {} if cacheable else geometry_profile(room_id, up, scale_value)
	var key := [p, radius]
	if geometry_memo_enabled and not profile.is_empty() and profile.spheres.has(key):
		geometry_sphere_hits += 1
		return profile.spheres.fetch(key)
	if cacheable and mask == sphere_sample_mask and corners == sphere_sample_corners and p == sphere_sample_position and radius == sphere_sample_radius:
		return sphere_sample_result
	var center := tube_sample(room_id, p, up, scale_value)
	var direction: Vector3 = center.normal
	var gap := tube_clearance(room_id, p + direction * radius, up, scale_value)
	for axis in NORMALS:
		var candidate := tube_clearance(room_id, p + axis * radius, up, scale_value)
		if candidate < gap:
			gap = candidate
			direction = axis
	for iteration in range(5):
		var surface := tube_sample(room_id, p + direction * radius, up, scale_value)
		var next: Vector3 = (direction + surface.normal).normalized()
		var candidate := tube_clearance(room_id, p + next * radius, up, scale_value)
		if candidate >= gap:
			break
		gap = candidate
		direction = next
	var normal := tube_sample(room_id, p + direction * radius, up, scale_value)
	sphere_sample_mask = mask if cacheable else -1
	sphere_sample_corners = corners
	sphere_sample_position = p
	sphere_sample_radius = radius
	if not cacheable:
		gap /= maxf(normal.gradientLength, 0.000001)
	sphere_sample_result = {"clearance": radius + gap, "normal": normal.normal}
	sphere_sample_result.make_read_only()
	if geometry_memo_enabled and not profile.is_empty():
		profile.spheres.put(key, sphere_sample_result)
	return sphere_sample_result

func constrain_actor(actor: Dictionary) -> void:
	if not tubes:
		constrain_zoom(actor)
		return
	rescale_actor(actor, Pipes.BALL_RADIUS * actor.get("zoomScale", 1.0))
	# Walk clearance encloses the body and the raised eye.
	var radius: float = actor.get("radius", 1.0)
	for iteration in range(8):
		var sample := tube_sphere_sample(actor.room, actor.p, radius, actor.up, actor.get("zoomScale", 1.0))
		if sample.clearance >= radius + 0.001:
			return
		actor.p -= sample.normal * (radius + 0.002 - sample.clearance)
		var outward: float = actor.velocity.dot(sample.normal)
		if outward > 0:
			actor.velocity -= sample.normal * outward

func set_tubes(enabled: bool, actors: Array) -> void:
	tubes = enabled
	for actor in actors:
		rescale_actor(actor, (Pipes.BALL_RADIUS if enabled else 0.5) * actor.get("zoomScale", 1.0))
		for axis in range(3):
			var face := axis * 2 + int(actor.p[axis] < 0)
			if rooms[actor.room].links[face] == null:
				actor.p[axis] = clampf(actor.p[axis], -HALF + actor.get("radius", 1.0), HALF - actor.get("radius", 1.0))
		constrain_actor(actor)
	impacts.clear()

func ensure_subdivision_cache() -> void:
	if subdivision_revision != topology_revision or subdivision_coefficient != zoom_coefficient:
		subdivision_profiles.clear()
		subdivision_corners_cache.clear()
		subdivision_revision = topology_revision
		subdivision_coefficient = zoom_coefficient

func subdivision_profile(room_id: int, up: Vector3, scale_value: float) -> Dictionary:
	ensure_subdivision_cache()
	var mask := tube_shape_mask(room_id)
	var corners := subdivision_corners(room_id)
	var widths := PackedFloat32Array()
	for face in range(6):
		widths.append(1.0 / maxf(1.0, passage_ratio(room_id, face, scale_value)))
	var key := [mask, corners, up, widths]
	if not subdivision_profiles.has(key):
		remember(subdivision_profiles, key, Subdivision.profile(Subdivision.symbol(mask, corners), widths, up), 128)
	return subdivision_profiles[key]

func prepare_subdivision() -> Array:
	ensure_subdivision_cache()
	var bases := {}
	for source in rooms:
		var mask := tube_shape_mask(source.id)
		var corners := subdivision_corners(source.id)
		var key := Vector2i(mask, corners)
		if bases.has(key):
			continue
		bases[key] = Subdivision.symbol(mask, corners)
		for up: Vector3 in NORMALS:
			subdivision_profile(source.id, up, 1.0)
	return bases.values()

func subdivision_corners(room_id: int) -> int:
	ensure_subdivision_cache()
	if subdivision_corners_cache.has(room_id):
		return subdivision_corners_cache[room_id]
	var result := tube_corner_mask(room_id)
	for octant in range(8):
		var directions := [int(octant & 1), 2 + int((octant >> 1) & 1), 4 + int((octant >> 2) & 1)]
		var members := {0: room_id}
		var complete := true
		for subset in range(8):
			if not members.has(subset):
				complete = false
				break
			for axis in range(3):
				if subset & (1 << axis):
					continue
				var target := straight_neighbor(members[subset], directions[axis])
				var next := subset | (1 << axis)
				if target < 0 or (members.has(next) and members[next] != target):
					complete = false
					break
				members[next] = target
			if not complete:
				break
		if complete:
			result |= 1 << (12 + octant)
	subdivision_corners_cache[room_id] = result
	return result

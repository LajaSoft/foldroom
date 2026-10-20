class_name FoldState
extends RefCounted

const Maze = preload("res://scripts/maze.gd")
const Motion = preload("res://scripts/motion.gd")
var error := ""

static func encode(value: Variant) -> Variant:
	if value is Vector3 or value is Vector3i:
		return [value.x, value.y, value.z]
	if value is Quaternion:
		return [value.x, value.y, value.z, value.w]
	if value is Array:
		var items: Array = []
		for item in value:
			items.append(encode(item))
		return items
	if value is Dictionary:
		var result := {}
		for key in value:
			result[key] = encode(value[key])
		return result
	return value

static func export_json(maze: FoldMaze, player: Dictionary, balls: Array, marks: Array) -> String:
	var passages := []
	var seen := {}
	var rooms := []
	for room in maze.rooms:
		rooms.append({"cell": room.cell, "markers": room.markers})
		for face in range(6):
			var link = room.links[face]
			if link == null or seen.has(link.id):
				continue
			seen[link.id] = true
			passages.append({"a": [room.id, face], "b": [link.target, link.face], "kind": link.kind})
	return JSON.stringify(encode({"format": "foldroom", "version": 1, "geometry": "tubes" if maze.tubes else "rooms", "rooms": rooms, "passages": passages, "player": player, "balls": balls, "marks": marks}), "  ")

func reject(message: String) -> Dictionary:
	error = message
	return {}

static func valid_vector(value: Variant, size: int, limit: float = 1000000.0) -> bool:
	if not value is Array or value.size() != size:
		return false
	for number in value:
		if not (number is float or number is int) or not is_finite(float(number)) or absf(float(number)) > limit:
			return false
	return true

static func vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])

static func unit(value: Variant) -> bool:
	return valid_vector(value, 3) and absf(vec(value).length() - 1.0) < 1e-5

static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) == floor(float(value)) and value >= minimum and value <= maximum

static func endpoint(value: Variant, room_count: int) -> bool:
	return value is Array and value.size() == 2 and integer(value[0], 0, room_count - 1) and integer(value[1], 0, 5)

func actor(source: Variant, count: int, ball: bool, controlled: bool = false) -> Dictionary:
	if not source is Dictionary or not integer(source.get("room"), 0, count - 1) or not unit(source.get("up")):
		return reject("Invalid actor room or gravity")
	var up := vec(source.up)
	if up.distance_to(Maze.NORMALS[Maze.face_of(up)]) > 1e-6:
		return reject("Gravity must align with a room axis")
	var position_ok := valid_vector(source.get("p"), 3, 3.6)
	var velocity_ok := valid_vector(source.get("velocity"), 3) and vec(source.velocity).length() <= Motion.MAX_SPEED
	if controlled and (not position_ok or not velocity_ok):
		return reject("Invalid player position or velocity")
	var result := {"room": int(source.room), "p": vec(source.p) if position_ok else up * -2.49, "up": up, "velocity": vec(source.velocity) if position_ok and velocity_ok else Vector3.ZERO}
	if ball:
		if not source.get("radius") in [0.5, Maze.Pipes.BALL_RADIUS] or not unit(source.get("motorAxis")) or not valid_vector(source.get("spin"), 4):
			return reject("Invalid ball")
		var spin := Quaternion(source.spin[0], source.spin[1], source.spin[2], source.spin[3])
		if absf(spin.length() - 1.0) > 1e-5:
			return reject("Invalid ball orientation")
		var omega_ok := valid_vector(source.get("omega"), 3) and vec(source.omega).length() <= Motion.MAX_SPIN
		result.merge({"radius": float(source.radius), "omega": vec(source.omega) if omega_ok else Vector3.ZERO, "motorAxis": vec(source.motorAxis), "spin": spin})
	if controlled:
		if not unit(source.get("forward")) or absf(vec(source.forward).dot(up)) > 1e-5 or not (source.get("pitch") is float or source.get("pitch") is int) or not is_finite(float(source.pitch)) or absf(source.pitch) > deg_to_rad(89.0) + 1e-6:
			return reject("Invalid player view")
		result.merge({"forward": vec(source.forward), "pitch": float(source.pitch), "mode": "ball" if ball else "walk"})
		if ball:
			if not unit(source.get("cameraForward")) or not unit(source.get("cameraUp")) or absf(vec(source.cameraForward).dot(vec(source.cameraUp))) > 1e-5:
				return reject("Invalid ball camera")
			result.merge({"controlled": true, "cameraForward": vec(source.cameraForward), "cameraUp": vec(source.cameraUp)})
	return result

func import_json(text: String) -> Dictionary:
	error = ""
	if text.length() > 16 * 1024 * 1024:
		return reject("JSON too large: maximum 16 MB")
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return reject("JSON line %d: %s" % [parser.get_error_line(), parser.get_error_message()])
	var data = parser.data
	if not data is Dictionary or data.get("format") != "foldroom" or data.get("version") != 1:
		return reject("A FOLDROOM version 1 export is required")
	if not data.get("rooms") is Array or data.rooms.is_empty() or data.rooms.size() > Maze.MAX_ROOMS:
		return reject("Invalid room list")
	if not data.get("marks") is Array or data.marks.size() > 128:
		return reject("Invalid mark list")
	for mark in data.marks:
		if not mark is String or mark.length() > 100000 or not mark.begins_with("data:image/png;base64,"):
			return reject("Invalid mark image")
		var image := Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(mark.substr(22))) != OK or image.get_width() != 128 or image.get_height() != 128:
			return reject("Mark image must be a 128×128 PNG")
	if not data.get("geometry", "rooms") in ["rooms", "tubes"]:
		return reject("Invalid geometry")
	var maze := Maze.new()
	maze.tubes = data.get("geometry", "rooms") == "tubes"
	for i in range(data.rooms.size()):
		var source = data.rooms[i]
		if not source is Dictionary or not valid_vector(source.get("cell"), 3, 100000):
			return reject("Invalid room coordinates")
		for number in source.cell:
			if number != floor(number):
				return reject("Room coordinates must be integers")
		var cell := Vector3i(vec(source.cell))
		if (i == 0 and cell != Vector3i.ZERO) or (i > 0 and maze.cells.has(cell)):
			return reject("Duplicate room or invalid origin")
		if not source.get("markers") is Array or source.markers.size() != 6:
			return reject("Invalid face marks")
		for slot in source.markers:
			if not integer(slot, -1, data.marks.size() - 1):
				return reject("Invalid face mark slot")
		var room := maze.room(cell)
		room.markers = source.markers.map(func(slot): return int(slot))
	if not data.get("passages") is Array or data.passages.size() > Maze.MAX_ROOMS * 3:
		return reject("Invalid passages")
	var boundary_kinds := {}
	for passage in data.passages:
		if not passage is Dictionary or not endpoint(passage.get("a"), maze.rooms.size()) or not endpoint(passage.get("b"), maze.rooms.size()):
			return reject("Invalid passage endpoint")
		var a := int(passage.a[0])
		var af := int(passage.a[1])
		var b := int(passage.b[0])
		var bf := int(passage.b[1])
		var kind = passage.get("kind")
		if not kind in ["straight", "up", "down"] or a == b or maze.rooms[a].links[af] != null or maze.rooms[b].links[bf] != null:
			return reject("Invalid passage type or occupied face")
		var normal: Vector3 = Maze.NORMALS[af]
		var direction: Vector3 = -Maze.NORMALS[bf]
		if (kind == "straight" and normal != direction) or (kind != "straight" and absf(normal.dot(direction)) > 0.01):
			return reject("Invalid passage rotation")
		var ac: Vector3i = maze.rooms[a].cell
		var bc: Vector3i = maze.rooms[b].cell
		if ac + Vector3i(direction) != bc and bc - Vector3i(normal) != ac:
			return reject("Passage does not match the cubic grid")
		var keys := [Maze.boundary_key(ac, af)]
		var second := Maze.boundary_key(bc, bf)
		if not second in keys:
			keys.append(second)
		for key in keys:
			if boundary_kinds.has(key) and (boundary_kinds[key] == "straight" or kind == "straight"):
				return reject("Straight and folded passages conflict")
			boundary_kinds[key] = kind
			maze.walls[key] = maze.walls.get(key, 0) + 1
		var q := Maze.rotation_between(normal, direction)
		maze.rooms[a].links[af] = {"id": maze.next_link, "target": b, "face": bf, "q": q, "kind": kind, "keys": keys}
		maze.rooms[b].links[bf] = {"id": maze.next_link, "target": a, "face": af, "q": q.inverse(), "kind": kind, "keys": keys}
		maze.next_link += 1
	if not data.get("player") is Dictionary or not data.player.get("mode", "walk") in ["walk", "ball"]:
		return reject("Invalid player mode")
	var player := actor(data.player, maze.rooms.size(), data.player.get("mode") == "ball", true)
	if player.is_empty():
		return {}
	if not data.get("balls") is Array or data.balls.size() > 16:
		return reject("Up to 16 balls are allowed")
	var balls := []
	for source in data.balls:
		var ball := actor(source, maze.rooms.size(), true)
		if ball.is_empty():
			return {}
		balls.append(ball)
	for value in balls + [player]:
		maze.constrain_actor(value)
	return {"maze": maze, "player": player, "balls": balls, "marks": data.marks}

class_name FoldMaze
extends RefCounted

const HALF := 3.0
const MAX_ROOMS := 10000
const NORMALS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
var rooms: Array = []
var cells: Dictionary = {}
var walls: Dictionary = {}
var next_link := 1
var last_error := ""
var impacts: Array = []
var player_rotation := Quaternion.IDENTITY

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
	return value

static func cell_key(cell: Vector3i) -> String:
	return "%d,%d,%d" % [cell.x, cell.y, cell.z]

static func boundary_key(cell: Vector3i, face: int) -> String:
	var pair := [cell_key(cell), cell_key(cell + Vector3i(NORMALS[face]))]
	pair.sort()
	return "|".join(pair)

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
	next_link += 1
	for wall in keys:
		walls[wall] = walls.get(wall, 0) + 1
	return link

func remove(room_id: int, face: int) -> bool:
	var link = rooms[room_id].links[face]
	if link == null:
		return false
	rooms[link.target].links[link.face] = null
	rooms[room_id].links[face] = null
	for key in link.keys:
		walls[key] -= 1
		if walls[key] == 0:
			walls.erase(key)
	return true

func transport(room_id: int, face: int, p: Vector3, vectors: Array = []) -> Dictionary:
	var link: Dictionary = rooms[room_id].links[face]
	var rotated: Array = []
	for v in vectors:
		rotated.append(link.q * v)
	return {"room": link.target, "p": link.q * (p - NORMALS[face] * HALF) + NORMALS[link.face] * HALF, "vectors": rotated}

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

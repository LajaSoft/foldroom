class_name PipeCatalog
extends RefCounted

const RESOLUTION := 49
const EXTENT := 3.6
const RADIUS := 1.65
const BALL_RADIUS := 0.33
const SCALE := 0.66
const ATLAS_COLUMNS := 64
static var samples := PackedFloat32Array()
static var atlas: ImageTexture

static func ensure_loaded() -> void:
	if not samples.is_empty():
		return
	var expected := 64 * RESOLUTION * RESOLUTION * RESOLUTION * 4
	var packed := FileAccess.get_file_as_bytes("res://assets/pipes/catalog.f32.gz")
	var bytes := packed.decompress(expected, FileAccess.COMPRESSION_GZIP)
	assert(bytes.size() == expected, "Pipe catalogue data must match its declared grid")
	samples = bytes.to_float32_array()

static func value(mask: int, x: int, y: int, z: int) -> float:
	return samples[((mask * RESOLUTION + z) * RESOLUTION + y) * RESOLUTION + x]

static func clearance(mask: int, p: Vector3) -> float:
	ensure_loaded()
	var grid := (p + Vector3.ONE * EXTENT) * ((RESOLUTION - 1) / (2.0 * EXTENT))
	grid = grid.clamp(Vector3.ZERO, Vector3.ONE * (RESOLUTION - 1.00001))
	var x := floori(grid.x)
	var y := floori(grid.y)
	var z := floori(grid.z)
	var t := grid - Vector3(x, y, z)
	# Adjacent grid corners share a base index; avoid eight function calls and
	# repeated mask/row arithmetic for every clearance query.
	var base := ((mask * RESOLUTION + z) * RESOLUTION + y) * RESOLUTION + x
	var row := RESOLUTION
	var plane := RESOLUTION * RESOLUTION
	var a := lerpf(samples[base], samples[base + 1], t.x)
	var b := lerpf(samples[base + row], samples[base + row + 1], t.x)
	var c := lerpf(samples[base + plane], samples[base + plane + 1], t.x)
	var d := lerpf(samples[base + plane + row], samples[base + plane + row + 1], t.x)
	return lerpf(lerpf(a, b, t.y), lerpf(c, d, t.y), t.z)

static func texture() -> ImageTexture:
	if atlas != null:
		return atlas
	ensure_loaded()
	var image := Image.create(ATLAS_COLUMNS * RESOLUTION, RESOLUTION * RESOLUTION, false, Image.FORMAT_RF)
	var bytes := samples.to_byte_array()
	var slice_bytes := RESOLUTION * RESOLUTION * 4
	for slice in range(64 * RESOLUTION):
		var tile := Image.create_from_data(RESOLUTION, RESOLUTION, false, Image.FORMAT_RF, bytes.slice(slice * slice_bytes, (slice + 1) * slice_bytes))
		image.blit_rect(tile, Rect2i(0, 0, RESOLUTION, RESOLUTION), Vector2i((slice % ATLAS_COLUMNS) * RESOLUTION, (slice / ATLAS_COLUMNS) * RESOLUTION))
	atlas = ImageTexture.create_from_image(image)
	return atlas

static func spine(mask: int, p: Vector3) -> Vector3:
	var normals := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var faces: Array[int] = []
	for face in range(6):
		if mask & (1 << face):
			faces.append(face)
	var candidates: Array[Vector3] = []
	if faces.size() != 2 or int(faces[0] / 2) == int(faces[1] / 2):
		for face in faces:
			candidates.append(normals[face] * maxf(0, p.dot(normals[face])))
	for first in range(faces.size()):
		for second in range(first + 1, faces.size()):
			var a: Vector3 = normals[faces[first]]
			var b: Vector3 = normals[faces[second]]
			if absf(a.dot(b)) > 0.5:
				continue
			var corner := (a + b) * 3.0
			var offset := p - corner
			var planar := a * minf(offset.dot(a), 0) + b * minf(offset.dot(b), 0)
			var direction := planar.normalized() if planar.length_squared() > 1e-12 else -a
			candidates.append(corner + direction * 3.0)
	var closest := Vector3.ZERO
	var distance := INF
	for candidate in candidates:
		if candidate.distance_squared_to(p) < distance:
			distance = candidate.distance_squared_to(p)
			closest = candidate
	return closest

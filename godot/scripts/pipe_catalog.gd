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
static var analytic_plans := {}
const NORMALS := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]

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

static func bend_distance(p: Vector3, a: Vector3, b: Vector3) -> float:
	var corner := (a + b) * 3.0
	var offset := p - corner
	var planar := a * minf(offset.dot(a), 0.0) + b * minf(offset.dot(b), 0.0)
	var direction := planar.normalized() if planar.length_squared() > 1e-12 else -a
	return p.distance_to(corner + direction * 3.0)

# At most 64 immutable instruction lists, shared by every maze and actor.
static func analytic_plan(mask: int) -> Dictionary:
	if analytic_plans.has(mask):
		return analytic_plans[mask]
	var faces: Array[int] = []
	var axes: Array[Vector3i] = []
	var bends: Array[Vector2i] = []
	for face in range(6):
		if mask & (1 << face):
			faces.append(face)
	for axis in range(3):
		if mask & (3 << (axis * 2)):
			axes.append(Vector3i(axis, mask & (1 << (axis * 2)), mask & (1 << (axis * 2 + 1))))
	if faces.size() >= 3:
		for first in range(faces.size()):
			for second in range(first + 1, faces.size()):
				if int(faces[first] / 2) != int(faces[second] / 2):
					bends.append(Vector2i(faces[first], faces[second]))
	faces.make_read_only()
	axes.make_read_only()
	bends.make_read_only()
	var plan := {"faces": faces, "axes": axes, "bends": bends}
	plan.make_read_only()
	analytic_plans[mask] = plan
	return plan

static func analytic_clearance(mask: int, p: Vector3) -> float:
	var plan := analytic_plan(mask)
	var faces: Array[int] = plan.faces
	if faces.is_empty():
		return RADIUS - p.length()
	if faces.size() == 2 and int(faces[0] / 2) != int(faces[1] / 2):
		return RADIUS - bend_distance(p, NORMALS[faces[0]], NORMALS[faces[1]])
	var distances: Array[float] = []
	for axis: Vector3i in plan.axes:
		var radial := p
		radial[axis.x] = 0.0
		if axis.y == 0:
			radial[axis.x] = maxf(p[axis.x], 0.0)
		if axis.z == 0:
			radial[axis.x] = minf(p[axis.x], 0.0)
		distances.append(radial.length())
	for bend: Vector2i in plan.bends:
		distances.append(bend_distance(p, NORMALS[bend.x], NORMALS[bend.y]))
	var minimum: float = distances.min()
	var total := 0.0
	for distance in distances:
		total += exp((minimum - distance) / 0.07)
	var clearance := RADIUS - minimum + 0.07 * log(total)
	for face in faces:
		var normal: Vector3 = NORMALS[face]
		var along := p.dot(normal)
		var t := clampf((along - 2.1) / 0.9, 0.0, 1.0)
		var weight := t * t * t * (10.0 + t * (-15.0 + 6.0 * t))
		clearance = lerpf(clearance, RADIUS - (p - normal * along).length(), weight)
	return clearance

extends SceneTree
const State = preload("res://scripts/state.gd")
const Maze = preload("res://scripts/maze.gd")

# Compare open/solid membership, not signed-distance magnitudes: the adjacent
# sloped walls have different normals, while their shared section must agree.
static func inspect(maze: FoldMaze, scales: Array = [0.2, 1.0]) -> Dictionary:
	var report := {"checks": 0, "mismatches": 0, "examples": []}
	for room in maze.rooms:
		for face in range(6):
			var link = room.links[face]
			if link == null:
				continue
			for scale_value in scales:
				for up in Maze.NORMALS:
					for u in [-2.9, -2.0, 0.0, 2.0, 2.9]:
						for v in [-2.9, -2.0, 0.0, 2.0, 2.9]:
							var p: Vector3 = Maze.NORMALS[face] * 3.0
							p[(int(face / 2) + 1) % 3] = u
							p[(int(face / 2) + 2) % 3] = v
							var moved := maze.zoom_transport(room.id, face, p, up, scale_value)
							var first := maze.zoom_clearance(room.id, p, up, scale_value)
							var second := maze.zoom_clearance(link.target, moved.p, link.q * up, scale_value * moved.ratio)
							# Outside the destination cube is solid, not a valid local query.
							for axis in range(3):
								if axis != int(link.face / 2) and absf(moved.p[axis]) > 3.0001:
									second = -1.0
							report.checks += 1
							if absf(first) <= 0.0001 or absf(second) <= 0.0001 or (first > 0) == (second > 0):
								continue
							report.mismatches += 1
							if report.examples.size() < 8:
								report.examples.append({"room": room.id, "face": face, "up": up, "scale": scale_value, "p": p, "first": first, "second": second})
	return report

func _initialize() -> void:
	var saved := State.new().import_json(FileAccess.get_file_as_string("res://tests/fixtures/zoom-box-propagated.json"))
	var report := inspect(saved.maze)
	print("BOX AUDIT checks=", report.checks, " mismatches=", report.mismatches, " ", report.examples)
	quit(1 if report.mismatches else 0)

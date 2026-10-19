class_name FoldMotion
extends RefCounted

const Maze = preload("res://scripts/maze.gd")
const HALF := 3.0
const MAX_SPEED := 1200.0
const MAX_SPIN := 48.0

static func initial_player() -> Dictionary:
	return {"room": 0, "p": Vector3(0, -2.5, 1.1), "forward": Vector3(0.18, 0, -1).normalized(), "up": Vector3.UP, "velocity": Vector3.ZERO, "pitch": 0.0, "mode": "ball", "controlled": true, "radius": 0.5, "omega": Vector3.ZERO, "motorAxis": Vector3(0.18, 0, -1).normalized().cross(Vector3.DOWN), "spin": Quaternion.IDENTITY, "cameraForward": Vector3(0.18, 0, -1).normalized(), "cameraUp": Vector3.UP}

static func create_ball(angle: float) -> Dictionary:
	var heading := Vector3(cos(angle), 0, sin(angle))
	return {"room": 0, "p": Vector3(0, -2.49, 0), "radius": 0.5, "up": Vector3.UP, "velocity": heading * 0.8, "omega": Vector3.UP.cross(heading) * 2.4, "motorAxis": Vector3.UP.cross(heading), "spin": Quaternion.IDENTITY}

static func set_mode(player: Dictionary, mode: String) -> void:
	if mode == player.get("mode", "walk"):
		return
	if mode == "ball":
		player.p -= player.up * 0.5
		player.merge({"radius": 0.5, "omega": Vector3.ZERO, "motorAxis": player.up.cross(player.forward).normalized(), "spin": Quaternion.IDENTITY, "controlled": true, "cameraForward": player.forward, "cameraUp": player.up, "pitch": 0.0}, true)
		player.mode = mode
		return
	player.p += player.up * 0.5
	for key in ["radius", "omega", "motorAxis", "spin", "controlled", "cameraForward", "cameraUp"]:
		player.erase(key)
	player.mode = mode

static func brake_vector(value: Vector3, dt: float, soft: float = 800.0, hard: float = MAX_SPEED) -> Vector3:
	if not value.is_finite():
		return Vector3.ZERO
	var speed := value.length()
	if speed <= soft:
		return value
	var limited := minf(speed, hard)
	return value * (soft + (limited - soft) * exp(-6.0 * maxf(0, dt))) / speed

static func limit_motion(ball: Dictionary, dt: float = 0.0) -> void:
	ball.velocity = brake_vector(ball.velocity, dt)
	ball.omega = brake_vector(ball.omega, dt, 24.0, MAX_SPIN)

static func motion_steps(dt: float, velocity: Vector3, extra_speed: float = 0.0) -> int:
	return maxi(1, ceili((minf(MAX_SPEED, velocity.length()) + extra_speed + 8.0 * dt) * dt / 0.2))

static func steer(player: Dictionary, side: float, dt: float) -> void:
	side = clampf(side, -1, 1)
	if absf(side) < 1e-6:
		return
	if player.velocity.length() < 0.12:
		player.cameraForward = (Quaternion(player.cameraUp, -1.8 * side * dt) * player.cameraForward).normalized()
		return
	var screen_right: Vector3 = player.cameraForward.cross(player.cameraUp).normalized()
	var target := screen_right * signf(side)
	var direction: Vector3 = player.velocity.normalized()
	var angle := acos(clampf(direction.dot(target), -1, 1))
	if angle < 1e-8:
		return
	var axis := direction.cross(target)
	if axis.length() < 1e-6:
		axis = player.cameraUp
	var turn := minf(angle, 1.8 * absf(side) * dt)
	var q := Quaternion(axis.normalized(), turn)
	var retention := exp(-0.12 * turn)
	player.velocity = (q * player.velocity) * retention
	player.omega = (q * player.omega) * retention

static func drive(maze: FoldMaze, player: Dictionary, dt: float, forward: float, side: float, boost: float = 1.0) -> void:
	steer(player, side, dt)
	if forward < 0:
		var retention := exp(-3.0 * minf(1, -forward) * dt)
		player.velocity *= retention
		player.omega *= retention
	if forward > 0:
		var impulse: Vector3 = player.cameraForward * (4.0 * boost * dt * minf(1, forward))
		player.velocity += impulse
		player.omega += player.up.cross(impulse) / player.radius
	move_ball(maze, player, dt)

static func smooth_direction(current: Vector3, target: Vector3, dt: float, axis_hint: Vector3) -> Vector3:
	var angle := acos(clampf(current.dot(target), -1, 1))
	if angle < 1e-8:
		return target
	var axis := current.cross(target)
	if axis.length() < 1e-6:
		axis = axis_hint - current * axis_hint.dot(current)
	if axis.length_squared() < 1e-12:
		axis = current.cross(Vector3.RIGHT if absf(current.x) < 0.9 else Vector3.UP)
	var turn := minf(angle * (1.0 - exp(-4.0 * dt)), 2.5 * dt)
	return (Quaternion(axis.normalized(), turn) * current).normalized()

static func update_camera(player: Dictionary, dt: float) -> void:
	var target: Vector3 = player.velocity.normalized() if player.velocity.length() > 0.12 else player.cameraForward
	var forward := smooth_direction(player.cameraForward, target, dt, player.cameraUp)
	var up: Vector3 = player.cameraUp - forward * player.cameraUp.dot(forward)
	if up.length() < 1e-5:
		up = forward.cross(player.forward).cross(forward)
	up = up.normalized()
	var gravity_up: Vector3 = player.up - forward * player.up.dot(forward)
	if gravity_up.length() > 0.15:
		up = smooth_direction(up, gravity_up.normalized(), dt, forward)
	player.cameraForward = forward
	player.cameraUp = (up - forward * up.dot(forward)).normalized()

static func move_ball(maze: FoldMaze, ball: Dictionary, dt: float) -> void:
	dt = clampf(dt, 0, 0.05)
	limit_motion(ball)
	var steps := motion_steps(dt, ball.velocity)
	for i in range(steps):
		step_ball(maze, ball, dt / steps)

static func step_ball(maze: FoldMaze, ball: Dictionary, dt: float) -> void:
	limit_motion(ball)
	var radius: float = ball.radius
	var inertia := 0.4 * radius * radius
	var p: Vector3 = ball.p
	if not p.is_finite() or maxf(absf(p.x), maxf(absf(p.y), absf(p.z))) > HALF + 0.6:
		ball.p = ball.up * -(HALF - radius - 0.01)
		ball.velocity = Vector3.ZERO
	var rolling_omega: Vector3 = ball.omega - ball.up * ball.omega.dot(ball.up)
	var spin_speed := rolling_omega.length()
	var motor_axis: Vector3 = rolling_omega.normalized() if spin_speed > 0.05 else ball.motorAxis
	ball.motorAxis = motor_axis
	ball.omega -= ball.up * ball.omega.dot(ball.up) * minf(1, dt * 0.4)
	var torque := 0.0 if ball.get("controlled", false) else clampf((2.4 - spin_speed) * 0.35, 0, 0.22)
	ball.omega += motor_axis * (torque / inertia * dt)
	ball.velocity -= ball.up * (8.0 * dt)
	limit_motion(ball, dt)
	var next: Vector3 = ball.p + ball.velocity * dt
	for axis in range(3):
		var sign_value := 1.0 if next[axis] >= 0 else -1.0
		var face := axis * 2 + int(sign_value < 0)
		var link = maze.rooms[ball.room].links[face]
		var fits := true
		for other in range(3):
			if other != axis and absf(next[other]) > HALF - radius + 0.002:
				fits = false
		if link != null and fits:
			if absf(next[axis]) >= HALF:
				var vectors: Array = [ball.velocity, ball.up, ball.omega, ball.motorAxis]
				if ball.get("controlled", false):
					maze.player_rotation = link.q * maze.player_rotation
					vectors.append_array([ball.forward, ball.cameraForward, ball.cameraUp])
				var moved := maze.transport(ball.room, face, next, vectors)
				ball.room = moved.room
				ball.p = moved.p
				var names := ["velocity", "up", "omega", "motorAxis", "forward", "cameraForward", "cameraUp"]
				for j in range(moved.vectors.size()):
					ball[names[j]] = moved.vectors[j]
				ball.up = Maze.NORMALS[Maze.face_of(ball.up)]
				ball.spin = (link.q * ball.spin).normalized()
				return
			continue
		if absf(next[axis]) <= HALF - radius:
			continue
		next[axis] = sign_value * (HALF - radius)
		var normal: Vector3 = -Maze.NORMALS[face]
		var normal_speed: float = ball.velocity.dot(normal)
		var is_floor: bool = normal.dot(ball.up) > 0.9
		var restitution := 0.12 if is_floor else 0.86
		var normal_impulse := maxf(0, -normal_speed * (1.0 + restitution))
		ball.velocity += normal * normal_impulse
		if normal_impulse > 0.25:
			maze.impacts.append({"room": ball.room, "p": next, "normal": normal, "impulse": normal_impulse, "controlled": ball.get("controlled", false), "right": ball.get("cameraForward", Vector3.FORWARD).cross(ball.get("cameraUp", Vector3.UP)).normalized()})
		var contact_arm := normal * -radius
		var contact_velocity: Vector3 = ball.velocity + ball.omega.cross(contact_arm)
		var slip := contact_velocity - normal * contact_velocity.dot(normal)
		var slip_speed := slip.length()
		if slip_speed > 1e-8:
			var friction := 0.6 if is_floor else 0.16
			var impulse := slip * (-minf(slip_speed / (1.0 + radius * radius / inertia), friction * normal_impulse) / slip_speed)
			ball.velocity += impulse
			ball.omega += contact_arm.cross(impulse) / inertia
		if is_floor and absf(ball.velocity.dot(normal)) < 0.05:
			ball.velocity -= normal * ball.velocity.dot(normal)
	ball.p = next
	limit_motion(ball)
	var speed: float = ball.omega.length()
	if speed > 1e-8:
		ball.spin = (Quaternion(ball.omega / speed, speed * dt) * ball.spin).normalized()

static func fits_player(player: Dictionary, p: Vector3, face: int) -> bool:
	for axis in range(3):
		if axis == int(face / 2):
			continue
		var extent := 1.0 if absf(player.up[axis]) > 0.5 else 0.32
		if absf(p[axis]) > HALF - extent + 0.02:
			return false
	return true

static func move_player(maze: FoldMaze, player: Dictionary, dt: float, forward: float, side: float, boost: float = 1.0) -> void:
	dt = clampf(dt, 0, 0.05)
	player.velocity = brake_vector(player.velocity, 0)
	var p: Vector3 = player.p
	if not p.is_finite() or maxf(absf(p.x), maxf(absf(p.y), absf(p.z))) > HALF + 0.6:
		player.p = player.up * -2.0
		player.velocity = Vector3.ZERO
	var steps := motion_steps(dt, player.velocity, 2.6 * boost)
	for i in range(steps):
		step_player(maze, player, dt / steps, forward, side, boost)

static func step_player(maze: FoldMaze, player: Dictionary, dt: float, forward: float, side: float, boost: float) -> void:
	var right: Vector3 = player.forward.cross(player.up).normalized()
	var wish: Vector3 = player.forward * forward + right * side
	var walking := wish.normalized() * (2.6 * boost)
	var falling: float = player.velocity.dot(player.up) - 8.0 * dt
	player.velocity = brake_vector(walking + player.up * falling, dt)
	var next: Vector3 = player.p + player.velocity * dt
	for axis in range(3):
		if absf(next[axis]) < 1e-8:
			continue
		var sign_value := 1.0 if next[axis] > 0 else -1.0
		var face := axis * 2 + int(sign_value < 0)
		var link = maze.rooms[player.room].links[face]
		var extent := 1.0 if absf(player.up[axis]) > 0.5 else 0.32
		if link != null and fits_player(player, next, face):
			if absf(next[axis]) >= HALF:
				var result := maze.transport(player.room, face, next, [player.forward, player.up, player.velocity])
				maze.player_rotation = link.q * maze.player_rotation
				player.room = result.room
				player.p = result.p
				player.forward = result.vectors[0]
				player.up = Maze.NORMALS[Maze.face_of(result.vectors[1])]
				player.velocity = result.vectors[2]
				player.forward = (player.forward - player.up * player.forward.dot(player.up)).normalized()
				return
			continue
		if absf(next[axis]) > HALF - extent:
			next[axis] = sign_value * (HALF - extent)
			player.velocity[axis] = 0
	player.p = next

static func resolve_contacts(actors: Array, maze: FoldMaze) -> void:
	for a in range(actors.size()):
		for b in range(a + 1, actors.size()):
			var first: Dictionary = actors[a]
			var second: Dictionary = actors[b]
			if first.room != second.room:
				continue
			var delta: Vector3 = second.p - first.p
			var distance := delta.length()
			var radius: float = first.radius + second.radius
			if distance >= radius:
				continue
			var normal := delta / distance if distance > 1e-8 else Vector3.RIGHT
			var correction := normal * (radius - distance) / 2.0
			first.p -= correction
			second.p += correction
			for actor in [first, second]:
				for axis in range(3):
					var sign_value := 1.0 if actor.p[axis] >= 0 else -1.0
					var face := axis * 2 + int(sign_value < 0)
					if maze.rooms[actor.room].links[face] == null:
						actor.p[axis] = sign_value * minf(absf(actor.p[axis]), HALF - actor.radius)
			var closing: float = (second.velocity - first.velocity).dot(normal)
			if closing >= 0:
				continue
			var impulse := normal * (-closing * 0.93)
			first.velocity -= impulse
			second.velocity += impulse
			limit_motion(first)
			limit_motion(second)
			for pair in [[first, -normal], [second, normal]]:
				var actor: Dictionary = pair[0]
				if actor.get("controlled", false):
					maze.impacts.append({"room": actor.room, "p": actor.p, "normal": pair[1], "impulse": impulse.length(), "controlled": true, "right": actor.cameraForward.cross(actor.cameraUp).normalized()})

static func camera_frame(maze: FoldMaze, player: Dictionary) -> Dictionary:
	var room_id: int = player.room
	var p: Vector3 = player.p
	var forward: Vector3 = player.get("cameraForward", player.forward)
	var up: Vector3 = player.get("cameraUp", player.up)
	if player.mode != "ball":
		p += player.up * 0.65
		for i in range(3):
			var axis := -1
			for j in range(3):
				if absf(p[j]) > HALF + 1e-7:
					axis = j
					break
			if axis < 0:
				break
			var face := axis * 2 + int(p[axis] < 0)
			if maze.rooms[room_id].links[face] == null:
				p[axis] = signf(p[axis]) * (HALF - 0.001)
				continue
			var result := maze.transport(room_id, face, p, [forward, up])
			room_id = result.room
			p = result.p
			forward = result.vectors[0]
			up = result.vectors[1]
	var pitch: float = player.pitch
	return {"room": room_id, "p": p, "forward": forward * cos(pitch) + up * sin(pitch), "up": up * cos(pitch) - forward * sin(pitch), "gravityUp": player.up if player.mode == "ball" else up}

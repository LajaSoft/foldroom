class_name FoldMusic
extends RefCounted

# Sample-clock sequencer: gameplay alters tendencies, phrases commit on bar lines.
const RATE := 22050.0
const OUTPUT_GAIN := 3.0
const MODES := [[0, 2, 3, 5, 7, 9, 10], [0, 2, 3, 5, 7, 8, 10]]
var random := RandomNumberGenerator.new()
var enabled := false
var volume := 0.45
var energy := 0.0
var tension := 0.0
var curiosity := 0.0
var idle_time := 0.0
var bpm := 124.0
var phrase_direction := 1
var phrase_bars_left := 0
var rhythm_masks: Array = []
var phrase_pan := 0.0
var beat := 0.0
var previous_speed := 0.0
var focus := 0.0
var focus_track := 1
var focus_cooldown := 0.0
var layer_gain := [0.62, 0.62, 0.62]
var layer_rate := [1.0, 1.0, 1.0]
var layer_clock := [0.0, 0.0, 0.0]
var layer_step := [0, 0, 0]
var delay := PackedVector2Array()
var delay_cursor := 0
var room := PackedVector2Array()
var room_cursor := 0
var room_damped := Vector2.ZERO
var echo_damped := Vector2.ZERO
const ROOM_TAPS := [507, 816, 1345, 1830] # 23, 37, 61 and 83 ms at RATE.
var pulse := 0.0
var noise := RandomNumberGenerator.new()
var tick := 0
var bar := -1
var degree := 7
var root := 0
var mode := 0
var phrase: Array[int] = []
var history: Array[int] = []
class Voice:
	var frequency: float
	var duration: float
	var age := 0.0
	var phase := 0.0
	var level: float
	var pan: float
	var stereo_gain := Vector2.ONE * 0.7
	var room_send := 0.0
	var instrument: StringName
	var layer: int

var voices: Array[Voice] = []
var gain := 0.0

func _init() -> void:
	random.seed = 94017
	noise.seed = 8137
	delay.resize(int(RATE * 0.34))
	delay.fill(Vector2.ZERO)
	room.resize(2048)
	room.fill(Vector2.ZERO)

func event(kind: StringName, strength: float = 1.0) -> void:
	var amount := clampf(strength, 0.0, 1.0)
	match kind:
		&"impact": tension = minf(1.0, tension + amount * 0.3)
		&"passage": curiosity = minf(1.0, curiosity + amount * 0.25)
		&"release": tension *= 1.0 - amount

func advance(dt: float, speed: float) -> void:
	if not enabled:
		return
	idle_time = idle_time + dt if speed < 1.0 else maxf(0.0, idle_time - dt * 2.0)
	energy = lerpf(energy, clampf(speed / 12.0, 0.0, 1.0), 1.0 - exp(-dt / 0.85))
	focus_cooldown = maxf(0.0, focus_cooldown - dt)
	var acceleration := (speed - previous_speed) / maxf(dt, 0.001)
	previous_speed = speed
	if acceleration > 1.2 and focus_cooldown <= 0.0:
		focus_track = (focus_track + 1) % 3
		focus = 1.0
		focus_cooldown = 4.0
	focus *= exp(-dt / 6.0)
	for layer in range(3):
		var selected := layer == focus_track
		var target_gain := 0.62 + focus * (0.4 if selected else -0.18)
		layer_gain[layer] = lerpf(layer_gain[layer], target_gain, 1.0 - exp(-dt / 0.65))
		var target_rate := 1.0 + focus * (energy * 0.75 - 0.22) if selected else 1.0
		layer_rate[layer] = lerpf(layer_rate[layer], target_rate, 1.0 - exp(-dt / 0.9))
	tension *= exp(-dt / 14.0)
	curiosity *= exp(-dt / 25.0)
	var target := 124.0 + energy * 16.0 - minf(idle_time / 20.0, 1.0) * 6.0
	bpm = lerpf(bpm, target, 1.0 - exp(-dt / 1.5))

func note(deg: int, octave: int = 0) -> float:
	var index := posmod(deg, 7)
	var midi := 45 + int(floor(float(deg) / 7.0)) * 12 + int(MODES[mode][index]) + octave * 12
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

func begin_bar() -> void:
	bar += 1
	if bar % 4 == 0:
		mode = 1 if idle_time > 15.0 else 0
		var choices := [0, 3, 5, 4]
		root = choices[random.randi_range(0, choices.size() - 1)]
	if bar % 16 == 15:
		root = 0
	phrase_bars_left -= 1
	if phrase_bars_left <= 0:
		phrase_bars_left = random.randi_range(3, 7)
		phrase_direction = -1 if random.randf() < 0.5 else 1
		phrase_pan = random.randf_range(-0.05, 0.05)
	var rhythms := [
		[1, 0, 1, 0, 0, 1, 0, 0],
		[1, 1, 0, 0, 1, 0, 1, 0],
		[0, 1, 0, 1, 1, 0, 0, 0],
		[1, 0, 0, 1, 0, 1, 1, 0],
		[1, 0, 0, 0, 1, 0, 0, 0],
	]
	rhythm_masks.clear()
	for layer in range(3):
		rhythm_masks.append(rhythms[random.randi_range(0, rhythms.size() - 1)])
	phrase.clear()
	var previous_movement := 0
	for i in range(8):
		var movement := random.randi_range(-2, 2)
		if random.randf() < 0.2:
			movement = phrase_direction * random.randi_range(2, 3)
		if absi(previous_movement) >= 3:
			movement = -signi(previous_movement)
		var candidate := clampi(degree + movement, 4, 16)
		if i == 3 or i == 7:
			var chord_notes := [root + 7, root + 9, root + 11]
			candidate = chord_notes[0]
			for chord_note in chord_notes:
				if absi(chord_note - degree) < absi(candidate - degree):
					candidate = chord_note
		if history.size() >= 3 and history[-1] == candidate and history[-2] == candidate:
			candidate = clampi(candidate + phrase_direction, 4, 16)
		previous_movement = candidate - degree
		degree = candidate
		phrase.append(degree)
		history.append(degree)
		if history.size() > 64:
			history.pop_front()

func voice(frequency: float, duration: float, level: float, instrument: StringName, pan: float = 0.0, layer: int = -1) -> void:
	if voices.size() >= 48:
		return
	var v := Voice.new()
	v.frequency = frequency
	v.duration = duration
	v.level = level
	v.instrument = instrument
	v.pan = clampf(pan, -1.0, 1.0)
	var angle := (v.pan + 1.0) * PI * 0.25
	v.stereo_gain = Vector2(cos(angle), sin(angle))
	match instrument:
		&"lead": v.room_send = 0.22
		&"pad": v.room_send = 0.55
		&"cymbal": v.room_send = 0.4
		&"hat", &"clap": v.room_send = 0.15
	v.layer = layer
	voices.append(v)

func schedule() -> void:
	var slot := tick % 16
	if slot == 0:
		begin_bar()
		for offset in [7, 9, 11]:
			voice(note(root + offset), 240.0 / bpm, 0.022, &"pad", float(offset - 9) * 0.4)
	if slot % 4 == 0:
		voice(60.0, 0.28, 0.85 * (0.85 + energy * 0.15), &"kick")
		pulse = 1.0
	# Short pickups at the end of four/eight-bar phrases.
	if bar % 4 == 3 and slot == 14:
		voice(60.0, 0.20, 0.55, &"kick")
		pulse = 1.0
	if bar % 8 == 7 and slot == 15:
		voice(65.0, 0.16, 0.45, &"kick")
		pulse = 1.0
	if slot == 0 and bar > 0 and bar % 4 == 0:
		voice(1730.0, 1.25, 0.065, &"cymbal", -0.4 if bar % 8 == 0 else 0.4)
	if slot % 4 == 2:
		var bass_degree := root + 4 if slot == 14 and bar % 3 == 2 else root
		voice(note(bass_degree), 0.18, 0.20, &"bass")
	if slot % 2 == 0:
		voice(0.0, 0.055 if slot % 4 == 0 else 0.13, 0.022 + energy * 0.022, &"hat", 0.3)
	if slot % 8 == 4:
		voice(0.0, 0.15, 0.05 * (0.4 + energy * 0.6), &"clap", -0.2)
	tick += 1

func schedule_layer(layer: int) -> void:
	var index: int = layer_step[layer]
	var position := posmod(index, 8)
	layer_step[layer] += 1
	if int(rhythm_masks[layer][position]) == 0:
		return
	# Each voice answers a different part of the phrase, rather than tracing it together.
	position = posmod(position + layer * 3, 8)
	var duration: float = [1.05, 0.48, 0.26][layer] * random.randf_range(0.85, 1.3)
	var level: float = [0.0454, 0.0378, 0.0252][layer]
	voice(note(phrase[position]), duration, level, &"lead", float([-0.78, 0.16, 0.78][layer]) + phrase_pan, layer)

func render_voice(v: Voice, dt: float) -> float:
	v.age += dt
	var progress := v.age / v.duration
	var attack := 0.012
	if v.instrument == &"pad":
		attack = 0.18
	if v.instrument == &"kick":
		attack = 0.004
	var envelope := smoothstep(0.0, attack, v.age) * smoothstep(0.0, minf(0.12, v.duration * 0.4), v.duration - v.age)
	var frequency := v.frequency
	if v.instrument == &"kick":
		frequency += 125.0 * exp(-v.age * 40.0)
	# Metallic partials have non-integer ratios: keep their phase continuous.
	if v.instrument == &"cymbal":
		v.phase += TAU * frequency * dt
	if v.instrument != &"cymbal":
		v.phase = fmod(v.phase + TAU * frequency * dt, TAU)
	var wave := 0.0
	match v.instrument:
		&"lead":
			# Rounded, slowly evolving subtractive-style harmonics; no noisy FM attack.
			var brightness := 0.2 + 0.22 * energy
			wave = sin(v.phase) + brightness * sin(v.phase * 2.0) + 0.12 * sin(v.phase * 3.0) + 0.06 * sin(v.phase * 4.0)
			wave *= 0.75 + 0.25 * exp(-v.age * 3.0)
		&"pad": wave = sin(v.phase) * 0.75 + sin(v.phase + sin(v.age * 0.7) * 0.08) * 0.25
		&"bass": wave = (sin(v.phase) + sin(v.phase * 2.0) * 0.45 + sin(v.phase * 3.0) * 0.2) * exp(-v.age * 6.0)
		&"kick": wave = (sin(v.phase) + sin(v.phase * 2.0) * 0.38 + sin(v.phase * 3.0) * 0.14) * exp(-v.age * 10.0)
		&"hat": wave = noise.randf_range(-1.0, 1.0) * exp(-progress * 8.0)
		&"cymbal":
			# Inharmonic ring modulation gives an electronic metallic wash.
			wave = (sin(v.phase) * sin(v.phase * 1.414) * 0.55 + sin(v.phase * 2.317) * 0.25 + noise.randf_range(-1.0, 1.0) * 0.2) * exp(-progress * 4.0)
		&"clap": wave = noise.randf_range(-1.0, 1.0) * exp(-progress * 5.0) * (0.6 + 0.4 * sin(v.age * 180.0))
	var level := v.level
	if v.layer >= 0:
		level *= float(layer_gain[v.layer])
	if v.instrument in [&"lead", &"pad"]:
		level *= 1.0 - pulse * 0.65
	if v.instrument == &"bass":
		level *= 1.0 - pulse * 0.25
	return wave * envelope * level

func sample() -> Vector2:
	var dt := 1.0 / RATE
	gain = move_toward(gain, volume if enabled else 0.0, dt * 0.7)
	pulse *= exp(-dt * 10.0)
	if enabled:
		if beat <= 0.0:
			schedule()
			beat += 0.25
		beat -= bpm / 60.0 * dt
		for layer in range(3):
			if layer_clock[layer] <= 0.0:
				schedule_layer(layer)
				layer_clock[layer] += float([2.0, 1.0, 0.5][layer])
			layer_clock[layer] -= bpm / 60.0 * dt * float(layer_rate[layer])
	var output := Vector2.ZERO
	var send := Vector2.ZERO
	var room_input := Vector2.ZERO
	for i in range(voices.size() - 1, -1, -1):
		var v := voices[i]
		if v.age >= v.duration:
			voices.remove_at(i)
			continue
		var value := render_voice(v, dt)
		var stereo := v.stereo_gain * value
		output += stereo
		room_input += stereo * v.room_send
		if v.instrument == &"lead":
			send += stereo * 0.18
	# Unequal positive-polarity reflections create depth without cancelling mono.
	var a := room[posmod(room_cursor - int(ROOM_TAPS[0]), room.size())]
	var b := room[posmod(room_cursor - int(ROOM_TAPS[1]), room.size())]
	var c := room[posmod(room_cursor - int(ROOM_TAPS[2]), room.size())]
	var d := room[posmod(room_cursor - int(ROOM_TAPS[3]), room.size())]
	var reflections := Vector2(a.y * 0.38 + c.x * 0.22, b.x * 0.38 + d.y * 0.22)
	room_damped = room_damped.lerp(reflections, 0.24)
	room[room_cursor] = room_input + room_damped * 0.36
	room_cursor = (room_cursor + 1) % room.size()
	var echo := delay[delay_cursor]
	echo_damped = echo_damped.lerp(echo, 0.18)
	delay[delay_cursor] = send + Vector2(echo_damped.y, echo_damped.x) * 0.32
	delay_cursor = (delay_cursor + 1) % delay.size()
	var ambience := (room_damped + echo_damped) * (1.0 - pulse * 0.35)
	return (output + ambience) * gain * OUTPUT_GAIN

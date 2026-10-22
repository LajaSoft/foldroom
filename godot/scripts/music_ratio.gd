extends "res://scripts/music_conversation.gd"

# Exact rational clocks share one fixed sample time. Speed only changes the mix.
const BASE_BPM := 120.0
const BEAT_FRAMES := 11025
const BAR_FRAMES := BEAT_FRAMES * 4
const NUMERATORS := [1, 1, 1, 1, 1, 1, 1, 1, 2, 3, 4, 5, 6, 7, 8]
const DENOMINATORS := [8, 7, 6, 5, 4, 3, 2, 1, 1, 1, 1, 1, 1, 1, 1]
const GEAR_UP := 32.0
const GEAR_DOWN := 26.0
const MIX_BLEND := 1.0 - exp(-1.0 / (RATE * 0.65))
var master_frame := 0
var gear_frame := 0
var next_lane_frame := 0
var drum_step := 0
var gear := 1
var requested_gear := 1
var mix_targets: Array[float] = []
var lane_steps: Array[int] = []
var lane_due: Array[int] = []
var lane_tapes: Array = []

func _init() -> void:
	super()
	bpm = BASE_BPM
	layer_gain.clear()
	for i in range(NUMERATORS.size()):
		layer_gain.append(0.0)
		mix_targets.append(0.0)
		lane_steps.append(0)
		lane_due.append(0)
		lane_tapes.append([])
	update_mix(0.0)
	layer_gain.assign(mix_targets)

func update_mix(speed: float) -> void:
	var desired_rate := clampf(0.125 + maxf(speed, 0.0) * 0.25 / gear, 0.125, 8.0)
	var position := log(desired_rate) / log(2.0)
	var total := 0.0
	for i in range(mix_targets.size()):
		var center := log(float(NUMERATORS[i]) / DENOMINATORS[i]) / log(2.0)
		var distance := absf(position - center)
		mix_targets[i] = pow(maxf(0.0, 1.0 - distance / 0.85), 2.0)
		total += mix_targets[i]
	for i in range(mix_targets.size()):
		mix_targets[i] /= total

func advance(dt: float, speed: float) -> void:
	if not enabled:
		return
	previous_speed = maxf(speed, 0.0)
	idle_time = idle_time + dt if speed < 1.0 else maxf(0.0, idle_time - dt * 2.0)
	energy = lerpf(energy, clampf(speed / 20.0, 0.0, 1.0), 1.0 - exp(-dt / 0.85))
	tension *= exp(-dt / 14.0)
	curiosity *= exp(-dt / 25.0)
	if speed >= GEAR_UP:
		requested_gear = 2
	if speed <= GEAR_DOWN:
		requested_gear = 1
	update_mix(speed)

func sequence(_dt: float) -> void:
	if master_frame % BAR_FRAMES == 0:
		# Gear changes insert/remove alternate pulses on a base bar boundary.
		gear = requested_gear
		update_mix(previous_speed)
		begin_bar()
		for offset in [7, 9, 11]:
			voice(note(root + offset), 1.9, 0.028, &"pad", float(offset - 9) * 0.38)
		if bar % 8 == 0:
			voice(1730.0, 1.2, 0.06, &"cymbal", 0.4)
	for i in range(layer_gain.size()):
		layer_gain[i] = lerpf(layer_gain[i], mix_targets[i], MIX_BLEND)
	if gear_frame * 4 >= drum_step * BEAT_FRAMES:
		schedule_drums()
	if gear_frame >= next_lane_frame:
		next_lane_frame = 9223372036854775807
		for i in range(lane_steps.size()):
			if gear_frame >= lane_due[i]:
				play_lane(i)
				lane_steps[i] += 1
				# Ceil from the absolute step: no accumulating float rounding drift.
				var numerator: int = lane_steps[i] * BEAT_FRAMES * DENOMINATORS[i]
				lane_due[i] = (numerator + NUMERATORS[i] - 1) / NUMERATORS[i]
			next_lane_frame = mini(next_lane_frame, lane_due[i])
	master_frame += 1
	gear_frame += gear

func schedule_drums() -> void:
	var slot := drum_step % 16
	if slot in [0, 6, 8, 10]:
		voice(62.0, 0.22, 0.62, &"kick")
		pulse = 0.35
	if slot in [4, 12]:
		voice(185.0, 0.19, 0.17, &"snare", -0.12)
	if slot % 2 == 0:
		voice(0.0, 0.055, 0.032, &"hat", 0.4)
		voice(note(root if slot % 4 == 0 else root + 4), 0.15 / gear, 0.16, &"bass")
	drum_step += 1

func play_lane(index: int) -> void:
	var slot := lane_steps[index] % 16
	if slot == 0:
		# A player receives a complete recorded phrase, never half a replacement.
		lane_tapes[index] = parts[index % parts.size()].events.duplicate(true)
	if float(layer_gain[index]) < 0.002:
		return
	for event in lane_tapes[index]:
		if event.slot != slot or event.rest:
			continue
		var pitch: int = event.degree
		if slot % 4 == 0:
			pitch = chord_tone(pitch)
		var rate: float = float(NUMERATORS[index]) / DENOMINATORS[index] * gear
		var duration := clampf(float(event.length) * 0.5 / rate * 0.8, 0.035, 2.8)
		var player := index % PLAYERS.size()
		var pan: float = [-0.55, 0.1, 0.55][player]
		voice(note(pitch), duration, 0.20, PLAYERS[player], pan, index)

func render_voice(v: Voice, dt: float) -> float:
	var value := super.render_voice(v, dt)
	# The shared rounded lead applies layer_gain itself; custom timbres do not.
	if v.layer >= 0 and v.instrument in [&"brass", &"guitar"]:
		value *= float(layer_gain[v.layer])
	return value

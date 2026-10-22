extends "res://scripts/music_anthem.gd"

# The conductor writes in scale degrees; players record and answer whole bars.
const SCALES := [
	[0, 2, 3, 5, 7, 8, 10], # Aeolian.
	[0, 2, 3, 5, 7, 9, 10], # Dorian.
	[0, 2, 3, 5, 7, 8, 11], # Harmonic minor.
	[0, 2, 4, 5, 7, 9, 11], # Major.
]
const PLAYERS := [&"brass", &"lead", &"guitar"]
const MAX_RECORDINGS := 8
const MAX_MOTIFS := 4
var scale_index := 1
var motif: Array = []
var motif_bank: Array = []
var recordings: Array = []
var parts: Array = []
var repeat_gain := 1.0
var conductor_phase := 0
var leader := 0

func note(deg: int, octave: int = 0) -> float:
	var midi := 45 + int(floor(float(deg) / 7.0)) * 12 + int(SCALES[scale_index][posmod(deg, 7)]) + octave * 12
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

func chord_tone(value: int) -> int:
	var closest := root + 7
	for candidate in range(4, 18):
		if posmod(candidate - root, 7) in [0, 2, 4] and absi(candidate - value) < absi(closest - value):
			closest = candidate
	return closest

func write_motif() -> Array:
	var result: Array = []
	var slot := 0
	var previous := 7
	var movement := 0
	while slot < 16:
		# Repeated values are weights, with longer notes on strong beats.
		var lengths := [1, 2, 2, 3, 4, 4] if slot % 4 == 0 else [1, 1, 2, 2, 3]
		var length: int = mini(lengths[random.randi_range(0, lengths.size() - 1)], 16 - slot)
		var steps := [-2, -1, -1, 0, 1, 1, 2, 3]
		var step: int = steps[random.randi_range(0, steps.size() - 1)]
		if absi(movement) >= 3:
			step = -signi(movement)
		var pitch := clampi(previous + step, 5, 16)
		if slot % 4 == 0 or slot + length == 16:
			pitch = chord_tone(pitch)
		var rest := slot > 0 and slot + length < 16 and random.randf() < 0.18
		result.append({"slot": slot, "length": length, "degree": pitch, "rest": rest})
		if not rest:
			movement = pitch - previous
			previous = pitch
		slot += length
	return result

func develop(source: Array, donor: Array, phase: int) -> Array:
	var result: Array = source.duplicate(true)
	# A recognizable head survives. Development happens in the answer.
	for i in range(1, result.size() - 1):
		var event: Dictionary = result[i]
		if phase in [2, 3, 6] and random.randf() < 0.3:
			event.degree = clampi(int(event.degree) + random.randi_range(-1, 1), 5, 16)
		if phase in [3, 6] and random.randf() < 0.25:
			event.rest = true
	if phase in [4, 5] and donor.size() > 2 and result.size() > 2:
		var destination := random.randi_range(1, result.size() - 2)
		var origin := random.randi_range(1, donor.size() - 2)
		# Exchange a note, retaining each player's rhythmic placement.
		var exchanged: int = result[destination].degree
		result[destination].degree = donor[origin].degree
		donor[origin].degree = exchanged
		result[destination].rest = false
	if phase == 7:
		result[-1].degree = 7
		result[-1].rest = false
	return result

func begin_bar() -> void:
	bar += 1
	conductor_phase = bar % 8
	root = HARMONY[conductor_phase]
	if bar % 16 == 0:
		scale_index = 1
		if idle_time > 15.0:
			scale_index = 0
		if energy > 0.8:
			scale_index = 3
		if tension > 0.35:
			scale_index = 2
	if conductor_phase == 0:
		leader = (bar / 8) % PLAYERS.size()
		motif = write_motif()
		# Recall an older idea as a response, rather than an endless random walk.
		if not motif_bank.is_empty() and bar % 24 == 16:
			motif = motif_bank[0].duplicate(true)
		motif_bank.append(motif.duplicate(true))
		if motif_bank.size() > MAX_MOTIFS:
			motif_bank.pop_front()
		repeat_gain = 1.0
	if conductor_phase > 0:
		repeat_gain *= 0.91
	var donor: Array = []
	if not recordings.is_empty():
		donor = recordings[-1].events.duplicate(true)
	var current := develop(motif, donor, conductor_phase)
	parts = [{"events": current, "player": leader, "gain": repeat_gain, "octave": 0}]
	for age in range(1, mini(3, recordings.size() + 1)):
		var recording: Dictionary = recordings[-age]
		var answer: Array = recording.events.duplicate(true)
		if age == 1 and not donor.is_empty():
			answer = donor
		# Removing alternate notes gives the foreground room to speak.
		for i in range(answer.size()):
			if (i + bar + age) % 3 == 0:
				answer[i].rest = true
		parts.append({"events": answer, "player": (leader + age) % PLAYERS.size(), "gain": float(recording.gain) * pow(0.38, age), "octave": -1 if age == 2 else 0})
	recordings.append({"events": current.duplicate(true), "gain": repeat_gain, "player": leader})
	if recordings.size() > MAX_RECORDINGS:
		recordings.pop_front()

func play_parts(slot: int, quarter: float) -> void:
	for part in parts:
		for event in part.events:
			if event.slot != slot or event.rest:
				continue
			var pitch: int = event.degree
			# Strong, sustained notes land on the current chord. Passing notes can rub.
			if slot % 4 == 0 and event.length >= 2:
				pitch = chord_tone(pitch)
			var player: int = part.player
			var level: float = [0.15, 0.12, 0.13][player] * float(part.gain)
			var pan: float = [0.05, 0.62, -0.62][player]
			voice(note(pitch, part.octave), quarter * 0.25 * float(event.length) * 0.9, level, PLAYERS[player], pan)

func schedule() -> void:
	var slot := tick % 16
	var quarter := 60.0 / bpm
	if slot == 0:
		begin_bar()
		for offset in [7, 9, 11]:
			voice(note(root + offset), quarter * 3.8, 0.035, &"pad", float(offset - 9) * 0.38)
		if conductor_phase == 0:
			voice(1730.0, 1.2, 0.07, &"cymbal", 0.45)
	if slot in [0, 6, 8, 10]:
		voice(62.0, 0.24, 0.65, &"kick")
		pulse = 0.35
	if slot in [4, 12] or (conductor_phase == 7 and slot in [14, 15]):
		voice(185.0, 0.21, 0.19, &"snare", -0.12)
	if slot % 2 == 0:
		voice(0.0, 0.07, 0.035, &"hat", 0.4)
		voice(note(root if slot % 4 == 0 else root + 4), quarter * 0.42, 0.19, &"bass")
	play_parts(slot, quarter)
	tick += 1

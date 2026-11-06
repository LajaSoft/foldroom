extends "res://scripts/music_anthem.gd"

# Exact source voices on the first pass; bounded phrase variations thereafter.
const SCORE: Dictionary = preload("res://music/generated_dm.json").data
const MINOR := [0, 2, 3, 5, 7, 8, 10]
const CHORDS := [
	[50, 53, 57], # D minor
	[46, 50, 53], # B flat
	[53, 57, 60], # F major
	[45, 48, 52], # A minor
]
var section_index := 0
var section_bar := -1
var cycle := 0
var generation := 0
var current_parts: Array = []
var chord: Array = []

func _init() -> void:
	super()
	bpm = float(SCORE.bpm)

func advance(dt: float, speed: float) -> void:
	# Reuse gameplay smoothing, but keep all source rhythms at the stated tempo.
	super.advance(dt, speed)
	bpm = float(SCORE.bpm)

func frequency(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

func develop(source: Array, variation: int) -> Array:
	var result: Array = source.duplicate(true)
	if variation == 0:
		return result
	var sounding: Array[int] = []
	for i in range(result.size()):
		if int(result[i].midi) >= 0:
			sounding.append(i)
	# Protect the head and cadence; change only one interior note per bar.
	if sounding.size() < 3:
		return result
	var index: int = sounding[1 + posmod(variation, sounding.size() - 2)]
	var pitch := int(result[index].midi)
	var direction := 1 if variation % 2 == 0 else -1
	for distance in range(1, 4):
		var candidate := pitch + distance * direction
		if candidate >= 60 and candidate <= 89 and posmod(candidate - 62, 12) in MINOR:
			result[index].midi = candidate
			break
	return result

func begin_bar() -> void:
	bar += 1
	section_bar += 1
	var section: Dictionary = SCORE.sections[section_index]
	if section_bar >= section.Vocal.size():
		section_bar = 0
		section_index += 1
		if section_index == SCORE.sections.size():
			section_index = 1 # Intro plays once; the complete song body loops.
			cycle += 1
		section = SCORE.sections[section_index]
	if section_bar % 4 == 0:
		generation = cycle * 17 + section_index * 3 + section_bar / 4
	current_parts.clear()
	for part in ["Vocal", "Ins"]:
		var source: Array = SCORE.patterns[int(section[part][section_bar])]
		# The E-flat interlude stays literal, including its bar-local accidentals.
		var variation := generation if cycle > 0 and section.name != "interlude" else 0
		current_parts.append(develop(source, variation))
	chord = CHORDS[section_bar % 4]
	if section.name == "verse":
		chord = [[50, 53, 57], [43, 46, 50], [46, 50, 53], [48, 52, 55]][section_bar % 4]
	if section.name == "interlude":
		chord = [[50, 53, 57], [51, 55, 58], [48, 52, 55], [45, 48, 52]][section_bar % 4]

func play_part(events: Array, slot: int, instrument: StringName, pan: float) -> void:
	for event in events:
		if int(event.slot) != slot * 2 or int(event.midi) < 0:
			continue
		var duration := float(event.length) * 60.0 / bpm / 8.0 * 0.92
		voice(frequency(int(event.midi)), duration, 0.115, instrument, pan)

func source_is_rest(events: Array, unit: int) -> bool:
	for event in events:
		if unit >= int(event.slot) and unit < int(event.slot) + int(event.length):
			return int(event.midi) < 0
	return false

func schedule() -> void:
	var slot := tick % 16
	var quarter := 60.0 / bpm
	if slot == 0:
		begin_bar()
		for i in range(chord.size()):
			voice(frequency(int(chord[i]) + 12), quarter * 3.8, 0.022, &"pad", float(i - 1) * 0.6)
	play_part(current_parts[0], slot, &"brass", -0.18)
	play_part(current_parts[1], slot, &"lead", 0.4)
	if slot % 4 == 0:
		voice(60.0, 0.24, 0.55, &"kick")
		pulse = 0.65
	if slot in [4, 12]:
		voice(185.0, 0.17, 0.11, &"snare", -0.12)
	if slot % 4 == 2 or (energy > 0.6 and slot % 4 == 0):
		voice(frequency(int(chord[0]) - 12), quarter * 0.42, 0.18, &"bass")
	if slot % 4 == 2 or (energy > 0.5 and slot % 2 == 0):
		voice(0.0, 0.07, 0.025 + energy * 0.015, &"hat", 0.5)
	# Responses occupy genuine gaps in both supplied voices, never cover the hook.
	if cycle > 0 and slot in [6, 10, 14] and energy + curiosity > 0.35:
		if source_is_rest(current_parts[0], slot * 2) and source_is_rest(current_parts[1], slot * 2):
			var pitch := int(chord[posmod(generation + slot / 2, chord.size())]) + 12
			voice(frequency(pitch), quarter * 0.42, 0.045 + tension * 0.02, &"guitar", 0.65)
	tick += 1

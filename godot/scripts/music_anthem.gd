extends "res://scripts/music.gd"

# Original eight-bar fanfare, in scale degrees. Rests let the chords answer.
const THEMES := [
	[7, -1, 9, 11, 12, -1, 11, 9],
	[10, -1, 9, 7, 8, 9, 11, -1],
	[12, -1, 14, 13, 11, -1, 9, 10],
	[11, 9, 8, -1, 7, -1, -1, -1],
]
const HARMONY := [0, 0, 5, 3, 0, 5, 3, 4]

func _init() -> void:
	super()
	bpm = 112.0

func advance(dt: float, speed: float) -> void:
	super.advance(dt, speed)
	if enabled:
		bpm = lerpf(bpm, 108.0 + energy * 12.0, 1.0 - exp(-dt / 0.3))

func begin_bar() -> void:
	bar += 1
	mode = 1
	root = HARMONY[bar % HARMONY.size()]
	phrase.assign(THEMES[(bar / 2) % THEMES.size()])

func schedule() -> void:
	var slot := tick % 16
	var quarter := 60.0 / bpm
	if slot == 0:
		begin_bar()
		for offset in [7, 9, 11]:
			voice(note(root + offset), quarter * 3.8, 0.045, &"pad", float(offset - 9) * 0.38)
		if bar % 4 == 0:
			voice(1730.0, 1.4, 0.09, &"cymbal", 0.45)
	if slot in [0, 6, 8, 10]:
		voice(62.0, 0.24, 0.65, &"kick")
		pulse = 0.35
	if slot in [4, 12] or (bar % 4 == 3 and slot in [14, 15]):
		voice(185.0, 0.21, 0.19, &"snare", -0.12)
	if slot % 2 == 0:
		voice(0.0, 0.07, 0.035, &"hat", 0.4)
		voice(note(root if slot % 4 == 0 else root + 4), quarter * 0.42, 0.19, &"bass")
		# Palm-muted power chords support the sustained fanfare.
		for offset in [0, 4]:
			voice(note(root + offset, 1), quarter * 0.35, 0.038, &"guitar", -0.55)
		var melody: int = phrase[slot / 2]
		if melody >= 0:
			var length := quarter * (0.9 if slot % 4 == 0 else 0.45)
			voice(note(melody), length, 0.17, &"brass", 0.12)
			voice(note(melody, -1), length, 0.055, &"brass", -0.22)
	tick += 1

func schedule_layer(_layer: int) -> void:
	# Fanfare timing stays locked to the rock rhythm during acceleration.
	pass

func voice(frequency: float, duration: float, level: float, instrument: StringName, pan: float = 0.0, layer: int = -1) -> void:
	var previous_count := voices.size()
	super.voice(frequency, duration, level, instrument, pan, layer)
	if voices.size() > previous_count and instrument in [&"brass", &"guitar", &"snare"]:
		voices[-1].room_send = 0.32

func render_voice(v: Voice, dt: float) -> float:
	if v.instrument not in [&"brass", &"guitar", &"snare"]:
		return super.render_voice(v, dt)
	v.age += dt
	v.phase = fmod(v.phase + TAU * v.frequency * dt, TAU)
	var attack := 0.035 if v.instrument == &"brass" else 0.004
	var envelope := smoothstep(0.0, attack, v.age) * smoothstep(0.0, minf(0.1, v.duration * 0.35), v.duration - v.age)
	var wave := 0.0
	match v.instrument:
		&"brass":
			var brightness := 0.65 * exp(-v.age * 2.0)
			wave = sin(v.phase) + brightness * sin(v.phase * 2.0) + 0.3 * sin(v.phase * 3.0) + 0.14 * sin(v.phase * 4.0)
		&"guitar":
			wave = tanh(2.0 * (sin(v.phase) + 0.4 * sin(v.phase * 3.0))) * exp(-v.age * 12.0)
		&"snare":
			wave = (noise.randf_range(-1.0, 1.0) * 0.75 + sin(v.phase) * 0.45) * exp(-v.age * 18.0)
	return wave * envelope * v.level

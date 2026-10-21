extends SceneTree

const Music = preload("res://scripts/music.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	failed = failed or not condition

func _init() -> void:
	var isolated = Music.new()
	isolated.gain = 0.45
	isolated.voice(440.0, 0.6, 0.1, &"lead")
	var last := Vector2.ZERO
	var jump := 0.0
	for i in range(16000):
		var frame: Vector2 = isolated.sample()
		jump = maxf(jump, (frame - last).length() / Music.OUTPUT_GAIN)
		last = frame
	check(jump < 0.02, "Isolated lead has continuous attack, waveform and release")
	var centered = Music.new()
	centered.gain = 0.45
	centered.voice(60.0, 0.28, 0.38, &"kick")
	var center_difference := 0.0
	for i in range(7000):
		var frame: Vector2 = centered.sample()
		center_difference = maxf(center_difference, absf(frame.x - frame.y))
	check(center_difference < 0.000001, "Kick remains centered and dry")
	var stage = Music.new()
	stage.gain = 0.45
	stage.voice(440.0, 0.4, 0.05, &"lead", -0.7)
	var stage_side := 0.0
	var stage_total := 0.0
	for i in range(10000):
		var frame: Vector2 = stage.sample()
		stage_side += pow((frame.x - frame.y) * 0.5, 2.0)
		stage_total += frame.length_squared() * 0.5
	check(stage_side / stage_total > 0.1, "Melodic stage retains stereo width independently of centered drums")
	var music = Music.new()
	music.enabled = true
	for i in range(600):
		music.advance(0.1, 18.0)
	check(music.energy > 0.99 and music.bpm > 110.0, "Sustained driving builds energy and tempo")
	music.advance(0.1, 0.0)
	music.advance(0.1, 18.0)
	check(music.focus > 0.9, "Acceleration selects a melodic foreground")
	music.advance(2.0, 18.0)
	check(music.layer_gain[music.focus_track] > music.layer_gain[(music.focus_track + 1) % 3], "Selected melody rises over accompanying layers")
	check(music.layer_rate[music.focus_track] > 1.0, "Selected melody accelerates independently")
	var previous: float = music.bpm
	music.advance(0.1, 0.0)
	check(absf(music.bpm - previous) < 1.0, "Braking preserves musical inertia")
	for i in range(600):
		music.advance(0.1, 0.0)
	check(music.focus < 0.001, "Foreground dissolves after acceleration")
	check(music.energy < 0.01 and music.bpm < 124.0, "Long stop relaxes tempo")
	music.event(&"impact", 1.0)
	music.event(&"passage", 1.0)
	check(music.tension > 0.0 and music.curiosity > 0.0, "Gameplay events alter musical tendencies")
	music.advance(30.0, 0.0)
	check(music.tension < 0.04, "Event influence decays")
	var peak := 0.0
	var output_peak := 0.0
	var stereo_energy := 0.0
	var mono_energy := 0.0
	var side_energy := 0.0
	var render_start := Time.get_ticks_usec()
	for i in range(22050 * 12):
		if i % 2205 == 0:
			music.advance(0.1, 18.0 if i > 22050 * 6 else 0.0)
		var frame: Vector2 = music.sample()
		check_finite(frame)
		stereo_energy += frame.length_squared() * 0.5
		mono_energy += pow((frame.x + frame.y) * 0.5, 2.0)
		side_energy += pow((frame.x - frame.y) * 0.5, 2.0)
		output_peak = maxf(output_peak, maxf(absf(tanh(frame.x)), absf(tanh(frame.y))))
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
	var render_seconds := (Time.get_ticks_usec() - render_start) / 1000000.0
	print("Synth render: 12 audio seconds in ", render_seconds, " seconds")
	check(render_seconds < 12.0, "Synth renders faster than real time")
	print("Pre-output peak: ", peak, "; final soft-clipped peak: ", output_peak)
	check(peak > 0.2 and peak < 2.0 and output_peak < 1.0, "Boosted mix remains within final output headroom")
	print("Stereo side fraction: ", side_energy / stereo_energy, "; mono energy fraction: ", mono_energy / stereo_energy)

	check(mono_energy / stereo_energy > 0.65, "Mono fold-down preserves musical energy")
	var phrases := {}
	for i in range(128):
		music.begin_bar()
		phrases[str(music.phrase)] = true
	check(phrases.size() > 100 and music.history.size() == 64, "Long form varies phrases and bounds memory")
	music.enabled = false
	for i in range(22050 * 5):
		music.sample()
	check(music.gain == 0.0 and music.voices.is_empty(), "Pause fades out and releases voices")
	quit(1 if failed else 0)

func check_finite(frame: Vector2) -> void:
	if not frame.is_finite():
		failed = true

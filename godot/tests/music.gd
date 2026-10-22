extends SceneTree

const Music = preload("res://scripts/music.gd")
var failed := false

func check(condition: bool, message: String) -> void:
	print("PASS " if condition else "FAIL ", message)
	failed = failed or not condition

func _init() -> void:
	var sound = preload("res://scripts/sound.gd").new()
	check(sound.track_index == 0 and sound.TRACKS[0] == "ratio drive", "Ratio drive is first and selected by default")
	sound.music.volume = 0.31
	sound.music.enabled = true
	sound.select_music(3)
	check(sound.TRACKS[3] == "trance style" and sound.music.volume == 0.31 and sound.music.enabled, "Track switch preserves volume and playback")
	sound.select_music(2)
	var anthem = sound.music
	var anthem_peak := 0.0
	var anthem_start := Time.get_ticks_usec()
	for i in range(22050 * 10):
		if i % 2205 == 0:
			anthem.advance(0.1, 12.0)
		var frame: Vector2 = anthem.sample()
		check_finite(frame)
		anthem_peak = maxf(anthem_peak, maxf(absf(frame.x), absf(frame.y)))
	check(anthem_peak > 0.1 and anthem_peak < 2.0, "Fanfare produces finite audio within output headroom")
	check(Time.get_ticks_usec() - anthem_start < 10000000, "Fanfare renders faster than real time")
	check(anthem.bar >= 3 and anthem.voices.size() < 48, "Fanfare advances harmony with bounded polyphony")
	var same_music = sound.music
	sound.select_music(-1)
	sound.select_music(99)
	sound.select_music(2)
	check(sound.music == same_music, "Invalid or repeated selection preserves composition")
	anthem.enabled = false
	for i in range(22050 * 5):
		anthem.sample()
	check(anthem.gain == 0.0 and anthem.voices.is_empty(), "Fanfare pause releases all voices")
	test_ratio_drive()
	test_conversation()
	sound.free()
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

func test_conversation() -> void:
	var Conversation = preload("res://scripts/music_conversation.gd")
	var composition = Conversation.new()
	var signatures := {}
	var valid_timing := true
	var bounded_memory := true
	var fading_answers := true
	var independent_recordings := true
	var players := {}
	for bar_index in range(128):
		composition.begin_bar()
		signatures[str(composition.parts[0].events)] = true
		players[composition.leader] = true
		bounded_memory = bounded_memory and composition.recordings.size() <= 8 and composition.motif_bank.size() <= 4
		for part in composition.parts:
			var end := 0
			for event in part.events:
				valid_timing = valid_timing and event.slot == end and event.length > 0 and event.degree >= 4 and event.degree <= 17
				end += int(event.length)
			valid_timing = valid_timing and end == 16
		for i in range(1, composition.parts.size()):
			fading_answers = fading_answers and composition.parts[i].gain < composition.parts[i - 1].gain
		var recorded: int = composition.recordings[-1].events[0].degree
		composition.parts[0].events[0].degree += 1
		independent_recordings = independent_recordings and composition.recordings[-1].events[0].degree == recorded
	check(valid_timing, "Recorded motifs retain bounded pitches and exactly one bar of rhythmic events")
	check(bounded_memory and independent_recordings, "Motif bank and recordings are bounded independent copies")
	check(signatures.size() > 40 and players.size() == 3, "Long form develops motifs and passes leadership to all instruments")
	check(fading_answers, "Recorded answers decay below the foreground")
	composition.scale_index = 0
	var minor_sixth: float = composition.note(5)
	composition.scale_index = 1
	var dorian_sixth: float = composition.note(5)
	check(absf(dorian_sixth / minor_sixth - pow(2.0, 1.0 / 12.0)) < 0.00001, "Scale remaps the same degree independently of its motif")
	var source: Array = [{"slot": 0, "length": 4, "degree": 7, "rest": false}, {"slot": 4, "length": 4, "degree": 9, "rest": false}, {"slot": 8, "length": 8, "degree": 11, "rest": false}]
	var donor: Array = source.duplicate(true)
	donor[1].degree = 13
	var exchanged: Array = composition.develop(source, donor, 4)
	check(exchanged[1].degree == 13 and donor[1].degree == 9 and source[1].degree == 9, "Players exchange notes without changing the source or rhythmic placement")
	var resolved: Array = composition.develop(source, [], 7)
	check(resolved[-1].degree == 7 and not resolved[-1].rest, "Section ending returns to the tonal center")
	composition = Conversation.new()
	composition.enabled = true
	var peak := 0.0
	var audible := 0.0
	var started := Time.get_ticks_usec()
	for i in range(22050 * 20):
		if i % 2205 == 0:
			composition.advance(0.1, 16.0 if i > 22050 * 5 else 0.0)
		var frame: Vector2 = composition.sample()
		check_finite(frame)
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		audible += frame.length_squared()
	check(peak > 0.1 and peak < 2.0 and audible > 1.0 and composition.voices.size() < 48, "Conversation renders audible finite bounded audio across section changes")
	var seconds := (Time.get_ticks_usec() - started) / 1000000.0
	print("Conversation render: 20 audio seconds in ", seconds, " seconds")
	check(seconds < 20.0, "Conversation renders faster than real time")
	composition.enabled = false
	var frozen_bar: int = composition.bar
	for i in range(22050 * 5):
		composition.sample()
	check(composition.gain == 0.0 and composition.voices.is_empty() and composition.bar == frozen_bar, "Conversation pause releases voices and freezes the conductor")

func test_ratio_drive() -> void:
	var Ratio = preload("res://scripts/music_ratio.gd")
	var composition = Ratio.new()
	composition.enabled = true
	for frame in range(Ratio.BEAT_FRAMES * 8):
		composition.sequence(1.0 / Music.RATE)
	var exact_ratios := true
	for i in range(composition.lane_steps.size()):
		var expected := ceili(8.0 * Ratio.NUMERATORS[i] / Ratio.DENOMINATORS[i])
		exact_ratios = exact_ratios and composition.lane_steps[i] == expected
	check(exact_ratios, "All /2 through /8 and x2 through x8 clocks retain exact rational counts")
	var old_steps: Array = composition.lane_steps.duplicate()
	composition.advance(0.1, 31.0)
	check(composition.lane_steps == old_steps and composition.bpm == 120.0, "Speed changes gains without resetting clocks or bending the metronome")
	var low_targets: Array = composition.mix_targets.duplicate()
	composition.advance(0.1, 0.0)
	check(composition.mix_targets.find(composition.mix_targets.max()) == 0 and low_targets.find(low_targets.max()) == low_targets.size() - 1, "Low and high speed select slow and fast rational layers")
	composition.advance(0.1, 40.0)
	check(composition.requested_gear == 2 and composition.gear == 1, "Overspeed requests doubling without changing clocks mid-bar")
	var previous_gear_frame: int = composition.gear_frame
	composition.sequence(1.0 / Music.RATE)
	check(composition.gear == 2 and composition.gear_frame == previous_gear_frame + 2, "Pulse doubling commits at a base bar boundary without resetting phase")
	composition.advance(0.1, 30.0)
	check(composition.requested_gear == 2, "Gear hysteresis retains doubling between thresholds")
	composition.advance(0.1, 20.0)
	check(composition.requested_gear == 1 and composition.gear == 2, "Slowing requests a base pulse at the next bar boundary")
	composition = Ratio.new()
	composition.enabled = true
	var peak := 0.0
	var energy_sum := 0.0
	var max_gain_step := 0.0
	var old_gain: float = composition.layer_gain[0]
	var started := Time.get_ticks_usec()
	var speeds := [0.0, 4.0, 12.0, 24.0, 40.0, 30.0, 20.0, 0.0]
	var real_time_polyphony := true
	var constant_tempo := true
	for frame in range(22050 * 24):
		if frame % 2205 == 0:
			composition.advance(0.1, speeds[mini(frame / (22050 * 3), speeds.size() - 1)])
		var sample: Vector2 = composition.sample()
		check_finite(sample)
		peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
		energy_sum += sample.length_squared()
		max_gain_step = maxf(max_gain_step, absf(float(composition.layer_gain[0]) - old_gain))
		old_gain = composition.layer_gain[0]
		real_time_polyphony = real_time_polyphony and composition.voices.size() < 48
		constant_tempo = constant_tempo and composition.bpm == 120.0
	var seconds := (Time.get_ticks_usec() - started) / 1000000.0
	print("Ratio drive render: 24 audio seconds in ", seconds, " seconds; peak ", peak)
	check(peak > 0.1 and peak < 2.0 and energy_sum > 1.0 and real_time_polyphony, "Ratio drive remains audible finite and bounded through speed and gear changes")
	check(composition.gear == 1 and composition.requested_gear == 1, "Braking removes pulse doubling at the following bar boundary")
	check(constant_tempo and composition.master_frame == 22050 * 24, "Base metronome stays at 120 BPM throughout acceleration and braking")
	check(max_gain_step < 0.0001, "Track selection fades per sample even with abrupt speed changes")
	check(seconds < 24.0, "Ratio drive renders faster than real time")
	composition.enabled = false
	var frozen_clock: int = composition.master_frame
	var frozen_steps: Array = composition.lane_steps.duplicate()
	for frame in range(22050 * 5):
		composition.sample()
	check(composition.master_frame == frozen_clock and composition.lane_steps == frozen_steps and composition.voices.is_empty() and composition.gain == 0.0, "Pause freezes rational clocks and releases all voices")

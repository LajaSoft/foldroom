class_name FoldSound
extends AudioStreamPlayer

var playback: AudioStreamGeneratorPlayback
var phase := 0.0
var speed := 0.0
var spin := 0.0
var throttle := 0.0
var active := false
var volume := 0.55
var voices: Array = []
var random := RandomNumberGenerator.new()
var smooth_frequency := 45.0

func _ready() -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = 22050.0
	generator.buffer_length = 0.08
	stream = generator
	play()
	playback = get_stream_playback()
	random.seed = 7843

func impact(impulse: float, attenuation: float = 1.0) -> void:
	if impulse < 0.3 or attenuation < 0.01:
		return
	voices.append({"age": 0.0, "level": minf(0.7, impulse * 0.075) * attenuation, "frequency": 70.0 + minf(180, impulse * 10.0), "phase": 0.0})
	if voices.size() > 8:
		voices.pop_front()

func silence() -> void:
	active = false
	voices.clear()

func _process(_dt: float) -> void:
	if playback == null:
		return
	var frames := mini(playback.get_frames_available(), 8192)
	var buffer := PackedVector2Array()
	buffer.resize(frames)
	var step := 1.0 / 22050.0
	for i in range(frames):
		var sample := 0.0
		var target := 45.0 + minf(speed, 60) * 13.0 + minf(spin, 48) * 5.0 + throttle * 70.0
		smooth_frequency = lerpf(smooth_frequency, target, 0.0008)
		phase = fmod(phase + TAU * smooth_frequency * step, TAU)
		if active:
			var motor := sin(phase) * 0.065 + sin(phase * 2.0) * 0.025 + sin(phase * 6.0) * 0.012
			sample += motor * (0.15 + minf(1, speed / 5.0) * 0.4 + throttle * 0.45)
		for voice in voices:
			voice.age += step
			voice.phase += TAU * voice.frequency * step
			var envelope := exp(-voice.age * 24.0)
			sample += voice.level * envelope * (sin(voice.phase) * 0.65 + random.randf_range(-1, 1) * 0.35)
		sample = tanh(sample * volume)
		buffer[i] = Vector2(sample, sample)
	voices = voices.filter(func(voice): return voice.age < 0.35)
	playback.push_buffer(buffer)

func shutdown() -> void:
	set_process(false)
	stop()
	playback = null
	stream = null

func _exit_tree() -> void:
	shutdown()

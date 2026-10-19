class_name FoldGyro
extends RefCounted

# A deliberately approximate single contact patch / internal rotor model.
# Physics remains identical to the web game; these terms only produce wheel torque.
var strength := 0.35
var gyro_resistance := 0.16
var centering := 0.32
var damping := 0.045
var lateral_gain := 0.035
var impact_gain := 0.13
var impact_strength := 0.85
var impact_frequency := 38.0
var pulse := 0.0
var pulse_phase := 0.0
var pulse_direction := 1.0
var base_output := 0.0
var output := 0.0
var components := {}

func reset() -> void:
	pulse = 0.0
	pulse_phase = 0.0
	pulse_direction = 1.0
	base_output = 0.0
	output = 0.0
	components.clear()

func impact(impulse: float, side: float) -> void:
	var amplitude := clampf(impulse * impact_gain, 0.0, 0.9)
	# Several integration substeps may report the same contact. Keep the strongest
	# kick, rather than restarting the vibration with every weaker impulse.
	if amplitude <= pulse * exp(-pulse_phase * 18.0):
		return
	pulse = amplitude
	pulse_direction = signf(side) if absf(side) > 0.05 else 1.0
	pulse_phase = 0.0

func compute(steering: float, steer_rate: float, spin: float, lateral_accel: float, contact: float, throttle: float, dt: float) -> float:
	var rotor := clampf(absf(spin) / 2.4, 0, 6)
	var load := clampf(contact, 0, 1)
	var align := -steering * centering * (0.2 + rotor * 0.4) * (0.25 + load * 0.75)
	var gyro := -steer_rate * gyro_resistance * (0.15 + rotor * 0.25)
	var damper := -damping * steer_rate
	var lateral := -clampf(lateral_accel, -30, 30) * lateral_gain * load
	var motor := -steering * throttle * rotor * 0.012
	var target := clampf((align + gyro + damper + lateral + motor) * strength, -strength, strength)
	base_output = move_toward(base_output, target, dt * 8.0)
	# A signed initial tap followed by a short 38 Hz vibration. Transients bypass
	# the slow steering slew limit, while the combined output retains the gain cap.
	var envelope := exp(-pulse_phase * 18.0)
	var attack := minf(1.0, (pulse_phase + dt) / 0.004)
	var tap := pulse_direction * 0.65 * exp(-pulse_phase * 40.0)
	var vibration := sin(TAU * impact_frequency * pulse_phase) * 0.8
	var kick := pulse * impact_strength * envelope * attack * (tap + vibration)
	components = {"align": align, "gyro": gyro, "damper": damper, "lateral": lateral, "impact": kick, "motor": motor}
	output = clampf(base_output + kick * strength, -strength, strength)
	pulse_phase += maxf(0.0, dt)
	if pulse_phase >= 0.22:
		pulse = 0.0
	return output

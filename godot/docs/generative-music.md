# Generative driving music — first sketch

Native Godot 4.4+; no additional dependencies or audio assets.
AudioStreamGenerator runs at 22050 Hz. Music has an independent volume control
in audio settings and shares the existing output buffer with motor/impact audio.

## Musical model

A-minor/Dorian family with three related melodic layers (two beats, one beat,
half a beat per note), rounded harmonic lead, sustained pad, offbeat bass,
four-on-the-floor kick, hats, clap and stereo feedback delay. Kick pulses duck
the tonal instruments. Every bar generates fresh phrases with bounded steps,
local leap resolution, chord-tone endings and recent-note memory. Harmony changes
every four bars and returns to the tonic every sixteen bars.

Speed controls energy with a 0.85-second time constant; the shared tempo stays
around 118–142 BPM. Acceleration above 1.2 world units/s² selects the next
foreground melody, with a four-second retrigger cooldown. Its gain rises while
the other two dip gently, and its independent note clock follows speed at
roughly 0.78–1.53 times its base rate. Pitch remains unchanged. Gain/rate changes
smooth over 0.65/0.9 seconds; the foreground influence decays over six seconds.

More than fifteen seconds near rest selects Aeolian at the next four-bar
boundary. Long-period modulation has been replaced by irregular phrase decisions.
The synth uses smooth attacks/releases; intentional noise is confined to hats
and clap. Output buffering is 180 ms to provide headroom for frame stalls.

## Gameplay input

`music.advance(delta, speed)` consumes speed in world units per second.
`music.event(kind, strength)` accepts a clamped strength from zero to one:

- `impact`: adds tension, affecting harmonics and the long oscillator rate.
- `passage`: adds curiosity, accelerating the shorter oscillator.
- `release`: reduces accumulated tension.

Room changes and distance-attenuated impacts are wired in the game.
The release input is available for future gameplay events.
Events decay over time; harmony and mode decisions occur on musical boundaries.
Pausing fades audio while preserving the composition clock.

## Validation and listening

Run `docker compose run --rm --no-deps godot-test`.
The music test checks sustained driving, short braking inertia, prolonged rest,
event response and decay, finite bounded audio, 128 varied bars, bounded memory,
voice release after pausing, independent foreground gain/rate changes, lead
waveform continuity, and synthesis throughput relative to real time.

Listen while accelerating, briefly braking, standing for 20–30 seconds and
crossing rooms. Tune timbres, density, register and phrase direction by ear.
No external music engine or Strudel port is included.

## Mix balance

Bass now starts at A2 (110 Hz), one octave above the initial sub-bass register,
with second/third harmonics for audibility. Kick settles at 60 Hz, with a shorter
4 ms attack, stronger second harmonic and longer body. Lead note levels are
30% lower; pad and delay send are reduced. Kick ducking reaches 65% for leads
and pads, and only 25% for bass, recovering over a 100 ms time constant.

Lead note levels have subsequently been reduced another 60% to foreground the
rhythm. Four-bar endings add a kick pickup; eight-bar endings add a second hit.
Every fourth bar boundary introduces a decaying electronic metallic cymbal,
alternating sides, with continuous inharmonic oscillator phases.

## Stereo stage

Kick and bass remain dry and centered. Melodic layers sit left, near center,
and right, with subtle slow position changes between notes. Equal-power pan
keeps perceived note levels consistent. Lead levels are restored by 80% from
the previous quiet mix, still below the earlier foreground-heavy arrangement.

Leads, pad and metallic percussion feed an asymmetric room with 23/37/61/83 ms
cross-channel reflections and damped feedback; pad has the deepest send.
Lead ping-pong echo now has damped repeats. Ambient returns duck gently on
kicks. No polarity inversion is used for width. Tests cover centered kick,
stereo side energy, mono fold-down energy, bounded peaks and render throughput.

## Irregular phrasing and stronger rhythm

No long sine wave controls contour, tempo or pan. Direction changes after a
random three-to-seven-bar interval. Each melodic layer gets its own sparse
rhythm mask and phrase offset, with variable note lengths, pauses and local
resolution after leaps. The fast layer no longer repeats a fixed up/down
arpeggio. Foreground gain contrast is reduced. Bass plays offbeats rather than
the previous repeating three-sixteenth roll, with occasional fifth pickups.

OUTPUT_GAIN raises the whole music bus by 3x (+9.54 dB), including existing saved
volume settings. Main kick level rises from 0.38 to 0.85, with a stronger body,
upper harmonics and a faster pitch transient. Quiet-speed kick attenuation is
reduced. The existing final tanh in sound.gd remains the output saturation;
there is no automatic level reducer or additional compressor. Raw music output
may exceed unity before this stage. Continuity tests normalize for the explicit
output gain; stereo width is also tested on an isolated melodic voice because
the louder centered rhythm intentionally dominates whole-mix energy.

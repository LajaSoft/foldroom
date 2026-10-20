# FOLDROOM

First-person cubic maze with reversible gravity-frame portals.

## Run

No build step. Strudel 1.3.0 and the soundtrack samples are bundled locally. Serve `dist/` with any static HTTP server.
For example: `python3 -m http.server 8080 --directory dist`.
Open `http://localhost:8080` in a browser supporting WebGL 2. Pointer Lock enables unrestricted mouse look. If the browser or an iframe sandbox denies Pointer Lock, the game starts with drag look: hold the middle mouse button or Alt + left mouse button and drag. WASD, passage editing, markers and Escape pause remain available. A persistent on-screen hint identifies drag mode. Releasing the drag lets you reposition the cursor at screen edges.

Development verification: Node.js 24.19.0. Tests require Node.js 22 or newer.
From the parent project, run `docker compose run --rm site-test`.

## Controls

| Input | Action |
| --- | --- |
| WASD / arrow keys | Walk relative to the player |
| Shift + WASD | Walk five times faster |
| Mouse | Free look: horizontal yaw and vertical pitch |
| Left click | Create a straight passage |
| Right click | Create an upward fold |
| Shift + right click | Create a downward fold |
| Shift + left drag | Draw on a face |
| Delete | Remove the targeted passage and its inverse |
| Mouse wheel | Pull the camera back; outside the maze, walls are 80% transparent |
| Shift + B | Remove the oldest ball |
| B / + Ball button | Spawn a powered ball in the initial room |
| Escape | Release the pointer and pause |

Holding Shift accelerates walking. Shift + left drag moves the marker cursor; free look remains available while sprinting.
The marker is attached to the room face, not to the screen.
Looking up/down never tilts gravity or walking. Pitch is limited to ±89° and
is preserved relative to local gravity through portal transitions. Creating
passages still requires targeting a side wall; simply looking never edits the maze.

## Geometry

Rooms occupy integer positions in one shared cubic lattice. A cell is reused
when a path reaches an existing coordinate. Each room is six units wide;
the player is two units tall. The player owns an orthonormal frame and velocity.
Its gravity direction is always opposite its frame's up vector.

Let `n` be the selected outward wall normal and `u` the player's local up.
A straight passage reaches cell `cell + n`. An upward fold reaches `cell + u`;
a downward fold reaches `cell - u`. Its destination entry normal is opposite
the travel direction. A fixed quarter-turn quaternion maps `n` onto that direction.
Position is rotated about the source face center and translated to the destination
face center. Orientation and velocity receive the same rotation. The reverse
endpoint holds the inverse rotation.

A physical wall boundary is identified independently of the viewing side. A fold
reserves it against a straight passage, while allowing a separate fold on the
opposite side. Deleting a passage removes both endpoints and releases its reservations.
Conflicting destination faces are rejected without overwriting existing connections.

The WebGL 2 fragment shader follows rays across the same portal transforms as
CPU movement. Thus the next room is visible before the player crosses. Face colors
are tied to world axes: +X coral, -X mint, +Y ivory, -Y blue, +Z lilac, -Z ochre.

## Powered balls

Each ball has diameter 1 (one-sixth of a room), its own gravity frame, linear
velocity and angular velocity. A rolling motor supplies torque to restore a
2.4 rad/s rolling spin. Floor contact transfers angular momentum through friction;
steady rolling speed is approximately 1.2 units/s, below the player's 2.6 units/s.
The motor drives the component perpendicular to local gravity so a vertical-axis
pirouette cannot permanently replace forward rolling. This is an idealized
controlled motor, not a complete model of a mechanical gyroscope.

Wall impacts use restitution 0.86 and tangential contact friction. Sphere inertia
is 2/5 mr² with unit mass. Balls collide with one another and pass through the same
portal transforms as the player; gravity and angular velocity transform separately
from visual spin. An open face under a player or ball permits falling. Straight
passages preserve the gravity frame; folded passages rotate it. The motor has no
battery depletion. The simulation pauses when pointer lock is released.

## MVP limits

- 10,000 rooms, 128 marked faces, 64 portal intersections per rendered ray.
- State lasts for the current page session; reloading starts a new maze.
- Keyboard and mouse required. Up to 16 powered balls.
- Rendering has no JavaScript library dependencies. Music uses vendored @strudel/web 1.3.0. Google Fonts is optional;
  system fonts are used if it is unavailable.

## Verification

Twenty-five automated tests cover all 24 valid wall/up orientations for each of the
three passage types (72 combinations), inverse transforms, walking across and back,
closed-wall collision, floor support, shared-wall restrictions, deleting both ends,
occupied-exit rejection, lattice loops, and ray targeting.

Both shaders were compiled, linked and rendered with a native EGL / OpenGL ES 3 context.
An end-to-end browser interaction test was unavailable in the build environment.

## Files

- `dist/core.js`: lattice, vector math, portal transforms, collision and movement.
- `dist/shaders.js`: first-person portal renderer.
- `dist/app.js`: input, marker textures, WebGL setup and HUD.
- `dist/index.html`, `dist/style.css`: interface.
- `tests/core.test.js`: geometry and movement tests.

## Save and restore

The Escape menu offers New ball, Export, Import and Jump to start. Export copies
versioned JSON containing the maze, marker images, player frame and powered-ball
states to the clipboard. Import validates the entire state and decodes marker
images before replacing the current game. Jump to start resets only the player.

## Outside view

The mouse wheel moves the camera backward from the player along the view direction,
up to 300,000 units. Mouse look orbits around the player in this view. On leaving
the occupied room lattice, rendering switches to instanced transparent cube faces
and opaque balls, with a player position indicator. The projection adapts its
near/far planes to the camera distance. Return to zero camera distance to edit
faces. Geometry and portal simulation continue while viewing from outside.

Room topology uses a packed 1024-wide texture so the 10,000-room limit fits
WebGL 2 texture dimensions. Native EGL checks compile all three shader programs
and render the first-person and instanced overview scenes.

## Music

The user-provided continuous progressive trance soundtrack plays through
`@strudel/web` 1.3.0 (AGPL-3.0-or-later), with 138 BPM (34.5 cycles/minute).
Its sixteen layers, long modulation phases, synth controls and harmonic offsets
are retained in `dist/soundtrack.js`. Three `.add(12)` / `.add(7)` callbacks were
adapted to `.add(note(12))` / `.add(note(7))` because Strudel control patterns need
a note control for arithmetic transposition.

Music is opt-in via the header or Escape menu, independently of gameplay pause.
The master volume defaults to 35% of the available 0.4 output gain. Volume is
applied at the Strudel output GainNode, preserving individual voice envelopes.
The library is imported once; drums are decoded before playback. Stopping pauses
the scheduler and suspends the AudioContext; starting resumes it.

Seven RolandTR909 sample files are bundled from the drum collection linked by
Strudel's official documentation. Original URLs are recorded in
`dist/audio/sources.json`. The vendored library is unmodified and came from
`https://unpkg.com/@strudel/web@1.3.0/dist/index.mjs`.

Project source is distributed under AGPL-3.0-or-later; see LICENSE. A complete
source archive, including the unmodified bundled library, tests and sample URLs,
is available from the Escape menu. Strudel upstream source and documentation:
https://codeberg.org/uzu/strudel and https://strudel.cc/.

## Mobile controls and audio

Coarse-pointer devices use a captured left joystick and an independent look finger on the canvas. Right-side buttons carve straight/up/down at the crosshair. Opening the menu, cancelling a pointer or backgrounding the page clears movement. Desktop pointer lock remains unchanged. Mobile rendering caps pixel ratio at 1 to leave room for audio processing.

Audio is unlocked on the initial music tap and uses a playback-latency context. Mobile supersaw unison is reduced while all 16 layers remain. An opt-out “Phone speaker” preset adds 4 dB around 200 Hz and cuts 4 dB above 3.5 kHz; a post-master compressor catches peaks. Turn the preset off for headphones. Strudel remains 1.3.0.

## Runaway sphere recovery

Retrograde damping starts at speed 800 with coefficient 6/s; linear speed has a safety cap of 1200 for balls and player. Distance-bounded substeps advance at most 0.2 units before another wall/portal check, including multiple portal crossings per frame. Spin damps above 24 rad/s and caps at 48 rad/s. Limits apply before integration, after wall contacts and after ball contacts. Escaped runtime positions recover inside the current room. Ball imports reset invalid or over-limit velocities to zero, recover escaped positions on the local floor, and reset invalid spin rates. Maze topology, valid balls, and strict player/orientation validation are preserved. Regression tests include 20 minutes in a continuously descending folded loop.

## English edition

All interface labels, keyboard and touch instructions, status messages and import validation errors are in English. Export format remains `foldroom` version 1, compatible with the Russian edition. Physics, controls, Strudel 1.3.0 and samples are unchanged.

The Esc menu includes Example (loads the supplied 27-room, 32-passage scene with 7 balls and its saved player pose) and Reset (one starting room, no balls or marks, initial player pose). Both clear camera offsets and movement input. The soundtrack continues independently.

## Ball player mode

The Esc menu switches Walk / Ball. In Ball mode the player has radius 0.5, the same mass and contact rules as a spawned sphere, and an eye at the sphere center. W / joystick up adds forward impulse (4 units/s², five times with Shift); S / down brakes, and A/D or joystick left/right steers relative to the screen with a small momentum loss. Releasing input keeps momentum. The automatic sphere motor is disabled for the player. Mouse / drag steers the current motion toward the screen edge. Camera heading tracks the full 3D velocity with exponential inertia and a 2.5 rad/s turn cap, retaining its direction near rest. Its frame follows portal transforms. Sphere contacts use shared distance-bounded simulation steps, including the player. Ball mode, rotation and camera frame roundtrip through JSON; legacy saves still load as Walk. Example and Reset restore their saved/default mode.

Ball steering fix: A/D or joystick left/right turns the current velocity toward screen left/right, using the actual smoothed camera basis rather than an independent heading. Steering rate is 1.8 rad/s with momentum retained by exp(-0.12 × turn angle). W/up accelerates toward the view; S/down brakes. Mouse horizontal motion also steers, without changing a hidden reference grid.

Mobile pinch on the canvas uses the same exponential camera dolly as the mouse wheel. Closing fingers pulls back; spreading fingers moves toward first-person view. Two-finger zoom suppresses look/steering until one finger remains. Joystick touches do not join the pinch; cancellation, pause and backgrounding clear gesture state.

In Ball mode vertical mouse/touch motion adds a manual pitch offset (±89°) to the computed motion-following camera frame. Pitch affects viewing only; steering and thrust retain the automatic movement basis. Looking up while the automatic camera follows a downward fall therefore looks mostly forward. Pinch remains independent of both steering and pitch.

Pointer input regression tests cover lock success, promise and event-only denial, missing API, drag capture/cancellation, focus loss, pause/resume and late asynchronous results.

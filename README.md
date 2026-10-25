# FoldRoom

Godot port of my game originally created in GPT Sites, with Moza force feedback.

## Preview

![Rolling balls and folded rooms](docs/media/rolling-balls.jpg)

![External room overview](docs/media/overview.jpg)

[Watch the tube demo and gameplay clips](https://lajasoft.github.io/foldroom/) · [Wheel and controls](docs/media/controls.jpg)

## CI and Linux builds

```bash
bash docker/run-ci.sh
```

GitHub Actions and GitLab CI run the same Docker pipeline: native regressions, original web tests, JSON round-trip verification, Linux release export and a headless launch of the exported executable. Results and logs are copied to `artifacts/`, including a tarball, `FoldRoom-x86_64.AppImage` and SHA-256 checksums. Download the `FoldRoom-AppImage-x86_64` artifact from a successful GitHub Actions run, unpack it, run `chmod +x FoldRoom-x86_64.AppImage`, then `./FoldRoom-x86_64.AppImage`. Without FUSE, use `./FoldRoom-x86_64.AppImage --appimage-extract-and-run`. The CI container needs no GPU or wheel. Desktop services continue to use the runtime image.

See [CI setup and test cases](docs/ci.md) and [Flatpak packaging assessment](docs/flatpak.md).

## Run

### Browser demo (current Godot game)

```bash
docker compose -f compose.web.yml run --build --rm web-export
docker compose -f compose.web.yml up -d web-demo
```

Open http://localhost:8081/play/. FoldRoom Playground loads the existing example,
with Ball / Walk, Rooms / Tubes, editing and the external overview. Click Enter /
Resume to play with keyboard and mouse. This exports the current Godot 4.4.1 project
to an HTML canvas using WebAssembly and WebGL 2, with single-threaded templates,
stream audio and no native FFB addon. The build requires only Docker Compose;
it does not build or download the wheel dependency. JSON can be downloaded or
pasted into Import; quick saves use browser storage. Desktop keyboard and mouse
are required; this demo does not add touch controls.

The Pages workflow builds the demo at `play/` alongside the existing video page
on every relevant push to main. See [web export checks](docs/web-demo.md).

```bash
# Native game, NVIDIA + X11 + Moza + PulseAudio
docker compose up godot

# Godot editor
docker compose run --rm godot-editor

# Original browser game at http://localhost:8080
docker compose up site
```

The native launcher imports the project and registers the FFB extension before running, including on a fresh checkout. No Node/npm, PHP or Godot installation on the host is needed.

The game opens paused. Enter starts; Escape pauses. Ball mode starts stationary; W accelerates and S brakes. A/D turn toward the side of the rendered screen. Shift boosts ×5. Mouse steers horizontally and adjusts pitch vertically. M switches between Ball and Walk. Arrow keys are secondary movement bindings.

LMB creates a straight passage; RMB folds upward; Shift+RMB folds downward. Delete removes both ends and discards rooms outside the player’s connected component, including balls in those rooms. Remaining room IDs are compacted; if the original start is discarded, the first retained room becomes the new origin. Folded entry walls cannot have a solid backside in an adjacent room: carving, closing a passage, and adding rooms all enforce this rule. Existing imports remain compatible; edits cannot introduce new violations. Shift+LMB draws on a wall. B spawns a powered sphere; Shift+B removes the oldest (16 maximum). Scroll pulls the camera back through the lattice into a transparent external overview. Home returns to the start. Ctrl+R resets the maze.

Pause → **Controls / Wheel / Audio** assigns keys, mouse buttons, gamepad buttons and Linux wheel buttons. Each action has Primary and Secondary assignments: keep the mouse/keyboard control and assign a wheel button alongside it. Click either slot and press the intended input; Escape cancels assignment, and × clears only that slot. Old single-assignment settings load into Primary. Holding both inputs keeps the action active until both are released, without double-triggering an identical binding. Axis assignment learns the ABS code from an axis moved through at least 20% of its travel. The screen shows live steering/pedal values, offers per-axis inversion, physical wheel range, game steering lock, deadzone, FFB enable/direction/strength and effects volume. Settings persist under `.runtime/godot/`, together with quick saves.

Pause → **Rooms ↔ Tubes** switches geometry inside the existing 6-unit cells. Tubes have radius **1.65** and spheres radius **0.33**; room mode retains radius 0.5 spheres. Switching and loading old tube saves scale each sphere's offset from the nearest pipe axis or bend centerline, preserving progress toward the portal. Linear velocity, drive acceleration and gravity scale by 0.66; angular speed is retained. New saves keep the smaller radius and are not scaled twice. The original quick save file is only changed by an explicit save.

The six local opening bits select one of ten fitting families (including an isolated room): end cap, straight, elbow, planar T, trihedral, planar cross, spatial four-way, five-way and six-way. Every opening has the same circular collar. Portal kind, target and rotation do not influence fitting shape. The existing ray tracer still handles transport; its surface query now makes two bilinear reads from a prepared field atlas. Physics interpolates the same field. No adjacent-room surface evaluation or runtime boolean geometry remains. The exterior overview continues to show the room lattice.

See [fitting catalogue, generation and validation](docs/pipe-catalog.md), [Blender cutaway models](docs/models/pipe-catalog.blend) and [catalogue preview](docs/models/pipe-catalog.jpg). The build-only generator uses Python and NumPy; normal play only needs the existing Godot runtime. Wall colors and grid shading remain tied to local face directions. Autonomous spheres retain exit selection and the small rollback skid; the player receives no automatic skid.

## Mechanics and compatibility

Planned gameplay concepts are collected in [Game mode ideas](docs/game-mode-ideas.md).

`godot/scripts/maze.gd` and `motion.gd` port the original room lattice, reversible quarter-turn portals, local gravity, distance-bounded integration, powered-ball motor, friction/restitution, sphere contacts and inertial ball camera. This uses the same formulas as the web game rather than Godot rigid-body collision solving. Room size 6, sphere diameter 1, gravity 8, steering rate 1.8 rad/s, walking speed 2.6, ×5 boost and the 10,000-room limit match the source.

The first-person Godot shader directly ports the WebGL portal ray tracer, including visible rooms beyond folds, sphere shading, wall grids and PNG ink. A sphere overlapping a portal has a render image in each room, with transformed position, gravity and spin; the simulation still contains only one sphere. This preserves its opaque surface when the center switches rooms. Native instanced geometry draws the external overview; its transparent-wall sorting and sphere lighting are not pixel-identical to WebGL. The UI is native Godot. Web touch controls and the Strudel/WebAudio music engine are not part of this desktop port; motor and impact sounds are synthesized natively.

Pause → Export/Import JSON exchanges version-1 state with the original web game, including room IDs, both portal endpoints, actor frames, spinning balls and wall PNGs. Imported Walk saves remain Walk; new games and the Example start in Ball mode. Import validates the entire state before replacing the live maze. Quick save/load uses `user://foldroom.json`; file import/export and clipboard export are also available.

## Moza / gyroscope model

The port uses the `godot-racing` evdev GDExtension to read the actual wheel axes/buttons and send signed constant force. It auto-finds the Gudsen/Moza FFB device or opens a path chosen in Setup. Initial ABS mappings match the R3 example: steering 0, throttle 2, brake 5, inverted force direction. The physical range defaults to the example's 2540° and game lock to 540°; set Physical wheel range to the actual range configured on your wheel.

`godot/scripts/gyro.gd` is an approximate feel model, separate from motion physics. Rolling angular speed increases resistance to steering and restoring torque. Steering velocity adds damping; actual sideways acceleration adds contact load. Wall and sphere collision impulses generate a signed initial tap followed by a decaying 38 Hz vibration lasting at most 220 ms. Its separate Impact vibration setting controls transient strength. The burst bypasses steering smoothing; the final combined torque still respects the overall FFB limit. A portal's frame rotation is removed from the acceleration calculation so changing gravity does not invent an impact. Ground-contact load vanishes in free fall while internal-rotor resistance remains.

FFB starts at 35% strength, with torque clipping and a slew limit. Pause, focus loss, Walk mode, disconnect and shutdown stop the constant-force effect. Setup never sends a test force. Hardware feel has not been judged by a human yet; the gains are the starting approximation for tuning with the wheel.

The FFB dependency is fetched from [LajaSoft/godot-racing](https://github.com/LajaSoft/godot-racing) at commit `3d9339ba851929f5dd9b834bb3f3efb5708bd4f0` by Docker BuildKit. Both debug and release libraries are compiled in Ubuntu 22.04 and installed with the complete MIT-licensed addon. No adjacent checkout is needed. The game, editor and test services install the dependency automatically before starting.

```bash
# First run or after changing the pinned GitHub commit
docker compose build godot
docker compose up godot

# Reinstall the addon from the built image
docker compose run --rm ffb-build
```

Source integration keeps the FFB build pinned and reproducible; the upstream binary `addon-v0.1.0` tag is also available. See [FFB dependency integration](docs/ffb-dependency.md) for the lock, build and gd-plug migration details.

## Docker desktop integration

Dependencies: Docker Engine + Compose with BuildKit Git/additional-context support, NVIDIA Container Toolkit, the host's working Moza kernel driver. `Dockerfile.godot` supplies Ubuntu 24.04 and Godot 4.4.1; its separate Ubuntu 22.04 stage builds the pinned FFB source. The public dependency is fetched over HTTPS without GitHub credentials. Browser service uses nginx `stable-alpine`; reference/web tests use Node.js `24-alpine` (no npm install needed).

The Godot services pass both NVIDIA GPUs, `/dev/input`, X11 sockets and the desktop runtime directory through as in the racing project. PulseAudio connects to the host's Pulse/PipeWire compatibility socket. Defaults are UID/GID 1000 and input group 995. Override `LOCAL_UID`, `LOCAL_GID`, `INPUT_GID`, `DISPLAY`, `XAUTHORITY`, `WAYLAND_DISPLAY`, `GODOT_DISPLAY_DRIVER` or `GODOT_AUDIO_DRIVER` when needed. Xauthority must be within the mounted runtime directory. For silent tests use `GODOT_AUDIO_DRIVER=Dummy`.

## Verification

```bash
# Original web regression suite
docker compose run --rm site-test

# Regenerate numerical fixtures with the original JS engine
docker compose run --rm godot-reference

# Native physics, JSON, controls, persistence and force model (no device mount)
docker compose run --rm godot-test

# Real NVIDIA/X11/PulseAudio integration; no physical wheel torque is sent
docker compose run --rm godot bash /work/godot/run.sh -- --smoke-test

# GPU regression: opaque spheres at straight/up/down portal seams
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/portal_render.gd

# Feed native-export.json back into the unmodified original web importer
docker compose run --rm godot-reference node godot/tests/verify-export.mjs
```

The numerical reference covers all 72 oriented straight/up/down portal cases, 36 Ball/Walk trajectories with multiple checkpoints, three powered-ball runs and sphere-to-sphere contacts. Native checks also cover inverse links/removal/conflicts, 10,000 rooms, high-speed bounds, camera orthogonality, JSON validation/recovery, signed and bounded gyro forces, axis/button learning, persistence, zero force on pause and failed-effect handling. Smoke checks exercise real application wiring, keyboard movement, wall painting/PNG export, settings capture and restore, plus screenshots of portal rendering, overview and Setup. Generated captures and native exports are ignored by Git.

Measured reference trajectory error on this machine: maximum vector difference approximately 0.00015 (Godot Vector3 uses single precision; JS uses double precision). NVIDIA/X11 rendering and PulseAudio output initialized successfully; Gudsen R3 device discovery and live input polling succeeded. Physical torque response still needs a hands-on driving session.

## Source and license

The original game was created in GPT Sites by the same author. Its source is preserved in `web/` for reference and regression testing; release builds contain the native Godot game. Original assets retain their names and license notices. The native derivative includes the original AGPL-3.0-or-later license under `godot/LICENSE`; the pinned GitHub FFB project supplies the MIT-licensed extension source and build scripts.

Portal seam regression captures compare a sphere in the same physical pose with its center owned by either adjacent room. All three portal types render identically in this test, with 100% opaque coverage in the central sampled area. The native suite also checks portal images in all 72 orientations, two-slot input learning/persistence/release behavior, legacy config migration and the alternating/decaying collision waveform.

## Native passage scaling

Aim at an existing passage and press `=` to grow or `-` to shrink on crossing.
The opposite edit first returns the passage to neutral; each face has one of
three states, −1 / 0 / +1. Both actions support primary and secondary bindings.
Reverse travel applies the inverse factor. **Setup → Game and audio** contains
the shared coefficient (default ×1.10, adjustable ×1.01–×2.00) and audio settings.

Each sphere retains its own cumulative scale, clamped to ×0.2–×4.5 of its initial
radius. At a limit the remaining factor is clamped exactly and further passages
become neutral. Mouths taper around the local gravity-side floor; portal ray
traversal carries scale along each visible path, including repeated room visits.
Linear speed is rotated at a crossing without a scale-dependent boost.
The HUD shows accumulated scale and the aimed passage's factor. JSON saves
include the coefficient, signed passage edits and actor scales; older saves
load with neutral passages and unit actor scale.

No new dependencies: the existing Docker Godot runtime (currently 4.4.1) runs
the implementation and tests. The native suite covers scale bounds, inverse
mapping, flat support planes, crossing dynamics and persistence. GPU regression
compares a scaled sphere at the same seam pose from both owning room frames,
for straight/up/down links in both room and tube geometry:

```bash
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/zoom_render.gd
```

The zoom boundary regression uses `godot/tests/fixtures/zoom-boundary.json`,
a captured quicksave at minimum scale with rotated gravity. It checks removal
of the portal frame; native tests also check continuity across a diagonal
between exit arms and migration of old ×5 saves to the ×4.5 limit.

```bash
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/zoom_boundary.gd
```

The round tube zoom regression also checks the full circular mouth under
straight and folded transport. `zoom_tube_seam.gd` renders a second captured
quicksave and detects non-finite shading before framebuffer conversion, covering
both the collar shape and grazing-ray surface classification.

```bash
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/zoom_tube_seam.gd
```

Zooming tubes now use one inverse deformation of the fitting, with quintic
interpolation and zero derivatives at both ends. Zoomed fittings are evaluated
analytically (the same primitives as the catalogue generator); ordinary fittings
retain their existing catalogue path. Physics, camera clearance and shading use
the same deformed surface. Sphere support distances account for the field's
local gradient rather than mistaking the conservative ray step for a body margin.
No dependencies or runtime version changes are required.

`zoom-smooth-fitting.json` preserves the reported multi-branch quicksave.
Native checks cover exact mouth circles, floor support, continuous tangents,
and driving through that saved passage. The GPU check rejects non-finite shading:

```bash
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/zoom_smooth_fitting.gd
```

Geometry reuse is shared across actors and equivalent rooms. The CPU prepares
at most 64 immutable analytic fitting instruction lists and keeps at most 64
maze deformation profiles, keyed by fitting openings, hall corners, growing
mouths, gravity and the effective scale factor. Each profile holds bounded FIFO
ring caches for exact field points (128), normal samples (64) and sphere queries
(16). Positions are never quantized. Maze topology or coefficient changes clear
the dependent profiles, including the last-profile shortcut. Movement cannot
grow cache memory without a bound. GPU topology and shape textures continue to
be rebuilt only when the maze/markings are dirty; ray shading stays view dependent.

Native tests compare cached and uncached motion for every sphere at ×5 boost,
check sharing across identical rooms, invalidation and all memory limits.
The scene profiler accepts a boost argument and optional `--no-memo`:

```bash
docker compose run --rm godot-test godot --headless --path /work/godot --script res://tests/profile_scene.gd -- res://tests/fixtures/zoom-smooth-fitting.json 5
```

On the saved 33-room scene with three NPCs, 1,200 accelerated physics ticks
improved from mean/p95/max 2.456/5.895/7.870 ms to 1.221/2.032/2.826 ms,
with the same final player room, position and velocity. These are physics tick
timings, not whole-frame render timings. No new dependencies are required.

Square mouths also include the neighboring room's perpendicular cuts. The
neighbor fitting is reflected into the approach and evaluated with transported
gravity and scale, so both sides have the same aperture. A closed side wall's
material continues into this cut instead of rendering a one-sided portal face.
Ball crossing checks test that shared aperture before transferring ownership,
including fast movement. `zoom-box-seam.json` preserves the reported case:

```bash
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/zoom_box_seam.gd
```

Square approach walls continue as complete planes between the opposite shared
mouth bounds. A neighbor-induced cut changes the wall's slope over the whole
room instead of adding a short bevel at the mouth; a horizontal slice therefore
has a trapezoid edge without an intermediate knee. CPU contact uses the same
normalized planes as the shader's analytic ray-plane intersection. Square plane
profiles have a separate 64-entry bound and are invalidated with the other maze
geometry caches. `zoom-box-trapezoid.json` checks the reported camera position;
native checks sample the entire edge and both sides of it.

```bash
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/zoom_box_trapezoid.gd
```

The square seam check also propagates already-derived neighbor wall planes,
not just rooms with their own zoom marker. Mouth bounds cover the full vertical
extent of a neighboring plane. Neighbor constraints are applied in the portal's
actual approach region so another perpendicular mouth cannot change one side
of the same interface. CPU contact and GPU ray intersections use the same
reflected planes. Nested shader loops use texture metadata limits to avoid excessive
compile-time unrolling by the graphics driver.

`box_seam_audit.gd` checks all 72 directed mouths of the saved maze, six gravity
axes, two scales and a 5×5 mouth grid including points near the floor/edges:
21,600 open/solid comparisons. The audit is part of the native suite. The new
camera capture is `zoom-box-propagated.json`:

```bash
docker compose run --rm godot-test godot --headless --path /work/godot --script res://tests/box_seam_audit.gd
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/zoom_box_propagated.gd
```

# FoldRoom Playground

The GitHub Pages demo exports the current native Godot game, with its existing
example scene, room/tube geometry, portal physics, painting and overview. The
first screen stays paused so the player can explicitly capture the mouse and
unlock browser audio. Enter / Resume begins play; Escape pauses.

## Build

Dependencies: Docker Engine + Compose, internet access when building the image.
Godot editor and single-threaded Web release templates are pinned together at
4.4.1, matching the native build. No npm, PHP, native wheel libraries or FFB
dependency are needed. The original `web/` application is independent.

```bash
docker compose -f compose.web.yml run --build --rm web-export
docker compose -f compose.web.yml up -d web-demo
```

Open http://localhost:8081/play/. Output is `artifacts/pages/play/`. Relative
engine/pack URLs support GitHub project Pages paths. Threads, extensions and PWA
are disabled, so Pages does not need COOP/COEP headers or a service worker.
Procedural audio uses Stream playback on Web. JSON file export downloads through
JavaScriptBridge; import uses pasted JSON. Quick save/load uses Godot's browser
storage and depends on the browser allowing IndexedDB.

The exporter copies the source into a clean staging directory excluding both
the host `.godot` cache and all native addons. Import and export fail on Godot
script, shader and export errors, including errors accompanied by exit code 0.

The Web renderer caches four shader variants: Rooms / Tubes, each with or without
scaled passages. Preprocessor branches remove the other geometry's calculations
before GPU compilation. Plain scenes also omit deformation calculations. This
retains scaling while avoiding the combined shader that crashed Chrome's GPU
process on the scale demo. Runtime loop bounds prevent nested constant-loop
expansion.

Scaled Rooms bake wall planes into a texture on the CPU using the same
`FoldMaze.box_wall_plane` equations as physics. A cached graph tracks each room's
reachable gravity and scale states across portals. The shader follows that graph
and reads the prepared planes instead of inlining the nested wall calculations
that still exceeded Chrome's GPU watchdog after geometry specialization.

The same Web shader can be checked on the native GPU without a browser:

```bash
docker compose run --rm --no-deps godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/portal_render.gd -- --web-demo-shader
```

This runs the six existing sphere-ownership and tube-seam cases for straight,
upward and downward portals using the Web shader selection path.

Scaled room and tube seams use the same selection path in this GPU regression:

```bash
docker compose run --rm --no-deps godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/zoom_render.gd -- --web-demo-shader
```

## Chromium regression

Launch a separate native Chrome profile with a local DevTools port, then run
Playwright from Docker (no Node/npm on the host):

```bash
/opt/google/chrome/google-chrome --user-data-dir=/tmp/foldroom-chromium-demo --remote-debugging-address=127.0.0.1 --remote-debugging-port=9223 --no-first-run --no-default-browser-check http://localhost:8081/play/
docker compose -f compose.web.yml run --build --rm web-browser-test
```

The test uses its own page in the connected browser. It checks loading, input,
Escape and pointer release without a keyboard event, captures screenshots and
console output in `artifacts/web-browser/`, and fails on page errors, renderer
crashes and lost WebGL contexts. The host network mode is for Linux, so the test
container can reach Chrome's localhost DevTools listener.

The default Example is the scale demo. The browser test keeps it running for
35 seconds after startup, then switches Rooms / Tubes and waits another 35
seconds, covering the previous GPU-watchdog failure window in both geometries.

Browser pointer-lock loss and pointer-lock errors pause the game. Escape in a
paused Web game leaves it paused; resume with Enter or the Resume button.

Verified locally: Web release export with no script/export errors; native suite
with 50,800 checks and no failures; all six portal ownership/tube seam cases for
the Web shader; six scaled portal cases in Rooms and Tubes; Chrome 155.0.8059.84
running the scale demo for 35 seconds in each geometry, Escape pause and pointer
release without a key event, with no page errors or lost WebGL context. The
Chrome checks use its default GPU flags, including the existing Wayland setup. Browser
captures and console output are under `artifacts/web-browser/`.

## Verification plan

- Build from a clean staging project: import scripts, export HTML/JS/WASM/PCK;
  each required artifact must be nonempty and export logs must have no errors.
- Run native regression tests after shared UI/control changes: geometry,
  physics, controls, persistence and audio synthesis.
- Serve under `/play/` without isolation headers: canvas renders the example,
  with no native extension load attempt or FFB setup controls.
- Click Resume: pointer capture, W/S drive/brake, A/D steer; Escape returns to
  the menu, including after browser pointer-lock release.
- Switch Rooms / Tubes, create straight/up/down passages, add a ball and scroll
  into overview; return to first-person view.
- Open Controls / Audio and rebind a key; exercise synthesized sound after user
  interaction. Download JSON, paste it into Import, and quick save/load.
- Open the exported HTML in Chromium and Firefox with WebGL 2 available. Check
  the browser console for script, shader, audio and WebAssembly errors.

Reference: [Godot 4.4 Web export documentation](https://docs.godotengine.org/en/4.4/tutorials/export/exporting_for_web.html).

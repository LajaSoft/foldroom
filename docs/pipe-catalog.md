# Local pipe fitting catalogue

The separate native Catmull–Clark prototype is documented in
[`godot/docs/subdivision-pipes.md`](../godot/docs/subdivision-pipes.md).

The cell side remains 6. Tube radius is 1.65 and sphere radius is 0.33. An elbow has a centerline radius of 3, leaving an inner bend radius of 1.35. These dimensions leave enough room for a curved fitting within a cell; nothing protrudes into a different cell's implicit solid geometry.

## Enumeration

A 3×3×3 neighborhood has 26 neighbors, but FoldRoom permits connections through its six faces only. There are therefore 2⁶ = 64 opening masks. Signed permutations of three axes give 48 rotations/reflections. Applying them to each mask gives ten equivalence classes:

| Openings | Family | Oriented masks |
| --- | --- | ---: |
| 0 | Isolated room | 1 |
| 1 | End cap | 6 |
| 2 | Straight | 3 |
| 2 | Elbow | 12 |
| 3 | Planar T | 12 |
| 3 | Trihedral | 8 |
| 4 | Planar cross | 3 |
| 4 | Spatial four-way | 12 |
| 5 | Five-way | 6 |
| 6 | Six-way | 1 |

There are nine nonempty families. The manifest includes every mask's canonical representative and transform. Portal kind, neighbor state, gravity and transported frame are excluded from this classification. Connecting a T to an elbow does not require a new family.

## Geometry and runtime cost

`tools/build_pipe_catalog.py` defines circular half-cylinders, exact quarter-circle swept elbows and symmetric blends for branching fittings. Branching surfaces transition into standard round collars inside the last 0.9 units. The thinner section leaves room for this transition. Two-mouth elbows remain exact swept circles.

The generator prepares all 64 orientations on 49³ grids over ±3.6, providing enough margin for a sphere crossing a face. The gzip archive contains little-endian float32 values in `[mask,z,y,x]` order. At startup Godot uploads the same data to a 2D slice atlas. Each ray step performs two bilinear texture reads; physics performs the equivalent eight-value interpolation. Both operate only on the local mask. Normals are differentiated over a finite interval, with a high-precision sampler to avoid color-boundary noise.

Complete squares of four straight passages remove their shared columns. Each room caches a 12-bit mask of these open corners alongside its fitting mask. Physics and the shader union the same radius-1.65 dilated quadrants with the catalogue field. This retains flat floor and ceiling at ±1.65 inside the hall and rounds its exterior walls. Dilating the entire quadrant also covers the old elbow surface along its approach; clipping a slab to the quadrant would leave solid fins at the floor and ceiling. Incomplete squares and folded passages retain their fitting surfaces. The masks rebuild after topology changes; no neighbor traversal runs during ray marching. Portal transport itself is unchanged. The atlas is included in release exports.

## Native ray traversal

The native tube renderer selects tube-only shader variants, with a separate
variant when the maze has no zoom links. Returning to rooms restores the room
renderer. No web sources are changed by this specialization.

Each pixel follows its own portal path. Only rooms reached by that ray evaluate
their surfaces; an additional whole-graph visibility walk is not required for
this renderer. The opening mask, open corners and six scale ratios are prepared
once per visited room, then reused by marching and normal evaluation. Zoom
ratios still use the transported gravity and accumulated scale of that path.
At each portal hop the destination's incoming collar uses the inverse of the
actual forward ratio, including partial or fully clamped zoom. It does not use
the coefficient of a hypothetical reverse traversal. A fully inactive
deformation uses the ordinary catalogue surface as well. Reverse movement
still evaluates its own zoom normally; no actor history or movement rule is
changed by this visual correction.

Straight zoom fittings interpolate their two circular end sections over the
entire six-unit cell, with zero first and second derivatives at the endpoints.
The section center follows the floor anchor, keeping the bottom at the same
height. Both ends can have independent narrowing; CPU collisions and the GPU
use the same profile. Branching fittings retain their localized mouth blends.
The regression fixture `zoom-straight-taper.json` captures the blue-room Quick
Save that previously concentrated the transition in the last 1.5 units.

Straight two-mouth fittings with no open corners or active deformation use an
exact ray/cylinder intersection clipped to the next cell boundary. Elbows,
junctions, expanded halls and deformed mouths retain their existing surface
evaluation. Physics, corridor lengths and circular sections are unchanged.
The cylinder replaces a sampled surface, so tiny sub-grid shading differences
are expected. GPU regressions compare both methods on all three axes, including
cameras close to the wall. `tube_fast_trace=false` selects marching for comparison.

The performance script accepts `--straight-tube` for a 24-cell corridor,
`--march-tubes` to disable exact cylinder intersections, and
`--reference-shader=/absolute/path.gdshader` to benchmark a saved shader in the
same process setup. Pass these after Godot's `--` separator. A reference path
must be accessible inside the container.

Measured on Godot 4.4.1, OpenGL Compatibility, NVIDIA RTX 5060 Ti at
1280×720 (30 synchronised frames including readback): the current local Quick
Save decreased from 11.286 ms to 7.976 ms median, and the 24-cell straight
corridor from 4.263 ms to 1.773 ms. These compare the original generic shader
with the specialized shader and exact straight intersections together; they
do not isolate either optimization or predict every maze's performance.

## Migration

Old tube saves contain radius 0.5 spheres. Their nearest pipe centerline is retained; the transverse offset and velocity are multiplied by 0.66, and radius becomes 0.33. Angular speed, gravity direction, spin and portal ownership are retained. Collision projection then verifies the complete sphere. Open mouths do not clamp axial progress. Radius 0.33 saves are already migrated. Returning to rooms restores radius 0.5.

Ball/Walk transitions use the active sphere radius. The existing room trajectories, default room sphere size and web state fixture remain unchanged. NPC motor speed is 4.29 in tubes; acceleration and gravity are scaled consistently.

## Reproduction and checks

Generation requires Python with NumPy (validated with NumPy 2.3.5). The runtime remains Godot 4.4.1. Blender previews were built in Blender 5.2.2 LTS using the same geometry definition, in a separate scene without deleting the user's scene.

```bash
python tools/build_pipe_catalog.py
# Inside Blender: run tools/preview_pipe_catalog.py

docker compose run --rm godot-test
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/portal_render.gd
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/zoom_tube_limits.gd
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/zoom_straight_taper.gd
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/pipe_performance.gd
```

Native regressions retain room physics, controls, collisions, stable steering, motor and JSON checks. Geometry checks cover every opening mask, the 72 straight/up/down portal orientations, constant straight sections, circular elbow sections, nonpenetrating sphere support, topology cache invalidation and old/new save scaling. GPU checks retain portal ownership tests and compare the two-read atlas lookup against explicit eight-value interpolation. Analytic comparisons allow for the grid's finite spatial resolution.

The performance script uses the current Quick Save when available. It warms the shader, measures 30 frames at 1280×720 with VSync disabled, and forces image readback after each frame so the result includes GPU completion and readback overhead. It also times 10,000 CPU field queries. It does not write the save or apply wheel forces.

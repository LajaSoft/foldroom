# Local pipe fitting catalogue

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
docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/pipe_performance.gd
```

Native regressions retain room physics, controls, collisions, stable steering, motor and JSON checks. Geometry checks cover every opening mask, the 72 straight/up/down portal orientations, constant straight sections, circular elbow sections, nonpenetrating sphere support, topology cache invalidation and old/new save scaling. GPU checks retain portal ownership tests and compare the two-read atlas lookup against explicit eight-value interpolation. Analytic comparisons allow for the grid's finite spatial resolution.

The performance script uses the current Quick Save when available. It warms the shader, measures 30 frames at 1280×720 with VSync disabled, and forces image readback after each frame so the result includes GPU completion and readback overhead. It also times 10,000 CPU field queries. It does not write the save or apply wheel forces.

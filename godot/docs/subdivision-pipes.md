# Catmull–Clark tube prototype

Select **Rooms / Tubes / Catmull–Clark** in the pause menu. The button cycles
through all three modes. From an existing tube Quick Save, one click selects
Catmull–Clark. JSON stores the new mode as `geometry: "subdivision"`; existing
`rooms` and `tubes` files retain their meaning. The native application is the
only target of this implementation.

## Cached symbols

`SubdivisionPipes` builds a manifold quad cage from the six-face opening mask.
The cage contains a central volume, passage arms and ghost collars extending
beyond the logical cell. Completed ordinary 2×2 squares remove shared columns;
a verified complete 2×2×2 cube also removes its shared central volume. Folded
connections do not imply physical adjacency. Zoom on an open corner remains
forbidden by the existing topology rules.

Straight passages and ordinary collars use eight-point circular control rings,
with compensation for the radius shrinkage of two subdivision passes. Expanded
halls retain their wider floor geometry. This is a polygonal approximation to
a circular section; subdivision is not an exact rational circle evaluator.

Two Catmull–Clark subdivision passes are applied to seven stencil channels:
one base position and six mouth deformation channels. Face points, interior
edge/vertex rules and open-boundary rules are evaluated once per symbol. Thus
coefficient changes do not subdivide the cage again. Startup/import and
geometry edits prepare symbols used by the maze; unused opening masks are not
built speculatively. The test suite does build all 64 masks.

A deformation channel stores a weighted transverse position and its scalar
weight. At evaluation time the floor-projected gravity anchor is included in
that channel. Consequently control points on a horizontal passage's floor
stay at the same height for both growing and shrinking transitions. The
straight symbol interpolates its two ends; junction arms use local blends.
Shared collars have identical, constant sections and support geometry on both
sides of the portal plane.

CPU geometry profiles are keyed by symbol, gravity and the six effective mouth
widths. They include evaluated vertices, a refitted BVH and an exact sample
memo. Up to 128 profiles are retained. A topology or coefficient edit clears
these profiles. Immutable subdivision channels are retained. Actor scale
limits still determine effective ratios, including partial last steps.

## Rendering and collision

GPU textures contain the same vertex channels and triangle indices used by CPU
collision. Rays follow the existing portal graph, transforming position,
direction, gravity and accumulated scale at each transition. Each visited
symbol uses triangle intersections through a stackless BVH instead of distance
field marching. Per-node channel bounds conservatively enclose every evaluated
triangle for the current widths. Geometry channels and ratios are prepared
independently of the pixel's triangle tests; evaluated vertex displacements
remain GPU arithmetic.

CPU collision queries use closest points on these triangles and nearest-first
BVH traversal. Sphere clearance is center-to-surface distance, rather than
clearance of the old implicit pipe model. Smooth shading interpolates vertex
normals with the local face rotation; collision uses geometric face normals and combines tied supporting facets at
shared edges to avoid a diagonal-triangle contact bias.

This is a finite tessellation of the subdivision surface, not an exact limit
surface evaluator. Logical portals still use the existing planar cell cuts
and similarity transforms. Arbitrary curved portal transfer is not implemented.
There is no claim of a speedup over the mature circular-pipe renderer: this
prototype establishes the shared geometry and cache first.

## Checks

Runtime: Godot 4.4.1, OpenGL Compatibility. No new runtime dependencies.

```bash
docker compose run --rm godot-test

docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/subdivision_render.gd

docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/zoom_tube_limits.gd -- --subdivision

docker compose run --rm godot dbus-run-session godot --path /work/godot --display-driver x11 --audio-driver Dummy --script res://tests/pipe_performance.gd -- --subdivision
```

The native suite checks every mask, coefficient-cache reuse, floor height and
normal in all three passage axes at minimum/ordinary/maximum actor scales,
stationary floor contact without longitudinal rolling, the complete 2×2×2
volume and cache invalidation, Quick Save traversal, and JSON round trips.
The GPU suite compares 2,304 rays per case with Godot PhysicsServer3D raycasts
against an independent concave collider, for straight, bent, branching and
six-mouth symbols at three scales. Zoom-limit image tests cover straight and
rotated chains, saturated steps, partial steps and normal reverse actions.

# Workplanes and sketches

`Smith.Plane` defines a local coordinate frame. `Smith.Sketch` describes a connected 2D region in that frame, optionally with holes. Both are ordinary immutable Elixir values; construction performs no native operations. `Smith.extrude/2` turns a sketch into a normal Smith model recipe, ready for holes, booleans, fillets, assemblies, and export.

```elixir
alias Smith.{Plane, Sketch}

model =
  Sketch.rectangle(60, 40)
  |> Sketch.fillet(radius: 2)
  |> Smith.extrude(5)
  |> Smith.hole(
    on: Plane.xy(z: 5),
    at: {10, 0},
    diameter: 8,
    through: :all
  )

{:ok, result} = Smith.evaluate(model)
{:ok, files} = Smith.export(result, "output", name: "mount", on_bed: true)
```

<div class="smith-doc-preview" data-preview="sketches-0-result" data-model="result" data-label="Mounting plate">
<p>Interactive preview available in HexDocs.</p>
</div>

## Frames

| Constructor      | World origin | Local X | Local Y | Normal |
| ---------------- | ------------ | ------- | ------- | ------ |
| `Plane.xy(z: z)` | `{0, 0, z}`  | +X      | +Y      | +Z     |
| `Plane.yz(x: x)` | `{x, 0, 0}`  | +Y      | +Z      | +X     |
| `Plane.xz(y: y)` | `{0, y, 0}`  | +X      | +Z      | −Y     |

The offset defaults to zero. Instead of an offset, use `origin: {x, y, z}`; supplying both is an error. All frames are right-handed.

For arbitrary orientation:

```elixir
plane = Plane.new(
  origin: {10, 20, 30},
  normal: {1, 2, 3},
  x_direction: {1, 0, 0}
)

{:ok, world_point} = Plane.to_world(plane, {5, 8})
{:ok, unit_normal} = Plane.normal(plane)
oriented = Sketch.rectangle(10, 16, on: plane)
```

<div class="smith-doc-preview" data-preview="sketches-1-oriented" data-model="oriented" data-label="Sketch on an inclined plane">
<p>Interactive preview available in HexDocs.</p>
</div>

`new/1` defaults to world origin, +Z normal, and +X direction. It normalizes the normal, projects X onto the plane, and derives local Y from their cross product. Zero directions and an X direction parallel to the normal are invalid. Supply an appropriate `x_direction:` when the default +X would be parallel. Frame queries return tagged results; model evaluation reports invalid frames as Smith errors. Distances are millimeters and sketch arc angles are degrees.

## Outlines and alignment

- `Sketch.rectangle(width, height, opts)` defaults to centered local bounds.
- `Sketch.circle(radius, opts)` defaults to a center at local `{0, 0}`.
- `Sketch.polygon(points, opts)` retains the supplied 2D coordinates by default.
- `Sketch.profile(edges, opts)` uses an ordered, connected, closed sequence of local line/arc descriptions.

All accept `on: plane` and `at: {u, v}`. Rectangles, circles, and polygons also accept `align: {x, y}`, with each axis one of `:min`, `:center`, or `:max`. Alignment anchors the corresponding bounding-box minimum, midpoint, or maximum at the local origin, then applies `at:`. `align: :none` retains authored coordinates. Profiles retain their authored coordinates and accept `at:`, but do not accept `align:`.

```elixir
# X bounds 10..14, Y bounds 14..20.
rectangle = Sketch.rectangle(4, 6, align: {:min, :max}, at: {10, 20})

# A semicircle authored in 2D, placed on a side plane.
semicircle = Sketch.profile([
  Sketch.arc({0, 0}, 2, 0, 180),
  Sketch.line({-2, 0}, {2, 0})
], on: Plane.yz(x: 10))
|> Smith.extrude(3)
```

<div class="smith-doc-preview" data-preview="sketches-2-rectangle" data-model="rectangle" data-label="Aligned rectangle">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="sketches-2-semicircle" data-model="semicircle" data-label="Extruded semicircle">
<p>Interactive preview available in HexDocs.</p>
</div>

`Sketch.line/2`, `arc/4`, and `spline/2` return edge descriptions for `profile/2`. Arc arguments are center, radius, start angle, and signed sweep. Positive angles turn counterclockwise in the local XY frame. Closure and topology are checked by the native kernel.

`Sketch.on(sketch, plane)` reuses an outline in a different frame without changing the original:

```elixir
outline = Sketch.rectangle(20, 10)
front = outline |> Smith.extrude(3)
side = outline |> Sketch.on(Plane.yz(x: 25)) |> Smith.extrude(3)
```

<div class="smith-doc-preview" data-preview="sketches-3-front" data-model="front" data-label="Front profile">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="sketches-3-side" data-model="side" data-label="Side profile">
<p>Interactive preview available in HexDocs.</p>
</div>

## Corners and extrusion

Use `Smith.extrude/3` for symmetric depth (`both: true`) or wall taper in degrees
(`taper: 5`). Use `Smith.extrude_until/3` to terminate at an infinite plane.
The [extrusion guide](extrusion.html) explains extent, hole behavior, and limits.

`Sketch.fillet(sketch, radius: r)` sets a uniform 2D corner radius on a rectangle or strictly convex polygon. Calling it again replaces the radius. It constructs tangent lines and circular arcs, accounting for each corner angle and either polygon winding. The radius must leave a positive straight segment between adjacent arcs. Concave polygons, collinear/degenerate corners, arbitrary arc profiles, circles, and overlapping fillets are rejected. Fillets apply to the original outline, before any sketch cuts, regardless of call order. They do not round corners introduced by a cut. Sketch constraint solving and general corner editing remain unsupported.

`Smith.extrude(sketch, distance)` uses the plane's normal. Positive distances extend along the normal and negative distances extend behind the plane. Zero is invalid. Polygon winding does not change the extrusion direction. Bare `Smith.evaluate(sketch)` returns an evaluated face for queries such as `OCEx.area/1`; extrude before printable export or adding it as an assembly part.

`Smith.extrude(face_model, {x, y, z})` accepts a world-vector displacement for a planar face recipe. The vector must have a normal component; it may also have an in-plane component for an oblique extrusion. The scalar form is only available for sketches.

## Sketch cutouts

```elixir
ring = Sketch.circle(25) |> Sketch.cut(Sketch.circle(15)) |> Smith.extrude(4)

plate =
  Sketch.rectangle(60, 40)
  |> Sketch.fillet(radius: 2)
  |> Sketch.cut([
    Sketch.circle(4, at: {-20, 0}),
    Sketch.circle(4, at: {20, 0})
  ])
  |> Sketch.on(Plane.yz(x: 10))
  |> Smith.extrude(5)
```

<div class="smith-doc-preview" data-preview="sketches-4-ring" data-model="ring" data-label="Ring">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="sketches-4-plate" data-model="plate" data-label="Side plate">
<p>Interactive preview available in HexDocs.</p>
</div>

`Sketch.cut/2` accepts a sketch or an ordered list. An empty list returns the original sketch. Cutters can overlap, contain their own cutouts, meet the outer edge, or miss it entirely. Subtraction uses set semantics: repeated cuts do not remove material twice, and a missed cut leaves the region unchanged.

A cutter without `on:` or `Sketch.on/2` inherits its parent's frame, including in nested cuts. Its `at:` offset is relative to that frame's origin, independent of the parent's alignment or `at:`. Moving the parent with `Sketch.on/2` also moves these inherited cutters. A cutter with an explicit plane keeps that world placement; it must be coplanar with its parent at evaluation. Coplanar frames may have different origins, in-plane axes, or opposite normals. There is no implicit projection between different planes.

The result must be one connected face, optionally containing multiple holes. Empty and disconnected results fail with `:empty_sketch` and `:disconnected_sketch`; mismatched planes fail with `:non_coplanar_sketches`. Use separate sketches and solids when a design needs disconnected regions. Invalid cutter inputs also return tagged evaluation errors.

## Revolve and loft

```elixir
# A sleeve formed by rotating an XZ cross-section about world Z.
sleeve =
  Sketch.rectangle(4, 20, align: {:min, :min}, at: {12, 0}, on: Plane.xz())
  |> Smith.revolve({0, 0, 1})

transition =
  Smith.loft([
    Sketch.rectangle(30, 20),
    Sketch.rectangle(20, 10, on: Plane.xy(z: 30))
  ])
```

<div class="smith-doc-preview" data-preview="sketches-5-sleeve" data-model="sleeve" data-label="Revolved sleeve">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="sketches-5-transition" data-model="transition" data-label="Rectangular loft">
<p>Interactive preview available in HexDocs.</p>
</div>

`Smith.revolve(profile, axis, degrees \\ 360, origin \\ {0, 0, 0})` accepts a sketch, including cutouts, or an existing world-coordinate face recipe. Axis and origin are world coordinates, consistent with `Smith.rotate/4`. Angles must be greater than zero and at most 360 degrees; reverse the axis vector for the opposite direction. Place the cross-section on one side of the rotation axis so its sweep forms a valid solid. Partial revolutions include end faces.

`Smith.loft(sketches, opts)` takes at least two ordered sketches on their respective planes. By default it produces a **ruled** solid: each adjacent pair is connected directly, without smoothing across intermediate sections. Rectangles, circles, polygons, rounded outlines, and line/arc/spline profiles are supported. Each section must have one closed boundary; a sketch with holes fails with `:loft_profile_has_holes`. Edge cutouts that retain a single boundary are supported. The kernel determines edge correspondence; there are no seam controls or guide rails. Set `ruled: false` to interpolate smoothly through the sections; the result may overshoot between them. See [paths, lofts, and shells](paths-and-shells.md) for an example. Degenerate or invalid solids fail during evaluation.

Both return model recipes for further transformations, booleans, assembly placement, and printable export.

Open the [Livebook examples](livebook.md) to inspect each modeling stage and generate verified printable files.

## Holes

`Smith.hole(model, on: plane, at: {u, v}, diameter: d, through: :all)` drills along the plane normal through its local point. `at:` defaults to `{0, 0}`. The cutter spans the body's projected world bounds, including disconnected solids; the plane itself may lie outside the body. A hole that removes no material fails with `:hole_misses_body`. Use `depth:` instead of `through:` for a flat-bottomed blind hole into the negative plane normal. See [mechanical parts](mechanical-parts.md) for entry placement and recessed holes.

`on: :top` selects the highest outward +Z planar face, positions relative to its area centroid, and drills along world Z. Earlier cuts can move that centroid; use a fixed plane when hole coordinates must remain fixed. Explicit planes do not select or attach to a face and do not resolve topology names.

## Complete examples

The [Livebook guide](livebook.md) includes runnable profiles and an assembly built from reusable part recipes, with previews and verified printable exports.

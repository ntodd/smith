# Modeling with functions and pipelines

A Smith model records operations. See [CAD concepts](cad-basics.md) for the geometry vocabulary. Every modeling operation returns a new recipe, so feature functions can accept a body, add a feature, and return the next body. `Smith.evaluate/1` executes the ordered operations and returns a native shape.

## Primitives and placement

Boxes, cylinders, and cones accept the same placement options:

- `at: {x, y, z}` anchors the primitive in world coordinates; default `{0, 0, 0}`.
- `align: {x, y, z}` selects `:min`, `:center`, or `:max` independently for each axis. The selected point of the primitive's bounds lands at `at:`.

| Primitive | Default alignment | Meaning of dimensions |
| --- | --- | --- |
| `Smith.box(width, depth, height, opts)` | `{:min, :min, :min}` | Positive X, Y, Z extents |
| `Smith.cylinder(radius, height, opts)` | `{:center, :center, :min}` | Radius and positive Z height |
| `Smith.cone(bottom_radius, top_radius, height, opts)` | `{:center, :center, :min}` | Bottom/top radii and positive Z height |

All dimensions are millimeters. Dimensions must exceed the native length tolerance of 1.0e-7 mm; a cone may have one zero end radius.
Alignment uses bounds before any subsequent rotations. A cone's X/Y bounds include
the larger radius, and its centered Z is halfway up its height, regardless of its
center of mass. Unsupported options, malformed points, and invalid alignment
return a `Smith.Error` with reason `:invalid_options` during evaluation.
Invalid dimensions retain the native `:invalid_argument` error.

```elixir
boss = Smith.cylinder(5, 8, at: {15, 0, 4})
plate = Smith.box(40, 20, 4, align: {:center, :center, :min})
model = plate |> Smith.fuse(boss)
```

<div class="smith-doc-preview" data-preview="modeling-0-model" data-model="model" data-label="Plate and boss">
<p>Interactive preview available in HexDocs.</p>
</div>

To describe a centered footprint between two elevations, keep the height explicit:

```elixir
bottom = 6
top = 14
body = Smith.box(30, 20, top - bottom,
  at: {12, -8, bottom}, align: {:center, :center, :min})
```

<div class="smith-doc-preview" data-preview="modeling-1-body" data-model="body" data-label="Positioned block">
<p>Interactive preview available in HexDocs.</p>
</div>

Use sketches for local 2D outlines and arbitrary planes; their `at:` uses two local coordinates, while
solid primitive `at:` uses three world coordinates.

`Smith.rotate(model, axis, degrees, origin)` uses a world axis vector and optional world origin (default zero). Rotation is right-handed. Transform order matters: translating then rotating moves the translated position around the rotation axis. Use `Smith.Plane` and local sketches for side-mounted profiles rather than manually rotating every point.

## Spheres and rings

`Smith.sphere(radius)` and `Smith.torus(major_radius, minor_radius)` default to centered bounds on all three axes. The torus lies around world Z; its major radius reaches the tube center, and its minor radius is the tube radius. Both support the standard world `at:` and three-axis `align:` options. Rotate the result for a different orientation. Tori must have major radius greater than minor radius by more than 1.0e-7 mm.

```elixir
ring = Smith.torus(10, 2, align: {:center, :center, :min})
ball = Smith.sphere(3, at: {0, 0, 3})
```

<div class="smith-doc-preview" data-preview="mechanical-parts-0-ring" data-model="ring" data-label="Torus">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="mechanical-parts-0-ball" data-model="ball" data-label="Sphere">
<p>Interactive preview available in HexDocs.</p>
</div>

## Boolean composition

A Boolean combines the material occupied by shapes. A boss is a raised pad, often
used around a fastener; a bore is a cylindrical opening.

`fuse/2` adds material, `cut/2` subtracts a tool, and `common/2` retains the intersection. Fuse and cut also accept ordered lists. An empty list leaves the recipe alone. Each operation resolves its tool recipe and cleans same-domain topology afterward.

```elixir
bores = for x <- [-12, 12], do: Smith.cylinder(2, 6, at: {x, 0, -1})
model = plate |> Smith.cut(bores)
```

<div class="smith-doc-preview" data-preview="modeling-2-model" data-model="model" data-label="Boolean cuts">
<p>Interactive preview available in HexDocs.</p>
</div>

Extend cutting tools past the surface when the intended feature is through-all; this avoids relying on coincident faces. Alternatively use `Smith.hole/2` with `through: :all`, which sizes its cutter across the complete body.

A missed Boolean tool can be a no-op; a missed `hole/2` fails explicitly. Disjoint unions can contain multiple solids. `Smith.compound/1` groups shapes without fusing and preserves separate boundaries. For separately named and printable parts, use [assemblies](assemblies.md).

## Fillets and chamfers

```elixir
model =
  Smith.box(60, 40, 5)
  |> Smith.fillet(edges: {:parallel, :z}, radius: 2, count: 4)
  |> Smith.hole(on: :top, diameter: 8, through: :all)
```

<div class="smith-doc-preview" data-preview="modeling-3-model" data-model="model" data-label="Fillet and hole">
<p>Interactive preview available in HexDocs.</p>
</div>

Fillet/chamfer selectors run against the body at that evaluation step. `{:parallel, axis}` selects straight edges parallel to the world axis; curved edges are not included. `edges: :all` selects all edges. A predicate receives native edge information together with its world bounds and a point at the middle of its parameter interval. For a spline, that point need not divide its length in half:

```elixir
round_vertical = fn edge ->
  edge.type == :line and abs(elem(edge.direction, 2)) > 0.99
end

model = Smith.box(20, 10, 4) |> Smith.fillet(edges: round_vertical, radius: 1, count: 4)
```

<div class="smith-doc-preview" data-preview="modeling-4-model" data-model="model" data-label="Selected vertical fillets">
<p>Interactive preview available in HexDocs.</p>
</div>

For reusable selections, compose `Smith.Selector` filters such as `Selector.type(:line) |> Selector.parallel(:z)`. The same selector machinery supports face queries and shell openings. `Smith.edges(result, selector)` and `Smith.faces(result, selector)` inspect evaluated geometry.

Use `count:` when the design expects a particular number of edges. Unexpected counts fail rather than rounding unintended geometry. Avoid relying on enumeration order; topology can change after booleans and cleanup. Predicates must return booleans, and exceptions in your own callbacks propagate.

The order of finishing operations affects the result. Filleting an outside edge before drilling can differ from filleting all edges after drilling. Use named functions to make that order clear.

## Hole placement

`on: :top` selects the highest outward +Z planar face. Its default hole
position is the **area centroid of that face**, which can move after a cut.
Two successive top holes with the same offset need not share the same XY
position. If the design specifies fixed hole coordinates, use a plane:

```elixir
model =
  Smith.box(60, 40, 5)
  |> Smith.hole(on: Smith.Plane.xy(), at: {10, 20}, diameter: 4, through: :all)
  |> Smith.hole(on: Smith.Plane.xy(), at: {50, 20}, diameter: 4, through: :all)
```

<div class="smith-doc-preview" data-preview="modeling-5-model" data-model="model" data-label="Fixed hole positions">
<p>Interactive preview available in HexDocs.</p>
</div>

The plane supplies a frame and drill direction; it does not need to coincide
with a face. The cutter spans the body's projected bounds. If several top
faces share the highest elevation, `on: :top` fails with
`:ambiguous_top_face` instead of choosing one.

## Curves and solid generation

`Smith.line/2`, `arc/6`, and `spline/2` describe world-coordinate edges. `Smith.profile/1` joins ordered edges into a closed planar face. `Smith.polygon/1` creates a planar face from world-coordinate points. Extrude a face recipe with a world vector.

Prefer `Smith.Sketch` for local 2D outlines. Its signed scalar extrusion, full/partial revolve, and loft are covered in [Sketches and planes](sketches.md). See [paths, lofts, and shells](paths-and-shells.md) for open paths, smooth interpolation, sweeps, and hollowing.

## Evaluation and branching

```elixir
base = Smith.box(20, 10, 4)
rounded = base |> Smith.fillet(edges: {:parallel, :z}, radius: 1)
drilled = base |> Smith.hole(on: :top, diameter: 3, through: :all)
```

<div class="smith-doc-preview" data-preview="modeling-6-base" data-model="base" data-label="Base">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="modeling-6-rounded" data-model="rounded" data-label="Rounded variant">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="modeling-6-drilled" data-model="drilled" data-label="Drilled variant">
<p>Interactive preview available in HexDocs.</p>
</div>

All three recipes remain independent. For a costly stage, evaluate once and branch
from `Smith.from_result(result)` to avoid rebuilding it for each variant:

```elixir
{:ok, evaluated_base} = Smith.evaluate(base)
snapshot = Smith.from_result(evaluated_base)
rounded_snapshot = snapshot |> Smith.fillet(edges: {:parallel, :z}, radius: 1, count: 4)
```

<div class="smith-doc-preview" data-preview="modeling-snapshot" data-model="rounded_snapshot" data-label="Variant from evaluated geometry">
<p>Interactive preview available in HexDocs.</p>
</div>

A snapshot contains the geometry from one evaluation. Reevaluating the source
produces a new snapshot; it does not change the old one. Keep the Elixir recipe
for editing. The evaluated `revision` is a SHA-256 hash of serialized BREP, used
to identify exports and detect stale results. The hash can differ across kernel
versions or platforms.

For measured filters, sorting, topology metadata, mirrored parts, blind holes, and recessed fasteners, see [mechanical parts](mechanical-parts.md).

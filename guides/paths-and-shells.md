# Paths, lofts, and shells

These operations build solids from a path, a sequence of sections, or an existing body. Dimensions are in millimeters. All Smith constructors below return recipes; geometry and selection errors appear when you call `Smith.evaluate/1`.

## Select geometry by its meaning

Selectors are ordinary immutable values. Each filter narrows the preceding selection:

```elixir
alias Smith.{Path, Plane, Selector, Sketch}

top = Selector.type(:plane) |> Selector.facing(:z) |> Selector.at_max(:z)
blank = Smith.box(40, 30, 18)
{:ok, body} = Smith.evaluate(blank)
{:ok, [opening]} = Smith.faces(body, top)
{:ok, opening_info} = OCEx.face_info(opening)
```

`facing(:z)` selects outward +Z planar faces. `facing({:z, :negative})` selects outward −Z faces. `parallel(:z)` ignores sign: it selects straight edges along Z, or planar faces with normals along Z. It does not mean the face itself lies parallel to Z.

`at_max(:z)` and `at_min(:z)` compare face area centroids or edge parameter midpoints, not bounding-box corners. They keep all ties within 1.0e-7 mm. A query returns an empty list when no geometry matches; it never chooses an arbitrary face from a tie.

For application-specific selection, use `Selector.where(fn info -> ... end)`. Face metadata includes area, centroid, plane normal where available, and bounds. Edge metadata includes length, geometry type, radius where available, bounds, and parameter midpoint. Predicates must return booleans; your exceptions propagate.

Selection handles belong to the evaluated body. Reuse the selector recipe after a modeling operation, not a previously extracted handle. A feature's `count:` option catches a change in how many faces or edges match.

## Hollow a solid

Remove the top face and build a 2 mm wall inward:

```elixir
tray = blank |> Smith.shell(openings: top, thickness: -2, count: 1)
{:ok, hollow} = Smith.evaluate(tray)
{:ok, volume} = OCEx.volume(hollow.shape)
true = abs(volume - (40 * 30 * 18 - 36 * 26 * 16)) < 1.0e-6
```

The floor is also 2 mm thick. Negative thickness retains the exterior dimensions; positive thickness builds outside the source surfaces. `join: :arc` is the default and rounds gaps between offset surfaces. `join: :intersection` extends adjacent surfaces to their intersection.

Multiple selected openings create multiple open faces. An empty selection fails with `:empty_selection`. Use `count: 1` when your design requires exactly one opening; ties then fail with `:selection_count_mismatch`.

Small radii and narrow details can prevent a requested thickness from fitting. OCEx validates the returned solid, and checks that an inward result removes material and stays inside its source within its documented volume tolerance. These checks do not measure every wall or prove freedom from arbitrary self-intersections. Inspect critical dimensions in your design.

Shelling requires one solid and at least one opening. It does not thicken an open face, offset a sketch, or create a sealed cavity.

## Build an open path

A path is an ordered chain of world-coordinate edge recipes:

```elixir
straight = Path.new([Smith.line({0, 0, 0}, {0, 0, 20})])
longer = Path.append(straight, Smith.line({0, 0, 20}, {0, 0, 30}))
{:ok, wire} = Smith.evaluate(longer)
{:ok, 30.0} = OCEx.length(wire.shape)
```

Use `Smith.line/2`, `Smith.arc/6`, and `Smith.spline/2` for its edges. Consecutive directed endpoints must agree within 1.0e-7 mm. Smith does not reverse edges or sort them into a path. Empty, disconnected, and closed paths fail during evaluation. A path is a wire; it has no printable volume on its own.

## Sweep a placed profile

A sketch's plane must pass through the start of the path and be perpendicular to its starting tangent. The sketch keeps its in-plane offset. For a straight +Z path, the default XY sketch plane already fits:

```elixir
rod = Sketch.circle(2) |> Smith.sweep(straight)
{:ok, rod_result} = Smith.evaluate(rod)
{:ok, rod_volume} = OCEx.volume(rod_result.shape)
true = abs(rod_volume - :math.pi() * 4 * 20) < 1.0e-6
```

For a quarter circle in XY, the path starts at `{20, 0, 0}` and points along +Y. An XZ sketch is perpendicular to that tangent. Its local `at:` places the section center at the path start:

```elixir
bend_path = Path.new([Smith.arc({0, 0, 0}, {0, 0, 1}, {1, 0, 0}, 20, 0, 90)])
bend = Sketch.circle(2, on: Plane.xz(), at: {20, 0}) |> Smith.sweep(bend_path)
{:ok, bend_result} = Smith.evaluate(bend)
{:ok, bend_volume} = OCEx.volume(bend_result.shape)
true = abs(bend_volume - 40 * :math.pi() * :math.pi()) < 1.0e-5
```

The profile must have one closed boundary. Cutouts that create holes return `:sweep_profile_has_holes`. A profile in the wrong plane returns `:misaligned_profile`. The first version deliberately keeps placement explicit rather than guessing how an arbitrary profile should attach.

`frame: :corrected` uses OCCT's corrected Frenet frame; `frame: :frenet` uses its Frenet frame. This controls section orientation along the spine. Test nonsymmetric sections on your intended curve before choosing a frame.

For sharp corners, `transition:` accepts `:transformed` (default), `:right` (intersect adjoining segments), and `:round` (rotate the section around the corner). Some combinations fail or self-intersect. Tangent-continuous lines, arcs, and splines are easier to reason about. Closed paths, multiple sweep sections, twist laws, and guide spines are not supported.

## Interpolate a smooth loft

A ruled loft joins adjacent sections directly. A smooth loft interpolates through the same sections:

```elixir
sections = [
  Sketch.circle(6),
  Sketch.circle(12, on: Plane.xy(z: 15)),
  Sketch.circle(8, on: Plane.xy(z: 30))
]
ruled = Smith.loft(sections)
smooth = Smith.loft(sections, ruled: false)
{:ok, smooth_result} = Smith.evaluate(smooth)
```

The default remains `ruled: true`, so existing recipes retain their geometry. Both modes require at least two sections with one closed boundary each. Section order controls traversal; OCCT chooses correspondence between their edges. Smooth interpolation can overshoot between sections. There are no seam controls, guide rails, or guaranteed continuity at caps.

## Draw a local spline

Sketch splines interpolate local points. They can be mixed with lines and arcs to close an outline:

```elixir
arched = Sketch.profile([
  Sketch.spline([{0, 0}, {5, 4}, {10, 0}], {{1, 1}, {1, -1}}),
  Sketch.line({10, 0}, {0, 0})
])
arched_part = arched |> Smith.extrude(3)
```

The optional tangent pair specifies endpoint directions, not derivative magnitudes. Sketch placement rotates these directions with the plane and translates the interpolation points. This is distinct from `Smith.spline/2`, whose points and tangent vectors use world coordinates and whose result is an edge recipe suitable for a path.

## Preview and export

With Kino installed, `Smith.Kino.render(tray)` directly returns a preview you can display as the last expression in a Livebook cell. The [worked notebook](https://github.com/ntodd/smith/blob/main/examples/paths-and-shells.livemd) compares ruled and smooth lofts, renders the construction stages, and exports all three parts as a named assembly.

```elixir
{:ok, files} = Smith.export(hollow, "output", name: "tray", on_bed: true, angular_tolerance: 0.1)
true = files.verification.mesh.watertight
true = files.verification.mesh.winding_consistent
```

The verified bundle contains STEP, BREP, STL, and 3MF files. Its checks cover mesh connectivity, winding, and STEP volume agreement. Printer settings, supports, strength, and fit remain design decisions; see [exporting](exporting.md).

# Mechanical parts

Define a reusable part by its outline, fastener locations, clearances, and placement. Keep those dimensions in ordinary Elixir values and functions. Smith recipes compose without evaluating intermediate bodies.

## A slotted mounting plate

`Sketch.rounded_rectangle(width, height, radius)` rounds all four corners before applying cutouts. `Sketch.slot(length, width)` uses **overall length**, with semicircular ends of diameter `width`. Both use the same local `on:`, `at:`, and `align:` options as a rectangle. Equal slot length and width make a circle. A nonzero straight span must exceed the native 1.0e-7 mm edge tolerance.

```elixir
alias Smith.{Plane, Selector, Sketch}

outline =
  Sketch.rounded_rectangle(60, 40, 4)
  |> Sketch.cut(Sketch.slot(20, 6))

plate = Smith.extrude(outline, 8)
```

<div class="smith-doc-preview" data-preview="mechanical-parts-0-outline" data-model="outline" data-label="Slotted outline">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="mechanical-parts-0-plate" data-model="plate" data-label="Slotted plate">
<p>Interactive preview available in HexDocs.</p>
</div>

## Holes and entry planes

A counterbore is a flat-bottomed recess for a screw head. A countersink is a
conical recess, commonly used for a flush screw. A blind hole stops inside the
part; a through hole passes all the way through it.

Every hole specifies a diameter and exactly one extent: `through: :all` or `depth: millimeters`. A blind hole starts at the entry plane, travels along its **negative normal**, and leaves a flat floor. If the plane is outside the body, part of the specified depth is spent reaching the surface. Through-all instead spans the body's projected bounds in both directions, regardless of where the plane lies.

With `on: :top`, Smith selects the unique highest outward +Z planar face. Coordinates in `at: {u, v}` are offsets from that face's area centroid. Earlier asymmetric cuts can move that centroid. Use an explicit plane for a pattern with fixed design coordinates:

```elixir
entry = Plane.xy(z: 8)

plate =
  for x <- [-22, 22], y <- [-12, 12], reduce: plate do
    model ->
      Smith.countersink(model,
        on: entry, at: {x, y}, diameter: 4,
        sink_diameter: 8, angle: 90, through: :all
      )
  end
```

<div class="smith-doc-preview" data-preview="mechanical-parts-1-plate" data-model="plate" data-label="Countersunk holes">
<p>Interactive preview available in HexDocs.</p>
</div>

Counterbores add `bore_diameter:` and `bore_depth:`. Countersinks add `sink_diameter:` and an included `angle:` in degrees, default 90. The recess diameter must exceed the pilot diameter. For a blind feature, total `depth:` includes the recess and must reach its bottom. A countersink's depth is `(sink_diameter - diameter) / (2 * tan(angle / 2))`.

```elixir
plate =
  plate
  |> Smith.counterbore(on: entry, at: {0, -12}, diameter: 4,
    bore_diameter: 8, bore_depth: 3, through: :all)
  |> Smith.hole(on: entry, at: {0, 12}, diameter: 3, depth: 4)
```

<div class="smith-doc-preview" data-preview="mechanical-parts-2-plate" data-model="plate" data-label="Counterbore and blind hole">
<p>Interactive preview available in HexDocs.</p>
</div>

A pilot cut must remove material or evaluation fails with `:hole_misses_body`. Its recess must remove additional material or it fails with `:recess_misses_body`. Invalid extent/recess options return `:invalid_options`. Errors retain the feature name and recipe step in `Smith.Error`. These features specify geometry rather than a thread standard, drill-point angle, or automatic clearance allowance.

## Select, sort, and inspect

Topology is the arrangement of faces and edges. Use geometry properties to select
a feature rather than memorizing an edge index.

Selector filters operate on the preceding selection. Length, radius, and area accept a numeric value or inclusive `{minimum, maximum}` range. The optional `tolerance:` defaults to 1.0e-7 in the property's units: mm for length/radius, mm² for area. Candidates with no reported radius do not match a radius filter.

```elixir
{:ok, part} = Smith.evaluate(plate)

circular_edges = Selector.type(:circle) |> Selector.radius({1.5, 4})
{:ok, circles} = Smith.inspect_edges(part, circular_edges)
true = circles != []

largest_planes = Selector.type(:plane) |> Selector.sort_by(:area, :desc) |> Selector.take(2)
{:ok, faces} = Smith.inspect_faces(part, largest_planes)
true = length(faces) == 2
```

<div class="smith-doc-preview" data-preview="mechanical-parts-3-circles" data-model="circles" data-label="Selected circular edges">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="mechanical-parts-3-faces" data-model="faces" data-label="Largest planar faces">
<p>Interactive preview available in HexDocs.</p>
</div>

`inspect_edges/2` and `inspect_faces/2` return maps containing a native `:shape` handle and geometry metadata, including world bounds. Edges also have a curve-parameter midpoint. Face centers are area centroids. These are not bounding-box centers. Query handles belong to the evaluated revision; retain and reevaluate selectors when the recipe changes.

`sort_by/3` accepts length, area, radius, or a world axis. Missing radii sort last in either direction, and exact ties retain their incoming order. Kernel order is not a persistent identity. `take/2` deliberately limits a selection and may discard ties; `at_min/2` and `at_max/2` retain all coordinate ties within 1.0e-7 mm.

```elixir
horizontal = Selector.any_of([Selector.facing(:z), Selector.facing({:z, :negative})])
sides = Selector.type(:plane) |> Selector.exclude(horizontal)
{:ok, side_faces} = Smith.inspect_faces(part, sides)
true = side_faces != []
```

<div class="smith-doc-preview" data-preview="mechanical-parts-4-side-faces" data-model="side_faces" data-label="Selected side faces">
<p>Interactive preview available in HexDocs.</p>
</div>

Each union or exclusion branch starts with the preceding selection. Union preserves that selection's order and includes each candidate only once. An empty union selects nothing. Invalid nested queries fail even when an earlier filter selected no candidates. Predicates must return booleans; predicate exceptions propagate to the caller.

## Mirror and export

A mirror returns the reflected recipe. Its plane can be `:xy`, `:xz`, `:yz`, or any positioned `Smith.Plane`. It preserves outward solid orientation and does not retain the original automatically. Use an assembly to keep both parts separately, or `fuse/2` when touching copies should form one body.

```elixir
alias Smith.Assembly

pair =
  Assembly.new(:mechanical_pair)
  |> Assembly.part(:left, plate, print: [on_bed: true])
  |> Assembly.part(:right, Smith.mirror(plate, Plane.yz(x: 40)), print: [on_bed: true])

{:ok, pair_result} = Smith.evaluate(pair)
{:ok, files} = Smith.export(pair_result, "output", name: "mechanical-pair", angular_tolerance: 0.1)
files.print_pack
```

<div class="smith-doc-preview" data-preview="mechanical-parts-5-pair-result" data-model="pair_result" data-label="Mirrored pair">
<p>Interactive preview available in HexDocs.</p>
</div>

The ZIP contains each part's STL and 3MF. Installed geometry remains in STEP; print placement affects the printable files. Export checks meshes and STEP round trips. Inspect wall thickness, fit, and print orientation for your own design. The [mechanical parts Livebook](livebook.md) shows each stage and checks the removed volume against independent formulas.

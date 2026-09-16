# Inspect and validate models

A valid solid can still be the wrong shape. Measure evaluated geometry, state the
requirements explicitly, and keep each report tied to the revision it checked.
These tools work in ordinary Elixir scripts; neither vision nor Livebook is required.
The complete script is `examples/inspection.exs`; `examples/inspection.livemd`
provides an interactive version.

## Named inspection inputs

Names refer to snapshots you supply. They can describe complete parts, intermediate
stages, or selected subshapes. They do not promise persistent face identities after
an edit. Reevaluate the model and rebuild selections when dimensions change.

```elixir
alias Smith.{Drawing, Inspection, Measure, Plane, Selector}

plate = Smith.box(40, 24, 6)
{:ok, plate_result} = Smith.evaluate(plate)

holes = [Smith.cylinder(2, 8, at: {10, 12, -1}), Smith.cylinder(2, 8, at: {30, 12, -1})]
{:ok, drilled} = plate_result |> Smith.from_result() |> Smith.cut(holes) |> Smith.evaluate()
Smith.Kino.render(drilled, view: :top, edges: true)
```

<div class="smith-doc-preview" data-preview="inspection-drilled" data-model="drilled" data-label="Plate with measured holes">
<p>Interactive preview available in HexDocs.</p>
</div>

## Topology queries and selectors

Topology inspection returns metadata rather than native handles. Pages include
source revision, total matches, and the next offset. Native topology order is not
stable across revisions. Prefer a geometric selector to a remembered face index.

```elixir
{:ok, page} = Inspection.topology(drilled, :edges, selector: Selector.type(:circle), limit: 10)
IO.inspect(page, label: "Circular edges")

left = fn edge ->
  edge.type == :circle and abs(elem(edge.center, 0) - 10) < 1.0e-6 and
    abs(elem(edge.center, 2) - 6) < 1.0e-6
end

right = fn edge ->
  edge.type == :circle and abs(elem(edge.center, 0) - 30) < 1.0e-6 and
    abs(elem(edge.center, 2) - 6) < 1.0e-6
end

{:ok, spacing} = Measure.distance(drilled, {:circle_center, left}, {:circle_center, right}, axis: :x)
{:ok, diameter} = Measure.diameter(drilled, left)
{:ok, width} = Measure.extent(drilled, :x)
```

A measurement selector must match exactly one item. Multiple matches return an
error; refine the selector to identify one edge. Circle centers and radii come
from native curves, including arcs; they are not inferred from mesh vertices.

## Requirements and reports

```elixir
{:ok, report} = Inspection.run(%{plate: drilled}, checks: [
  {:topology, :plate, :solids, expected: 1},
  {:bounds, :plate, {{0, 0, 0}, {40, 24, 6}}, tolerance: 1.0e-6},
  {:measurement, :plate, spacing, expected: 20, tolerance: 1.0e-6},
  {:measurement, :plate, diameter, expected: 4, tolerance: 1.0e-6}
])

:passed = report.status
{:ok, json} = Inspection.json(report)
IO.puts(json)
```

`{:ok, report}` means inspection ran. `report.status` tells you whether the
requirements passed. A failed requirement has `status: :failed`, with its measured
value, expectation, units, and tolerance. A kernel error, unknown name, or stale
measurement is `:error`. An empty or failed section must not be treated as evidence
that there is no material.

The JSON contains no native handles. Model summaries include revisions, native
bounds, area, volume, and topology counts. A text-only agent can use these values
to decide what to change and rerun the same requirements afterward.

## Containment and clearance

```elixir
ledge = Smith.box(4, 10, 1, at: {38, 7, 5})
{:ok, failed} = Inspection.run(%{plate: plate_result, ledge: ledge}, checks: [
  {:contained, :ledge, :plate, tolerance: 1.0e-7}
])

:failed = failed.status
[excess] = failed.checks
IO.inspect({excess.measured, excess.unit, excess.bounds}, label: "Outside material")
ledge_scene = [{plate_result, {130, 150, 170}}, {ledge, {210, 55, 45}}]
Smith.Kino.render(ledge_scene, edges: true)
```

<div class="smith-doc-preview" data-preview="inspection-ledge" data-model="ledge_scene" data-label="Overhanging feature">
<p>Interactive preview available in HexDocs.</p>
</div>

This reports 20 mm³ outside the plate. Containment measures volume for solids,
area for faces, and length for curves. Its tolerance uses those units. To check whether a
feature is fully supported, inspect its bottom face against the supporting body.
Exposed area indicates an overhang, even when the fused result is a valid solid.

For mating parts, use `{:clearance, :pin, :socket_body, minimum: 0.1,
tolerance: 1.0e-6}`. It measures material distance and also checks common volume.
A pin contained inside solid material has zero distance, but that is interference,
not a successful zero-clearance fit. Linear and volume tolerances are separate.

## Images and report files

```elixir
{:ok, artifacts} = Inspection.write(report, "output/inspection",
  views: [:isometric, :top, :front, :right],
  sections: [Plane.xz(y: 12)],
  width: 640,
  height: 480
)
IO.puts(artifacts.report)
```

Each run gets its own directory and a JSON manifest. Images reference both the
source and rendered geometry revisions. Failed containment checks also produce
images of the excess material. Read the returned manifest rather than selecting
an old image by its filename. An image generation failure does not write a final
report manifest; partial image files can remain in that run's directory.

`Smith.Render.write/3` writes an individual PNG. It uses an orthographic software
depth buffer, with no GPU, browser, display server, or additional renderer install.
Top looks from +Z, front from −Y, and right from +X. Named views use world axes,
not inferred product orientation. Pass a `Smith.Plane` for another convention.
Images use tessellation. Mesh deflection, numerical measurement tolerance,
manufacturing tolerance, and printer compensation are different quantities.

## Compare modeling stages

```elixir
{:ok, change} = Inspection.compare(plate_result, drilled)
IO.inspect({change.added_mm3, change.removed_mm3}, label: "Stage material changes")

layers = [
  {drilled, {130, 150, 170}},
  {change.removed, {210, 55, 45}},
  {change.added, {45, 170, 90}}
]
Smith.Kino.render(layers, view: :isometric, edges: true)
```

<div class="smith-doc-preview" data-preview="inspection-change" data-model="layers" data-label="Removed material in red">
<p>Interactive preview available in HexDocs.</p>
</div>

The removed material is red and added material green. The same layer list works
with `Smith.Render.png/2`. These are opaque solids, so orbit or clip the scene to
inspect occluded regions. Full BREP differences can be expensive for coincident
curved faces. They locate changes that a total-volume comparison can miss.

## Drawing dimensions

```elixir
{:ok, drawing} = Drawing.new(drilled, on: :xy)
{:ok, drawing} = Drawing.dimension(drawing, width, orientation: :horizontal, offset: -6)
{:ok, drawing} = Drawing.dimension(drawing, spacing, orientation: :horizontal, offset: 18)
{:ok, drawing} = Drawing.dimension(drawing, diameter, offset: -3)
{:ok, svg} = Drawing.svg(drawing, hidden: false, title: "Measured mounting plate")
Smith.Kino.render(drawing, label: "Measured mounting plate", hidden: false)
```

<div class="smith-doc-preview" data-preview="inspection-dimensions" data-model="svg" data-label="Dimensions measured from geometry">
<p>Dimensioned SVG available in HexDocs.</p>
</div>

Dimensions retain source revision, measured value, and anchors. A mismatched
revision or foreshortened projection is rejected. Linear, radius, diameter, and
angular dimensions are supported. SVG includes extension lines, arrows, and
center marks; placement is explicit. There is no automatic label layout or sketch
constraint solver. Annotated DXF currently returns `:unsupported_annotations`.

## Working with agents

Give an agent the requirements, coordinate convention, source drawing or model,
and the location of its output directory. Ask it to keep assumptions separate
from measurements and to return the inspection manifest with its changes.

The [agent modeling guide](agent-modeling.html) is available as plain Markdown
through ExDoc's `llms.txt`. Smith also ships `skills/smith-cad/SKILL.md` for harnesses
that support skills. The guide and skill describe which tools to use and how to check their results.

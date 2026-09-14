# Project curves onto surfaces

Projection transfers boundary curves to target surfaces. It does not intersect
filled sketch material with a body. Use it to place an outline on a face, measure
a curve on a curved surface, or create a planar profile for another operation.
Coordinates stay in world space.

## Parallel projection

```elixir
alias Smith.{Plane, Selector, Sketch}

source = Sketch.circle(4, on: Plane.xy(z: 12))
inclined = Plane.new(normal: {1, 0, 1}, x_direction: {1, 0, -1})
target = Sketch.rectangle(30, 30, on: inclined)
outline = Smith.project(source, target, direction: {0, 0, -1})
{:ok, projected} = Smith.evaluate(outline)
{:ok, [_wire]} = OCEx.wires(projected.shape)
```

<div class="smith-doc-preview" data-preview="projection-0-source" data-model="source" data-label="Source circle">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="projection-0-target" data-model="target" data-label="Inclined target">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="projection-0-projected" data-model="projected" data-label="Projected ellipse">
<p>Interactive preview available in HexDocs.</p>
</div>

The source circle lies above the target plane `z = -x`. Its projection is an
ellipse on that plane. The direction is normalized, so its magnitude does not
set a travel distance. Parallel projection is bidirectional: changing `{0,0,-1}`
to `{0,0,1}` does not select a different side.

## Fill a planar outline

```elixir
profile = Smith.face(outline)
{:ok, face_result} = Smith.evaluate(profile)
{:ok, area} = OCEx.area(face_result.shape)
true = abs(area - 16 * :math.pi() * :math.sqrt(2)) < 1.0e-6

part = profile |> Smith.extrude({0, 0, 3})
{:ok, result} = Smith.evaluate(part)
{:ok, volume} = OCEx.volume(result.shape)
true = abs(volume - 48 * :math.pi()) < 1.0e-6
```

<div class="smith-doc-preview" data-preview="projection-1-face-result" data-model="face_result" data-label="Filled ellipse">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="projection-1-result" data-model="result" data-label="Extruded projection">
<p>Interactive preview available in HexDocs.</p>
</div>

`face/1` accepts one closed planar wire. It preserves world placement and returns
a face recipe that composes with extrusion, revolution, and Boolean operations.
It does not guess which projected boundaries are holes or pick one of several
surface hits. Multiple wires return `:wrong_shape_type`, open wires return
`:open_wire`, and nonplanar boundaries cannot be filled by this operation.

## Project through a point

```elixir
enlarged = Sketch.circle(2, on: Plane.xy(z: 5))
  |> Smith.project(Sketch.rectangle(20, 20), from: {0, 0, 10})
  |> Smith.face()
{:ok, enlarged_result} = Smith.evaluate(enlarged)
{:ok, area} = OCEx.area(enlarged_result.shape)
true = abs(area - 16 * :math.pi()) < 1.0e-6
```

<div class="smith-doc-preview" data-preview="projection-2-enlarged-result" data-model="enlarged_result" data-label="Conical projection">
<p>Interactive preview available in HexDocs.</p>
</div>

This conical projection follows half-rays from the point through the source.
The target is twice as far from the point as the source plane, so the radius
doubles from 2 to 4 mm. Targets between the point and source can also be hit;
targets behind the point are excluded. Source curves passing through the point,
or other degenerate configurations, may fail.

Exactly one of `:direction` and `:from` is required. There is no implicit view
direction or perspective point.

## Choose the target surface

```elixir
body = Smith.box(20, 20, 4, align: {:center, :center, :min})
top = Smith.surface(body, Selector.facing(:z))
top_outline = Smith.project(source, top, direction: {0, 0, -1})
{:ok, top_result} = Smith.evaluate(top_outline)
{:ok, [_wire]} = OCEx.wires(top_result.shape)
```

<div class="smith-doc-preview" data-preview="projection-3-top" data-model="top" data-label="Selected target face">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="projection-3-top-result" data-model="top_result" data-label="Projected top outline">
<p>Interactive preview available in HexDocs.</p>
</div>

Projecting onto the whole box instead would retain both the top and bottom hits.
Projection does not sort intersections by distance or choose a visible surface.
Selecting target faces first makes that choice explicit. Native targets may be
faces, shells, solids, or compounds of those types; free edges are rejected.

## Curved surfaces and clipping

```elixir
wall = Smith.cylinder(5, 10) |> Smith.surface(Selector.type(:cylinder))
curves = Smith.line({-3, -10, 5}, {3, -10, 5})
  |> Smith.project(wall, direction: {0, 1, 0})
{:ok, curves_result} = Smith.evaluate(curves)
{:ok, wires} = OCEx.wires(curves_result.shape)
2 = length(wires)
{:ok, length} = OCEx.length(curves_result.shape)
true = abs(length - 20 * :math.asin(3 / 5)) < 1.0e-5
```

<div class="smith-doc-preview" data-preview="projection-4-wall" data-model="wall" data-label="Cylindrical target">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="projection-4-curves-result" data-model="curves_result" data-label="Projected arcs">
<p>Interactive preview available in HexDocs.</p>
</div>

The line produces an arc on each side of the cylinder. Inspect them with
`Smith.edges/2`, `Smith.inspect_edges/2`, or `OCEx.edge_sample/2`. The projected
curves remain exact native geometry; this operation does not use a mesh.

Target boundaries and holes clip curves, so a closed source can yield open or
disconnected results. A sketch contributes all its boundary wires, including
holes. A completely enclosing outline that misses the target boundary does not
fill the target. A missed or failed source boundary returns `:projection_failed`;
collections fail if any boundary fails. Successful partial intersections remain
valid output. If a swept source curve lies on a target surface, the intersection
is not an isolated curve: OCCT can return boundaries of the coincident region.
Avoid coincident or tangent configurations when a unique projected curve is needed.

## Preview and export

Kino renders faces and solids as triangle surfaces, and wire-only results as
sampled curves. Preview each stage or inspect exact geometry with curve queries. Wires can be exported as BREP/STEP through OCEx, but printable
STL/3MF require solid geometry.

```elixir
{:ok, files} = Smith.export(result, "output", name: "projected-cap", on_bed: true,
  angular_tolerance: 0.1)
true = files.verification.mesh.watertight
```

<div class="smith-doc-preview" data-preview="projection-5-result" data-model="result" data-label="Exported projected cap">
<p>Interactive preview available in HexDocs.</p>
</div>

The [projection Livebook](https://github.com/ntodd/smith/blob/main/examples/projection.livemd)
shows these stages and exports a two-part print pack. Orthographic drawings and
hidden-line removal are separate operations; this API projects source curves
onto supplied target geometry.

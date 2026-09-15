# CAD concepts used in Smith

You need ordinary Elixir functions, pipelines, and pattern matching to follow the
examples. This page explains the geometry vocabulary used in the guides. Start
with [getting started](getting-started.md) for installation and a runnable part.

## From a sketch to a part

A **sketch** is a flat region, such as a rectangle with two circular cutouts.
An **extrusion** gives it depth by moving that region along a direction. A
**revolution** turns a cross-section around an axis, like making a sleeve from a
rectangular wall section. A **loft** joins outlines at several positions; a
**sweep** carries one outline along a path.

```elixir
alias Smith.Sketch

outline = Sketch.rectangle(30, 20) |> Sketch.cut(Sketch.circle(3))
part = outline |> Smith.extrude(4)
```

<div class="smith-doc-preview" data-preview="basics-outline" data-model="outline" data-label="Flat sketch with a cutout">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="basics-part" data-model="part" data-label="The same sketch with 4 mm depth">
<p>Interactive preview available in HexDocs.</p>
</div>

The circle takes a **radius**, so the opening is 6 mm across. `Smith.hole/2`
instead takes a **diameter**. Check the argument name when choosing dimensions.

## Coordinates and workplanes

World coordinates are `{x, y, z}` in millimeters. In the early examples, X runs
left to right, Y runs front to back, and Z points up. Each complete project states
its own convention. Positive rotation follows the right-hand rule: point your
right thumb along the axis; your curled fingers show the positive direction.

A **workplane** is a local drawing surface with an origin and two in-plane axes.
Its **normal** is a perpendicular direction. `Plane.xy()` has a +Z normal, so a
positive sketch extrusion goes upward. `Plane.xz()` has a −Y normal. The
[workplane table](sketches.md#frames) gives all three standard orientations.

Sketch coordinates `{u, v}` belong to that workplane. Solid primitive coordinates
`{x, y, z}` belong to the world. A sketch rectangle is centered by default; a
solid box starts at its minimum corner. Use `align:` and `at:` when that
placement should be explicit.

A **datum** is a chosen reference for measurements, such as the bottom-left
corner of a board. Keep hole patterns tied to fixed datums. A face's **centroid**
is its area-weighted center; it can move when material is cut away. That is why
repeated holes generally use an explicit plane instead of `on: :top`.

## What a shape contains

| Term | Meaning |
| --- | --- |
| Vertex | A point where edges meet or end |
| Edge | A bounded curve, straight or curved |
| Wire | Connected edges forming an open path or closed boundary |
| Face | A bounded surface, possibly with holes; it can be curved |
| Shell | Connected faces; it may be open or closed |
| Solid | An enclosed volume of material |
| Compound | A collection of shapes that have not been fused together |

These relationships are called **topology**. A selector asks for shapes with
properties such as vertical direction, circular geometry, or a particular
radius. It avoids hard-coding an edge's position in an enumeration. Selections
must be rebuilt after changes to geometry.

An **assembly** retains separately named parts and their positions. Use it for a
lid and a base that must print separately. Fusing the two would instead combine
their material into a modeling result.

## Adding, removing, and finishing material

| Operation | Effect |
| --- | --- |
| Fuse | Add the material of another shape |
| Cut | Remove the material occupied by a cutting tool |
| Common | Keep only material shared by both shapes |
| Fillet | Round an edge with a curved transition |
| Chamfer | Replace an edge with a flat bevel |
| Shell | Hollow a solid through selected face openings |
| Draft | Tilt walls away from a plane, often to ease removal from a mold |
| Section | Take a flat slice for inspection or further modeling |
| Split | Divide a solid into pieces at a plane |

Fuse, cut, and common are **Boolean operations**. A tool that misses the body
may leave it unchanged. A successful operation therefore still needs checks
against the intended design.

## Geometry, pictures, and printed dimensions

Smith evaluates recipes into OCCT **boundary representations**, usually shortened
to **BREP**. A BREP describes surfaces, curves, and how they meet. Numerical
measurements use this geometry. A **mesh** approximates surfaces with triangles
for screen previews and STL/3MF printing. Adding triangles does not recover
missing design information or improve a printer's accuracy.

Keep these four quantities separate:

- **Design clearance:** an intentional gap between parts, modeled in millimeters.
- **Check tolerance:** the allowed numerical difference in a particular test.
- **Mesh deflection:** how finely a curved surface is approximated for output.
- **Manufacturing allowance:** a design adjustment for the material and process,
  established through measurement and test prints.

For example, a 0.4 mm sliding gap is real geometry. A check tolerance of
0.000001 mm verifies a computation; it does not promise that a print is accurate
to that distance.

An **orthographic drawing** shows a view without perspective: distant features
remain the same size. Drawing dimensions annotate measured geometry; they do not
change the model. Continue with [modeling](modeling.md), [sketches](sketches.md),
or the [first Livebook lesson](../examples/plate.livemd).

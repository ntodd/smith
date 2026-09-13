# Forming and cutting

Use planes to define where a cut, cross-section, or taper belongs. Use face selectors
to choose which surfaces participate. The recipes below remain reusable after each
operation; native geometry is built by `Smith.evaluate/1`.

## Draft about a neutral plane

```elixir
alias Smith.{Plane, Selector}

sides = Selector.type(:plane) |> Selector.exclude(Selector.parallel(:z))
tapered = Smith.box(20, 16, 10)
  |> Smith.draft(faces: sides, neutral: :xy, angle: 5, count: 4)
{:ok, result} = Smith.evaluate(tapered)
```

At the neutral plane, the footprint stays fixed. Positive angles remove material
on the pull side. `direction:` defaults to the plane normal; it must not lie in
the neutral plane. Angles are degrees and must be strictly between −90 and 90.
Zero validates and copies the body. Selected faces must be planar, cylindrical,
or conical. OCCT may propagate the draft across tangent-connected faces; `count:`
checks the explicit selection before that propagation. Disappearing faces and
other topology transitions can fail.

## Split a solid or reuse its section

```elixir
plane = Plane.xy(z: 6)
lower = Smith.split(tapered, plane, keep: :negative)
upper = Smith.split(tapered, plane, keep: :positive)
both = Smith.split(tapered, plane)

cap = tapered
  |> Smith.section(plane)
  |> Smith.translate({0, 0, -6})
  |> Smith.extrude({0, 0, 2})
```

Positive means the side toward the plane normal. The default `keep: :both` keeps
separate solids; it does not fuse the cut back together. These operations accept
solids or compounds containing only solids. A missed section or discarded side
returns a valid empty compound. Tangent edges and points do not create solids or
section faces. A section coincident with a planar boundary retains that face.

`section` produces filled faces with normals matching the plane, preserving holes
and disconnected regions. It is not a projection. Extrude these faces with a world
vector that has a nonzero component normal to every face. Multiple regions become
separate solids. Scalar extrusion remains a sketch operation.

## Extract, offset, and thicken surfaces

```elixir
wall = Smith.cylinder(10, 12) |> Smith.surface(Selector.type(:cylinder))
sleeve = wall |> Smith.offset(2) |> Smith.thicken(-1)
{:ok, sleeve_result} = Smith.evaluate(sleeve)
{:ok, volume} = OCEx.volume(sleeve_result.shape)
true = abs(volume - :math.pi() * (144 - 121) * 12) < 1.0e-5

expanded = Smith.box(20, 16, 10) |> Smith.offset(2, join: :intersection)
```

`surface` selects faces and sews their shared boundaries. An empty selection fails.
Connected faces become shells; disconnected regions stay separate. The cylinder
wall above has outward normals, so the offset increases its radius from 10 to 12.
Negative thickening builds inward, closing a solid wall between radii 11 and 12.

`offset` moves a surface along its normals. On a solid it expands or contracts the
boundary; on a planar sketch it moves the face out of its plane. It does **not**
expand the sketch outline in 2D. `thicken` turns a face or open shell into a solid,
closing its boundary. It rejects existing solids and closed shells. To hollow a
solid by removing selected faces, use `Smith.shell/2`.

Both operations accept `join: :arc` or `:intersection`. Arc joins round gaps;
intersection joins extend adjacent surfaces. Offset defaults to arc and thickening
to intersection. Signed distances must have magnitude greater than 1.0e-7 mm.
Compound members are processed independently; the result is not automatically fused.

These algorithms require suitable smooth surfaces and can fail at narrow gaps,
large offsets, or self-intersections. Self-intersection repair is disabled.
Successful BREP validation is not a complete self-intersection check. Inspect
sections and measure the resulting walls before relying on a part's fit.

## Preview and export

The [forming Livebook](https://github.com/ntodd/smith/blob/main/examples/forming.livemd)
shows these operations in stages, checks analytic volumes and section area, and
exports a three-part assembly. Each preview supports fullscreen and PNG download.
Use [verified export](exporting.md) for STL and 3MF fabrication files; open surfaces
must first become solids to pass printable-mesh checks.

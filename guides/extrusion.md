# Extrusion extent and taper

Extrusion turns a filled planar profile into solid material. A sketch uses a signed
distance along its local plane normal. A face recipe uses a world displacement
vector. Holes pass through the result, and disconnected faces produce separate
solids without fusing them.

## Extrude on both sides

```elixir
alias Smith.{Plane, Sketch}

outline = Sketch.rectangle(20, 16)
centered = Smith.extrude(outline, 5, both: true)
{:ok, result} = Smith.evaluate(centered)
{:ok, {{-10.0, -8.0, -5.0}, {10.0, 8.0, 5.0}}} = OCEx.bounds(result.shape)
```

`both: true` applies the supplied distance on **each** side: 5 mm makes a total
depth of 10 mm. It does not split a total depth in half. The original sketch plane
stays at the center. Reversing the distance produces the same symmetric extent.
For an oblique face extrusion, both directions use the complete world vector.

## Taper the walls

```elixir
tapered = outline |> Smith.extrude(10, taper: 5)
{:ok, result} = Smith.evaluate(tapered)
slope = :math.tan(5 * :math.pi() / 180)
expected = 320 * 10 - 36 * slope * 100 + 4 * slope * slope * 1000 / 3
{:ok, volume} = OCEx.volume(result.shape)
true = abs(volume - expected) < 1.0e-5
```

Taper angles are degrees, strictly between −90 and 90. A positive angle removes
material away from the sketch plane; a negative angle adds material. The starting
outline stays fixed. For the rectangle above, a section at height `z` is
`20 - 2*z*tan(5°)` by `16 - 2*z*tan(5°)`. This defines the volume check above.

Hole boundaries move in the opposite radial direction from outer boundaries:
positive taper widens a hole while narrowing the outside. Taper is a wall angle,
not proportional scaling of the entire profile. With `both: true`, both halves
taper away from the same neutral section and join into one solid per profile.

```elixir
ring = Sketch.circle(10)
  |> Sketch.cut(Sketch.circle(4))
  |> Smith.extrude(5, both: true, taper: 4)
{:ok, ring_result} = Smith.evaluate(ring)
```

Nonzero taper requires extrusion perpendicular to the profile plane. Straight and
circular boundaries produce supported planar and cylindrical prism walls, including
tangent rounded rectangles and slots. Spline walls return `:unsupported_draft_surface`.
Walls that collapse, holes that close, or boundaries that merge can fail. OCCT's
draft operation does not construct new topology for those transitions. Use explicit
sections and lofting when the intended shape needs a different profile at the end.

## Stop at a plane

```elixir
target = Plane.new(origin: {0, 0, 4}, normal: {-0.5, 0, 1}, x_direction: {1, 0, 0.5})
sloped = Sketch.rectangle(10, 6, align: {:min, :min})
  |> Smith.extrude_until(target)
{:ok, result} = Smith.evaluate(sloped)
{:ok, volume} = OCEx.volume(result.shape)
true = abs(volume - 390) < 1.0e-6
```

The target above is `z = 4 + x/2`. Its height runs from 4 to 9 mm across the
rectangle, giving an average height of 6.5 mm and a volume of 390 mm³.
The target is an infinite plane; its X direction defines its local frame but does
not bound the cap. Reversing the target normal does not change the result.

Sketches travel along their normal unless `direction:` supplies a world vector.
Face recipes require `direction:`. The vector's magnitude is ignored. Holes and
separate face regions are preserved, and travel can be oblique to the profile.

```elixir
backward = Sketch.circle(3)
  |> Smith.extrude_until(Plane.xy(z: -8), direction: {0, 0, -1})
{:ok, backward_result} = Smith.evaluate(backward)
```

Every point of the profile must reach the target in the positive travel direction,
more than 1.0e-7 mm away. A target touching or crossing the initial profile returns
`:target_not_ahead`. Parallel travel and target planes return `:invalid_direction`.
The operation supports straight, untapered walls and accepts only `:direction`;
it does not find the nearest face of a target body. For finite symmetric or tapered
extrusions, use `extrude/3`.

## Inspect and print

The result is an ordinary Smith model: finishing operations, assembly membership,
Kino previews, and verified export work as usual.

```elixir
{:ok, files} = Smith.export(ring_result, "output", name: "tapered-ring", on_bed: true,
  angular_tolerance: 0.1)
true = files.verification.mesh.watertight
```

The [extrusion Livebook](https://github.com/ntodd/smith/blob/main/examples/extrusion.livemd)
shows these stages, checks analytic volumes, and exports three parts as a print pack.

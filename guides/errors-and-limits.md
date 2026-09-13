# Errors, contracts, and limits

Curve projection returns wires, clips to target surfaces, and retains multiple hits.
Parallel projection is bidirectional; conical projection follows source half-rays.
`face/1` fills only one closed planar wire; it does not infer holes or select hits.
See [projection](projection.html) for source/target rules and examples.

Extrusion supports signed or symmetric extent, tapered straight/circular walls,
and straight extrusion up to an infinite plane. Symmetric distance applies to
each side. Taper requires normal travel and cannot construct topology changes
such as collapsed walls. Up-to-plane extrusion requires the entire profile to
reach the plane ahead; it does not find the nearest face of a target body.
See [extrusion](extrusion.html) for contracts and examples.

Smith separates recipe construction from native evaluation. Construction is intended for typed Elixir values and records requested geometry without making native calls. Geometric and option validation runs when the recipe is evaluated.

## Handle evaluation results

```elixir
case Smith.box(20, 10, 4)
     |> Smith.fillet(edges: {:parallel, :z}, radius: 100)
     |> Smith.evaluate() do
  {:ok, result} -> IO.inspect(result.revision)
  {:error, %Smith.Error{} = error} -> IO.inspect(error)
  {:error, reason} -> IO.inspect(reason)
end
```

`Smith.Error` contains `step` (one-based construction index), `operation`, `reason`, and optional assembly `part`. Nested tool failures retain their nested error. Assembly option/name errors use `operation: :assembly` and may have no step. Joint definition and connection failures use `:joint` or `:connect`, with the affected name/path in `part`. Invalid top-level recipe terms return `:invalid_recipe`; an empty model returns `:empty_model`.

Common reasons include `:invalid_options`, `:selection_count_mismatch`, `:ambiguous_top_face`, `:hole_misses_body`, `:invalid_plane`, `:non_coplanar_sketches`, `:empty_sketch`, `:disconnected_sketch`, `:loft_profile_has_holes`, `:sweep_profile_has_holes`, `:misaligned_profile`, `:empty_selection`, `:disconnected_path`, `:closed_path`, `:invalid_thickness`, and native `:operation_failed` or `:invalid_shape`. These categories locate the failed feature; they are not exhaustive explanations of every OCCT algorithm failure.

A `with` expression returns the first unmatched error; it does not itself halt
a script. Pattern-match the result when a failed model should stop execution.
For recoverable failures, handle both `%Smith.Error{}` and bare reasons as
in the example above. Use explicit planes for fixed hole coordinates and
`count:` when a finishing operation expects a specific edge count.

Incorrect argument types passed to recipe constructors or low-level `Smith.Mesh` utilities can raise ordinary Elixir exceptions. User callback exceptions propagate. The error contract does not turn arbitrary programming errors or malformed hand-built structs into valid recipes. `Smith.evaluate/1` and verified export entrypoints accept their documented values and return tagged failures for modeled errors.

## Revisions and geometry

Shapes are immutable native resources. Retain the resource while using it; never persist its opaque handle through Erlang term serialization. Persist BREP or STEP, and retain the Elixir recipe for editing.

A BREP revision identifies that serialized geometry. It is not a semantic design hash and is not guaranteed stable across OCCT versions, compilers, or platforms. Query fresh edges after a modeling operation; edge order and topology names are not persistent selection identities.

## Native execution

OCEx performs CPU-bound work on dirty schedulers, with a mutex serializing native operations. Other ordinary BEAM processes remain schedulable, but submitting more geometry tasks does not create parallel kernel throughput. Evaluation is synchronous. Timing out or killing the caller cannot interrupt an already running native operation.

C++ exceptions are caught and translated. A native memory fault can still terminate the VM. Run experimental or untrusted modeling workloads in a separate OS process when isolation is required. NIF hot upgrade, hard cancellation, and external worker orchestration are not included.

## Supported modeling scope

- Sketches have one connected region; cutouts may create multiple inner loops. Sketch union/intersection, constraint solving, and face-attached planes are not implemented. Solid Boolean union and intersection are available through `Smith.fuse/2` and `Smith.common/2`.
- Sketch fillets round the original convex outline before cuts; they do not round new cut corners.
- Revolve uses positive angles through 360 degrees; reverse its axis to reverse the sweep.
- Loft defaults to ruled; `ruled: false` enables smooth interpolation. Both require one closed boundary per section. There are no guide rails, seam controls, or hole-bearing sections.
- Holes support through-all or flat-bottomed blind depth, with counterbore and countersink entries. They do not model threads or drill-point tips. See [mechanical parts](mechanical-parts.md).
- Assemblies support reusable nested trees with explicit placements and path-based lookup. Named frames support rigid, revolute, linear, cylindrical, and ball connections with explicit motion limits. Closed linkages, collision solving, material assignments, and named STEP product trees are not supported. JSON export retains the assembly tree.
- Sweeps require an open path and a single-boundary planar profile placed perpendicular to its starting tangent. There is no automatic profile placement, multisection sweep, or guide spine. Sharp corners and self-intersections may fail.
- Shelling requires a single solid and at least one selected face opening. Signed thickness builds inward or outward. Sealed cavities are not supported by shelling.
- Mirror reflects about an explicit plane. Split keeps either or both solid sides of a plane; section returns filled planar faces, including holes. Neither operation performs projection.
- Draft supports planar, cylindrical, and conical selected faces; tangent-connected faces may also change. Collapsing faces and topology transitions are not generally supported.
- Offset follows surface normals in 3D, not a sketch outline within its plane. Thickening accepts faces and open shells. Compound members are processed independently, without fusion. Self-intersection repair is not enabled, and validity checks do not prove every self-intersection absent. See [forming and cutting](forming.md).
- Orthographic drawings retain native visible/hidden curves. SVG/DXF export samples them into polylines in millimeters; it does not import drawings, join cutting contours, or generate dimensions. See [drawings](drawings.md).
- OCEx provides a curated native API rather than a class-by-class OCCT binding.

These limits describe the supported public contract. Internal modules and functions marked with hidden documentation may change without compatibility guarantees.

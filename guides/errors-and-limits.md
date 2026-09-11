# Errors, contracts, and limits

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

`Smith.Error` contains `step` (one-based construction index), `operation`, `reason`, and optional assembly `part`. Nested tool failures retain their nested error. Assembly option/name errors use `operation: :assembly` and may have no step. Invalid top-level recipe terms return `:invalid_recipe`; an empty model returns `:empty_model`.

Common reasons include `:invalid_options`, `:selection_count_mismatch`, `:ambiguous_top_face`, `:hole_misses_body`, `:invalid_plane`, `:non_coplanar_sketches`, `:empty_sketch`, `:disconnected_sketch`, `:loft_profile_has_holes`, and native `:operation_failed` or `:invalid_shape`. These categories locate the failed feature; they are not exhaustive explanations of every OCCT algorithm failure.

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
- Loft is ruled and requires one closed boundary per section. There are no guide rails, seam controls, or hole-bearing sections.
- Holes are through-all; blind holes require explicit cutting tools.
- Assemblies are flat named values with explicit placements. There are no mates, nested assemblies, material assignments, or STEP product trees.
- Sweep, shell/thickness, offset, mirror, and a broad class-by-class OCCT binding are outside 0.1.

These limits describe the supported public contract. Internal modules and functions marked with hidden documentation may change without compatibility guarantees.

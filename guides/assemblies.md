# Named assemblies

Assemblies are ordinary immutable values. Parts contain deferred Smith recipes; evaluation constructs native geometry. A design can stay in a standalone `.exs` file with `Mix.install([{:smith, "~> 0.1.0"}])`, or in a Livebook.

```elixir
alias Smith.Assembly

bracket = Smith.box(2, 3, 4)

model =
  Assembly.new(:mount)
  |> Assembly.part(:left, bracket,
    position: {-10, 0, 20},
    print: [on_bed: true]
  )
  |> Assembly.part(:right, bracket,
    position: {10, 0, 20},
    rotation: {{0, 0, 1}, 180},
    print: [on_bed: true],
    exploded_offset: {0, 0, 30}
  )
  |> Assembly.reference(:electronics, Smith.box(5, 5, 2),
    position: {0, 0, 10}
  )

{:ok, result} = Smith.evaluate(model)
{:ok, left} = Assembly.fetch(result, :left)
{:ok, volume} = OCEx.volume(left.shape)

{:ok, files} =
  Smith.export(result, "output",
    name: "mount",
    formats: [:step, :stl, :three_mf]
  )
```

Identical recipe terms reused as instances are evaluated once per `Smith.evaluate/1` call. Each instance receives its own installed transform. There is no global cache or assembly process.

## Members and placement

`Assembly.part/3,4` adds a manufactured part. `Assembly.reference/3,4` adds electronics, hardware, or other reference solids. Both accept an atom or string name and a `Smith.Model`. Names start with an ASCII letter or digit and may then contain letters, digits, underscores, or hyphens. They are case-sensitive and must be unique across both kinds, including after underscores normalize to hyphens: `:wall_plate` and `"wall-plate"` identify the same name. `Assembly.fetch/2` uses the same lookup and returns `{:error, :unknown_part}` when absent.

| Option                                             | Meaning                                                                    |
| -------------------------------------------------- | -------------------------------------------------------------------------- |
| `position: {x, y, z}`                              | Installed translation, default zero                                        |
| `rotation: {axis, degrees}`                        | Installed rotation about the world origin, applied before translation      |
| `print: [rotation: ..., offset: ..., on_bed: ...]` | Printable orientation and placement, starting from the installed shape     |
| `exploded_offset: {x, y, z}`                       | Additional exploded offset stored in exported metadata                     |
| `display_offset: {x, y, z}`                        | Viewer offset, independent of geometry and printing                        |
| `installed: false`                                 | Printable extra excluded from the installed assembly, such as a fit coupon |

Print, display, exploded, and installed options apply only to manufactured parts. References accept `position:` and `rotation:`. Print `on_bed: true` centers geometry-derived XY bounds and puts the lowest point on Z=0 after print rotation; it cannot be combined with print `offset:`. The export preview uses installed placement plus `display_offset:`. `exploded_offset:` is recorded as metadata for a viewer to interpret. Neither option moves a direct `Smith.Kino` preview. Print transforms do not change the installed STEP geometry. Distances use millimeters and rotations use degrees; mesh angular tolerance uses radians.

An assembly must have at least one installed manufactured part. Each member must contain at least one solid; a member may contain several. Bare sketches and nested assemblies cannot be members. Duplicate names, invalid options, and unsupported recipes fail during evaluation. A named failure retains the underlying operation and one-based index:

```elixir
{:error,
 %Smith.Error{
   part: :shell,
   step: 2,
   operation: :fillet,
   reason: :invalid_argument
 }}
```

Assembly-level member validation uses `operation: :assembly` and `step: nil`. Nested tool errors retain their original nested reason. Exceptions raised by selector callbacks propagate to the caller.

## Evaluation and export

`Smith.Assembly.Result` retains the installed compound in `shape`, its BREP geometry hash in `revision`, and evaluated members in `entries`. `Assembly.fetch/2` returns a normal `Smith.Result` for any member, including references and printable extras. Geometry hashes describe installed manufactured geometry; export IDs distinguish runs with different references, print settings, or metadata.

Assembly `Smith.export/3` accepts required `name:`, optional `formats:`, `tolerance:`, `angular_tolerance:`, `step_tolerance:`, `metadata:`, and `part_metadata:`. The mesh/STEP defaults match ordinary verified exports. `part_metadata:` is a map keyed by known manufactured part names; it attaches model-specific audit results without coupling Smith to those audits.

By default export produces:

- Per-part STEP, BREP, STL, 3MF, preview mesh, and check reports, named `<assembly>-<part>`.
- An installed `assembly.step` and `assembly.brep`, excluding references and printable extras.
- A separate `references-DO-NOT-PRINT.step` when references exist.
- A `printables.zip` containing each manufactured part's STL and 3MF, including extras.
- A permanent `assembly.json` report with part names, paths, references, and export identity.

`formats:` must be a nonempty unique selection of `:step`, `:stl`, and `:three_mf`. Unrequested file paths are `nil`. STEP-only exports have no print pack. Geometry/preview reports and BREP snapshots remain available regardless of format selection. Print meshes are checked even when only STEP is requested. Every emitted STEP is reimported and checked for validity, solid count, and volume. 3MF contains geometry without printer settings.

Names are preserved in the Elixir result, report, and part filenames. The combined STEP currently contains an OCCT compound, not an XCAF product tree with named instances or materials. The shared viewer displays manufactured parts; reference geometry is available through `fetch/2` and its separate STEP.

## Publication

`output/current.json` is the single authoritative current manifest. Its `models` list contains preview records; its `assemblies` list contains complete assembly export reports. Find an assembly by its export `name`. The returned `files.report` points to the permanent report for that specific export.

Files are written into new export directories. After the part mesh checks and requested STEP round trips pass, one manifest replacement publishes the complete assembly. A failure preserves previous current records and their files, although unpublished files may remain. Updating an assembly removes retired parts from the manifest and preserves unrelated models/assemblies. Standalone exports cannot replace parts owned by a named assembly.

Run writers to one output root sequentially. This is atomic publication through one manifest; it is not a concurrent-writer protocol or a power-loss durability guarantee.

Explore the [Livebook guide](livebook.md) and its runnable assembly notebook for reusable parts, placement, previews, and printable exports. Nested assemblies, mates, materials, and named STEP product trees are not supported.

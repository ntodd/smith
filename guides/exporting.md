# Exporting printable models and assemblies

Use `Smith.export/3` for verified print output.
STL is a triangle mesh; 3MF also records units, while STEP retains native CAD
geometry for exchange. A slicer turns STL or 3MF into printer instructions.
Use the [inspection guide](inspection.md) to check design dimensions before export. Use `Smith.export/2` only when you need a single raw STEP or STL file.

## Verified part bundles

```elixir
{:ok, result} = Smith.box(20, 10, 4) |> Smith.evaluate()
{:ok, files} = Smith.export(result, "output", name: "block", on_bed: true)

files.step
files.stl
files.three_mf
files.verification.mesh
```

<div class="smith-doc-preview" data-preview="exporting-0-result" data-model="result" data-label="Exported block">
<p>Interactive preview available in HexDocs.</p>
</div>

A bundle is written below `output/<name>/<geometry_revision>/<export_id>/`. It includes `model.step`, `model.brep`, `model.stl`, `model.3mf`, `model.json`, and `verification.json`. Each export gets a unique ID, even when geometry is unchanged. The root `current.json` points to the latest verified exports; old directories are preserved.

The returned record includes `name`, `revision`, `export_id`, `step`, `stl`, `three_mf`, `volume`, display `mesh`, and `verification`. Paths for unrequested formats are `nil`.

## Formats and print placement

| Option                 | Default                    | Meaning                                                      |
| ---------------------- | -------------------------- | ------------------------------------------------------------ |
| `name:`                | Required                   | String starting with a letter/digit, then letters, digits, `_`, or `-`               |
| `formats:`             | `[:step, :stl, :three_mf]` | Nonempty unique subset of those formats                      |
| `on_bed:`              | `false`                    | Center printable XY bounds and put minimum Z at zero         |
| `print_rotation:`      | None                       | `{axis_vector, degrees}`, about the world origin             |
| `print_offset:`        | Zero                       | World translation after print rotation                       |
| `tolerance:`           | `0.03`                     | Absolute linear mesh deflection in mm                        |
| `angular_tolerance:`   | `0.5`                      | Angular mesh deflection in radians                           |
| `step_tolerance:`      | `1.0e-6`                   | Maximum relative STEP volume error, capped at `1.0e-5`       |
| `display_offset:`      | Zero                       | Viewer placement; does not move printable geometry           |
| `display_orientation:` | `:print`                  | `:installed` keeps display geometry in installed coordinates |
| `metadata:`            | `%{}`                      | Caller data added to the verification record                 |

`on_bed: true` is applied after print rotation and cannot be combined with `print_offset:`. STEP and BREP retain the evaluated orientation. STL and 3MF use the resolved print placement. The display mesh always uses 0.03 mm linear and 0.5 rad angular deflection, independently of the requested print settings. Returned paths are relative if the output root is relative.

```elixir
{:ok, files} = Smith.export(result, "output",
  name: "side-printed-block",
  formats: [:stl, :three_mf],
  print_rotation: {{1, 0, 0}, 90},
  on_bed: true,
  tolerance: 0.02,
  angular_tolerance: 0.1
)

# The exported STL, in its print orientation.
print_model = files.stl |> File.read!() |> Smith.Mesh.from_stl()
```

<div class="smith-doc-preview" data-preview="exporting-1-print-model" data-model="print_model" data-label="Print orientation">
<p>Interactive preview available in HexDocs.</p>
</div>

Smaller deflection values generally produce more triangles and larger files. `tolerance:` is not a dimensional offset or printer clearance. Model clearances explicitly in the design. 3MF contains millimeter geometry; it is not a configured printer project.

## Export checks

Export first compares the evaluated shape's BREP hash with its stored revision,
then requires positive volume and at least one solid. Evaluation and the native
constructors perform OCCT shape validation; the bundle does not separately run
a new validity check on the input shape.

The print mesh is welded, serialized as binary STL, and read back. Smith then checks:

- Every edge belongs to exactly two triangles, traversed in opposite directions.
- The number of triangle components connected by shared edges equals the native solid count.
- Signed mesh volume differs from native volume by less than 0.5%.

The STL round trip matters because STL stores coordinates as 32-bit floats.
3MF is generated from the welded mesh before that float conversion. The
exporter does not independently reimport the 3MF archive.

Every requested STEP is read back and checked for native validity, the same
solid count, and relative volume error strictly below `step_tolerance:`.
This does not compare boundary distances or prove that every dimension
survived exchange.

Even STEP-only bundles run the mesh checks; this API is for printable solid models. For faces/edges or raw exchange use the lower-level `Smith.export/2` or OCEx operations. Mesh checks do not certify physical fit, printer calibration, supports, strength, or absence of arbitrary triangle self-intersections. Check design clearances and critical dimensions separately. A fully enclosed cavity can produce multiple disconnected boundary shells inside one solid; the current component-count check rejects that arrangement.

## Assembly exports

```elixir
assembly_recipe =
  Smith.Assembly.new(:enclosure)
  |> Smith.Assembly.part(:base, Smith.box(20, 10, 4), print: [on_bed: true])
  |> Smith.Assembly.part(:lid, Smith.box(20, 10, 2),
    position: {0, 0, 12}, print: [on_bed: true])

{:ok, assembly} = Smith.evaluate(assembly_recipe)
{:ok, files} = Smith.export(assembly, "output", name: "enclosure")
files.assembly_step
files.references_step
files.print_pack
files.parts
```

<div class="smith-doc-preview" data-preview="exporting-2-assembly" data-model="assembly" data-label="Exported enclosure">
<p>Interactive preview available in HexDocs.</p>
</div>

The assembly result produces checked manufactured-part bundles, a geometry-only installed assembly STEP/BREP, a separate reference-only STEP, and `printables.zip` containing requested STL/3MF pairs. `installed: false` parts remain printable but stay out of the installed assembly. References never enter the print pack. STEP carries geometry without a named XCAF product tree; member identity remains in Smith results, filenames, and reports.

Assembly options are `name:`, `formats:`, `tolerance:`, `angular_tolerance:`, `step_tolerance:`, `metadata:`, and `part_metadata:`. Print and display placement belong on each assembly part, not in these export options. `part_metadata:` maps member names to metadata maps. See [Assemblies](assemblies.md).

## File writes and failures

Files are staged and checked before the root manifest is replaced. A failed export preserves the prior current manifest and all earlier permanent files; it may leave a unique unpublished directory for inspection. Run writers to the same output root sequentially. There is no multi-process publication lock.

`Smith.Export.write_many/2` publishes several independent `{result, options}` entries together. Assemblies enforce ownership of their part names and reject stale member geometry. `Smith.Export.publish/2` only updates records; it does not run the file or geometry checks performed by the bundle writers. Do not manually modify evaluated structs or overwrite files beneath an existing export ID.

## When an export fails

Inspect the returned reason before changing the model. Common failures are:

| Reason | What to check |
| --- | --- |
| `:mesh_volume_mismatch` | Reduce linear and angular deflection for curved or small features |
| `:invalid_print_mesh` | Check disconnected shells, touching parts, and mesh edge connectivity |
| `:no_solids` | Extrude or revolve a face before printable export |
| `:revision_mismatch` | Use the unmodified result from `Smith.evaluate/1` |
| `:step_volume_mismatch` | Inspect the STEP round trip and the chosen threshold |
| `:assembly_part_conflict` | Choose a standalone export name that is not owned by an assembly |

The return from `Smith.Export.mesh/3` exposes the checked STL and the
mesh report when successful. `Smith.Mesh.inspect/1` can inspect a welded
native mesh directly when diagnosing connectivity; that report alone does
not represent the serialized STL check.

## Single-file exchange

For a raw file:

```elixir
{:ok, :ok} = Smith.export(result, "block.step")
```

<div class="smith-doc-preview" data-preview="exporting-3-result" data-model="result" data-label="STEP geometry">
<p>Interactive preview available in HexDocs.</p>
</div>

This overwrites the given file, requires the parent directory to exist, and does not perform bundle verification or update `current.json`. Raw STL uses OCEx defaults of 0.1 mm / 0.5 rad.

## Two-dimensional views

Use `Smith.Drawing.new/2` followed by `Smith.Drawing.write/3` for SVG or DXF.
These drawing files have separate visible/hidden layers and millimeter coordinates.
They are sampled views, not printable solid bundles. See [drawings](drawings.md).

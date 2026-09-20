# Assemblies

An assembly names parts and places them relative to one another without fusing
them. A reference is hardware or another object you need to fit around but will
not print. Assemblies are ordinary immutable values. Parts contain deferred Smith recipes; evaluation constructs native geometry. A design can stay in a standalone `.exs` file with `Mix.install([{:smith, "~> 0.4.0"}])`, or in a Livebook.

```elixir
alias Smith.Assembly

spacer_block = Smith.box(2, 3, 4)

model =
  Assembly.new(:mount)
  |> Assembly.part(:left, spacer_block,
    position: {-10, 0, 20},
    print: [on_bed: true]
  )
  |> Assembly.part(:right, spacer_block,
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

<div class="smith-doc-preview" data-preview="assembly-installed" data-model="result" data-label="Installed assembly">
<p>Interactive 3D preview available in HexDocs.</p>
</div>

Identical recipe terms reused as instances are evaluated once per `Smith.evaluate/1` call. Each instance receives its own installed transform. There is no global cache or assembly process.

## Inspection views

Build a snapshot from an evaluated assembly, then render it:

```elixir
exploded = Smith.Assembly.view(result, :exploded)
Smith.Kino.render(exploded, label: "Exploded assembly")
```

<div class="smith-doc-preview" data-preview="assembly-exploded" data-model="exploded" data-label="Exploded assembly">
<p>Interactive 3D preview available in HexDocs.</p>
</div>

The default `:installed` mode retains the installed compound. `:display` shows all
manufactured leaves, including printable extras, with accumulated display offsets.
`:exploded` adds exploded offsets to that display placement, matching the exported
viewer. Both use resolved world geometry, including nested placement and joints.
References remain excluded; fetch them individually to inspect them.

The view is a `Smith.Result` with its own geometry revision. It does not change
the assembly or apply print transforms. Export the original assembly result to
keep its named parts, print orientations, and separate printable files.

## Members and placement

`Assembly.part/3,4` adds a manufactured part. `Assembly.reference/3,4` adds electronics, hardware, or other reference solids. Both accept an atom or string name and a `Smith.Model`. `Assembly.subassembly/4` adds another assembly under an instance name. Names start with an ASCII letter or digit and may then contain letters, digits, underscores, or hyphens. They are case-sensitive and must be unique among sibling parts, references, and subassemblies, including after underscores normalize to hyphens: `:wall_plate` and `"wall-plate"` identify the same name. `Assembly.fetch/2` uses the same lookup and returns `{:error, :unknown_part}` when absent.

| Option                                             | Meaning                                                                    |
| -------------------------------------------------- | -------------------------------------------------------------------------- |
| `position: {x, y, z}`                              | Installed translation, default zero                                        |
| `rotation: {axis, degrees}`                        | Rotation about the local origin, applied before translation      |
| `print: [rotation: ..., offset: ..., on_bed: ...]` | Printable orientation and placement, starting from the installed shape     |
| `exploded_offset: {x, y, z}`                       | Additional exploded offset stored in exported metadata                     |
| `display_offset: {x, y, z}`                        | Viewer offset, independent of geometry and printing                        |
| `installed: false`                                 | Printable extra excluded from the installed assembly, such as a fit coupon |

Print options belong to manufactured leaves. Subassemblies also accept display, exploded, and installed options. References accept `position:` and `rotation:`. Print `on_bed: true` centers geometry-derived XY bounds and puts the lowest point on Z=0 after print rotation; it cannot be combined with print `offset:`. The export preview uses installed placement plus `display_offset:`. `exploded_offset:` is recorded as metadata for a viewer to interpret. Direct `Smith.Kino` assembly previews retain installed geometry. Use `Smith.Assembly.view/2` to apply these offsets explicitly. Print transforms do not change the installed STEP geometry. Distances use millimeters and rotations use degrees; mesh angular tolerance uses radians.

An assembly must have at least one installed manufactured part. Each member must contain at least one solid; a member may contain several. Bare sketches cannot be members. Add a nested assembly with `subassembly/4`; `part/4` continues to require a solid-containing model. Duplicate names, invalid options, and unsupported recipes fail during evaluation. A named failure retains the underlying operation and one-based index:

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

## Reusable subassemblies

Build one assembly recipe, then place it more than once. For a parameterized
module, put that construction in an ordinary function. Children rotate and translate in their local frame before parent transforms
apply. Reused leaf recipes evaluate once across the whole tree. Names need only be
unique among siblings.

```elixir
module_recipe = Assembly.new(:module)
  |> Assembly.part(:base, Smith.box(20, 12, 4), print: [on_bed: true])
  |> Assembly.part(:spacer, Smith.cylinder(2, 6), position: {10, 6, 4}, print: [on_bed: true])
  |> Assembly.reference(:device, Smith.box(20, 12, 5), position: {0, 0, 10})

pair = Assembly.new(:pair)
  |> Assembly.subassembly(:left, module_recipe, position: {-30, 0, 0})
  |> Assembly.subassembly(:right, module_recipe,
    rotation: {{0, 0, 1}, 90}, position: {30, 0, 0})

{:ok, assembled} = Smith.evaluate(pair)
{:ok, right} = Assembly.fetch(assembled, :right)
{:ok, spacer} = Assembly.fetch(assembled, [:right, :spacer])
{:ok, ^spacer} = Assembly.fetch(right, :spacer)
{:ok, members} = Assembly.members(assembled)
6 = length(members)
4 = Enum.count(members, & &1.installed)
```

<div class="smith-doc-preview" data-preview="assemblies-3-assembled" data-model="assembled" data-label="Nested assembly">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="assemblies-3-right" data-model="right" data-label="Right subassembly">
<p>Interactive preview available in HexDocs.</p>
</div>

<div class="smith-doc-preview" data-preview="assemblies-3-spacer" data-model="spacer" data-label="Fetched spacer">
<p>Interactive preview available in HexDocs.</p>
</div>

Paths can also be strings: `"right/spacer"`. Empty paths, unknown names,
and descent through a leaf return `:unknown_part`. Fetching a branch keeps
its descendants in final world coordinates. `members/1` returns all leaves
in depth-first insertion order, with normalized path segments, a slash-separated
key, kind, effective installed status, placed result, and export options.

An uninstalled subassembly excludes all its manufactured leaves from the parent's
installed compound. Those leaves still receive print files. References remain
references regardless of ancestor settings. Each assembly must have at least one
locally installed manufactured member, even when the entire instance is marked
uninstalled in its parent.

Print transforms act on each leaf's final world geometry. A parent rotation can
therefore change its print orientation; `on_bed: true` fixes bed placement,
not orientation. Display and exploded offsets are world vectors and add along
the ancestry without rotation. Direct Kino previews show installed geometry.

Nested export identities use slash paths. Filenames join normalized segments with
`__`, for example `pair-right__spacer.stl`. Since normalization replaces
name underscores with hyphens, a single segment cannot imitate that separator.
Flat part filenames remain unchanged. The JSON `tree` retains local options,
effective installed flags, revisions, and child nodes. Combined STEP remains
geometry-only; it has no named XCAF product structure.

The [nested assembly Livebook](../examples/nested-assemblies.livemd)
builds and previews two modules and exports their printable leaves. A nested
modeling error identifies the full path, such as `"left/base"`, while retaining
the original failing operation and step.

## Evaluation and export

`Smith.Assembly.Result` retains the installed compound in `shape`, its BREP geometry hash in `revision`, and evaluated members in `entries`. `Assembly.fetch/2` returns a `Smith.Result` for a leaf (including references and printable extras), or another `Smith.Assembly.Result` for a subassembly. Geometry hashes describe installed manufactured geometry; export IDs distinguish runs with different references, print settings, or metadata.

Assembly `Smith.export/3` accepts required `name:`, optional `formats:`, `tolerance:`, `angular_tolerance:`, `step_tolerance:`, `metadata:`, and `part_metadata:`. The mesh/STEP defaults match ordinary verified exports. `part_metadata:` is a map keyed by known manufactured leaf paths (single names, slash strings, or lists of names); it attaches model-specific audit results without coupling Smith to those audits.

By default export produces:

- Per-part STEP, BREP, STL, 3MF, preview mesh, and check reports, named `<assembly>-<part>`.
- An installed `assembly.step` and `assembly.brep`, excluding references and printable extras.
- A separate `references-DO-NOT-PRINT.step` when references exist.
- A `printables.zip` containing each manufactured part's STL and 3MF, including extras.
- A permanent `assembly.json` report with part names, paths, references, export identity, and the nested tree.

`formats:` must be a nonempty unique selection of `:step`, `:stl`, and `:three_mf`. Unrequested file paths are `nil`. STEP-only exports have no print pack. Geometry/preview reports and BREP snapshots remain available regardless of format selection. Print meshes are checked even when only STEP is requested. Every emitted STEP is reimported and checked for validity, solid count, and volume. 3MF contains geometry without printer settings.

Names are preserved in the Elixir result, report, and part filenames. The combined STEP currently contains an OCCT compound, not an XCAF product tree with named instances or materials. The shared viewer displays manufactured parts; reference geometry is available through `fetch/2` and its separate STEP.

## Export identity and failures

`files.report` identifies this export; `output/current.json` lists current exports.
A failed check leaves the previous manifest intact. Run writers to one output
root sequentially. The [export guide](exporting.md#file-writes-and-failures)
explains file placement, atomic updates, and failure recovery.

Continue with [joints and poses](joints.md) for attachment frames and movement, or
open the [assembly lesson](../examples/assembly.livemd) to build reusable feet and
export a print pack.

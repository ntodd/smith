# Modeling in Livebook

Livebook makes a model a sequence of executable, editable steps. Keep each stage
in its own variable and display it with `Smith.Kino.render/2`. Earlier stages stay
available for comparison and reuse. Changing a parameter and reevaluating dependent
cells rebuilds the geometry using native OCEx operations.

## Setup

Install [Livebook](https://livebook.dev/) and the pinned toolkit described in the
[OCEx installation guide](https://hexdocs.pm/ocex/installation.html). The Elixir
runtime evaluating the notebook needs OCCT, a compiler, and its headers. Installing
OCCT on your laptop does not install it in a remote or container runtime.

In the notebook's setup cell:

```elixir
Mix.install([
  {:smith, "~> 0.1.0"},
  {:kino, "~> 0.19.0"}
])
```

Smith brings in OCEx as a Hex dependency; no sibling checkout or dependency
override is needed.

OCEx discovers Homebrew CMake even when the Livebook desktop runtime omits it from
`PATH`. If dependency compilation already failed, restart the runtime and run setup
again.

Kino is optional. Ordinary scripts and applications need only Smith. If adding
Kino to an already compiled application, recompile Smith to enable the renderer.
Without it, `Smith.Kino.render/2` raises with reason `:kino_not_available`. For a
notebook previously compiled without Kino, restart its runtime and use
`Mix.install(deps, force: true)` once, then remove `force: true` for normal use.

The previews on this page use the same renderer as Livebook. Their meshes are
built from the guide's examples when the documentation is generated. You can
inspect them here without installing Elixir; open the notebook to edit a recipe
and rebuild its geometry.

## Show each stage

Use separate cells for these steps. `render/2` returns the Kino directly, so the
render call can be the final expression in each cell:

```elixir
blank = Smith.box(60, 40, 5)
Smith.Kino.render(blank, label: "1 · Blank")
```

<div class="smith-doc-preview" data-preview="plate-blank" data-model="blank" data-label="Blank">
<p>Interactive 3D preview available in HexDocs.</p>
</div>

```elixir
rounded = blank |> Smith.fillet(edges: {:parallel, :z}, radius: 2)
Smith.Kino.render(rounded, label: "2 · Rounded corners")
```

<div class="smith-doc-preview" data-preview="plate-rounded" data-model="rounded" data-label="Rounded corners">
<p>Interactive 3D preview available in HexDocs.</p>
</div>

```elixir
finished = rounded |> Smith.hole(on: :top, diameter: 8, through: :all)
{:ok, result} = Smith.evaluate(finished)
Smith.Kino.render(result, label: "3 · Drilled plate")
```

<div class="smith-doc-preview" data-preview="plate-drilled" data-model="result" data-label="Drilled plate">
<p>Interactive 3D preview available in HexDocs.</p>
</div>

Drag to rotate and scroll to zoom. **Fullscreen** expands the preview to the screen
while retaining the current camera and controls. Choose **Exit fullscreen** or press
**Esc** to return to the notebook. The canvas resizes with the available space;
**Download PNG** saves the view at its current canvas resolution. **Reset view**
restores the initial camera. Fullscreen requires browser/iframe support; the
button is disabled when unavailable, and a denied request displays a message. Geometry and the renderer's JavaScript are sent
to your browser through Livebook. Rendering uses WebGL with no external CDN,
Python process, or graphics server. Every preview includes its geometry revision.

`render/2` accepts a recipe, sketch, assembly, or evaluated result. It also accepts
`{:ok, result}`, so evaluation and assembly views can pipe directly into it:

```elixir
finished
|> Smith.evaluate()
|> Smith.Kino.render(label: "Finished plate")
```

<div class="smith-doc-preview" data-preview="livebook-4-finished" data-model="finished" data-label="Piped evaluation">
<p>Interactive preview available in HexDocs.</p>
</div>

Passing an existing result avoids reevaluating the recipe. Preview failures raise
`RuntimeError` with the reason, including the operation and step for modeling
failures. A piped `{:error, reason}` raises the same error. Match on
`Smith.evaluate/1` before rendering when you need to handle a failure yourself.

The default mesh uses 0.03 mm
linear and 0.5 rad angular deflection. Large meshes increase notebook transfer and
browser memory use; raise `tolerance:` for a lighter preview. Camera position is
local to each output and resets when that cell is reevaluated. Assembly
`display_offset:` and `exploded_offset:` do not move a direct assembly preview.
Use `Smith.Assembly.view(result, :display)` or `:exploded` to create a snapshot
with these offsets applied, then pass that result to `Smith.Kino.render/2`.

## Assemblies and files

An assembly preview shows installed manufactured parts. Fetch a member with
`Smith.Assembly.fetch/2` to inspect a reference or a printable extra individually.
The initial preview has one surface color; it does not offer part selection,
dimensions or material rendering. Exploded placement comes from `Smith.Assembly.view/2`;
export the original assembly result to preserve its installed and print placements.

To generate printable files, export the evaluated result:

```elixir
{:ok, files} = Smith.export(result, "output", name: "plate", on_bed: true)
files
```

<div class="smith-doc-preview" data-preview="livebook-5-result" data-model="result" data-label="Exported plate">
<p>Interactive preview available in HexDocs.</p>
</div>

PNG is an illustration, not a fabrication file. Export produces verified STL and
3MF geometry plus STEP and reports; see [exporting](exporting.md). Files are written
on the machine running the notebook's Elixir runtime.

## Raspberry Pi enclosure walkthrough

[Design a Raspberry Pi enclosure](../examples/raspberry-pi-enclosure.livemd)
builds a complete mechanical assembly from reference geometry through printable
exports. Follow the sliding tray, rotating latch, and curved duct through their
construction stages, then inspect the installed and exploded poses. The notebook
includes interference checks, drawings, and a rail fit test. It assumes Smith is
installed and concentrates on modeling decisions.

## Runnable notebooks

Download or open these from the repository in Livebook:

- [A plate, step by step](https://github.com/ntodd/smith/blob/main/examples/plate.livemd)
- [Selectors, sweeps, smooth lofts, and shelling](https://github.com/ntodd/smith/blob/main/examples/paths-and-shells.livemd)
- [Sketches, revolve, and loft](https://github.com/ntodd/smith/blob/main/examples/profiles.livemd)
- [Draft, split, section, offset, and thickening](https://github.com/ntodd/smith/blob/main/examples/forming.livemd)
- [Attachment frames and joint poses](https://github.com/ntodd/smith/blob/main/examples/joints.livemd)
- [Reusable nested assemblies](https://github.com/ntodd/smith/blob/main/examples/nested-assemblies.livemd)
- [A named assembly and print pack](https://github.com/ntodd/smith/blob/main/examples/assembly.livemd)

The notebooks are also included under `examples/` in the Hex package. Their setup
cells install Smith and Kino from Hex.

The [mechanical parts notebook](https://github.com/ntodd/smith/blob/v0.1.0/examples/mechanical-parts.livemd) builds a slotted plate in stages, adds blind and recessed holes, inspects selections, mirrors the result, and exports the parts with a torus and sphere.

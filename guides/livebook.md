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

When working from this repository before publication, include Kino alongside both
path dependencies:

```elixir
Mix.install([
  {:smith, path: Path.expand("..", __DIR__)},
  {:ocex, path: Path.expand("../../ocex", __DIR__), override: true},
  {:kino, "~> 0.19.0"}
])
```

These paths assume a notebook saved in Smith's `examples/` directory and an OCEx checkout beside the Smith repository. The OCEx override is optional once the dependency is published on Hex. Unsaved or
remotely evaluated notebooks should use absolute paths to the runtime's checkout.
OCEx discovers Homebrew CMake even when the Livebook desktop runtime omits it from
`PATH`. If dependency compilation already failed, restart the runtime and run setup
again.

Kino is optional. Ordinary scripts and applications need only Smith. If adding
Kino to an already compiled application, recompile Smith to enable the renderer.
Without it, `Smith.Kino.render/2` returns `{:error, :kino_not_available}`. For a
notebook previously compiled without Kino, restart its runtime and use
`Mix.install(deps, force: true)` once, then remove `force: true` for normal use.

## Show each stage

Use separate cells for these steps. The return is `{:ok, preview}`, so unwrap it first. Each cell ends with the preview value:

```elixir
blank = Smith.box(60, 40, 5)
{:ok, preview} = Smith.Kino.render(blank, label: "1 · Blank")
preview
```

```elixir
rounded = blank |> Smith.fillet(edges: {:parallel, :z}, radius: 2)
{:ok, preview} = Smith.Kino.render(rounded, label: "2 · Rounded corners")
preview
```

```elixir
finished = rounded |> Smith.hole(on: :top, diameter: 8, through: :all)
{:ok, result} = Smith.evaluate(finished)
{:ok, preview} = Smith.Kino.render(result, label: "3 · Drilled plate")
preview
```

Drag to rotate and scroll to zoom. **Fullscreen** expands the preview to the screen
while retaining the current camera and controls. Choose **Exit fullscreen** or press
**Esc** to return to the notebook. The canvas resizes with the available space;
**Download PNG** saves the view at its current canvas resolution. **Reset view**
restores the initial camera. Fullscreen requires browser/iframe support; the
button is disabled when unavailable, and a denied request displays a message. Geometry and the renderer's JavaScript are sent
to your browser through Livebook. Rendering uses WebGL with no external CDN,
Python process, or graphics server. Every preview includes its geometry revision.

`render/2` accepts a recipe, sketch, assembly, or evaluated result. Passing an
existing result avoids reevaluating the recipe. The default mesh uses 0.03 mm
linear and 0.5 rad angular deflection. Large meshes increase notebook transfer and
browser memory use; raise `tolerance:` for a lighter preview. Camera position is
local to each output and resets when that cell is reevaluated. Assembly
`display_offset:` and `exploded_offset:` are export metadata; this preview
does not apply them.

## Assemblies and files

An assembly preview shows installed manufactured parts. Fetch a member with
`Smith.Assembly.fetch/2` to inspect a reference or a printable extra individually.
The initial preview has one surface color; it does not offer part selection,
exploded placement, dimensions, or material rendering.

To generate printable files, export the evaluated result:

```elixir
{:ok, files} = Smith.export(result, "output", name: "plate", on_bed: true)
files
```

PNG is an illustration, not a fabrication file. Export produces verified STL and
3MF geometry plus STEP and reports; see [exporting](exporting.md). Files are written
on the machine running the notebook's Elixir runtime.

## Runnable notebooks

Download or open these from the repository in Livebook:

- [A plate, step by step](https://github.com/ntodd/smith/blob/main/examples/plate.livemd)
- [Sketches, revolve, and loft](https://github.com/ntodd/smith/blob/main/examples/profiles.livemd)
- [A named assembly and print pack](https://github.com/ntodd/smith/blob/main/examples/assembly.livemd)

The notebooks are also included under `examples/` in the Hex package. Their setup
cells use published dependencies. For local development, replace the setup cell
with path dependencies for Smith and an explicit OCEx override, as shown above. The repository's notebook check evaluates the model cells using its local dependency build; setup dependency resolution is checked separately.

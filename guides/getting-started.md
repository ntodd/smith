# Getting started

Smith turns Elixir values into precise geometry and printable files. Start with a small script, then extract named functions as the design grows.

## Install the native toolkit

Follow [OCEx installation](https://hexdocs.pm/ocex/installation.html) to install the supported OCCT 7.9.3 build and set `OpenCASCADE_DIR`. Install Elixir 1.18 or newer. The native NIF compiles automatically the first time the dependency is compiled; subsequent runs reuse the compiled library.

The OCCT libraries must remain installed after compilation. A successful Mix dependency download alone does not provide the toolkit.

## Choose a script or project

For a standalone file:

```elixir
Mix.install([{:smith, "~> 0.1.0"}])
```

For an existing Mix application, add `{:smith, "~> 0.1.0"}` to its dependencies and run `mix deps.get`. Use `Mix.install` only in standalone scripts or notebook setup, not inside an existing Mix project. There is no Smith application process or supervision tree to configure.

## Define a reusable part

```elixir
defmodule Mount do
  alias Smith.Sketch

  def build(width \\ 60, depth \\ 40, thickness \\ 5) do
    Sketch.rectangle(width, depth)
    |> Sketch.fillet(radius: 2)
    |> Sketch.cut(mounting_holes(width))
    |> Smith.extrude(thickness)
  end

  defp mounting_holes(width) do
    for x <- [-width / 3, width / 3], do: Sketch.circle(4, at: {x, 0})
  end
end

{:ok, part} = Mount.build() |> Smith.evaluate()
{:ok, files} = Smith.export(part, "output", name: "mount", on_bed: true)
IO.puts(files.three_mf)
```

<div class="smith-doc-preview" data-preview="getting-started-1-part" data-model="part" data-label="Mounting plate">
<p>Interactive preview available in HexDocs.</p>
</div>

`build/3` returns an immutable `Smith.Model`. Native operations run at evaluation. Reusing a recipe does not mutate the original or share a mutable modeling context.

Use a struct for parameters when a design has many dimensions; pass it to feature functions. Ordinary `Enum.map`, comprehensions, and pipelines are enough for patterns and assembly construction. Parameter values do not need a separate schema or framework.

## Understand the values

| Value                   | Meaning                                               |
| ----------------------- | ----------------------------------------------------- |
| `Smith.Plane`           | A deferred local coordinate frame                     |
| `Smith.Sketch`          | A connected 2D region with optional holes             |
| `Smith.Model`           | A deferred edge, face, or solid recipe                |
| `Smith.Result`          | An evaluated native shape plus geometry revision      |
| `Smith.Assembly`        | A recipe with named manufactured parts and references |
| `Smith.Assembly.Result` | Evaluated members and their installed compound        |

Bare sketches evaluate to faces, which can be inspected with `OCEx.area/1`. Extrude, revolve, loft, or sweep before printable export. A model recipe may also describe an edge or an empty compound; successful evaluation does not necessarily mean a printable solid.

## Inspect and export

```elixir
{:ok, volume} = OCEx.volume(part.shape)
{:ok, bounds} = OCEx.bounds(part.shape)
{:ok, solids} = OCEx.solids(part.shape)
```

<div class="smith-doc-preview" data-preview="getting-started-2-part" data-model="part" data-label="Measured part">
<p>Interactive preview available in HexDocs.</p>
</div>

Queries return tagged results. Dimensions use millimeters, volumes cubic millimeters, and modeling angles degrees. Meshing angles use radians. Start with verified export defaults, then adjust mesh tolerances when necessary; see [Exporting](exporting.md).

Open the [Livebook guide](livebook.md) to see stages while editing. Native geometry and printable exports also work in a terminal without a browser.

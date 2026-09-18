# Modeling in Livebook

Livebook lets you edit a model one stage at a time and inspect each result.
This guide covers setup and previews. The lessons below teach modeling; you do
not need to read every feature guide before starting the first one.

## Setup

Install Livebook and the toolkit described in the
[OCEx installation guide](https://hexdocs.pm/ocex/installation.html).
The runtime executing the notebook needs the toolkit, compiler, and OTP headers.
For a remote runtime, install them on that machine.

```elixir
Mix.install([{:smith, "~> 0.3.0"}, {:kino, "~> 0.19.0"}])
```

Run this in the setup cell. Smith brings OCEx in as a dependency. Kino provides
Livebook outputs; ordinary modeling scripts do not need it. After changing
native code or dependencies, restart the runtime and reevaluate setup. When
compilation fails, read the native error above Mix's dependency summary. The
installation guide covers missing tools, headers, and Xcode license acceptance.

If the runtime already compiled Smith without Kino, rebuild once with
`Mix.install(deps, force: true)`, then remove `force: true` for normal use.
The release notebooks use Hex dependencies; local development can replace Smith
with a path dependency and add a local OCEx override in setup.

## Show each stage

Put each block in its own cell. Recipes are ordinary Elixir values, and each
operation returns a new one. A fillet rounds edges; a hole removes material.
See [CAD concepts](cad-basics.md) for unfamiliar terms.

```elixir
blank = Smith.box(60, 40, 5)
Smith.Kino.render(blank, label: "1 · Blank")
```

<div class="smith-doc-preview" data-preview="plate-blank" data-model="blank" data-label="Blank">
<p>Interactive preview available in HexDocs.</p>
</div>

```elixir
rounded = blank |> Smith.fillet(edges: {:parallel, :z}, count: 4, radius: 2)
Smith.Kino.render(rounded, label: "2 · Rounded corners")
```

<div class="smith-doc-preview" data-preview="plate-rounded" data-model="rounded" data-label="Rounded corners">
<p>Interactive preview available in HexDocs.</p>
</div>

```elixir
finished = rounded |> Smith.hole(on: :top, diameter: 8, through: :all)
{:ok, result} = Smith.evaluate(finished)
Smith.Kino.render(result, label: "3 · Drilled plate")
```

<div class="smith-doc-preview" data-preview="plate-drilled" data-model="result" data-label="Drilled plate">
<p>Interactive preview available in HexDocs.</p>
</div>

`render/2` returns the Kino directly, so leave it as the cell's final expression.
It accepts recipes, sketches, paths, native shapes, assemblies, evaluated results,
and tagged `{:ok, result}` values. For example,
`finished |> Smith.evaluate() |> Smith.Kino.render()` displays the result.
Match on evaluation first when you also need the result for measurements or export.
Rendering errors raise with the failed operation and reason.

## Inspect the preview

Drag to orbit and scroll to zoom. **View** chooses a standard orthographic view;
**Edges** shows native boundaries. Open **Clipping** to choose a plane, move
the cut with the position slider, or flip the visible side. Clipping reveals
interior surfaces without modifying or capping geometry. Use `Smith.section/2`
when you need an actual measurable cross-section.

**Fullscreen** expands the output; **Esc** returns to the notebook. **Download
PNG** saves the current 3D view. The toolbar buttons have tooltips with these
names. Each output has its own camera and clipping settings, which reset when
the output is replaced. The renderer uses WebGL in your browser; no
separate graphics server is needed.

Set the initial view explicitly when it helps explain a feature:

```elixir
Smith.Kino.render(result, label: "Hole from above", view: :top, edges: true)
```

<div class="smith-doc-preview" data-preview="livebook-4-finished" data-model="result" data-label="Hole from above">
<p>Interactive preview available in HexDocs.</p>
</div>

Top looks from +Z, front from −Y, and right from +X. These are world directions;
Smith does not infer the front of a product. The default preview mesh uses
0.03 mm linear and 0.5 rad angular deflection. Larger `tolerance:` values can
make large previews lighter without changing the native geometry.

## Reuse an evaluated stage

Rendering a recipe evaluates it. Evaluating the same recipe again repeats that
work. When an expensive stage feeds several operations, keep its result and
branch with `Smith.from_result/1`:

```elixir
blank_snapshot = Smith.from_result(result)
upper = Smith.split(blank_snapshot, Smith.Plane.xy(z: 2.5), keep: :positive)
Smith.Kino.render(upper, label: "Upper half from the existing geometry")
```

<div class="smith-doc-preview" data-preview="evaluated-branch" data-model="upper" data-label="Branch from an evaluated plate">
<p>Interactive preview available in HexDocs.</p>
</div>

Keep the original recipe as the editable source. A snapshot holds native geometry
in this runtime; it does not update itself or survive a runtime restart. After
editing upstream parameters, reevaluate the affected cells in order.

## Drawings and colored stages

Drawings also use `Smith.Kino.render/2`. The preview fits the complete drawing
within the output area, with fullscreen and SVG download controls. Display size
does not change the exported dimensions.

```elixir
{:ok, width} = Smith.Measure.extent(result, :x)
{:ok, drawing} = Smith.Drawing.new(result, on: :xy)
{:ok, drawing} = Smith.Drawing.dimension(drawing, width, orientation: :horizontal, offset: -8)
Smith.Kino.render(drawing, label: "Measured plate", hidden: false)
```

<div class="smith-doc-preview" data-preview="livebook-measured-plate" data-model="drawing" data-label="Measured plate">
<p>Dimensioned drawing available in HexDocs.</p>
</div>

For a colored 3D scene, pass `[{source, {red, green, blue}}, ...]`. The
[inspection lesson](../examples/inspection.livemd) uses this to distinguish
added and removed material. Layers are opaque; orbit or clip to see hidden areas.
These colors are presentation choices, not assembly material assignments.

## Assemblies and files

A direct assembly preview shows installed manufactured parts. Fetch a reference
with `Smith.Assembly.fetch/2` to include it in a colored scene. For display offsets
or an exploded arrangement, pass `Smith.Assembly.view(result, :display)` or
`:exploded` into the renderer. Export the original assembly to retain its part
names and print placements.

```elixir
{:ok, files} = Smith.export(result, "output", name: "plate", on_bed: true)
files.three_mf
```

<div class="smith-doc-preview" data-preview="livebook-5-result" data-model="result" data-label="Exported plate">
<p>Interactive preview available in HexDocs.</p>
</div>

Files are written on the runtime's machine. PNG and SVG show views; STL and 3MF
contain printable geometry. See [exporting](exporting.md) for verification and
print orientation.

## Choose a lesson

The [SVG artwork notebook](../examples/svg.livemd) imports a local SVG, previews its
CAD regions, and builds a personalized volleyball keychain with raised or
engraved detail.

The notebooks are included in the Hex package's `examples/` directory and shown
in HexDocs. Open their `.livemd` source in Livebook to edit and run the cells.
Within each group, the order below moves from simpler concepts to larger models.

| Level | Notebook | Topics |
| --- | --- | --- |
| Start | [A plate](../examples/plate.livemd) | Build, round, drill, measure, export |
| Start | [Sketches and solid forms](../examples/profiles.livemd) | Extrude a ring, revolve a sleeve, join sections |
| Start | [Mechanical parts](../examples/mechanical-parts.livemd) | Slots, fastener recesses, selectors, mirrored parts |
| Inspect | [Inspection](../examples/inspection.livemd) | Measure, detect a failed requirement, compare stages |
| Inspect | [Drawings](../examples/drawings.livemd) | Views, hidden features, measured SVG dimensions |
| Personalize | [Text and fonts](../examples/text.livemd) | Font snapshots, measured lettering, fitted keychains |
| Shape | [Extrusion](../examples/extrusion.livemd) | Symmetric depth, tapered walls, tilted end planes |
| Shape | [Paths, lofts, and shells](../examples/paths-and-shells.livemd) | A tray, a swept bend, a smooth transition |
| Shape | [Forming and cutting](../examples/forming.livemd) | Draft, split, section, surface offset, thickening |
| Shape | [Projection](../examples/projection.livemd) | Transfer outlines onto flat and curved surfaces |
| Assemble | [Named parts](../examples/assembly.livemd) | Reusable feet, references, placements, print packs |
| Assemble | [Nested assemblies](../examples/nested-assemblies.livemd) | Repeated modules and member paths |
| Assemble | [Joints](../examples/joints.livemd) | A pivoting arm and checks across poses |
| Project | [Raspberry Pi enclosure](../examples/raspberry-pi-enclosure.livemd) | Integrate parts, fits, motion, and printable exports |
| Advanced study | [Phone fit dummy](../examples/iphone-17-pro.livemd) | Interpret a drawing, bound curves, expose model limitations |

The enclosure is the complete design walkthrough. The phone is an advanced
study with an unresolved edge-roll defect and incompletely specified camera
surfaces; it is not yet an accurate case-fit reference. Both distinguish model
checks from physical print testing.

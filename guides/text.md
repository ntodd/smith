# Text and fonts

Smith 0.3 can turn a name and an explicit TTF/OTF font into filled outlines,
measure the layout, and extrude it for raised or engraved lettering. Native
installation also needs FreeType, HarfBuzz and pkg-config; see the
[OCEx installation guide](https://hexdocs.pm/ocex/installation.html).

## Load a font and inspect the name

Load the font once. The returned snapshot contains its bytes and SHA-256, so
later edits to the file cannot change a recipe. The bundled Graduate font is a
varsity-style example with its SIL Open Font License in `priv/fonts`. Use your
own licensed font by changing the path.

```elixir
alias Smith.{Font, Text, Plane, Sketch}
font_path = Path.join(:code.priv_dir(:smith), "fonts/Graduate-Regular.ttf")
{:ok, font} = Font.load(font_path)
name = Text.new("ALEXANDRA", font: font, size: 10, align: {:center, :center})
{:ok, fitted} = Text.fit(name, {43, 14}, margin: 1, min_size: 5)
{:ok, layout} = Text.validate(fitted,
  within: {{-21.5, -7}, {21.5, 7}}, margin: 1, min_height: 4)
:passed = layout.report.status
IO.inspect(Map.take(layout.report, [:width, :height, :area, :font, :revision]))
{:ok, observations} = Text.write(layout, "output/text-inspection")
IO.puts(observations.report)
```

<div class="smith-doc-preview" data-preview="text-name" data-model="fitted" data-label="Measured varsity lettering">
<p>Interactive lettering preview available in HexDocs.</p>
</div>

`Text.write/3` produces measured JSON, a PNG of the actual faces, and an SVG of
outline geometry that does not require the font on the viewing computer. The
artifacts share the measured geometry revision. The report includes glyph IDs,
UTF-8 byte clusters, positions and bounds, baseline, typography metrics, font
hash, local ink bounds and world bounds. A generated validation report can have
`:failed` status: check it explicitly before using the result.

`size` means em size, not visible capital height. `width` and `height` measure
actual ink, including accents and descenders. Typographic `advance` includes
spaces and may be larger than the ink. Fit uses ink and scales both size and
tracking uniformly; it does not stretch, clip or omit characters. Placement
validation checks the ink against the allowed rectangle and margins. Visible
height is a design check, not a guarantee about stroke thickness or printer
resolution. Inspect small lettering at the intended print size.

## A named keychain

The pill is an ordinary slot extrusion. The left end contains a small key-ring
hole; this example reserves that end for a ball motif you can build from curved
groove cutters. Letters overlap the top by 0.2 mm before fusing so they become
part of one solid. The dimensions below are example design choices in mm.

```elixir
build_tag = fn name ->
  text = Smith.text(name, font: font, size: 10,
    align: {:center, :center}, at: {8, 0}, on: Plane.xy(z: 2.8))
  {:ok, text} = Text.fit(text, {43, 14}, margin: 1, min_size: 5)
  {:ok, label} = Text.validate(text,
    within: {{-13.5, -7}, {29.5, 7}}, margin: 1, min_height: 4)
  :passed = label.report.status
  letters = label.result |> Smith.from_result() |> Smith.extrude({0, 0, 1})
  body = Sketch.slot(70, 22)
    |> Sketch.cut(Sketch.circle(2, at: {-29, 0}))
    |> Smith.extrude(3)
    |> Smith.fuse(letters)
  {:ok, result} = Smith.evaluate(body)
  {:ok, inspection} = Smith.Inspection.run(%{tag: result},
    checks: [{:topology, :tag, :solids, expected: 1}])
  :passed = inspection.status
  {result, label}
end
{tag, label} = build_tag.("ALEXANDRA")
{:ok, files} = Smith.export(tag, "output/keychains", name: "sample-name", on_bed: true)
IO.puts(files.three_mf)
```

<div class="smith-doc-preview" data-preview="text-keychain" data-model="tag" data-label="Raised varsity name keychain">
<p>Interactive keychain preview available in HexDocs.</p>
</div>

For engraving, position the text inside the top surface and cut its extrusion
from the body with `Smith.cut/2`. Preserve enough base thickness. For a roster,
call `build_tag` for each name and export using unique, filesystem-safe identifiers
such as `"player-01"`; names themselves need not become filenames. Keep real team
rosters and custom font assets in a private consumer project outside Smith/OCEx.

## Placement and limits

Text defaults to XY with its ink left edge and baseline anchored at `{0, 0}`.
Use `align: {:center, :center}` to center the visible lettering. X also accepts
`:min`, `:max` and `:origin`; Y also accepts `:min`, `:max` and `:baseline`.
`on:` accepts any `Smith.Plane`; scalar extrusion follows that plane's normal.
`Text.layout/1` returns an evaluated result you can reuse through
`Smith.from_result/1`, measure, render, draw or inspect without rebuilding.

HarfBuzz supplies kerning, ligatures and script shaping. `tracking:` is extra mm
between shaped clusters; nonzero tracking disables optional ligatures. Use
`direction:` and `language:` when needed. Text is one horizontal script/direction
run, with no automatic mixed-direction paragraphs or wrapping. Unsupported
characters fail as `:missing_glyph`; fonts are never silently replaced. Empty or
whitespace-only labels fail. Variable-font axes, bitmap/color glyphs, and text
wrapped around curved surfaces are not exposed in 0.3.

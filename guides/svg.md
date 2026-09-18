# SVG artwork

Import SVG line art or filled outlines as measurable planar CAD geometry. Fit it
in millimeters, place it on any plane, then extrude and fuse or cut it like text.
The [interactive notebook](svg-notebook.html) includes a local file upload,
selection, sizing, stroke width, raised/engraved controls, and printable exports.

## Snapshot and inspect

```elixir
alias Smith.{SVG, Plane, Sketch, Font, Text}
{:ok, artwork} = SVG.load(Path.join(:code.priv_dir(:smith), "svg/volleyball.svg"))
IO.inspect(SVG.elements(artwork), label: "Selectable SVG elements")
motif = SVG.new(artwork, width: 18, align: {:center, :center})
{:ok, layout} = SVG.layout(motif)
IO.inspect(Map.take(layout.report, [:width, :height, :area, :regions, :source_sha256]))
{:ok, previews} = SVG.write(layout, "output/svg-inspection")
```

<div class="smith-doc-preview" data-preview="svg-volleyball" data-model="motif" data-label="Imported volleyball geometry">
<p>Interactive preview of the converted SVG regions.</p>
</div>

`SVG.from_binary/1` accepts uploaded bytes. Loading parses the document and saves
its SHA-256; it does not build native geometry. Editing the source file cannot
change an existing asset. `SVG.new/2` records a deferred recipe; `Smith.svg/2` is
a shorthand. Evaluation and reports use the same geometry snapshot.

## Fills, strokes and selection

| Mode | Result |
| --- | --- |
| `:painted` (default) | Union of selected filled areas and expanded strokes |
| `:fill` | Filled contours, with holes and disconnected islands |
| `:strokes` | Visible stroke areas, including open centerlines, caps and joins |

Source colors are metadata. A white background is material in painted mode; it
is not automatically subtracted. Select the intended group or use stroke mode
for line art. Overlapping paint colors are not browser-style compositing.

```elixir
seams = SVG.new(artwork, select: "seams", mode: :strokes,
  width: 18, stroke_width: 0.6, align: {:center, :center})
{:ok, seam_layout} = SVG.layout(seams)
```

Selection accepts IDs, group IDs/labels, lists, stable element indices, and
`{:fill, "black"}` or `{:stroke, "black"}`. Paint selection uses the resolved
source string, not a color-distance calculation. An unmatched selection fails.
`reference: :document` keeps selected pieces registered to the same document
bounds and size. Use `reference: :selection` to size/align only selected artwork.

Source stroke widths follow SVG affine transforms and uniform CAD scaling.
`stroke_width:` overrides them in final millimeters, after all transforms.
This is useful for adjusting groove width independently of motif size. An
unreachable size, such as fitting a fixed 2 mm round stroke into 1 mm, fails
with `:size_unreachable` rather than distorting the geometry.

## Size and placement

`width:` sets artwork width; `height:` sets height. Specifying both contains the
artwork within the box without stretching. `SVG.fit/3` also accepts a margin.
Artwork bounds exclude blank document margins; `bounds: :viewport` explicitly
uses the document viewport instead. Measurements use native kernel tolerances.

Without an explicit size, physical units follow the document (96 px per inch).
A viewBox-only SVG uses its viewBox dimensions as the viewport in CSS pixels.
The importer resolves viewBox and transforms, then flips SVG Y into CAD Y.
Default alignment preserves the document origin. Use `:min`, `:center`, `:max`,
or `:origin` for each axis, `at: {x,y}` for the anchor and `on:` for the plane.
Scalar extrusion follows the plane's normal.

## Engraved and raised volleyball tags

```elixir
base = Sketch.slot(80, 24)
  |> Sketch.cut(Sketch.circle(2, at: {-34, 0}))
  |> Smith.extrude(3)
{:ok, font} = Font.load(Path.join(:code.priv_dir(:smith), "fonts/Graduate-Regular.ttf"))
text = Text.new("ALEX", font: font, size: 10, align: {:center, :center},
  at: {10, 0}, on: Plane.xy(z: 2.8))
{:ok, text} = Text.fit(text, {38, 15}, margin: 1, min_size: 5)
base = Smith.fuse(base, Smith.extrude(text, 1))
engraving = SVG.new(artwork, width: 18, align: {:center, :center},
  at: {-20, 0}, on: Plane.xy(z: 3))
raised = SVG.new(artwork, width: 18, align: {:center, :center},
  at: {-20, 0}, on: Plane.xy(z: 2.8))
engraved_tag = Smith.cut(base, Smith.extrude(engraving, -0.6))
raised_tag = Smith.fuse(base, Smith.extrude(raised, 0.8))
{:ok, engraved_result} = Smith.evaluate(engraved_tag)
{:ok, raised_result} = Smith.evaluate(raised_tag)
{:ok, files} = Smith.export(engraved_result, "output/svg-keychains", name: "engraved", on_bed: true)
```

<div class="smith-doc-preview" data-preview="svg-keychain" data-model="engraved_result" data-label="SVG volleyball and personalized name">
<p>Interactive preview of the engraved volleyball keychain.</p>
</div>

Both versions should remain one printable solid. Raised artwork overlaps the
base by 0.2 mm. The engraving leaves 2.4 mm of base beneath it. Region count,
width and height are not printer-resolution or minimum-wall guarantees.

The bundled MIT-licensed original is stroked. `volleyball-outlined.svg` contains
filled outlines of the same motif, generated with 0.001 mm sampling. Tests
compare their symmetric difference against boundary length times that tolerance.
User artwork and team assets belong in private consumer projects.

## Reuse centerlines

`SVG.paths/1` returns positioned wire models with element IDs and closed/open
metadata. Open paths also expose a `Smith.Path` for the existing sweep API;
closed loops expose `path: nil` because Smith sweeps require open paths.

```elixir
{:ok, line_asset} = SVG.from_binary("<svg viewBox='0 0 20 20'><path fill='none' stroke='black' d='M0 0H20'/></svg>")
{:ok, [%{path: spine}]} = SVG.paths(SVG.new(line_asset, width: 20))
swept = Smith.Sketch.circle(0.3, on: Plane.yz()) |> Smith.sweep(spine)
{:ok, swept_result} = Smith.evaluate(swept)
```

## Supported content and failures

Paths support absolute/relative M/L/H/V/C/S/Q/T/A/Z, implicit repetition,
compact arc flags, and SVG's implicit closure for fills. Quadratic/cubic curves
and elliptical arcs remain native curves. Native stroke expansion samples curved
centerlines using `tolerance: 0.01` in final mm; straight edges and round caps are
analytic. `SVG.outline_svg/2` exports sampled filled boundaries for reuse.

Basic shapes, rounded rectangles, nested group transforms, local `<use>`
references, inline styles and inherited presentation attributes are supported.
The nonzero and even-odd fill rules preserve nested holes, intersections, and
separate regions. Hidden content and editor metadata are excluded.

Stylesheets, text, raster images, external references, gradients/patterns,
clipping/masks, filters, dashes, markers, alpha color syntax, non-scaling strokes and partial opacity
return errors identifying the affected element. Convert text to paths or use
`Smith.Text`; use a vector editor to expand unsupported effects. Nested SVG
viewports and preserveAspectRatio slice/clipping are currently unsupported.
No unsupported visible geometry is silently omitted.

XML has a 4 MiB limit, bounded nesting, node and expansion counts. DTDs/entities
and processing instructions (except the initial XML declaration) are rejected.
No network or script execution occurs. Native complexity limits return tagged
errors. Like other OCEx operations, geometry runs synchronously on serialized
dirty schedulers; it cannot be forcibly cancelled inside the VM.

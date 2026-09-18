# Run with mix run; all source assets are original, public Smith examples.
alias Smith.{SVG, Text, Font, Plane, Sketch}
{:ok, asset} = SVG.load(Path.join(:code.priv_dir(:smith), "svg/volleyball.svg"))
{:ok, font} = Font.load(Path.join(:code.priv_dir(:smith), "fonts/Graduate-Regular.ttf"))
root = Path.expand("../output/models", __DIR__)
for {mode, offset} <- [{:engraved, {185, 60, 0}}, {:raised, {185, 92, 0}}] do
  z = if mode == :engraved, do: 3, else: 2.8
  motif = SVG.new(asset, width: 18, align: {:center, :center}, at: {-20, 0}, on: Plane.xy(z: z))
  {:ok, layout} = SVG.layout(motif)
  {:ok, previews} = SVG.write(layout, Path.join(root, "svg-artwork"))
  text = Text.new("ALEX", font: font, size: 10, align: {:center, :center}, at: {10, 0}, on: Plane.xy(z: 2.8))
  {:ok, text} = Text.fit(text, {38, 15}, margin: 1, min_size: 5)
  base = Sketch.slot(80, 24) |> Sketch.cut(Sketch.circle(2, at: {-34, 0})) |> Smith.extrude(3)
  base = Smith.fuse(base, Smith.extrude(text, 1))
  # Reuse the inspected snapshot; do not rebuild a different motif for export.
  art = layout.result |> Smith.from_result() |> Smith.extrude({0, 0, if(mode == :engraved, do: -0.6, else: 0.8)})
  tag = if mode == :engraved, do: Smith.cut(base, art), else: Smith.fuse(base, art)
  {:ok, result} = Smith.evaluate(tag)
  {:ok, inspection} = Smith.Inspection.run(%{tag: result}, checks: [{:topology, :tag, :solids, expected: 1}])
  :passed = inspection.status
  {:ok, export} = Smith.export(result, root, name: "svg-volleyball-#{mode}", on_bed: true,
    display_offset: offset, metadata: %{svg_source: asset.sha256, artwork_revision: layout.result.revision, artwork_report: previews.report})
  IO.inspect(%{mode: mode, revision: result.revision, export_id: export.export_id, print_file: export.three_mf})
end

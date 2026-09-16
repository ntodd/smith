defmodule Smith.TextTest do
  use ExUnit.Case, async: true
  alias Smith.{Font, Text, Plane}

  @path Path.expand("../priv/fonts/Graduate-Regular.ttf", __DIR__)

  test "font snapshots survive source deletion and preserve provenance" do
    path = Path.join(System.tmp_dir!(), "smith-font-#{System.unique_integer([:positive])}.ttf")
    File.cp!(@path, path)
    assert {:ok, font} = Font.load(path)
    File.rm!(path)
    assert {:ok, layout} = Text.new("TEAM", font: font, size: 10) |> Text.layout()
    assert layout.report.font.sha256 == font.sha256
    assert layout.report.revision == layout.result.revision
    assert {:ok, true} = OCEx.valid?(layout.result.shape)
    assert {:error, :enoent} = Font.load(path)
    assert {:error, :invalid_font} = Font.from_binary("not a font")
  end

  test "alignment uses ink bounds, and measurements track placement in an arbitrary plane" do
    {:ok, font} = Font.load(@path)

    text =
      Text.new("AVA",
        font: font,
        size: 10,
        align: {:center, :center},
        at: {5, 8},
        on: Plane.yz(x: 3)
      )

    assert {:ok, layout} = Text.layout(text)
    {{x0, y0}, {x1, y1}} = layout.report.ink_bounds
    assert_in_delta (x0 + x1) / 2, 5, 1.0e-6
    assert_in_delta (y0 + y1) / 2, 8, 1.0e-6
    assert {:ok, {{a, b, c}, {d, e, f}}} = OCEx.bounds(layout.result.shape)
    assert_in_delta a, 3, 1.0e-6
    assert_in_delta d, 3, 1.0e-6
    assert_in_delta b, x0, 1.0e-6
    assert_in_delta e, x1, 1.0e-6
    assert_in_delta c, y0, 1.0e-6
    assert_in_delta f, y1, 1.0e-6
    assert {:ok, body} = text |> Smith.extrude(2) |> Smith.evaluate()
    assert {:ok, volume} = OCEx.volume(body.shape)
    assert_in_delta volume, layout.report.area * 2, 1.0e-5
  end

  test "fit preserves proportions, validates actual placement, and rejects unreadable sizing" do
    {:ok, font} = Font.load(@path)
    text = Text.new("ALEXANDRA", font: font, size: 12, align: {:center, :center})
    assert {:ok, fitted} = Text.fit(text, {35, 10}, margin: 1)

    assert {:ok, layout} =
             Text.validate(fitted, within: {{-17.5, -5}, {17.5, 5}}, margin: 1, min_height: 3)

    assert layout.report.status == :passed
    assert layout.report.width <= 33 + 1.0e-6
    assert layout.report.height <= 8 + 1.0e-6
    assert {:ok, failed} = Text.validate(text, within: {{-10, -5}, {10, 5}})
    assert failed.report.status == :failed
    assert {:error, :text_too_small} = Text.fit(text, {5, 2}, min_size: 5)
    assert {:error, :invalid_options} = Text.fit(text, {5, 2}, margin: 2)
  end

  test "raised names fuse into one printable solid and text renders as actual geometry" do
    {:ok, font} = Font.load(@path)
    text = Text.new("BO", font: font, size: 8, align: {:center, :center}, on: Plane.xy(z: 1.8))
    letters = Smith.extrude(text, 1)
    tag = Smith.Sketch.slot(35, 15) |> Smith.extrude(2) |> Smith.fuse(letters)
    assert {:ok, model} = Smith.evaluate(tag)

    assert {:ok, report} =
             Smith.Inspection.run(%{tag: model},
               checks: [{:topology, :tag, :solids, expected: 1}]
             )

    assert report.status == :passed

    assert {:ok, <<137, 80, 78, 71, _::binary>>} =
             Smith.Render.png(model, view: :top, width: 320, height: 160)

    assert {:ok, drawing} = Smith.Drawing.new(text, on: :xy)
    assert {:ok, svg} = Smith.Drawing.svg(drawing)
    assert String.contains?(svg, "<svg")
  end

  test "invalid text construction stays deferred and reports the failed operation" do
    text = Text.new("A", font: :missing, size: 10)
    assert {:error, %Smith.Error{operation: :text, reason: :invalid_font}} = Smith.evaluate(text)
    assert {:error, :invalid_options} = Text.layout(Text.new("A", unexpected: true))
  end

  test "agent artifacts share the measured geometry revision and reject stale snapshots" do
    {:ok, font} = Font.load(@path)
    {:ok, layout} = Text.new("TEAM", font: font, size: 10) |> Text.layout()
    root = Path.join(System.tmp_dir!(), "smith-text-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    assert {:ok, files} = Text.write(layout, root, width: 320, height: 160)
    data = files.report |> File.read!() |> JSON.decode!()
    assert data["revision"] == layout.result.revision
    assert data["font"]["sha256"] == font.sha256
    assert File.read!(files.png) =~ layout.result.revision
    assert File.read!(files.svg) =~ "<svg"
    refute File.read!(files.svg) =~ "<text "
    stale = %{layout | result: %{layout.result | revision: "stale"}}
    assert {:error, :revision_mismatch} = Text.write(stale, root)
    stale_report = %{layout | report: %{layout.report | revision: "stale"}}
    assert {:error, :revision_mismatch} = Text.write(stale_report, root)
    assert {:error, :invalid_argument} = Text.write(%{result: nil, report: %{}}, root)
  end

  test "engraving removes the measured area times cut depth while preserving the base" do
    {:ok, font} = Font.load(@path)
    text = Text.new("BO", font: font, size: 8, align: {:center, :center}, on: Plane.xy(z: 2.2))
    {:ok, layout} = Text.layout(text)
    blank = Smith.Sketch.slot(35, 15) |> Smith.extrude(3)
    {:ok, before} = Smith.evaluate(blank)
    {:ok, engraved} = blank |> Smith.cut(Smith.extrude(text, 1)) |> Smith.evaluate()
    {:ok, before_volume} = OCEx.volume(before.shape)
    {:ok, after_volume} = OCEx.volume(engraved.shape)
    assert_in_delta before_volume - after_volume, layout.report.area * 0.8, 1.0e-5
    assert {:ok, [_]} = OCEx.solids(engraved.shape)
    assert {:ok, true} = OCEx.valid?(engraved.shape)
  end
end

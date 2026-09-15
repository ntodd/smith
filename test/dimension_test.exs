defmodule Smith.Drawing.DimensionTest do
  use ExUnit.Case, async: true
  alias Smith.{Drawing, Measure, Plane}

  test "dimensions retain measured values and SVG includes their extensions and labels" do
    {:ok, result} = Smith.box(20, 10, 4) |> Smith.evaluate()
    {:ok, width} = Measure.extent(result, :x)
    {:ok, height} = Measure.extent(result, :y)
    {:ok, drawing} = Drawing.new(result, on: :xy)

    assert {:ok, drawing} =
             Drawing.dimension(drawing, width, orientation: :horizontal, offset: -6)

    assert {:ok, drawing} = Drawing.dimension(drawing, height, orientation: :vertical, offset: 26)
    assert {:ok, svg} = Drawing.svg(drawing)
    assert svg =~ "20.00 mm" and svg =~ "10.00 mm"
    assert length(drawing.dimensions) == 2
    assert svg =~ "dimension"
    assert {:error, :unsupported_annotations} = Drawing.dxf(drawing)
  end

  test "oblique or stale measurements cannot receive misleading labels" do
    {:ok, result} = Smith.box(20, 10, 4) |> Smith.evaluate()
    {:ok, width} = Measure.extent(result, :x)
    {:ok, drawing} = Drawing.new(result, on: Plane.yz())
    assert {:error, :dimension_out_of_plane} = Drawing.dimension(drawing, width)

    assert {:error, :revision_mismatch} =
             Drawing.dimension(drawing, %{width | source_revision: "stale"})
  end

  test "circular dimensions include center marks and reject edge-on projection" do
    {:ok, result} = Smith.cylinder(3, 4) |> Smith.evaluate()
    selector = fn edge -> edge.type == :circle and abs(elem(edge.start, 2) - 4) < 1.0e-7 end
    {:ok, diameter} = Measure.diameter(result, selector)
    {:ok, top} = Drawing.new(result, on: :xy)
    assert {:ok, top} = Drawing.dimension(top, diameter, offset: 5)
    {:ok, svg} = Drawing.svg(top)
    assert svg =~ "⌀6.00 mm" and svg =~ "center-mark"
    {:ok, side} = Drawing.new(result, on: :xz)
    assert {:error, :dimension_out_of_plane} = Drawing.dimension(side, diameter)
  end

  test "angular annotations preserve a measured right angle" do
    {:ok, result} = Smith.polygon([{0, 0, 0}, {3, 0, 0}, {3, 4, 0}]) |> Smith.evaluate()

    {:ok, angle} =
      Measure.angle(result, fn e -> abs(e.length - 3) < 1.0e-7 end, fn e ->
        abs(e.length - 4) < 1.0e-7
      end)

    {:ok, drawing} = Drawing.new(result, on: :xy)
    assert {:ok, drawing} = Drawing.dimension(drawing, angle, offset: 6)
    {:ok, svg} = Drawing.svg(drawing)
    assert svg =~ "90.00°"
  end
end

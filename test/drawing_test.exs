defmodule Smith.DrawingTest do
  use ExUnit.Case, async: true
  alias Smith.{Assembly, Drawing, Plane, Sketch}

  test "drawings evaluate recipes and retain the source revision and view plane" do
    model = Smith.box(10, 6, 4)
    assert {:ok, result} = Smith.evaluate(model)
    assert {:ok, drawing} = Drawing.new(result, on: Plane.xy(origin: {2, 3, 9}))
    assert drawing.source_revision == result.revision
    assert {:ok, lines} = Drawing.polylines(drawing)
    points = List.flatten(lines.visible)
    assert Enum.min(Enum.map(points, &elem(&1, 0))) == -2
    assert Enum.max(Enum.map(points, &elem(&1, 1))) == 3
    assert {:ok, _} = Drawing.new(model, on: :yz)
    assert {:ok, _} = Drawing.new(Sketch.circle(3))
    assert {:ok, _} = Drawing.new(Smith.Path.new([Smith.line({0, 0, 0}, {5, 0, 0})]))
  end

  test "assembly drawings use installed parts; an explicit view includes printable extras" do
    assembly =
      Assembly.new(:fixture)
      |> Assembly.part(:base, Smith.box(10, 5, 2))
      |> Assembly.part(:coupon, Smith.box(3, 3, 1), installed: false, position: {20, 0, 0})
      |> Assembly.reference(:device, Smith.box(100, 100, 100))

    assert {:ok, result} = Smith.evaluate(assembly)
    assert {:ok, drawing} = Drawing.new(result)
    assert {:ok, {{_, _, _}, {high, _, _}}} = OCEx.bounds(drawing.visible)
    assert_in_delta high, 10, 1.0e-6
    assert {:ok, display} = Assembly.view(result, :display)
    assert {:ok, drawing} = Drawing.new(display)
    assert {:ok, {{_, _, _}, {high, _, _}}} = OCEx.bounds(drawing.visible)
    assert_in_delta high, 23, 1.0e-6
    assert {:ok, _} = Drawing.new(assembly)
  end

  test "SVG uses millimeters, flips only screen Y, and escapes text" do
    assert {:ok, drawing} = Drawing.new(Sketch.rectangle(10, 6, align: {:min, :min}))
    assert {:ok, svg} = Drawing.svg(drawing, padding: 2, title: "A&B <top>")
    assert svg =~ ~s|xmlns="http://www.w3.org/2000/svg"|
    assert svg =~ ~s|width="14.25mm"|
    assert svg =~ ~s|height="10.25mm"|
    assert svg =~ ~s|transform="scale(1,-1)"|
    assert svg =~ ~s|viewBox="-2.125 -8.125 14.25 10.25"|
    assert svg =~ "A&amp;B &lt;top&gt;"
    assert svg =~ ~s|fill="none"|
    assert {:ok, ^svg} = Drawing.svg(drawing, padding: 2, title: "A&B <top>")
  end

  test "SVG and DXF distinguish hidden curves and can omit them" do
    cover = Sketch.rectangle(10, 10, on: Plane.xy(z: 5))
    model = Smith.compound([Smith.box(10, 10, 1, at: {-5, -5, 5}), Smith.sphere(2)])
    assert {:ok, drawing} = Drawing.new(model)
    assert {:ok, lines} = Drawing.polylines(drawing)
    assert lines.hidden != []
    assert {:ok, svg} = Drawing.svg(drawing)
    assert svg =~ ~s|id="hidden"|
    assert svg =~ ~s|stroke-dasharray="2 1"|
    assert {:ok, visible} = Drawing.svg(drawing, hidden: false)
    refute visible =~ ~s|id="hidden"|
    assert {:ok, dxf} = Drawing.dxf(drawing)
    assert dxf =~ "9\n$ACADVER\n1\nAC1015\n"
    assert dxf =~ "9\n$INSUNITS\n70\n4\n"
    assert dxf =~ "0\nLWPOLYLINE\n100\nAcDbEntity\n8\nHIDDEN\n"
    assert {:ok, visible} = Drawing.dxf(drawing, hidden: false)
    refute visible =~ "0\nLWPOLYLINE\n100\nAcDbEntity\n8\nHIDDEN\n"
    assert {:ok, _} = Drawing.new(cover)
  end

  test "curve sampling density can increase without changing exact drawing curves" do
    assert {:ok, drawing} = Drawing.new(Smith.sphere(10))
    assert {:ok, before} = OCEx.to_brep(drawing.visible)
    assert {:ok, coarse} = Drawing.polylines(drawing, tolerance: 0.1, angular_tolerance: 1)
    assert {:ok, fine} = Drawing.polylines(drawing, tolerance: 0.001, angular_tolerance: 1)
    assert length(List.flatten(fine.visible)) > length(List.flatten(coarse.visible))
    assert {:ok, ^before} = OCEx.to_brep(drawing.visible)
  end

  @tag :tmp_dir
  test "file writing infers the format and preserves files when options fail", %{tmp_dir: dir} do
    assert {:ok, drawing} = Drawing.new(Smith.box(10, 6, 4))

    for extension <- ["svg", "dxf"] do
      path = Path.join(dir, "drawing." <> extension)
      assert {:ok, ^path} = Drawing.write(drawing, path)
      original = File.read!(path)
      assert {:error, :invalid_options} = Drawing.write(drawing, path, tolerance: -1)
      assert File.read!(path) == original
    end

    assert {:error, :unsupported_format} = Drawing.write(drawing, Path.join(dir, "drawing.stl"))
    assert {:error, :enoent} = Drawing.write(drawing, Path.join([dir, "missing", "drawing.svg"]))
  end

  test "invalid options, stale inputs and failed recipes return tagged errors" do
    assert {:error, %Smith.Error{operation: :box}} = Drawing.new(Smith.box(0, 2, 3))
    assert {:error, :invalid_recipe} = Drawing.new(nil)
    assert {:ok, result} = Smith.evaluate(Smith.box(1, 2, 3))
    assert {:error, :revision_mismatch} = Drawing.new(%{result | revision: "stale"})

    for opts <- [[on: :bad], [on: :xy, on: :yz], [tangents: 1], nil] do
      assert {:error, :invalid_options} = Drawing.new(result, opts)
    end

    assert {:error, :invalid_plane} = Drawing.new(result, on: Plane.new(normal: {0, 0, 0}))
    assert {:ok, drawing} = Drawing.new(result)

    for opts <- [
          [tolerance: 0],
          [hidden: :yes],
          [padding: -1],
          [unknown: 1],
          [title: <<0>>],
          [hidden: true, hidden: false],
          nil
        ] do
      assert {:error, :invalid_options} = Drawing.svg(drawing, opts)
    end

    assert {:error, :invalid_options} = Drawing.dxf(drawing, padding: 1)
    assert {:error, :invalid_argument} = Drawing.svg(nil)
  end

  test "empty drawings serialize DXF but SVG requires visible extent" do
    assert {:ok, drawing} = Drawing.new(Smith.compound([]))
    assert {:ok, %{visible: [], hidden: []}} = Drawing.polylines(drawing)
    assert {:error, :empty_drawing} = Drawing.svg(drawing)
    assert {:ok, dxf} = Drawing.dxf(drawing)
    refute dxf =~ "0\nLWPOLYLINE\n"
    assert String.ends_with?(dxf, "0\nEOF\n")
  end

  test "DXF closes circular polylines and preserves sampled coordinates" do
    assert {:ok, drawing} = Drawing.new(Smith.sphere(5))

    for tolerance <- [0.001, 100] do
      opts = [tolerance: tolerance, angular_tolerance: 100]
      assert {:ok, %{visible: [points], hidden: []}} = Drawing.polylines(drawing, opts)
      assert {:ok, dxf} = Drawing.dxf(drawing, opts)
      [_header, entity] = String.split(dxf, "0\nLWPOLYLINE\n")
      pairs = entity |> String.split("\n", trim: true) |> Enum.chunk_every(2)
      assert ["70", "1"] in pairs
      ["90", count] = Enum.find(pairs, &(hd(&1) == "90"))
      assert String.to_integer(count) == length(points) - 1
      xs = for ["10", x] <- pairs, do: String.to_float(x)
      ys = for ["20", y] <- pairs, do: String.to_float(y)
      assert Enum.zip(xs, ys) == Enum.drop(points, -1)
      assert length(xs) >= 3
      for {x, y} <- Enum.zip(xs, ys), do: assert_in_delta(x * x + y * y, 25, 1.0e-6)
    end
  end
end

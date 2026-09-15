defmodule Smith.MeasureTest do
  use ExUnit.Case, async: true
  alias Smith.{Measure, Selector}

  test "dimensions come from evaluated geometry and retain their revision" do
    {:ok, body} = Smith.box(20, 10, 4) |> Smith.evaluate()
    assert {:ok, width} = Measure.extent(body, :x)
    assert_in_delta width.value, 20, 1.0e-7
    assert width.unit == :mm
    assert width.source_revision == body.revision

    assert {:ok, moved} =
             body |> Smith.from_result() |> Smith.translate({100, 20, -5}) |> Smith.evaluate()

    assert {:ok, same_width} = Measure.extent(moved, :x)
    assert_in_delta same_width.value, width.value, 1.0e-7
    refute same_width.source_revision == width.source_revision
    assert {:error, :revision_mismatch} = Measure.extent(%{body | revision: "bad"}, :x)
  end

  test "circular measurements and center spacing use selected native edges" do
    recipe =
      Smith.box(30, 20, 5)
      |> Smith.cut([
        Smith.cylinder(2, 7, at: {6, 10, -1}),
        Smith.cylinder(3, 7, at: {22, 10, -1})
      ])

    {:ok, body} = Smith.evaluate(recipe)

    left = fn e ->
      e.type == :circle and abs(e.radius - 2) < 1.0e-7 and abs(elem(e.start, 2) - 5) < 1.0e-7
    end

    right = fn e ->
      e.type == :circle and abs(e.radius - 3) < 1.0e-7 and abs(elem(e.start, 2) - 5) < 1.0e-7
    end

    assert {:ok, diameter} = Measure.diameter(body, left)
    assert_in_delta diameter.value, 4, 1.0e-7

    assert {:ok, spacing} =
             Measure.distance(body, {:circle_center, left}, {:circle_center, right}, axis: :x)

    assert_in_delta spacing.value, 16, 1.0e-7
    assert {:error, :ambiguous_selection} = Measure.radius(body, Selector.type(:circle))
    assert {:error, :empty_selection} = Measure.radius(body, fn _ -> false end)
    assert {:error, :invalid_options} = Measure.distance(body, :bad, :bad, axis: :banana)
  end

  test "aligned distance and angles use geometry rather than supplied labels" do
    {:ok, triangle} = Smith.polygon([{0, 0, 0}, {3, 0, 0}, {3, 4, 0}]) |> Smith.evaluate()
    line = fn e -> e.type == :line and abs(e.length - 5) < 1.0e-7 end
    assert {:ok, d} = Measure.distance(triangle, {:edge_start, line}, {:edge_end, line})
    assert_in_delta d.value, 5, 1.0e-7
    horizontal = fn e -> abs(e.length - 3) < 1.0e-7 end
    vertical = fn e -> abs(e.length - 4) < 1.0e-7 end
    assert {:ok, a} = Measure.angle(triangle, horizontal, vertical)
    assert_in_delta a.value, 90, 1.0e-7
  end
end

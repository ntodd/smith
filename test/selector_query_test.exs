defmodule Smith.SelectorQueryTest do
  use ExUnit.Case, async: true
  alias Smith.Selector, as: S

  defp body(recipe) do
    {:ok, result} = Smith.evaluate(recipe)
    result
  end

  defp measures(shapes, kind, key) do
    Enum.map(shapes, fn shape ->
      {:ok, info} = apply(OCEx, kind, [shape])
      Map.fetch!(info, key)
    end)
  end

  test "length and area filters use inclusive ranges and explicit numeric tolerance" do
    block = body(Smith.box(20, 10, 5))
    assert {:ok, edges} = Smith.edges(block, S.length(10))
    assert length(edges) == 4
    assert measures(edges, :edge_info, :length) == List.duplicate(10.0, 4)
    assert {:ok, edges} = Smith.edges(block, S.length({5, 10}))
    assert length(edges) == 8
    assert {:ok, faces} = Smith.faces(block, S.area(200))
    assert length(faces) == 2
    assert {:ok, faces} = Smith.faces(block, S.area(200.01, tolerance: 0.02))
    assert length(faces) == 2
    assert {:ok, []} = Smith.faces(block, S.area(200.01))
  end

  test "radius excludes candidates without radii; sorting places missing values last" do
    cylinder = body(Smith.cylinder(3, 8))
    assert {:ok, circles} = Smith.edges(cylinder, S.radius(3))
    assert length(circles) == 2
    assert {:ok, [_]} = Smith.faces(cylinder, S.radius({2, 4}))

    for direction <- [:asc, :desc] do
      assert {:ok, faces} = Smith.faces(cylinder, S.sort_by(:radius, direction))
      assert measures(faces, :face_info, :radius) == [3.0, nil, nil]
    end
  end

  test "sorting and take compose in order and preserve all ties until explicitly limited" do
    block = body(Smith.box(20, 10, 5))
    assert {:ok, faces} = Smith.faces(block, S.sort_by(:area, :desc) |> S.take(3))

    for {actual, expected} <- Enum.zip(measures(faces, :face_info, :area), [200.0, 200.0, 100.0]),
        do: assert_in_delta(actual, expected, 1.0e-7)

    assert {:ok, faces} = Smith.faces(block, S.parallel(:z) |> S.sort_by(:z))
    assert Enum.map(measures(faces, :face_info, :center), &elem(&1, 2)) == [0.0, 5.0]
    assert {:ok, []} = Smith.edges(block, S.take(0))
  end

  test "union and exclusion apply within the preceding selection without duplicates" do
    block = body(Smith.box(20, 10, 5))
    ends = S.any_of([S.facing(:z), S.facing({:z, :negative}), S.facing(:z)])
    assert {:ok, faces} = Smith.faces(block, ends)
    assert length(faces) == 2
    assert {:ok, [_]} = Smith.faces(block, S.facing(:z) |> S.any_of([ends, S.new()]))
    assert {:ok, sides} = Smith.faces(block, S.exclude(ends))
    assert length(sides) == 4
    assert {:ok, []} = Smith.faces(block, S.any_of([]))
    assert {:ok, faces} = Smith.faces(block, S.sort_by(:area, :desc) |> S.exclude(S.take(2)))

    for {actual, expected} <-
          Enum.zip(measures(faces, :face_info, :area), [100.0, 100.0, 50.0, 50.0]),
        do: assert_in_delta(actual, expected, 1.0e-7)
  end

  test "invalid property, range, order and nested query fail even on empty selections" do
    block = body(Smith.box(20, 10, 5))

    for selector <- [
          S.area(2),
          S.length({10, 5}),
          S.length(-1),
          S.length(1, tolerance: -1),
          S.length(1, unknown: true),
          S.length(1, tolerance: 1, tolerance: 2),
          S.sort_by(:area),
          S.sort_by(:length, :wrong),
          S.take(-1),
          S.take(1.5),
          S.any_of([S.facing(:z)]),
          S.any_of(nil),
          S.exclude(:bad)
        ] do
      assert {:error, :invalid_options} = Smith.edges(block, selector)

      assert {:error, :invalid_options} =
               Smith.edges(block, S.type(:sphere) |> S.any_of([selector]))
    end
  end

  test "composed selectors remain usable as feature selections after transforms" do
    selector = S.length(5) |> S.exclude(S.parallel(:x))

    assert {:ok, result} =
             Smith.box(20, 10, 5)
             |> Smith.translate({2, 3, 4})
             |> Smith.fillet(edges: selector, radius: 1, count: 4)
             |> Smith.evaluate()

    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, (200 - (4 - :math.pi())) * 5, 1.0e-6
  end

  test "inspection returns selected topology with world metadata in query order" do
    block = body(Smith.box(20, 10, 5) |> Smith.translate({2, 3, 4}))
    assert {:ok, [top]} = Smith.inspect_faces(block, S.facing(:z))
    assert top.center == {12.0, 8.0, 9.0}
    assert {:ok, :face} = OCEx.shape_type(top.shape)
    assert {:ok, edges} = Smith.inspect_edges(block, S.length(5))
    assert length(edges) == 4

    for edge <- edges do
      assert edge.length == 5.0
      assert elem(edge.midpoint, 2) == 6.5
      assert {_, _} = edge.bounds
      assert {:ok, :edge} = OCEx.shape_type(edge.shape)
    end
  end
end

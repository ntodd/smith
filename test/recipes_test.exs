defmodule Smith.RecipesTest do
  use ExUnit.Case, async: true

  test "cones compose and compounds preserve separate placed parts" do
    cone = Smith.cone(4, 2, 6)
    assert {:ok, result} = cone |> Smith.translate({0, 0, 8}) |> Smith.evaluate()
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, :math.pi() * 6 / 3 * (16 + 8 + 4), 1.0e-7

    assert {:ok, assembly} =
             Smith.compound([Smith.box(2, 3, 4), cone |> Smith.translate({10, 0, 0})])
             |> Smith.evaluate()

    assert {:ok, solids} = OCEx.solids(assembly.shape)
    assert length(solids) == 2

    assert {:error, %Smith.Error{operation: :compound, reason: %Smith.Error{operation: :cone}}} =
             Smith.compound([Smith.cone(-1, 2, 3)]) |> Smith.evaluate()
  end

  test "lists of features compose in order and an empty list leaves the recipe alone" do
    base = Smith.box(10, 10, 10)
    extension = Smith.box(10, 10, 10) |> Smith.translate({10, 0, 0})
    cutter = Smith.box(5, 10, 10) |> Smith.translate({15, 0, 0})

    assert Smith.fuse(base, []) == base
    assert Smith.cut(base, []) == base

    assert {:ok, result} =
             base |> Smith.fuse([extension]) |> Smith.cut([cutter]) |> Smith.evaluate()

    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 1500, 1.0e-7

    assert {:error, %Smith.Error{operation: :cylinder}} =
             base |> Smith.cut([Smith.cylinder(-1, 2)]) |> Smith.evaluate() |> nested_error()
  end

  defp nested_error({:error, %Smith.Error{reason: %Smith.Error{} = reason}}), do: {:error, reason}

  test "nested recipes support boolean operations and placement" do
    recipe =
      Smith.cylinder(5, 10)
      |> Smith.cut(Smith.cylinder(2, 12) |> Smith.translate({0, 0, -1}))
      |> Smith.rotate({1, 0, 0}, 90)
      |> Smith.clean()

    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, :math.pi() * 210, 1.0e-7

    assert {:ok, _} =
             Smith.evaluate(
               Smith.box(2, 2, 2)
               |> Smith.fuse(Smith.box(2, 2, 2) |> Smith.translate({2, 0, 0}))
             )
  end

  test "polygon and arc profiles extrude along arbitrary vectors" do
    recipe =
      Smith.profile([
        Smith.arc({0, 0, 0}, {0, 0, 1}, {1, 0, 0}, 2, 0, 180),
        Smith.line({-2, 0, 0}, {2, 0, 0})
      ])
      |> Smith.extrude({0, 0, 3})

    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 6 * :math.pi(), 1.0e-7

    assert {:ok, result} =
             Smith.polygon([{0, 0, 0}, {2, 0, 0}, {2, 0, 3}, {0, 0, 3}])
             |> Smith.extrude({0, 4, 0})
             |> Smith.evaluate()

    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 24, 1.0e-7
  end

  test "predicate selectors inspect current edges and enforce expected counts" do
    recipe =
      Smith.box(10, 10, 5)
      |> Smith.fillet(
        edges: fn e -> e.type == :line and abs(elem(e.direction, 2)) > 0.99 end,
        count: 4,
        radius: 1
      )

    assert {:ok, _} = Smith.evaluate(recipe)

    assert {:error, %Smith.Error{reason: :selection_count_mismatch}} =
             Smith.box(10, 10, 5)
             |> Smith.fillet(edges: :all, count: 3, radius: 1)
             |> Smith.evaluate()

    assert {:ok, _} =
             Smith.box(10, 10, 5)
             |> Smith.chamfer(edges: {:parallel, :z}, distance: 1)
             |> Smith.evaluate()
  end

  test "invalid nested recipes preserve the evaluation error" do
    assert {:error, %Smith.Error{operation: :cut}} =
             Smith.box(2, 2, 2) |> Smith.cut(Smith.cylinder(-1, 3)) |> Smith.evaluate()

    assert {:error, _} = Smith.polygon([]) |> Smith.evaluate()
  end
end

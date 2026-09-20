defmodule Smith.TransformPlanTest do
  use ExUnit.Case, async: true

  test "ordinary transform chains match separately evaluated steps" do
    source = Smith.box(4, 3, 2) |> Smith.fillet(edges: :all, radius: 0.2)

    steps = [
      fn s -> Smith.translate(s, {3, -2, 5}) end,
      fn s -> Smith.rotate(s, {1, 2, 3}, 37, {1, 2, 3}) end,
      fn s -> Smith.mirror(s, Smith.Plane.yz(x: 2)) end,
      fn s -> Smith.translate(s, {-1, 2, -3}) end
    ]

    {:ok, actual} = Enum.reduce(steps, source, & &1.(&2)) |> Smith.evaluate()

    separate =
      Enum.reduce(steps, source, fn step, s ->
        {:ok, result} = step.(s) |> Smith.evaluate()
        Smith.from_result(result)
      end)

    {:ok, expected} = Smith.evaluate(separate)

    for {a, b} <- [{actual.shape, expected.shape}, {expected.shape, actual.shape}] do
      {:ok, delta} = OCEx.cut(a, b)
      assert {:ok, volume} = OCEx.volume(delta)
      assert_in_delta volume, 0, 1.0e-7
    end
  end

  test "invalid intermediate transforms retain their first recipe error" do
    recipe =
      Smith.box(1, 2, 3)
      |> Smith.translate({1, 2, 3})
      |> Smith.rotate({0, 0, 0}, 0)
      |> Smith.translate({-1, -2, -3})

    assert {:error, %Smith.Error{step: 3, operation: :rotate, reason: :invalid_argument}} =
             Smith.evaluate(recipe)
  end

  test "cancelling extreme placements cannot hide an invalid intermediate shape" do
    recipe = Smith.box(1, 2, 3) |> Smith.translate({1.0e308, 0, 0})
    assert {:error, expected} = Smith.evaluate(recipe)
    assert {:error, ^expected} = recipe |> Smith.translate({-1.0e308, 0, 0}) |> Smith.evaluate()
  end
end

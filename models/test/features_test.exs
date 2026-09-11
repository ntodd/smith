defmodule Models.FeaturesTest do
  use ExUnit.Case, async: true

  test "a hook can be evaluated independently and parameter variants do not change the original" do
    dimensions = %Models.DeckClip{}
    original = Models.DeckClip.hook(dimensions)
    narrower = Models.DeckClip.hook(%{dimensions | hook_width: 32.0})

    for {recipe, width} <- [{original, 40.4}, {narrower, 32.0}] do
      assert {:ok, result} = Smith.evaluate(recipe)
      # Measure topology vertices: spline bounding boxes can include tolerance padding.
      assert {:ok, vertices} = OCEx.vertices(result.shape)

      xs =
        Enum.map(vertices, fn vertex ->
          {:ok, {x, _, _}} = OCEx.point(vertex)
          x
        end)

      assert_in_delta Enum.max(xs) - Enum.min(xs), width, 1.0e-7
      assert {:ok, [_solid]} = OCEx.solids(result.shape)
    end

    assert dimensions.hook_width == 40.4
  end

  test "stand features can be composed and inspected without constructing the whole stand" do
    dimensions = %Models.PlantStand{}
    foot = Models.PlantStand.center_foot(dimensions)
    pair = foot |> Smith.fuse(foot |> Smith.translate({30, 0, 0}))

    assert {:ok, result} = Smith.evaluate(pair)
    assert {:ok, [_, _]} = OCEx.solids(result.shape)
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 2 * :math.pi() * 8 * 8 * 14.05, 1.0e-7
  end
end

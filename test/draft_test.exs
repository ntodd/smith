defmodule Smith.DraftTest do
  use ExUnit.Case, async: true
  alias Smith.{Plane, Selector}

  defp volume(recipe, expected) do
    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, true} = OCEx.valid?(result.shape)
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, expected, 1.0e-5
    result
  end

  test "draft uses plane-normal pull by default and resolves selectors after placement" do
    sides = Selector.type(:plane) |> Selector.exclude(Selector.parallel(:z))
    t = :math.tan(5 * :math.pi() / 180)
    expected = 3200 - 36 * t * 100 + 4 / 3 * t * t * 1000

    Smith.box(20, 16, 10, at: {4, 5, 6})
    |> Smith.draft(faces: sides, neutral: Plane.xy(z: 6), angle: 5, count: 4)
    |> volume(expected)

    Smith.box(20, 16, 10)
    |> Smith.draft(faces: sides, neutral: :xy, angle: -5, direction: {0, 0, -1})
    |> volume(expected)
  end

  test "draft composes after holes and preserves the neutral profile" do
    sides = Selector.type(:plane) |> Selector.exclude(Selector.parallel(:z))
    t = :math.tan(5 * :math.pi() / 180)
    expected = 3200 - 36 * t * 100 + 4 / 3 * t * t * 1000 - 10 * :math.pi()

    recipe =
      Smith.box(20, 16, 10)
      |> Smith.hole(on: :top, diameter: 2, through: :all)
      |> Smith.draft(faces: sides, neutral: :xy, angle: 5, count: 4)

    volume(recipe, expected)
    assert {:ok, section} = recipe |> Smith.section(:xy) |> Smith.evaluate()
    assert {:ok, area} = OCEx.area(section.shape)
    assert_in_delta area, 320 - :math.pi(), 1.0e-5
  end

  test "draft errors retain selector count and operation context" do
    for {opts, reason} <- [
          {[faces: :all, neutral: :xy], :invalid_options},
          {[faces: :all, angle: 5, neutral: :bad], :invalid_plane},
          {[faces: Selector.type(:sphere), neutral: :xy, angle: 5], :empty_selection},
          {[faces: Selector.facing(:x), neutral: :xy, angle: 5, count: 2],
           :selection_count_mismatch},
          {[faces: :all, neutral: :xy, angle: 90], :invalid_argument},
          {[faces: :all, neutral: :xy, angle: 5, direction: {1, 0, 0}], :invalid_direction},
          {[faces: :all, neutral: :xy, angle: 5, extra: true], :invalid_options}
        ] do
      assert {:error, %Smith.Error{step: 2, operation: :draft, reason: ^reason}} =
               Smith.box(20, 16, 10) |> Smith.draft(opts) |> Smith.evaluate()
    end
  end

  test "draft propagates tangent-connected walls without duplicating work" do
    sides = Selector.exclude(Selector.parallel(:z))
    angle = 5
    t = :math.tan(angle * :math.pi() / 180)
    rectangular = 3200 - 36 * t * 100 + 4 / 3 * t * t * 1000
    corner_loss = (4 - :math.pi()) * (4 * 10 - 2 * t * 100 + t * t * 1000 / 3)

    Smith.Sketch.rounded_rectangle(20, 16, 2)
    |> Smith.extrude(10)
    |> Smith.draft(faces: sides, neutral: :xy, angle: angle, count: 8)
    |> volume(rectangular - corner_loss)
  end
end

defmodule Smith.OffsetTest do
  use ExUnit.Case, async: true
  alias Smith.{Plane, Selector, Sketch}

  defp result(recipe) do
    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, true} = OCEx.valid?(result.shape)
    result
  end

  defp volume(recipe, expected) do
    result = result(recipe)
    assert {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, expected, 1.0e-5
    result
  end

  test "offset expands a solid and composes after earlier cuts" do
    Smith.box(20, 16, 10) |> Smith.offset(2, join: :intersection) |> volume(24 * 20 * 14)

    Smith.box(20, 16, 10)
    |> Smith.hole(on: :top, diameter: 4, through: :all)
    |> Smith.offset(-2)
    |> volume(16 * 12 * 6 - :math.pi() * 16 * 6)
  end

  test "selected curved surfaces can be offset and thickened as recipes" do
    source = Smith.cylinder(10, 12)
    wall = Smith.surface(source, Selector.type(:cylinder))
    face = result(wall)
    assert {:ok, []} = OCEx.solids(face.shape)
    wall |> Smith.thicken(-2) |> volume((100 - 64) * 12 * :math.pi())
    wall |> Smith.offset(2) |> Smith.thicken(1) |> volume((169 - 144) * 12 * :math.pi())
    source |> volume(1200 * :math.pi())
  end

  test "connected selected faces sew into a shell before thickening" do
    sides = Selector.any_of([Selector.facing({:x, :negative}), Selector.facing({:y, :negative})])

    Smith.box(10, 10, 10)
    |> Smith.surface(sides)
    |> Smith.thicken(1)
    |> volume(210)
  end

  test "planar sketch thickening follows orientation and preserves holes" do
    ring = Sketch.circle(5, on: Plane.yz(x: 3)) |> Sketch.cut(Sketch.circle(2))
    ring |> Smith.thicken(2) |> volume(42 * :math.pi())
    ring |> Smith.thicken(-2) |> volume(42 * :math.pi())
    shifted = ring |> Smith.offset(2) |> result()
    assert {:ok, {low, high}} = OCEx.bounds(shifted.shape)
    assert_in_delta elem(low, 0), 5, 1.0e-6
    assert_in_delta elem(high, 0), 5, 1.0e-6
  end

  test "disconnected surface members become separately thickened solids" do
    surface =
      Smith.compound([Smith.box(4, 5, 6), Smith.box(4, 5, 6, at: {10, 0, 0})])
      |> Smith.surface(Selector.facing(:z))

    thick = surface |> Smith.thicken(2) |> volume(80)
    assert {:ok, [_, _]} = OCEx.solids(thick.shape)
  end

  test "errors distinguish empty selection, closed surfaces, solid inputs and invalid options" do
    for {operation, args, reason} <- [
          {:surface, [Selector.type(:sphere)], :empty_selection},
          {:surface, [:bad], :invalid_options},
          {:offset, [0], :invalid_argument},
          {:offset, [1, [join: :bad]], :invalid_options},
          {:thicken, [1], :wrong_shape_type}
        ] do
      assert {:error, %Smith.Error{operation: ^operation, step: 2, reason: ^reason}} =
               apply(Smith, operation, [Smith.box(10, 10, 10) | args]) |> Smith.evaluate()
    end

    assert {:error, %Smith.Error{operation: :thicken, reason: :closed_shell}} =
             Smith.box(10, 10, 10) |> Smith.surface() |> Smith.thicken(1) |> Smith.evaluate()
  end

  test "shell accepts a single solid wrapped by an earlier Boolean cut" do
    source = Smith.box(20, 16, 10) |> Smith.hole(on: :top, diameter: 4, through: :all)
    # Removing the top creates an open tray with a thickened tube around the hole.
    assert {:ok, hollow} =
             source
             |> Smith.shell(openings: Selector.facing(:z), thickness: -1, count: 1)
             |> Smith.evaluate()

    assert {:ok, true} = OCEx.valid?(hollow.shape)
    assert {:ok, volume} = OCEx.volume(hollow.shape)
    expected = 3200 - 40 * :math.pi() - (18 * 14 - 9 * :math.pi()) * 9
    assert_in_delta volume, expected, 1.0e-5
  end
end

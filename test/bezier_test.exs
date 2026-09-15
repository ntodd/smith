defmodule Smith.BezierTest do
  use ExUnit.Case, async: true
  alias Smith.{Plane, Sketch}

  test "world-space Bezier recipes transform without changing the original" do
    curve = Smith.bezier([{0, 0, 0}, {1, 2, 0}, {2, 0, 0}])
    assert {:ok, original} = Smith.evaluate(curve)
    assert {:ok, placed} = curve |> Smith.translate({4, 5, 6}) |> Smith.evaluate()
    assert {:ok, %{point: {5.0, 6.0, 6.0}}} = OCEx.edge_sample(placed.shape, 0.5)
    assert {:ok, again} = Smith.evaluate(curve)
    assert again.revision == original.revision

    assert {:error, %Smith.Error{operation: :bezier, reason: :invalid_argument}} =
             Smith.bezier([]) |> Smith.evaluate()
  end

  test "a quadratic arch bounds an analytic area and extrudes on an arbitrary plane" do
    profile =
      Sketch.profile(
        [
          Sketch.bezier([{0, 0}, {1, 2}, {2, 0}]),
          Sketch.line({2, 0}, {0, 0})
        ],
        on: Plane.yz(x: 7)
      )

    assert {:ok, face} = Smith.evaluate(profile)
    assert {:ok, area} = OCEx.area(face.shape)
    assert_in_delta area, 4 / 3, 1.0e-8
    assert {:ok, body} = profile |> Smith.extrude(3) |> Smith.evaluate()
    assert {:ok, volume} = OCEx.volume(body.shape)
    assert_in_delta volume, 4, 1.0e-8
    assert {:ok, [_]} = OCEx.solids(body.shape)
    assert {:ok, {{xmin, _, _}, {xmax, _, _}}} = OCEx.bounds(body.shape)
    assert_in_delta xmin, 7, 1.0e-6
    assert_in_delta xmax, 10, 1.0e-6
  end

  test "invalid local control points return a modeling error during evaluation" do
    for points <- [nil, [], [{0, 0}], [{0, 0}, {1, 2, 3}], [{0, 0} | :bad]] do
      assert {:error, %Smith.Error{}} =
               Sketch.profile([Sketch.bezier(points)]) |> Smith.evaluate()
    end
  end
end

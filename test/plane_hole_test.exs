defmodule Smith.PlaneHoleTest do
  use ExUnit.Case, async: true
  alias Smith.{Plane, Sketch}

  test "plane-local hole coordinates remove the expected volume and cylindrical axis" do
    for plane <- [
          Plane.xy(z: 20),
          Plane.yz(x: 10),
          Plane.xz(y: 4),
          Plane.new(origin: {10, -20, 30}, normal: {1, 2, 3}, x_direction: {1, 0, 0})
        ] do
      assert {:ok, result} =
               Sketch.rectangle(20, 16, on: plane)
               |> Smith.extrude(5)
               |> Smith.hole(on: plane, at: {3, 2}, diameter: 4, through: :all)
               |> Smith.evaluate()

      assert {:ok, volume} = OCEx.volume(result.shape)
      assert_in_delta volume, 1600 - 20 * :math.pi(), 1.0e-6
      {:ok, center} = Plane.to_world(plane, {3, 2})
      {:ok, normal} = Plane.normal(plane)
      {:ok, faces} = OCEx.faces(result.shape)

      cylinders =
        for face <- faces, {:ok, %{type: :cylinder} = info} <- [OCEx.face_info(face)], do: info

      assert length(cylinders) == 1
      assert_in_delta hd(cylinders).radius, 2, 1.0e-7
      # A narrow bore probe must be completely clear through the body.
      {:ok, probe} =
        Sketch.circle(1, on: plane, at: {3, 2}) |> Smith.extrude(5) |> Smith.evaluate()

      {:ok, intersection} = OCEx.common(result.shape, probe.shape)
      {:ok, overlap} = OCEx.volume(intersection)
      assert_in_delta overlap, 0, 1.0e-7
      direction = hd(cylinders).axis_direction

      dot =
        Enum.zip(Tuple.to_list(direction), Tuple.to_list(normal))
        |> Enum.map(fn {a, b} -> a * b end)
        |> Enum.sum()

      assert_in_delta abs(dot), 1, 1.0e-8

      delta =
        Enum.zip(Tuple.to_list(center), Tuple.to_list(hd(cylinders).axis_origin))
        |> Enum.map(fn {a, b} -> a - b end)

      axial =
        Enum.zip(delta, Tuple.to_list(normal)) |> Enum.map(fn {a, b} -> a * b end) |> Enum.sum()

      perpendicular_squared = Enum.sum(Enum.map(delta, &(&1 * &1))) - axial * axial
      assert_in_delta perpendicular_squared, 0, 1.0e-7
    end
  end

  test "through-all spans disconnected solids even when the plane is outside their bounds" do
    body = Smith.box(10, 10, 3) |> Smith.fuse(Smith.box(10, 10, 3) |> Smith.translate({0, 0, 10}))

    assert {:ok, result} =
             body
             |> Smith.hole(on: Plane.xy(z: 100), at: {5, 5}, diameter: 2, through: :all)
             |> Smith.evaluate()

    {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 600 - 6 * :math.pi(), 1.0e-7
  end

  test "plane hole errors identify the hole step and preserve old top-face behavior" do
    for opts <- [
          [on: Plane.xy(), at: {100, 0}, diameter: 2, through: :all],
          [on: Plane.new(normal: {0, 0, 0}), diameter: 2, through: :all],
          [on: Plane.xy(), at: {0, :bad}, diameter: 2, through: :all],
          [on: Plane.xy(), diameter: 2, through: :blind]
        ] do
      assert {:error, %Smith.Error{operation: :hole, step: 2}} =
               Smith.box(10, 10, 3) |> Smith.hole(opts) |> Smith.evaluate()
    end

    assert {:ok, result} =
             Smith.box(10, 10, 3)
             |> Smith.hole(on: :top, diameter: 2, through: :all)
             |> Smith.evaluate()

    {:ok, volume} = OCEx.volume(result.shape)
    assert_in_delta volume, 300 - 3 * :math.pi(), 1.0e-7
  end
end

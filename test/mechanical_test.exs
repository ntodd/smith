defmodule Smith.MechanicalTest do
  use ExUnit.Case, async: true
  alias Smith.{Plane, Selector, Sketch}

  defp result(recipe) do
    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, true} = OCEx.valid?(result.shape)
    result
  end

  defp volume(recipe, expected) do
    result = result(recipe)
    assert {:ok, actual} = OCEx.volume(result.shape)
    assert_in_delta actual, expected, 1.0e-5
    result
  end

  test "sphere and torus use centered defaults and the common placement options" do
    sphere = volume(Smith.sphere(3), 36 * :math.pi())
    assert {:ok, {low, high}} = OCEx.bounds(sphere.shape)
    assert low == {-3.0, -3.0, -3.0}
    assert high == {3.0, 3.0, 3.0}

    ring =
      volume(
        Smith.torus(10, 2, at: {5, 6, 7}, align: {:min, :center, :min}),
        80 * :math.pi() * :math.pi()
      )

    assert {:ok, {low, high}} = OCEx.bounds(ring.shape)

    for {actual, expected} <-
          Enum.zip(Tuple.to_list(low) ++ Tuple.to_list(high), [5, -6, 7, 29, 18, 11]),
        do: assert_in_delta(actual, expected, 1.0e-6)

    for recipe <- [
          Smith.sphere(-1),
          Smith.torus(2, 3),
          Smith.sphere(2, align: :bad),
          Smith.torus(5, 1, extra: 2)
        ] do
      assert {:error, %Smith.Error{step: 1}} = Smith.evaluate(recipe)
    end
  end

  test "mirror accepts named and positioned planes and remains a normal recipe step" do
    source = Smith.box(10, 8, 6)

    for plane <- [:xy, :xz, :yz, Plane.yz(x: 20), Plane.new(normal: {1, 1, 1})] do
      mirrored = source |> Smith.mirror(plane)
      volume(mirrored, 480)
      twice = result(mirrored |> Smith.mirror(plane))
      original = result(source)
      assert {:ok, difference} = OCEx.cut(original.shape, twice.shape)
      assert {:ok, v} = OCEx.volume(difference)
      assert_in_delta v, 0, 1.0e-6
    end

    source
    |> Smith.mirror(:yz)
    |> Smith.hole(on: :top, diameter: 2, through: :all)
    |> volume(480 - 6 * :math.pi())

    assert {:error, %Smith.Error{operation: :mirror, step: 2, reason: :invalid_plane}} =
             source |> Smith.mirror(:bad) |> Smith.evaluate()

    assert {:ok, [%{normal: {_, _, z}}]} =
             source |> Smith.mirror(:xy) |> result() |> Smith.inspect_faces(Selector.facing(:z))

    assert z > 0.99
  end

  test "rounded rectangle is an exact curved profile and inherits placement and cuts" do
    area = 20 * 12 - (4 - :math.pi()) * 4

    Sketch.rounded_rectangle(20, 12, 2, on: Plane.yz(x: 4), at: {3, 5})
    |> Sketch.cut(Sketch.circle(1, at: {3, 5}))
    |> Smith.extrude(3)
    |> volume((area - :math.pi()) * 3)

    assert {:error, %Smith.Error{}} = Sketch.rounded_rectangle(20, 12, 7) |> Smith.evaluate()
  end

  test "slot length is overall length with semicircular ends and standard alignment" do
    for {length, width} <- [{20, 6}, {6, 6}] do
      area = (length - width) * width + :math.pi() * width * width / 4
      face = result(Sketch.slot(length, width, align: {:min, :min}, at: {2, 3}))
      assert {:ok, actual} = OCEx.area(face.shape)
      assert_in_delta actual, area, 1.0e-6
      assert {:ok, {low, high}} = OCEx.bounds(face.shape)

      for {actual, expected} <-
            Enum.zip(Tuple.to_list(low) ++ Tuple.to_list(high), [
              2,
              3,
              0,
              2 + length,
              3 + width,
              0
            ]),
          do: assert_in_delta(actual, expected, 1.0e-6)

      Sketch.slot(length, width, on: Plane.xz(y: 7)) |> Smith.extrude(-2) |> volume(area * 2)
    end

    for {length, width} <- [{2, 3}, {0, 3}, {3, 0}, {nil, 2}] do
      assert {:error, %Smith.Error{}} = Sketch.slot(length, width) |> Smith.evaluate()
    end
  end

  @tag :tmp_dir
  test "mechanical shapes and reflected faces export with consistent printable winding", %{
    tmp_dir: root
  } do
    plate =
      Sketch.rounded_rectangle(30, 20, 2)
      |> Sketch.cut(Sketch.slot(10, 4))
      |> Smith.extrude(6)
      |> Smith.counterbore(
        on: Plane.xy(z: 6),
        at: {10, 0},
        diameter: 2,
        bore_diameter: 4,
        bore_depth: 2,
        through: :all
      )
      |> Smith.countersink(
        on: Plane.xy(z: 6),
        at: {-10, 0},
        diameter: 2,
        sink_diameter: 4,
        depth: 4
      )
      |> Smith.mirror(:xy)

    for {name, recipe} <- [
          {"plate", plate},
          {"torus", Smith.torus(10, 2)},
          {"sphere", Smith.sphere(3)}
        ] do
      assert {:ok, files} =
               Smith.export(result(recipe), root,
                 name: name,
                 on_bed: true,
                 angular_tolerance: 0.1
               )

      assert files.verification.mesh.watertight
      assert files.verification.mesh.winding_consistent
      assert files.verification.mesh.components == 1
      assert files.verification.step_relative_volume_error < 1.0e-6
      assert {:ok, zip} = :zip.extract(File.read!(files.three_mf), [:memory])
      assert Enum.any?(zip, fn {name, _} -> to_string(name) == "3D/3dmodel.model" end)
    end
  end
end

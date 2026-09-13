defmodule Smith.HoleFeaturesTest do
  use ExUnit.Case, async: true
  alias Smith.Plane

  defp volume(recipe, expected) do
    assert {:ok, result} = Smith.evaluate(recipe)
    assert {:ok, true} = OCEx.valid?(result.shape)
    assert {:ok, actual} = OCEx.volume(result.shape)
    assert_in_delta actual, expected, 1.0e-5
    result
  end

  test "blind holes measure depth from the entry plane into its negative normal" do
    body = Smith.box(20, 16, 10)
    result = body |> Smith.hole(on: :top, diameter: 4, depth: 6) |> volume(3200 - 24 * :math.pi())
    assert {:ok, probe} = OCEx.box(1, 1, 1)
    assert {:ok, probe} = OCEx.translate(probe, {9.5, 7.5, 1})
    assert {:ok, material} = OCEx.common(result.shape, probe)
    assert {:ok, retained} = OCEx.volume(material)
    assert_in_delta retained, 1, 1.0e-7
    assert {:ok, d} = OCEx.distance_to_point(result.shape, {10, 8, 8})
    assert_in_delta d, 2, 1.0e-7

    body
    |> Smith.hole(on: Plane.yz(x: 20), at: {8, 5}, diameter: 4, depth: 6)
    |> volume(3200 - 24 * :math.pi())

    body
    |> Smith.hole(on: Plane.xy(z: 12), at: {10, 8}, diameter: 4, depth: 6)
    |> volume(3200 - 16 * :math.pi())
  end

  test "counterbore depth is measured from entry and included in total blind depth" do
    for extent <- [[depth: 8], [through: :all]] do
      depth = if extent == [depth: 8], do: 8, else: 10

      Smith.box(20, 16, 10)
      |> Smith.counterbore([on: :top, diameter: 4, bore_diameter: 8, bore_depth: 3] ++ extent)
      |> volume(3200 - :math.pi() * (4 * depth + 12 * 3))
    end
  end

  test "countersink angle is included cone angle with analytic frustum volume" do
    for angle <- [60, 90, 120], extent <- [[depth: 8], [through: :all]] do
      depth = if extent == [depth: 8], do: 8, else: 10
      h = (4 - 2) / :math.tan(angle * :math.pi() / 360)
      removed = :math.pi() * 4 * (depth - h) + :math.pi() * h / 3 * (16 + 8 + 4)

      Smith.box(20, 16, 10)
      |> Smith.countersink([on: :top, diameter: 4, sink_diameter: 8, angle: angle] ++ extent)
      |> volume(3200 - removed)
    end

    Smith.box(20, 16, 10)
    |> Smith.countersink(on: :top, diameter: 4, sink_diameter: 8, through: :all)
    |> volume(3200 - :math.pi() * (4 * 8 + 2 / 3 * 28))
  end

  test "recesses follow plane-local placement and work after mirroring" do
    source = Smith.box(20, 16, 10) |> Smith.mirror(:yz)

    source
    |> Smith.counterbore(
      on: Plane.new(origin: {-20, 0, 0}, normal: {-1, 0, 0}, x_direction: {0, 1, 0}),
      at: {8, -5},
      diameter: 4,
      bore_diameter: 8,
      bore_depth: 2,
      depth: 6
    )
    |> volume(3200 - :math.pi() * (4 * 6 + 12 * 2))
  end

  test "ambiguous extent and malformed recess dimensions return errors at the feature step" do
    for {op, opts} <- [
          {:hole, [diameter: 4]},
          {:hole, [diameter: 4, depth: 0]},
          {:hole, [diameter: 4, depth: 4, through: :all]},
          {:counterbore, [diameter: 4, bore_diameter: 4, bore_depth: 2, depth: 6]},
          {:counterbore, [diameter: 4, bore_diameter: 8, bore_depth: 7, depth: 6]},
          {:counterbore, [diameter: 4, bore_diameter: 8, bore_depth: 0, through: :all]},
          {:countersink, [diameter: 4, sink_diameter: 8, angle: 0, through: :all]},
          {:countersink, [diameter: 4, sink_diameter: 8, angle: 180, through: :all]},
          {:countersink, [diameter: 4, sink_diameter: 8, depth: 1]},
          {:countersink, [diameter: 4, sink_diameter: nil, through: :all]},
          {:hole, [diameter: 4, depth: 2, depth: 3]}
        ] do
      assert {:error, %Smith.Error{operation: ^op, step: 2, reason: :invalid_options}} =
               apply(Smith, op, [Smith.box(20, 16, 10), [on: :top] ++ opts]) |> Smith.evaluate()
    end
  end

  test "holes and recesses must remove material and leave their source reusable" do
    source = Smith.box(20, 16, 10)

    assert {:error, %Smith.Error{reason: :hole_misses_body}} =
             source
             |> Smith.hole(on: :top, at: {100, 0}, diameter: 4, depth: 2)
             |> Smith.evaluate()

    assert {:error, %Smith.Error{reason: :recess_misses_body}} =
             source
             |> Smith.counterbore(
               on: Plane.xy(z: 20),
               at: {10, 8},
               diameter: 4,
               bore_diameter: 8,
               bore_depth: 2,
               through: :all
             )
             |> Smith.evaluate()

    volume(source, 3200)
  end
end

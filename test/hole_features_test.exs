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

  test "successive holes reject repeated and tangent cutters at their original step" do
    hole = [on: Plane.xy(), at: {5, 5}, diameter: 2, through: :all]

    assert {:error, %Smith.Error{step: 3, operation: :hole, reason: :hole_misses_body}} =
             Smith.box(10, 10, 3)
             |> Smith.hole(hole)
             |> Smith.hole(hole)
             |> Smith.evaluate()

    assert {:error, %Smith.Error{step: 3, operation: :hole, reason: :hole_misses_body}} =
             Smith.box(10, 10, 3)
             |> Smith.hole(hole)
             |> Smith.hole(on: Plane.xy(), at: {11, 5}, diameter: 2, through: :all)
             |> Smith.evaluate()
  end

  test "a recess must remove additional material beyond an existing wider bore" do
    assert {:error, %Smith.Error{step: 3, operation: :counterbore, reason: :recess_misses_body}} =
             Smith.box(10, 10, 10)
             |> Smith.hole(on: Plane.xy(z: 10), at: {5, 5}, diameter: 6, depth: 3)
             |> Smith.counterbore(
               on: Plane.xy(z: 10),
               at: {5, 5},
               diameter: 2,
               through: :all,
               bore_diameter: 4,
               bore_depth: 2
             )
             |> Smith.evaluate()
  end

  test "top placement is resolved again after each hole changes the face centroid" do
    first = Smith.box(20, 16, 10) |> Smith.hole(on: :top, at: {-4, 0}, diameter: 2, depth: 3)
    assert {:ok, intermediate} = Smith.evaluate(first)
    selector = Smith.Selector.facing(:z) |> Smith.Selector.at_max(:z)
    assert {:ok, [face]} = Smith.Selector.select(intermediate.shape, :faces, selector)
    assert {:ok, %{center: {x, y, z}}} = OCEx.face_info(face)
    assert x > 10

    expected = first |> Smith.hole(on: Plane.xy(z: z), at: {x, y}, diameter: 2, through: :all)
    actual = first |> Smith.hole(on: :top, diameter: 2, through: :all)
    assert {:ok, a} = Smith.evaluate(actual)
    assert {:ok, b} = Smith.evaluate(expected)

    for {left, right} <- [{a.shape, b.shape}, {b.shape, a.shape}] do
      assert {:ok, delta} = OCEx.cut(left, right)
      assert {:ok, amount} = OCEx.volume(delta)
      assert_in_delta amount, 0, 1.0e-7
    end
  end

  test "through-hole bounds follow intervening transformations" do
    Smith.box(20, 16, 10)
    |> Smith.hole(on: Plane.xy(), at: {5, 5}, diameter: 2, through: :all)
    |> Smith.translate({0, 0, 100})
    |> Smith.hole(on: Plane.xy(), at: {15, 5}, diameter: 2, through: :all)
    |> volume(3200 - 20 * :math.pi())
  end

  test "successive intersecting holes match separate evaluations as the envelope shrinks" do
    first =
      Smith.box(20, 10, 10)
      |> Smith.hole(on: Plane.xy(), at: {0, 5}, diameter: 20, through: :all)

    assert {:ok, snapshot} = Smith.evaluate(first)
    opts = [on: Plane.xz(y: 100), at: {12, 5}, diameter: 8, through: :all]
    assert {:ok, together} = first |> Smith.hole(opts) |> Smith.evaluate()

    assert {:ok, separate} =
             snapshot |> Smith.from_result() |> Smith.hole(opts) |> Smith.evaluate()

    for {a, b} <- [{together.shape, separate.shape}, {separate.shape, together.shape}] do
      assert {:ok, delta} = OCEx.cut(a, b)
      assert {:ok, volume} = OCEx.volume(delta)
      assert_in_delta volume, 0, 1.0e-7
    end
  end

  test "a through-hole following complete removal retains the empty-body error" do
    assert {:error, %Smith.Error{step: 3, operation: :hole, reason: :empty_shape}} =
             Smith.box(2, 2, 2)
             |> Smith.hole(on: Plane.xy(), at: {1, 1}, diameter: 10, through: :all)
             |> Smith.hole(on: Plane.xy(), at: {1, 1}, diameter: 2, through: :all)
             |> Smith.evaluate()
  end
end

defmodule Smith.PrimitivePlacementTest do
  use ExUnit.Case, async: true

  defp result(recipe) do
    assert {:ok, result} = Smith.evaluate(recipe)
    result
  end

  defp bounds(shape, low, high) do
    assert {:ok, {actual_low, actual_high}} = OCEx.bounds(shape)

    for {actual, expected} <-
          Enum.zip(
            Tuple.to_list(actual_low) ++ Tuple.to_list(actual_high),
            Tuple.to_list(low) ++ Tuple.to_list(high)
          ),
        do: assert_in_delta(actual, expected, 1.0e-7)
  end

  test "omitting options preserves original origins and geometry revisions" do
    for {op, dimensions, low, high} <- [
          {:box, [4, 6, 8], {0, 0, 0}, {4, 6, 8}},
          {:cylinder, [3, 8], {-3, -3, 0}, {3, 3, 8}},
          {:cone, [3, 1, 8], {-3, -3, 0}, {3, 3, 8}}
        ] do
      original = apply(Smith, op, dimensions) |> result()
      explicit = apply(Smith, op, dimensions ++ [[at: {0, 0, 0}]]) |> result()
      empty = apply(Smith, op, dimensions ++ [[]]) |> result()
      bounds(original.shape, low, high)
      assert original.revision == explicit.revision
      assert original.revision == empty.revision
    end
  end

  test "box alignment independently anchors each axis at the requested point" do
    for {alignment, low, high} <- [
          {{:min, :min, :min}, {10, -20, 30}, {14, -14, 38}},
          {{:center, :center, :center}, {8, -23, 26}, {12, -17, 34}},
          {{:max, :max, :max}, {6, -26, 22}, {10, -20, 30}},
          {{:center, :max, :min}, {8, -26, 30}, {12, -20, 38}}
        ] do
      body = Smith.box(4, 6, 8, at: {10, -20, 30}, align: alignment) |> result()
      bounds(body.shape, low, high)
      assert {:ok, volume} = OCEx.volume(body.shape)
      assert_in_delta volume, 192, 1.0e-7
    end

    centered = Smith.box(4, 6, 8, align: {:center, :center, :min}) |> result()
    bounds(centered.shape, {-2, -3, 0}, {2, 3, 8})
  end

  test "cylinders and either orientation of a cone share bounds alignment" do
    cylinder = Smith.cylinder(3, 8, at: {10, -20, 30}) |> result()
    bounds(cylinder.shape, {7, -23, 30}, {13, -17, 38})
    assert {:ok, volume} = OCEx.volume(cylinder.shape)
    assert_in_delta volume, :math.pi() * 72, 1.0e-7

    for {bottom, top} <- [{3, 1}, {1, 3}, {0, 3}, {3, 0}] do
      cone =
        Smith.cone(bottom, top, 8, at: {10, -20, 30}, align: {:min, :max, :center}) |> result()

      bounds(cone.shape, {10, -26, 26}, {16, -20, 34})
      assert {:ok, volume} = OCEx.volume(cone.shape)

      assert_in_delta volume,
                      :math.pi() * 8 / 3 * (bottom * bottom + bottom * top + top * top),
                      1.0e-7
    end

    anchored = Smith.cylinder(3, 8, at: {10, -20, 30}, align: {:min, :max, :center}) |> result()
    bounds(anchored.shape, {10, -26, 26}, {16, -20, 34})
  end

  test "placement composes with finishing, drilling and rotation without mutation" do
    base = Smith.box(20, 10, 4, at: {25, -10, 6}, align: {:center, :center, :min})
    before = result(base)

    finished =
      base
      |> Smith.fillet(edges: {:parallel, :z}, count: 4, radius: 1)
      |> Smith.hole(on: :top, diameter: 2, through: :all)
      |> result()

    bounds(finished.shape, {15, -15, 6}, {35, -5, 10})
    assert {:ok, volume} = OCEx.volume(finished.shape)
    assert_in_delta volume, 196 * 4, 1.0e-7
    assert result(base).revision == before.revision
    rotated = base |> Smith.rotate({0, 0, 1}, 90) |> result()
    bounds(rotated.shape, {5, 15, 6}, {15, 35, 10})
  end

  test "invalid options stay deferred and identify the originating primitive" do
    for {operation, args} <- [box: [4, 6, 8], cylinder: [3, 8], cone: [3, 1, 8]],
        opts <- [
          nil,
          %{},
          [:bad],
          [at: {1, 2}],
          [at: {1, 2, :bad}],
          [at: {0, 0, 0}, at: {1, 2, 3}],
          [align: {:center, :min}],
          [align: {:min, :middle, :max}],
          [align: :center],
          [unknown: true]
        ] do
      assert %Smith.Model{} = recipe = apply(Smith, operation, args ++ [opts])

      assert {:error, %Smith.Error{step: 1, operation: ^operation, reason: :invalid_options}} =
               Smith.evaluate(recipe)
    end
  end

  test "invalid dimensions and unrepresentable coordinates return tagged errors" do
    for recipe <- [
          Smith.box(-1, 2, 3, at: {1, 2, 3}),
          Smith.cylinder(0, 3, align: {:center, :center, :center}),
          Smith.cone(3, 3, 8, at: {1, 2, 3}),
          Smith.box(1, 2, 3, at: {Integer.pow(10, 400), 0, 0})
        ] do
      assert {:error, %Smith.Error{step: 1, reason: :invalid_argument}} = Smith.evaluate(recipe)
    end
  end

  @tag :tmp_dir
  test "placed parts assemble and export verified printable files", %{tmp_dir: root} do
    assembly =
      Smith.Assembly.new(:support)
      |> Smith.Assembly.part(
        :base,
        Smith.box(20, 10, 4, at: {20, 0, 5}, align: {:center, :center, :min}),
        print: [on_bed: true]
      )
      |> Smith.Assembly.part(:pin, Smith.cylinder(2, 6, at: {20, 0, 9}), print: [on_bed: true])
      |> result()

    assert {:ok, files} = Smith.export(assembly, root, name: "support", angular_tolerance: 0.1)
    assert length(files.parts) == 2
    assert Enum.all?(files.parts, & &1.verification.mesh.watertight)
    assert {:ok, entries} = :zip.extract(String.to_charlist(files.print_pack), [:memory])
    assert length(entries) == 4
    assert {:ok, restored} = OCEx.read_step(files.assembly_step)
    bounds(restored, {10, -5, 5}, {30, 5, 15})
  end
end
